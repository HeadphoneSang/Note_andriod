import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/editor/note_document_convert.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/core/store/user_store.dart';
import 'package:note_for_android/models/node_change_event.dart';
import 'package:provider/provider.dart';

/// 待同步的块变更
class _PendingBlock {
  final String nodeId;
  final int? chunkId;
  final String? type;
  final String? deltaJson;
  String? orderKey;
  final NodeChangeType changeType;
  final double version;

  _PendingBlock({
    required this.nodeId,
    this.chunkId,
    this.type,
    this.deltaJson,
    this.orderKey,
    required this.changeType,
    this.version = 1.0,
  });
}

/// 增量保存服务 — 处理事件分发、防抖、块级 CRUD
class IncrementalSaveService {
  final EditorState editorState;
  final TextEditingController titleCtrl;
  final int? Function() provideNotebookId;
  final BuildContext Function() provideContext;
  final VoidCallback onDirty;

  IncrementalSaveService({
    required this.editorState,
    required this.titleCtrl,
    required this.provideNotebookId,
    required this.provideContext,
    required this.onDirty,
  });

  int? _noteId;
  bool _isFlushing = false;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 10000);
  final Map<String, _PendingBlock> _pending = {};

  /// 取消防抖定时器
  void cancelDebounce() => _debounceTimer?.cancel();

  /// 等待当前刷新完成
  Future<void> flush() async {
    cancelDebounce();
    await _flushPending();
  }

  /// 获取笔记 ID（创建后才有）
  int? get noteId => _noteId;

  // ── 事件分发 ──

  void dispatch(Operation op) {
    switch (op) {
      case InsertOperation():
        for (final node in op.nodes) {
          _onInsert(
            NodeChangeEvent(
              changeType: NodeChangeType.insert,
              node: node,
              editorState: editorState,
              operation: op,
            ),
          );
        }
      case DeleteOperation():
        for (final node in op.nodes) {
          _onDelete(
            NodeChangeEvent(
              changeType: NodeChangeType.delete,
              node: node,
              editorState: editorState,
              operation: op,
            ),
          );
        }
      case UpdateTextOperation():
        final node = editorState.document.nodeAtPath(op.path);
        if (node == null) break;
        _onUpdateText(
          NodeChangeEvent(
            changeType: NodeChangeType.updateText,
            node: node,
            editorState: editorState,
            operation: op,
          ),
        );
      case UpdateOperation():
        final node = editorState.document.nodeAtPath(op.path);
        if (node == null) break;
        _onUpdateAttr(
          NodeChangeEvent(
            changeType: NodeChangeType.updateAttr,
            node: node,
            editorState: editorState,
            operation: op,
          ),
        );
    }
  }

  // ── orderKey 分配 ──

  void _binaryAssignOrderKey(
    List<Node> rangeNode,
    int leftIndex,
    int rightIndex,
    String? leftOrderKey,
    String? rightOrderkey,
  ) {
    if (leftIndex > rightIndex) return;
    int mid = (leftIndex + rightIndex) ~/ 2;
    final orderKey = NoteDocumentConvert.generateOrderKey(
      leftOrderKey,
      rightOrderkey,
    );
    rangeNode[mid].attributes[NoteDocumentConvert.attrBlockOrderKey] = orderKey;
    debugPrint("给节点${rangeNode[mid].path}分配的OrderKey $orderKey");
    _binaryAssignOrderKey(
      rangeNode,
      leftIndex,
      mid - 1,
      leftOrderKey,
      orderKey,
    );
    _binaryAssignOrderKey(
      rangeNode,
      mid + 1,
      rightIndex,
      orderKey,
      rightOrderkey,
    );
  }

  void _assignOrderKeyForRange(NodeChangeEvent event) {
    String? startOrderKey;
    String? endOrderKey;
    final preNulls = <Node>[];
    final allNulls = <Node>[];
    var preNode = event.previousNode;
    var nextNode = event.nextNode;

    while (preNode != null &&
        preNode.attributes[NoteDocumentConvert.attrBlockOrderKey] == null) {
      preNulls.add(preNode);
      preNode = preNode.previous;
    }
    startOrderKey = preNode == null
        ? null
        : preNode.attributes[NoteDocumentConvert.attrBlockOrderKey];
    allNulls.addAll(preNulls.reversed);
    allNulls.add(event.rootNode!);

    while (nextNode != null &&
        nextNode.attributes[NoteDocumentConvert.attrBlockOrderKey] == null) {
      allNulls.add(nextNode);
      nextNode = nextNode.next;
    }
    endOrderKey = nextNode == null
        ? null
        : nextNode.attributes[NoteDocumentConvert.attrBlockOrderKey];

    _binaryAssignOrderKey(
      allNulls,
      0,
      allNulls.length - 1,
      startOrderKey,
      endOrderKey,
    );
  }

  // ── 事件处理 ──

  void _onInsert(NodeChangeEvent event) {
    if (event.isSubNode) {
      return _onUpdateAttr(
        event.copyWith(
          changeType: NodeChangeType.updateAttr,
          node: event.rootNode,
        ),
      );
    }
    debugPrint('$event');
    if (_noteId != null && event.chunkOrderKey == null) {
      _assignOrderKeyForRange(event);
    }
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: null,
      changeType: event.chunkId != null
          ? NodeChangeType.updateAttr
          : NodeChangeType.insert,
    );
    debugPrint('↑↑↑↑↑插入事件入队↑↑↑↑↑');
    _debounce();
  }

  void _onDelete(NodeChangeEvent event) {
    if (event.isSubNode) {
      return _onUpdateAttr(
        event.copyWith(
          changeType: NodeChangeType.updateAttr,
          node: event.rootNode,
        ),
      );
    }
    debugPrint('$event');
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      changeType: NodeChangeType.delete,
    );
    debugPrint('↑↑↑↑删除事件入队↑↑↑↑↑');
    _debounce();
  }

  void _onUpdateText(NodeChangeEvent event) {
    if (event.chunkId == null) {
      _onInsert(event);
      return;
    }
    debugPrint('$event');
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: event.chunkOrderKey,
      changeType: NodeChangeType.updateText,
      version: event.chunkVersion,
    );
    debugPrint('↑↑↑↑↑更新文本事件入队↑↑↑↑↑');
    _debounce();
  }

  void _onUpdateAttr(NodeChangeEvent event) {
    if (event.chunkId == null) {
      _onInsert(event);
      return;
    }
    debugPrint('$event');
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: event.chunkOrderKey,
      changeType: NodeChangeType.updateAttr,
      version: event.chunkVersion,
    );
    debugPrint('↑↑↑↑↑更新属性事件入队↑↑↑↑↑');
    _debounce();
  }

  String _extractDeltaJson(Node node) {
    final delta = node.attributes[blockComponentDelta];
    return jsonEncode(
      delta ??
          [
            {'insert': '\n'},
          ],
    );
  }

  // ── 防抖提交 ──

  void _debounce() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _flushPending);
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty || _isFlushing) return;
    _isFlushing = true;

    if (_noteId == null) {
      try {
        final ctx = provideContext();
        final userId = ctx.read<UserStore>().user?.id;
        if (userId == null) throw Exception('用户未登录');

        final title = titleCtrl.text.trim();
        final response = await HttpClient.instance.post<Map<String, dynamic>>(
          '/note',
          data: {
            'title': title.isNotEmpty ? title : '未命名笔记',
            'userId': userId,
            'notebookId': provideNotebookId(),
          },
        );
        if (response.code == 200 && response.data != null) {
          _noteId = response.data!['id'] as int;
        } else {
          throw Exception(response.message ?? '创建笔记失败');
        }
      } catch (e) {
        debugPrint('创建笔记失败: $e');
        _isFlushing = false;
        return;
      }

      int i = 0;
      for (final node in editorState.document.root.children) {
        final pending = _pending[node.id];
        if (pending != null && pending.orderKey == null) {
          pending.orderKey = NoteDocumentConvert.orderKeyForIndex(i);
        }
        i++;
      }
    }

    try {
      final batch = Map<String, _PendingBlock>.from(_pending);
      _pending.clear();

      for (final entry in batch.entries) {
        final block = entry.value;
        try {
          switch (block.changeType) {
            case NodeChangeType.insert:
              await _createBlock(block);
            case NodeChangeType.delete:
              if (block.chunkId != null) await _deleteBlock(block.chunkId!);
            case NodeChangeType.updateText:
            case NodeChangeType.updateAttr:
              if (block.chunkId != null) await _updateBlock(block);
          }
        } catch (e) {
          debugPrint('同步失败: ${block.nodeId} → $e');
          _pending[entry.key] = block;
        }
      }
    } finally {
      _isFlushing = false;
      if (_pending.isNotEmpty) _debounce();
    }
  }

  Future<void> _createBlock(_PendingBlock block) async {
    debugPrint('创建块: ${block.type}');
  }

  Future<void> _deleteBlock(int chunkId) async {
    debugPrint('删除块: id=$chunkId');
  }

  Future<void> _updateBlock(_PendingBlock block) async {
    debugPrint('更新块: id=${block.chunkId}');
  }
}
