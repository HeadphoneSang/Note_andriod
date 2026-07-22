import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/editor/note_document_convert.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/models/node_change_event.dart';
import 'package:note_for_android/models/note.dart';
import 'package:note_for_android/models/note_block.dart';
import 'package:note_for_android/models/note_diff.dart';
import 'package:note_for_android/models/note_diff_result.dart';
import 'package:note_for_android/utils/toast_util.dart';
import 'package:uuid/uuid.dart';

/// 待同步的块变更
class _PendingBlock {
  final String nodeId;
  String? chunkId;
  final String? type;
  final String? deltaJson;
  String? orderKey;
  final NodeChangeType changeType;
  int version;

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
  static const _debounceDuration = Duration(milliseconds: 2000); // 防抖的时间，单位是毫秒
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
    if (event.chunkOrderKey == null) {
      _assignOrderKeyForRange(event);
    }
    // 不在这里生成 UUID，延迟到 _buildDiff 发送请求时再生成
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
    event.node.updateAttributes({NoteDocumentConvert.attrBlockOrderKey: null});
    if (event.isSubNode) {
      final rootNode = event.rootNode;
      if (rootNode == null) return;
      return _onUpdateAttr(
        event.copyWith(changeType: NodeChangeType.updateAttr, node: rootNode),
      );
    }
    // 节点从未上传过（chunkId == null），服务端无此节点，无需删除
    if (event.chunkId == null) {
      _pending.remove(event.nodeId);
      debugPrint('删除未上传节点: ${event.nodeId}，已忽略');
      return;
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
    if (event.isSubNode) {
      _onUpdateText(event.copyWith(node: event.rootNode));
      return;
    }
    if (event.chunkId == null) {
      _onInsert(event.copyWith(changeType: NodeChangeType.insert));
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
    if (event.isSubNode) {
      _onUpdateAttr(event.copyWith(node: event.rootNode));
      return;
    }
    if (event.chunkId == null) {
      _onInsert(event.copyWith(changeType: NodeChangeType.insert));
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

  /// 将编辑器节点（含子节点）序列化为 JSON 字符串
  String _extractDeltaJson(Node node) {
    return jsonEncode(node.toJson());
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
    final Map<String, _PendingBlock> batch = _pending.isNotEmpty
        ? Map<String, _PendingBlock>.from(_pending)
        : {};
    _pending.clear();
    final snapTitle = titleCtrl.text.trim();
    bool needUpdateTitle = _isUpdateTitle;
    _isUpdateTitle = false;
    bool flushSucceeded = false;
    try {
      // ── ① 创建笔记（首次保存时） ──
      if (_noteId == null) {
        if (snapTitle.isEmpty) {
          ToastUtil.warning(
            provideContext(),
            title: "自动保存",
            description: "请输入有效的标题",
          );
          return;
        }
        if (!await _tryCreateNote(snapTitle)) return;
        needUpdateTitle = false;
        // 刚创建的笔记，直接给所有块分配 orderKey
        if (batch.isEmpty) return;
        _assignOrderKeys(batch);
      }

      // ── ② 更新笔记标题 ──
      if (needUpdateTitle) {
        if (!await _tryUpdateTitle(snapTitle)) return;
      }

      // ── ③ 构建增量更新并提交 ──
      debugPrint("准备处理增量更新");
      if (batch.isEmpty) return;
      final diff = _buildDiff(batch);
      // 将增量更新提交到后端服务
      debugPrint('${diff.toJson()}');
      debugPrint("$diff");
      flushSucceeded = await _tryUpdateNoteDiff(diff, batch);
    } finally {
      if (!flushSucceeded) {
        // 保存失败，恢复缓存区，等下次 debounce 重试
        for (final entry in batch.entries) {
          _pending.putIfAbsent(entry.key, () => entry.value);
        }
        // _debounce();
      }
      // 保证动画至少显示 600ms，让用户能感知到
      final elapsed = flushStopwatch.elapsedMilliseconds;
      if (elapsed < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsed));
      }
      _isFlushing = false;
      isFlushingNotifier.value = false;
    }
  }

  /// 创建笔记，成功返回 true
  Future<bool> _tryCreateNote(String title) async {
    try {
      final note = Note.fromJson({
        "title": title,
        "id": null,
        "notebookId": notebookId,
      });
      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/note/create',
        data: note.toJson(),
      );
      if (response.code == 200 && response.data != null) {
        final responseNote = Note.fromJson(response.data!);
        _noteId = responseNote.id;
        _currentNoteInfo = responseNote;
        print(_currentNoteInfo);
        ToastUtil.success(
          provideContext(),
          title: "创建成功",
          description: "笔记: $title",
        );
        return true;
      } else {
        throw Exception(response.message ?? '创建笔记失败');
      }
    } catch (e) {
      debugPrint('创建笔记失败: $e');
      _isUpdateTitle = true;
      return false;
    }
  }

