import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_for_android/models/notebook.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/screens/note/mixins/tag_service.dart';
import 'package:note_for_android/screens/note/widgets/floating_toolbar.dart';
import 'package:note_for_android/screens/note/widgets/note_info_sheet.dart';
import 'package:note_for_android/screens/note/widgets/notebook_sheet.dart';
import 'package:note_for_android/screens/note/widgets/save_status_overlay.dart';
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
  late final TagService _tagService;
  bool _isSaving = false;
  bool _isRefreshing = false;
  bool _isLoadingNoteInfo = false;
  StreamSubscription? _txSub;
  Selection? _lastSelection;
  late List<Notebook>? _notebookAbList = [];
  int? _selectedNotebookId;

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
    _saveService.onFlushCompleted = () {
      if (mounted) setState(() {});
    };

    _tagService = TagService(
      provideNotebookId: () => widget.notebookId,
      provideContext: () => context,
      noteIdProvider: () => _saveService.noteId,
    );
    _tagService.onFlushCompleted = () {
      if (mounted) setState(() {});
    };

    _txSub = _editorState.transactionStream.listen((event) {
      final (time, transaction, _) = event;
      if (time != TransactionTime.after) return;
      for (final op in transaction.operations) {
        _saveService.dispatch(op);
      }
    });

    _editorState.selectionNotifier.addListener(_onSelectionChanged);
    _selectedNotebookId = widget.notebookId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      _saveService
          .tryLoadAllNotebooks()
          .then((abList) {
            _notebookAbList =
                [
                  Notebook.fromJson({"id": -1, "name": "全部笔记"}),
                ] +
                abList;
          })
          .onError<Exception>((error, stackTrace) {
            if (mounted) {
              ToastUtil.error(context, title: "网络错误", description: "笔记本列表加载失败");
            }
          })
          .whenComplete(() {
            if (mounted) {
              Navigator.of(context).pop();
              setState(() {});
            }
          });
    });
  }

  @override
  void dispose() {
    _editorState.selectionNotifier.removeListener(_onSelectionChanged);
    _saveService.cancelDebounce();
    _tagService.cancelDebounce();
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

  bool get _hasSelection =>
      _lastSelection != null && !_lastSelection!.isCollapsed;

  // ── 剪贴板操作 ──

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

  // ── 保存 & 刷新 ──

  Future<void> _saveNote() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ToastUtil.warning(context, title: '请输入标题');
      return;
    }
    if (!_saveService.haveTotalChange && !_tagService.hasPendingChanges) {
      ToastUtil.warning(context, title: '没有任何修改');
      return;
    }
    await _saveService.flush();
    await _tagService.flush();

    if (_saveService.noteId == null) {
      if (!mounted) return;
      ToastUtil.error(context, title: '保存失败');
      return;
    }
  }

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await _saveService.flush();
      await _tagService.flush();
    } catch (_) {}
    try {
      if (!await _saveService.tryLoadNote()) return;
      if (!await _saveService.tryLoadChunks()) return;
      if (_saveService.noteId != null) {
        await _tagService.tryLoadTags();
      }
      if (mounted) {
        ToastUtil.success(
          context,
          title: "刷新成功",
          description: "内容已更新",
          alignment: AlignmentGeometry.bottomRight,
        );
      }
    } catch (e, stackTrace) {
      debugPrint("$e");
      debugPrint("$stackTrace");
      if (mounted) ToastUtil.error(context, title: "网络错误", description: "刷新失败");
    } finally {
      _isRefreshing = false;
      if (mounted) Navigator.of(context).pop();
      if (mounted) setState(() {});
    }
  }

  Future<void> _reloadNotebooks() async {
    try {
      final abList = await _saveService.tryLoadAllNotebooks();
      if (!mounted) return;
      setState(() {
        _notebookAbList =
            [
              Notebook.fromJson({"id": null, "name": "全部笔记"}),
            ] +
            abList;
      });
    } catch (e) {
      debugPrint("加载笔记本列表失败: $e");
    }
  }

  // ── UI 辅助 ──

  String _formatDate(DateTime? date) {
    if (date == null) return "-";
    return "${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")} ${date.hour.toString().padLeft(2, "0")}:${date.minute.toString().padLeft(2, "0")}";
  }

  int get _wordCount {
    int count = 0;
    for (final node in _editorState.document.root.children) {
      count += node.delta?.toPlainText().length ?? 0;
    }
    return count;
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ── Sheet 入口 ──

  void _openNoteInfoSheet() async {
    if (_isLoadingNoteInfo) return;
    _isLoadingNoteInfo = true;
    try {
      await _tagService.tryLoadTags();
      await _tagService.tryLoadAllUserTags();
      if (!mounted) return;
      _isLoadingNoteInfo = false;
      await showNoteInfoSheet(
        context: context,
        tagService: _tagService,
        saveService: _saveService,
        initialSummary: _saveService.currentNoteInfo?.summary ?? "",
      );
    } finally {
      _isLoadingNoteInfo = false;
    }
  }

  void _openNotebookSheet() {
    if (_notebookAbList == null) return;
    showNotebookSheet(
      context: context,
      saveService: _saveService,
      selectedNotebookId: _selectedNotebookId,
      allNotebooks: _notebookAbList!,
      onReloadNotebooks: _reloadNotebooks,
      onSelectedNotebookChanged: (id) {
        setState(() => _selectedNotebookId = id);
      },
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建笔记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isRefreshing ? null : _onRefresh,
          ),
          if (_saveService.noteId != null)
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: _openNoteInfoSheet,
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
                _saveService.noteId != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            _infoChip(
                              Icons.access_time_rounded,
                              _formatDate(
                                _saveService.currentNoteInfo?.createdAt,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _infoChip(Icons.text_fields, _wordCount.toString()),
                            const SizedBox(width: 12),
                            SelectNotebookButton(
                              allNotebooks: _notebookAbList!,
                              selectedNotebookId: _selectedNotebookId,
                              onTap: _openNotebookSheet,
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            _infoChip(
                              Icons.access_time_rounded,
                              _formatDate(DateTime.now()),
                            ),
                            const SizedBox(width: 12),
                            _infoChip(Icons.text_fields, _wordCount.toString()),
                            const SizedBox(width: 12),
                            _notebookAbList != null
                                ? SelectNotebookButton(
                                    allNotebooks: _notebookAbList!,
                                    selectedNotebookId: _selectedNotebookId,
                                    onTap: _openNotebookSheet,
                                  )
                                : const SizedBox(width: 12),
                          ],
                        ),
                      ),
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
            if (_hasSelection)
              EditorFloatingToolbar(
                selectionRects: _editorState.selectionService.selectionRects,
                onCopy: _copySelection,
                onCut: _cutSelection,
                onPaste: _pasteClipboard,
                onSelectAll: _selectAll,
              ),
            SaveStatusOverlay(
              isFlushingNotifier: _saveService.isFlushingNotifier,
              lastSavedTime: _saveService.lastSavedTime,
            ),
            if (_isLoadingNoteInfo)
              Positioned.fill(
                child: Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
