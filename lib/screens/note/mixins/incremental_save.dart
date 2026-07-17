import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/editor/note_document_convert.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/core/store/user_store.dart';
import 'package:note_for_android/models/node_change_event.dart';
import 'package:note_for_android/models/note.dart';
import 'package:note_for_android/models/note_block.dart';
import 'package:note_for_android/models/note_diff.dart';
import 'package:note_for_android/utils/toast_util.dart';
import 'package:provider/provider.dart';

/// 待同步的块变更
class _PendingBlock {
  final String nodeId;
  final int? chunkId;
  final String? type;
  final String? deltaJson;
  String? orderKey;
  final NodeChangeType changeType;
  final int version;

  _PendingBlock({
    required this.nodeId,
    this.chunkId,
    this.type,
    this.deltaJson,
    this.orderKey,
    required this.changeType,
    this.version = 1,
  });

  NoteBlock toNoteBlock(int noteId) {
    return NoteBlock(
      id: chunkId,
      noteId: noteId,
      type: type,
      createdAt: null,
      updatedAt: null,
      orderKey: orderKey,
      deltaJson: deltaJson,
      version: version,
    );
  }
}

/// 增量保存服务 — 处理事件分发、防抖、块级 CRUD
class IncrementalSaveService {
  final EditorState editorState;
  final TextEditingController titleCtrl;
  final int? Function() provideNotebookId;
  final BuildContext Function() provideContext;
  final int? notebookId;
  Note? _currentNoteInfo; // 当前持有的Note的信息，包含了Note的版本号

  IncrementalSaveService({
    required this.editorState,
    required this.titleCtrl,
    required this.provideNotebookId,
    required this.provideContext,
    required this.notebookId,
  }) {
    titleCtrl.addListener(() {
      _isUpdateTitle = true;
      _debounce();
    });
  }

  int? _noteId; // 当前服务对应的笔记的id
  bool _isFlushing = false; // 文本块防抖缓冲池锁
  bool _isUpdateTitle = false;
  Timer? _debounceTimer; // 防抖延迟网络请求计时器
  static const _debounceDuration = Duration(milliseconds: 5000); // 防抖的时间，单位是毫秒
  final Map<String, _PendingBlock> _pending = {}; //  防抖缓存

  /// 上传状态通知器 — UI 监听此对象来显示/隐藏上传动画
  final isFlushingNotifier = ValueNotifier<bool>(false);

  // 就是Note本身是否有变化
  bool get haveTotalChange {
    return _isUpdateTitle || _pending.isNotEmpty;
  }

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
    // rangeNode[mid].attributes[NoteDocumentConvert.attrBlockOrderKey] = orderKey;
    rangeNode[mid].updateAttributes({
      NoteDocumentConvert.attrBlockOrderKey: orderKey,
    });
    debugPrint("给节点${rangeNode[mid].path}分配的OrderKey $orderKey");
    debugPrint("${rangeNode[mid]}");
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
    debugPrint('${event.rootNode}');
    if (_noteId != null && event.chunkOrderKey == null) {
      _assignOrderKeyForRange(event);
    }
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: event.chunkOrderKey,
      changeType: event.chunkId != null
          ? NodeChangeType.updateAttr
          : NodeChangeType.insert,
      version: event.chunkVersion,
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
      version: event.chunkVersion,
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