  /// 为新创建的笔记分配 orderKey
  void _assignOrderKeys(Map<String, _PendingBlock> batch) {
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

  /// 更新笔记标题，成功返回 true
  Future<bool> _tryUpdateTitle(String title) async {
    try {
      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/note/title',
        queryParameters: {
          "noteId": _currentNoteInfo!.id,
          "title": title,
          "version": _currentNoteInfo!.version,
        },
      );
      if (response.code == 200 && response.data != null) {
        _currentNoteInfo = Note.fromJson(response.data!);
        ToastUtil.success(
          provideContext(),
          title: "保存成功",
          description: "标题已更改为:$title",
          alignment: AlignmentGeometry.bottomRight,
        );
        return true;
      } else if (response.code == 409) {
        ToastUtil.warning(
          provideContext(),
          title: "保存失败",
          description: "有用户修改了内容，请刷新后重试!",
          alignment: AlignmentGeometry.bottomRight,
        );
        _isUpdateTitle = true;
        return false;
      } else {
        ToastUtil.warning(
          provideContext(),
          title: "保存失败",
          description: "网络错误：${response.message}",
          alignment: AlignmentGeometry.bottomRight,
        );
        _isUpdateTitle = true;
        return false;
      }
    } catch (e) {
      ToastUtil.error(
        provideContext(),
        title: "网络请求错误",
        description: "标题保存失败",
        alignment: AlignmentGeometry.bottomRight,
      );
      return false;
    }
  }

  /// 从 batch 构建 NoteBlockDiff
  /// 新块（chunkId == null）在此时生成 UUID。
  NoteBlockDiff _buildDiff(Map<String, _PendingBlock> batch) {
    final diff = NoteBlockDiff();
    for (final entry in batch.entries) {
      final block = entry.value;
      try {
        // 新块在发送请求时才生成 UUID，避免提前占位影响事件转发
        if (block.chunkId == null) {
          block.chunkId = const Uuid().v4();
        }
        switch (block.changeType) {
          case NodeChangeType.insert:
            diff.addInsertBlocks(block.toNoteBlock(_noteId!), block.nodeId);
          case NodeChangeType.delete:
            diff.addDeleteBlocks(block.toNoteBlock(_noteId!), block.nodeId);
          case NodeChangeType.updateText:
          case NodeChangeType.updateAttr:
            diff.addUpdateBlock(block.toNoteBlock(_noteId!), block.nodeId);
        }
      } catch (e) {
        debugPrint('同步预处理阶段失败: ${block.nodeId} → $e');
        _pending.putIfAbsent(entry.key, () => block);
      }
    }
    return diff;
  }

