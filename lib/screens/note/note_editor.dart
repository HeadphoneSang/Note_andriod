import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/screens/note/widgets/table_toolbar_items.dart';
import 'package:note_for_android/utils/toast_util.dart';

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
  late final IncrementalSaveService _saveService;
  bool _isSaving = false;
  StreamSubscription? _txSub;
  Selection? _lastSelection;

  @override
  void initState() {
    super.initState();
    _editorState = EditorState.blank(withInitialText: true);

    _saveService = IncrementalSaveService(
      editorState: _editorState,
      titleCtrl: _titleCtrl,
      provideNotebookId: () => widget.notebookId,
      provideContext: () => context,
      notebookId: widget.notebookId,
    );

    _txSub = _editorState.transactionStream.listen((event) {
      final (time, transaction, _) = event;
      if (time != TransactionTime.after) return;
      for (final op in transaction.operations) {
        _saveService.dispatch(op);
      }
    });

    _editorState.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _editorState.selectionNotifier.removeListener(_onSelectionChanged);
    _saveService.cancelDebounce();
    _txSub?.cancel();
    _editorState.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    setState(() {
      _lastSelection = _editorState.selectionNotifier.value;
    });
  }

  /// 当前是否选中了文本
  bool get _hasSelection =>
      _lastSelection != null && !_lastSelection!.isCollapsed;

  void _copySelection() {
    final text = _editorState.selectionService.currentSelectedNodes
        .map((n) => n.delta?.toPlainText() ?? '')
        .join('\n');
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ToastUtil.success(context, title: '已复制');
    }
  }

  void _cutSelection() {
    _copySelection();
    _editorState.deleteSelection(_lastSelection!);
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;

    final selection = _editorState.selection;
    if (selection == null) return;

    // 有选中文本时先删除选中内容，再粘贴
    if (!selection.isCollapsed) {
      await _editorState.deleteSelection(selection);
    }
    await _editorState.insertTextAtCurrentSelection(text);
  }

  void _selectAll() {
    final doc = _editorState.document;
    if (doc.root.children.isEmpty) return;
    final lastNode = doc.root.children.last;
    _editorState.updateSelectionWithReason(
      Selection(
        start: Position(path: [0], offset: 0),
        end: Position(
          path: [doc.root.children.length - 1],
          offset: lastNode.delta?.length ?? 0,
        ),
      ),
      reason: SelectionUpdateReason.selectAll,
    );
  }

  /// 长按空白处：插入一个新段落并粘贴

  /// 构建浮动工具栏，定位在选中区域上方
  Widget _buildFloatingToolbar() {
    final rects = _editorState.selectionService.selectionRects;
    double top = 8;
    if (rects.isNotEmpty) {
      top = rects.first.topLeft.dy - 50;
    }
    if (top < 0) top = 8;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          color: Colors.grey.shade800,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _contextMenuButton(Icons.content_copy, '复制', _copySelection),
              _contextMenuButton(Icons.content_cut, '剪切', _cutSelection),
              _contextMenuButton(Icons.content_paste, '粘贴', _pasteClipboard),
              _contextMenuButton(Icons.select_all_rounded, '全选', _selectAll),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contextMenuButton(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── 保存 ──

  Future<void> _saveNote() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ToastUtil.warning(context, title: '请输入标题');
      return;
    }
    if (!_saveService.haveTotalChange) {
      ToastUtil.warning(context, title: '没有任何修改');
      return;
    }
    await _saveService.flush();

    if (_saveService.noteId == null) {
      if (!mounted) return;
      ToastUtil.error(context, title: '保存失败');
      return;
    }
  }

  // ── 下拉刷新 ──
  Future<void> _onRefresh() async {
    // TODO: 实现刷新逻辑
  }
  void _showNoteInfoSheet(BuildContext context) {
    final summaryCtrl = TextEditingController(
      text: _saveService.currentNoteInfo?.summary ?? "",
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "笔记信息",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 摘要
              const Text(
                "摘要",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: summaryCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: "添加摘要...",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(8),
                ),
              ),
              const SizedBox(height: 16),
              // 标签
              const Text(
                "标签",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ...(_saveService.currentNoteInfo?.tags ?? []).map((tag) {
                    return Chip(
                      label: Text(
                        tag.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {},
                    );
                  }),
                  ActionChip(
                    label: const Text("+ 添加标签", style: TextStyle(fontSize: 12)),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // TODO: 保存摘要和标签
                    Navigator.pop(ctx);
                  },
                  child: const Text("保存"),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建笔记'),
        actions: [
          if (_saveService.noteId != null)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: () => _showNoteInfoSheet(context),
            ),
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
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      hintText: '标题',
                      hintStyle: TextStyle(
                        color: Color.fromARGB(255, 145, 145, 145),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
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
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
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
            // ── 浮动工具栏（选中文本时显示在选中位置上方） ──
            if (_hasSelection) _buildFloatingToolbar(),

            // ── 右下角上传动画 ──
            ValueListenableBuilder<bool>(
              valueListenable: _saveService.isFlushingNotifier,
              builder: (context, isFlushing, _) {
                return AnimatedOpacity(
                  opacity: isFlushing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 16),
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            // ── 最近保存时间 ──
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ValueListenableBuilder<DateTime?>(
                  valueListenable: _saveService.lastSavedTime,
                  builder: (context, time, _) {
                    if (time == null) return SizedBox.shrink();
                    final formatted =
                        time.hour.toString().padLeft(2, '0') +
                        ':' +
                        time.minute.toString().padLeft(2, '0') +
                        ':' +
                        time.second.toString().padLeft(2, '0');
                    return Text(
                      '最近一次保存: ' + formatted,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