  /// 从当前内存读一份最新的笔记信息快照，然后阻塞上传保存
  Future<void> _flushPending() async {
    if (!haveTotalChange || _isFlushing) return;
    // 加标志位，并发控制
    _isFlushing = true;
    isFlushingNotifier.value = true;
    final flushStopwatch = Stopwatch()..start();
    // 记录当前需要保存的所有信息的快照
    final batch = _pending.isNotEmpty
        ? Map<String, _PendingBlock>.from(_pending)
        : {};
    _pending.clear();
    final snapTitle = titleCtrl.text.trim();
    bool needUpdateTitle = _isUpdateTitle;
    _isUpdateTitle = false;
    try {
      if (_noteId == null) {
        try {
          final Note note = Note.fromJson({
            "title": snapTitle,
            "id": null,
            "notebookId": notebookId,
          });
          final response = await HttpClient.instance.post<Map<String, dynamic>>(
            '/note/create',
            data: note.toJson(),
          );
          if (response.code == 200 && response.data != null) {
            Note responseNote = Note.fromJson(response.data!);
            _noteId = responseNote.id;
            _currentNoteInfo = responseNote;
            print(_currentNoteInfo);
            ToastUtil.success(
              provideContext(),
              title: "创建成功",
              description: "笔记: $snapTitle",
            );
            needUpdateTitle = false;
          } else {
            throw Exception(response.message ?? '创建笔记失败');
          }
        } catch (e) {
          debugPrint('创建笔记失败: $e');
          _isUpdateTitle = true;
          return;
        }
        // 因为是刚创建的笔记，所以直接给所有的块分配orderKey就行
        if (batch.isEmpty) return;
        int i = 0;
        for (final node in editorState.document.root.children) {
          final pending = batch[node.id];
          if (pending != null && pending.orderKey == null) {
            pending.orderKey = NoteDocumentConvert.orderKeyForIndex(i);
            node.updateAttributes({
              NoteDocumentConvert.attrBlockOrderKey: pending.orderKey,
            });
            print(node);
          }
          i++;
        }
      }
      //更新笔记的标题
      if (needUpdateTitle) {
        try {
          final response = await HttpClient.instance.post<Map<String, dynamic>>(
            '/note/title',
            queryParameters: {
              "noteId": _currentNoteInfo!.id,
              "title": snapTitle,
              "version": _currentNoteInfo!.version,
            },
          );
          if (response.code == 200 && response.data != null) {
            _currentNoteInfo = Note.fromJson(response.data!);
            ToastUtil.success(
              provideContext(),
              title: "保存成功",
              description: "标题已更改为:$snapTitle",
              alignment: AlignmentGeometry.bottomRight,
            );
          } else if (response.code == 409) {
            //修改标题冲突
            ToastUtil.warning(
              provideContext(),
              title: "保存失败",
              description: "有用户修改了内容，请刷新后重试!",
              alignment: AlignmentGeometry.bottomRight,
            );
            _isUpdateTitle = true;
            return;
          } else {
            ToastUtil.warning(
              provideContext(),
              title: "保存失败",
              description: "网络错误：${response.message}",
              alignment: AlignmentGeometry.bottomRight,
            );
            _isUpdateTitle = true;
            return;
          }
        } catch (e) {
          ToastUtil.error(
            provideContext(),
            title: "网络请求错误",
            description: "标题保存失败",
            alignment: AlignmentGeometry.bottomRight,
          );
        }
      }
      debugPrint("准备处理增量更新");
      // 更新笔记内容
      if (batch.isEmpty) return;
      final diff = NoteBlockDiff(); //最后要提交的更新
      // 预热增量更新列表
      for (final entry in batch.entries) {
        _PendingBlock block = entry.value;
        try {
          switch (block.changeType) {
            case NodeChangeType.insert:
              diff.addInsertBlocks(block.toNoteBlock(_noteId!));
            case NodeChangeType.delete:
              diff.addDeleteBlocks(block.toNoteBlock(_noteId!));
            case NodeChangeType.updateText:
            case NodeChangeType.updateAttr:
              diff.addUpdateBlock(block.toNoteBlock(_noteId!));
          }
        } catch (e) {
          debugPrint('同步预处理阶段失败: ${block.nodeId} → $e');
          _pending[entry.key] = block;
        }
      }
      // 将增量更新提交到后端服务
      debugPrint('${diff.toJson()}');
    } finally {
      // 保证动画至少显示 600ms，让用户能感知到
      final elapsed = flushStopwatch.elapsedMilliseconds;
      if (elapsed < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsed));
      }
      _isFlushing = false;
      isFlushingNotifier.value = false;
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