  Future<bool> _tryUpdateNoteDiff(
    NoteBlockDiff diffBlock,
    Map<String, _PendingBlock> batch,
  ) async {
    // 构建 chunkId → nodeId / _PendingBlock 的映射，用于处理失败的块
    final failedChunkIds = <String>{};
    try {
      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/noteBlock/batchUpdate',
        data: diffBlock.toJson(),
      );
      if (response.code == 200 && response.data != null) {
        final result = NoteDiffResult.fromJson(response.data!);
        if (result.hasConflict) {
          // 有部分块保存失败
          failedChunkIds.addAll(result.failUpdateBlocks);
          failedChunkIds.addAll(result.failDeletedBlocks);
          failedChunkIds.addAll(result.failCreatedBlocks);

          // 将失败的块重新加入 pending 缓存，覆盖已有的
          for (final entry in batch.entries) {
            final block = entry.value;
            if (block.chunkId != null &&
                failedChunkIds.contains(block.chunkId)) {
              // 新块上传失败 → 清除 chunkId，下次重试时重新生成 UUID
              if (block.changeType == NodeChangeType.insert) {
                block.chunkId = null;
              }
              _pending[entry.key] = block;
              // 在编辑器中标记为红色高亮
              _markNodeError(entry.key, true);
            } else {
              // 成功块：更新/删除的版本号 +1，新插入的保持 1
              if (block.changeType != NodeChangeType.insert) {
                _updateBlockVersion(entry.key, block);
              }
              _persistChunkId(entry.key, block);
            }
          }
          // 提示用户刷新
          ToastUtil.warning(
            provideContext(),
            title: "部分保存失败",
            description: "有 ${failedChunkIds.length} 个块冲突，请刷新页面",
            alignment: AlignmentGeometry.bottomRight,
          );
        } else {
          // 全部成功 → 更新/删除的版本号 +1，新插入的保持 1，并持久化 UUID
          for (final entry in batch.entries) {
            if (entry.value.changeType != NodeChangeType.insert) {
              _updateBlockVersion(entry.key, entry.value);
            }
            _persistChunkId(entry.key, entry.value);
          }
          ToastUtil.success(
            provideContext(),
            title: "保存成功",
            description: "内容已保存",
            alignment: AlignmentGeometry.bottomRight,
          );
        }
        return !result.hasConflict;
      } else if (response.code == 409) {
        // 版本冲突，全部失败
        for (final entry in batch.entries) {
          final block = entry.value;
          // 新块上传失败 → 清除 chunkId
          if (block.changeType == NodeChangeType.insert) {
            block.chunkId = null;
          }
          _pending[entry.key] = block;
        }
        ToastUtil.warning(
          provideContext(),
          title: "保存失败",
          description: "版本冲突，请刷新页面",
          alignment: AlignmentGeometry.bottomRight,
        );
        return false;
      } else {
        throw Exception(response.message ?? '保存失败');
      }
    } catch (e) {
      ToastUtil.error(
        provideContext(),
        title: "网络请求错误",
        description: "保存失败",
        alignment: AlignmentGeometry.bottomRight,
      );
      return false;
    }
  }

  /// 将成功块的版本号 +1，并更新编辑器节点属性
  void _updateBlockVersion(String nodeId, _PendingBlock block) {
    block.version++;
    _updateNodeAttribute(nodeId, {
      NoteDocumentConvert.attrBlockVersion: block.version,
    });
  }

  /// 将新块生成的 UUID 持久化到编辑器节点属性，后续事件可引用
  void _persistChunkId(String nodeId, _PendingBlock block) {
    if (block.chunkId == null) return;
    _updateNodeAttribute(nodeId, {
      NoteDocumentConvert.attrBlockId: block.chunkId,
    });
  }

  /// 标记/清除编辑器节点的错误状态
  void _markNodeError(String nodeId, bool hasError) {
    _updateNodeAttribute(nodeId, {'chunkError': hasError});
  }

  /// 按 nodeId 查找编辑器节点并更新属性
  void _updateNodeAttribute(String nodeId, Map<String, dynamic> attrs) {
    final idx = editorState.document.root.children.indexWhere(
      (n) => n.id == nodeId,
    );
    if (idx < 0) return;
    final node = editorState.document.nodeAtPath([idx]);
    node?.updateAttributes(attrs);
  }
}
