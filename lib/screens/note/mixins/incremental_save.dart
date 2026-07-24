import 'dart:async';
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
  final Map<String, Object>? deltaJson;
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

/// 编辑器节点的元数据（不存储在 node.attributes 中，避免触发编辑器重建）
class _NodeMeta {
  String? chunkId;
  int version;
  String? orderKey;
  bool hasError;

  _NodeMeta({
    this.chunkId,
    this.version = 1,
    this.orderKey,
    this.hasError = false,
  });
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
    // 初始化元数据映射
    _initNodeMeta();
  }

  int? _noteId; // 当前服务对应的笔记的id
  bool _isFlushing = false; // 文本块防抖缓冲池锁
  bool _isUpdateTitle = false;
  Timer? _debounceTimer; // 防抖延迟网络请求计时器
  static const _debounceDuration = Duration(milliseconds: 3000); // 防抖的时间，单位是毫秒
  final Map<String, _PendingBlock> _pending = {}; //  防抖缓存

  /// 节点元数据映射，避免直接修改 node.attributes 触发编辑器重建
  final Map<String, _NodeMeta> _nodeMeta = {};

  /// 从 node.attributes 中读取初始元数据
  void _initNodeMeta() {
    for (final node in editorState.document.root.children) {
      _nodeMeta[node.id] = _NodeMeta(
        chunkId: node.attributes[NoteDocumentConvert.attrBlockId] as String?,
        version:
            (node.attributes[NoteDocumentConvert.attrBlockVersion] as num?)
                ?.toInt() ??
            1,
        orderKey:
            node.attributes[NoteDocumentConvert.attrBlockOrderKey] as String?,
      );
    }
  }

  // 清空并重新构建节点元数据（刷新时调用）
  void _resetNodeMeta(
    List<NoteBlock> blocks,
    Map<String, String> NoteToNodeMap,
  ) {
    _nodeMeta.clear();
    for (final block in blocks) {
      if (block.id == null) continue;
      final id = NoteToNodeMap[block.id];
      _nodeMeta[id!] = _NodeMeta(
        chunkId: block.id,
        version: block.version,
        orderKey: block.orderKey,
      );
    }
  }

  void _resetPending() {
    _pending.clear();
  }

  /// 获取节点的元数据，不存在则创建默认值
  _NodeMeta _metaFor(String nodeId) {
    return _nodeMeta.putIfAbsent(nodeId, () => _NodeMeta());
  }

  /// 上传状态通知器 — UI 监听此对象来显示/隐藏上传动画
  final isFlushingNotifier = ValueNotifier<bool>(false);

  /// 最近一次成功保存的时间
  ValueNotifier<DateTime?> lastSavedTime = ValueNotifier<DateTime?>(null);

  /// 当前笔记信息
  Note? get currentNoteInfo => _currentNoteInfo;

  // 就是Note本身是否有变化
  bool get haveTotalChange {
    return _isUpdateTitle || _pending.isNotEmpty;
  }

  /// 取消防抖定时器
  void cancelDebounce() => _debounceTimer?.cancel();

  /// 取消所有未完成的保存操作，清空缓存
  void cancelAll() {
    cancelDebounce();
    _isFlushing = false;
    isFlushingNotifier.value = false;
    _isUpdateTitle = false;
    _pending.clear();
  }

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
    _metaFor(rangeNode[mid].id).orderKey = orderKey;
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

    while (preNode != null && _metaFor(preNode.id).orderKey == null) {
      preNulls.add(preNode);
      preNode = preNode.previous;
    }
    startOrderKey = preNode == null ? null : _metaFor(preNode.id).orderKey;
    allNulls.addAll(preNulls.reversed);
    allNulls.add(event.rootNode!);

    while (nextNode != null && _metaFor(nextNode.id).orderKey == null) {
      allNulls.add(nextNode);
      nextNode = nextNode.next;
    }
    endOrderKey = nextNode == null ? null : _metaFor(nextNode.id).orderKey;

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
    final meta = _metaFor(event.nodeId);
    if (meta.orderKey == null) {
      _assignOrderKeyForRange(event);
    }
    // 不在这里生成 UUID，延迟到 _buildDiff 发送请求时再生成
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: meta.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: meta.orderKey,
      changeType: meta.chunkId != null
          ? NodeChangeType.updateAttr
          : NodeChangeType.insert,
      version: meta.version,
    );
    debugPrint('↑↑↑↑↑插入事件入队↑↑↑↑↑');
    _debounce();
  }

  void _onDelete(NodeChangeEvent event) {
    _metaFor(event.nodeId).orderKey = null;
    if (event.isSubNode) {
      final rootNode = event.rootNode;
      if (rootNode == null) return;
      return _onUpdateAttr(
        event.copyWith(changeType: NodeChangeType.updateAttr, node: rootNode),
      );
    }
    // 节点从未上传过（chunkId == null），服务端无此节点，无需删除
    final meta = _metaFor(event.nodeId);
    if (meta.chunkId == null) {
      _pending.remove(event.nodeId);
      debugPrint('删除未上传节点: ${event.nodeId}，已忽略');
      return;
    }
    debugPrint('$event');
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: meta.chunkId,
      changeType: NodeChangeType.delete,
      version: meta.version,
    );
    debugPrint('↑↑↑↑删除事件入队↑↑↑↑↑');
    _debounce();
  }

  void _onUpdateText(NodeChangeEvent event) {
    if (event.isSubNode) {
      _onUpdateText(event.copyWith(node: event.rootNode));
      return;
    }
    final meta = _metaFor(event.nodeId);
    if (meta.chunkId == null) {
      _onInsert(event.copyWith(changeType: NodeChangeType.insert));
      return;
    }
    debugPrint('$event');
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: meta.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: meta.orderKey,
      changeType: NodeChangeType.updateText,
      version: meta.version,
    );
    debugPrint('↑↑↑↑↑更新文本事件入队↑↑↑↑↑');
    _debounce();
  }

  void _onUpdateAttr(NodeChangeEvent event) {
    if (event.isSubNode) {
      _onUpdateAttr(event.copyWith(node: event.rootNode));
      return;
    }
    final meta = _metaFor(event.nodeId);
    if (meta.chunkId == null) {
      _onInsert(event.copyWith(changeType: NodeChangeType.insert));
      return;
    }
    debugPrint('$event');
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: meta.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: meta.orderKey,
      changeType: NodeChangeType.updateAttr,
      version: meta.version,
    );
    debugPrint('↑↑↑↑↑更新属性事件入队↑↑↑↑↑');
    _debounce();
  }

  /// 安全的节点序列化，先复制 attributes 再操作，避免触发编辑器 ChangeNotifier
  Map<String, Object> _extractDeltaJson(Node node) {
    return _nodeToJsonSafe(node);
  }

  /// 安全的节点序列化，先复制 attributes 再操作，避免触发编辑器 ChangeNotifier
  Map<String, Object> _nodeToJsonSafe(Node node) {
    final map = <String, Object>{'type': node.type};
    if (node.children.isNotEmpty) {
      map['children'] = node.children.map(_nodeToJsonSafe).toList();
    }
    if (node.attributes.isNotEmpty) {
      // 复制一份 attributes，避免 removeWhere 污染原始数据
      map['data'] = Map<String, dynamic>.from(node.attributes)
        ..removeWhere((_, value) => value == null);
    }
    return map;
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

  Future<bool> tryLoadChunks() async {
    try {
      final response = await HttpClient.instance.get(
        "/noteBlock/getBlocks",
        queryParameters: {"noteId": noteId},
      );
      if (response.code == 200 && response.data != null) {
        List<dynamic> blocksJson = response.data;
        List<NoteBlock> blocks = blocksJson
            .map((json) => NoteBlock.fromJson(json))
            .toList();
        // 构建新文档
        Document newDoc = NoteDocumentConvert.toDocument(blocks);
        // 用事务替换当前文档内容
        final transaction = Transaction(document: editorState.document);
        // 删除所有现有节点
        for (
          int i = editorState.document.root.children.length - 1;
          i >= 0;
          i--
        ) {
          transaction.deleteNode(editorState.document.root.children[i]);
        }
        // 插入新节点
        for (final node in newDoc.root.children) {
          transaction.insertNode([
            editorState.document.root.children.length,
          ], node);
        }
        await editorState.apply(transaction);
        // 构建新的文档中的chunkId2NodeIdMap
        final Map<String, String> chunkId2NodeIdMap = {};
        for (var node in editorState.document.root.children) {
          chunkId2NodeIdMap[node.attributes[NoteDocumentConvert.attrBlockId]] =
              node.id;
        }
        // 清空_nodeMeta，根据获得的blocks重新构建新的_nodeMeta
        _resetNodeMeta(blocks, chunkId2NodeIdMap);
        // 清空_pending，防止触发更新。
        _resetPending();
        return true;
      } else {
        if (provideContext().mounted) {
          ToastUtil.error(
            provideContext(),
            title: "加载错误",
            description: response.message,
          );
        }
        return false;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> tryLoadNote() async {
    try {
      final response = await HttpClient.instance.get<Map<String, dynamic>>(
        '/note/getNote',
        queryParameters: {"noteId": _noteId},
      );
      if (response.code == 200 && response.data != null) {
        final currentNote = Note.fromJson(response.data!);
        _currentNoteInfo = currentNote;
        return true;
      } else {
        ToastUtil.error(
          provideContext(),
          title: "网络错误",
          description: response.message,
        );
        return false;
      }
    } catch (e) {
      rethrow;
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
        lastSavedTime.value = DateTime.now();
        print(_currentNoteInfo);
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
        _metaFor(node.id).orderKey = pending.orderKey;
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
        lastSavedTime.value = DateTime.now();
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
          lastSavedTime.value = DateTime.now();
        }
        return !result.hasConflict;
      } else if (response.code == 409) {
        // 版本冲突，全部失败
        for (final entry in batch.entries) {
          final block = entry.value;
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

  /// 将成功块的版本号 +1
  void _updateBlockVersion(String nodeId, _PendingBlock block) {
    block.version++;
    _metaFor(nodeId).version = block.version;
  }

  /// 将新块生成的 UUID 持久化到元数据，后续事件可引用
  void _persistChunkId(String nodeId, _PendingBlock block) {
    if (block.chunkId == null) return;
    _metaFor(nodeId).chunkId = block.chunkId;
  }

  /// 标记/清除编辑器节点的错误状态
  void _markNodeError(String nodeId, bool hasError) {
    _metaFor(nodeId).hasError = hasError;
    // 同步到编辑器节点属性，触发视觉渲染
    _updateNodeAttribute(nodeId, {'chunkError': hasError});
  }

  /// 按 nodeId 查找编辑器节点并更新属性
  void _updateNodeAttribute(String nodeId, Map<String, dynamic> attrs) {
    final idx = editorState.document.root.children.indexWhere(
      (n) => n.id == nodeId,
    );
    if (idx < 0) return;
    final node = editorState.document.nodeAtPath([idx]);
    if (node != null) {
      node.updateAttributes(attrs);
    }
  }
}
