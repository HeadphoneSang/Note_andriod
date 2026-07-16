import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/models/node_change_event.dart';
import 'package:note_for_android/screens/note/widgets/table_toolbar_items.dart';
import 'package:provider/provider.dart';
import '../../core/store/user_store.dart';
import '../../models/note.dart';

/// 新建笔记页面 — 从底部弹出
class NoteEditor extends StatefulWidget {
  final int? notebookId;

  const NoteEditor({super.key, this.notebookId});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _titleCtrl = TextEditingController();
  late final EditorState _editorState;
  late final _tableInsertItem = createTableInsertToolbarItem();
  late final _tableActionItem = createTableActionToolbarItem();
  bool _isSaving = false;
  bool _isDirty = false;
  bool _isFlushing = false;
  StreamSubscription? _txSub;

  int? _noteId; // 创建成功后由后端返回

  // ── 防抖增量保存 ──

  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 1500);

  /// 节点 id(nanoid) → 待同步的块数据
  final Map<String, _PendingBlock> _pending = {};

  @override
  void initState() {
    super.initState();
    _editorState = EditorState.blank(withInitialText: true);

    _txSub = _editorState.transactionStream.listen((event) {
      final (time, transaction, options) = event;
      if (time != TransactionTime.after) return;

      _isDirty = true;

      for (final op in transaction.operations) {
        _dispatch(op);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _txSub?.cancel();
    _editorState.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── 事件分发 ──

  void _dispatch(Operation op) {
    switch (op) {
      case InsertOperation():
        for (final node in op.nodes) {
          _onInsert(
            NodeChangeEvent(
              changeType: NodeChangeType.insert,
              node: node,
              editorState: _editorState,
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
              editorState: _editorState,
              operation: op,
            ),
          );
        }
      case UpdateTextOperation():
        final node = _editorState.document.nodeAtPath(op.path);
        if (node == null) break;
        _onUpdateText(
          NodeChangeEvent(
            changeType: NodeChangeType.updateText,
            node: node,
            editorState: _editorState,
            operation: op,
          ),
        );
      case UpdateOperation():
        final node = _editorState.document.nodeAtPath(op.path);
        if (node == null) break;
        _onUpdateAttr(
          NodeChangeEvent(
            changeType: NodeChangeType.updateAttr,
            node: node,
            editorState: _editorState,
            operation: op,
          ),
        );
    }
  }

  void _onInsert(NodeChangeEvent event) {
    debugPrint('$event');
    if (event.isSubNode) {
      return _onUpdateAttr(event);
    }
    // 已有 ID 的块（如从其他笔记复制来的）→ PUT 更新，否则标记为新增
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: event.chunkOrderKey,
      changeType: event.chunkId != null
          ? NodeChangeType.updateAttr
          : NodeChangeType.insert,
    );
    _debounce();
  }

  void _onDelete(NodeChangeEvent event) {
    debugPrint('$event');
    if (event.isSubNode) {
      return _onUpdateAttr(event);
    }
    // 标记删除，即使 chunkId 为 null（新建后未保存就删除）也要记录
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      changeType: NodeChangeType.delete,
    );
    _debounce();
  }

  void _onUpdateText(NodeChangeEvent event) {
    debugPrint('$event');
    // 新块还没 ID → 按 insert 处理
    if (event.chunkId == null) {
      _onInsert(event);
      return;
    }
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: event.chunkOrderKey,
      changeType: NodeChangeType.updateText,
      version: event.chunkVersion,
    );
    _debounce();
  }

  void _onUpdateAttr(NodeChangeEvent event) {
    debugPrint('$event');
    if (event.chunkId == null) {
      _onInsert(event);
      return;
    }
    // 已经有 pending 记录且是 insert → 保持 insert 状态
    final existing = _pending[event.nodeId];
    if (existing != null && existing.changeType == NodeChangeType.insert) {
      return;
    }
    _pending[event.nodeId] = _PendingBlock(
      nodeId: event.nodeId,
      chunkId: event.chunkId,
      type: event.type,
      deltaJson: _extractDeltaJson(event.node),
      orderKey: event.chunkOrderKey,
      changeType: NodeChangeType.updateAttr,
      version: event.chunkVersion,
    );
    _debounce();
  }

  /// 从 Node 提取完整 delta JSON
  String _extractDeltaJson(Node node) {
    final delta = node.attributes[blockComponentDelta];
    return jsonEncode(
      delta ??
          [
            {'insert': '\n'},
          ],
    );
  }

  // ── 防抖 ──

  void _debounce() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _flushPending);
  }

  /// 将累积的待同步变更发送到后端
  Future<void> _flushPending() async {
    debugPrint("提交修改");
    if (_pending.isEmpty || _isFlushing) return;
    _isFlushing = true;

    // 还没有笔记 ID → 先自动创建笔记，拿到 _noteId
    if (_noteId == null) {
      try {
        final userId = context.read<UserStore>().user?.id;
        if (userId == null) throw Exception('用户未登录');

        final title = _titleCtrl.text.trim();
        final response = await HttpClient.instance.post<Map<String, dynamic>>(
          '/note',
          data: {
            'title': title.isNotEmpty ? title : '未命名笔记',
            'userId': userId,
            'notebookId': widget.notebookId,
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
        return; // 本次不提交块变更，下次防抖重试
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
              if (block.chunkId != null) {
                await _deleteBlock(block.chunkId!);
              }
            case NodeChangeType.updateText:
            case NodeChangeType.updateAttr:
              if (block.chunkId != null) {
                await _updateBlock(block);
              }
          }
        } catch (e) {
          debugPrint('同步失败: ${block.nodeId} → $e');
          _pending[entry.key] = block;
        }
      }
    } finally {
      _isFlushing = false;
      if (_pending.isNotEmpty) {
        _debounce();
      }
    }
  }

  Future<void> _createBlock(_PendingBlock block) async {
    // TODO: 替换为实际 API
    // final resp = await HttpClient.instance.post<Map<String, dynamic>>(
    //   '/blocks',
    //   data: {
    //     'noteId': _noteId,
    //     'type': block.type,
    //     'deltaJson': block.deltaJson,
    //     'orderKey': block.orderKey,
    //   },
    // );
    // if (resp.code == 200 && resp.data != null) {
    //   // 把后端返回的 ID 写回 Node 的 attributes，下次修改就知道是已有块了
    //   final node = _editorState.document.nodeAtPath([...]);
    //   node?.attributes[NoteDocumentConvert.attrBlockId] = resp.data!['id'];
    //   node?.attributes[NoteDocumentConvert.attrBlockVersion] = resp.data!['version'];
    // }
    debugPrint('创建块: ${block.type}');
  }

  Future<void> _deleteBlock(int chunkId) async {
    // TODO: DELETE /blocks/$chunkId
    debugPrint('删除块: id=$chunkId');
  }

  Future<void> _updateBlock(_PendingBlock block) async {
    // TODO: PUT /blocks/${block.chunkId}
    // data: { type, deltaJson, orderKey, version(乐观锁) }
    debugPrint('更新块: id=${block.chunkId}');
  }

  // ── 保存 ──

  Future<void> _saveNote() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题'), backgroundColor: Colors.orange),
      );
      return;
    }

    // 先等防抖提交所有待同步变更（如果还没创建笔记，会自动创建）
    _debounceTimer?.cancel();
    await _flushPending();

    if (_noteId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存失败'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 更新标题
      final response = await HttpClient.instance.put<Map<String, dynamic>>(
        '/note/$_noteId',
        data: {'title': title},
      );
      if (response.code == 200 && response.data != null) {
        final note = Note.fromJson(response.data!);
        if (!mounted) return;
        Navigator.pop(context, note);
      } else {
        throw Exception(response.message ?? '保存失败');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建笔记'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _saveNote,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                hintText: '标题',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  MobileToolbar(
                    editorState: _editorState,
                    toolbarItems: [
                      textDecorationMobileToolbarItem,
                      headingMobileToolbarItem,
                      blocksMobileToolbarItem,
                      listMobileToolbarItem,
                      todoListMobileToolbarItem,
                      codeMobileToolbarItem,
                      quoteMobileToolbarItem,
                      dividerMobileToolbarItem,
                      linkMobileToolbarItem,
                      _tableInsertItem,
                      _tableActionItem,
                      buildTextAndBackgroundColorMobileToolbarItem(),
                    ],
                  ),
                  Expanded(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 3.0,
                      child: AppFlowyEditor(
                        editorState: _editorState,
                        editorStyle: const EditorStyle.mobile(
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 待同步的块变更
class _PendingBlock {
  final String nodeId;
  final int? chunkId;
  final String? type;
  final String? deltaJson;
  final String? orderKey;
  final NodeChangeType changeType;
  final double version;

  const _PendingBlock({
    required this.nodeId,
    this.chunkId,
    this.type,
    this.deltaJson,
    this.orderKey,
    required this.changeType,
    this.version = 1.0,
  });
}
