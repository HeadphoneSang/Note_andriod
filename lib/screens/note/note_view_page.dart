import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_for_android/models/note.dart';
import 'package:note_for_android/models/notebook.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/screens/note/mixins/tag_service.dart';
import 'package:note_for_android/screens/note/widgets/floating_toolbar.dart';
import 'package:note_for_android/screens/note/widgets/keyboard_safe_toolbar.dart';
import 'package:note_for_android/screens/note/widgets/note_info_sheet.dart';
import 'package:note_for_android/screens/note/widgets/notebook_sheet.dart';
import 'package:note_for_android/screens/note/widgets/save_status_overlay.dart';
import 'package:note_for_android/screens/note/widgets/table_toolbar_items.dart';
import 'package:note_for_android/utils/toast_util.dart';

/// 查看/编辑已有笔记页面 — 列表点击进入，打开即编辑
///
/// 复用 NoteEditor 全部服务与子组件，仅通过 [IncrementalSaveService.existingNote]
/// 预设 noteId + Note 元信息，使增量保存直接走更新路径。
class NoteViewPage extends StatefulWidget {
  /// 完整 Note 对象（列表接口已返回，直接透传）
  final Note note;

  /// 来源笔记本（列表过滤用）
  final int? notebookId;

  const NoteViewPage({super.key, required this.note, this.notebookId});

  @override
  State<NoteViewPage> createState() => _NoteViewPageState();
}

class _NoteViewPageState extends State<NoteViewPage> {
  final _titleCtrl = TextEditingController();
  late final EditorState _editorState;
  late final _tableInsertItem = createTableInsertToolbarItem();
  late final _tableActionItem = createTableActionToolbarItem();
  late final IncrementalSaveService _saveService;
  late final TagService _tagService;
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isLoadingNoteInfo = false;
  bool _isDeleting = false;
  bool _allowPop = false;
  /// 下滑隐藏标题/信息栏，只留编辑内容
  bool _hideHeader = false;
  double _lastScrollOffset = 0;
  StreamSubscription? _txSub;
  Selection? _lastSelection;
  late List<Notebook>? _notebookAbList = [];
  int? _selectedNotebookId;
  late bool _isMarked;

  @override
  void initState() {
    super.initState();
    _titleCtrl.text = widget.note.title;
    _isMarked = widget.note.isMarked;
    _editorState = EditorState.blank(withInitialText: false);

    _saveService = IncrementalSaveService(
      editorState: _editorState,
      titleCtrl: _titleCtrl,
      provideNotebookId: () => widget.notebookId,
      provideContext: () => context,
      notebookId: widget.notebookId,
      existingNote: widget.note,
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
    _selectedNotebookId = widget.note.notebookId ?? widget.notebookId;

    WidgetsBinding.instance.addPostFrameCallback((_) => _initPage());
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

  // ── 初始化加载（打开即编辑） ──

  Future<void> _initPage() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      // 关键步骤：把服务端 blocks 灌入编辑器，内部完成 _resetNodeMeta + _resetPending
      await _saveService.tryLoadChunks();
      await _tagService.tryLoadTags();
      final abList = await _saveService.tryLoadAllNotebooks();
      if (!mounted) return;
      setState(() {
        _notebookAbList = [
          Notebook.fromJson({"id": null, "name": "全部笔记"}),
          ...abList,
        ];
      });
    } catch (e) {
      debugPrint('加载笔记失败: $e');
      if (mounted) {
        ToastUtil.error(context, title: "网络错误", description: "笔记加载失败");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 选区 & 剪贴板操作 ──

  void _onSelectionChanged() {
    setState(() {
      _lastSelection = _editorState.selectionNotifier.value;
    });
  }

  bool get _hasSelection =>
      _lastSelection != null && !_lastSelection!.isCollapsed;

  void _copySelection() {
    final selection = _editorState.selection;
    if (selection == null || selection.isCollapsed) return;
    // 用 getTextInSelection 从当前选区实时计算，不依赖 selectionService 的缓存
    // （移动端 currentSelectedNodes 只在拖选时更新，全选/程序化选区会拿不到完整文本）
    final text = _editorState.getTextInSelection(selection).join('\n');
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
    final selection = Selection(
      start: Position(path: [0], offset: 0),
      end: Position(
        path: [doc.root.children.length - 1],
        offset: lastNode.delta?.length ?? 0,
      ),
    );
    // 走 selectionService.updateSelection：让移动端手势服务刷新
    // currentSelectedNodes 与选区高亮，复制才能拿到完整内容
    _editorState.service.selectionService.updateSelection(selection);
  }

  // ── 下滑隐藏标题/信息栏 ──

  bool _onEditorScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final offset = notification.metrics.pixels;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    // 顶部附近始终显示；下滑隐藏，上滑显示
    final shouldHide = offset > 24 && delta > 0;
    if (_hideHeader != shouldHide) {
      setState(() => _hideHeader = shouldHide);
    }
    return false;
  }

  // ── 保存 & 刷新 ──

  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _saveService.flush();
      await _tagService.flush();
    } catch (_) {}
    try {
      // 刷新最新版本号（409 冲突后恢复）
      if (!await _saveService.tryLoadNote()) return;
      if (!await _saveService.tryLoadChunks()) return;
      await _tagService.tryLoadTags();
      if (!mounted) return;
      setState(() {
        _isMarked = _saveService.currentNoteInfo?.isMarked ?? _isMarked;
        _selectedNotebookId =
            _saveService.currentNoteInfo?.notebookId ?? _selectedNotebookId;
      });
      ToastUtil.success(
        context,
        title: "刷新成功",
        description: "内容已更新",
        alignment: AlignmentGeometry.bottomRight,
      );
    } catch (e, stackTrace) {
      debugPrint("$e");
      debugPrint("$stackTrace");
      if (mounted) {
        ToastUtil.error(context, title: "网络错误", description: "刷新失败");
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _reloadNotebooks() async {
    try {
      final abList = await _saveService.tryLoadAllNotebooks();
      if (!mounted) return;
      setState(() {
        _notebookAbList = [
          Notebook.fromJson({"id": null, "name": "全部笔记"}),
          ...abList,
        ];
      });
    } catch (e) {
      debugPrint("加载笔记本列表失败: $e");
    }
  }

  /// 返回前自动保存未提交修改，再 pop 页面
  Future<void> _flushAndPop() async {
    if (_isDeleting) return;
    await _saveService.flush();
    await _tagService.flush();
    if (!mounted) return;
    _allowPop = true;
    Navigator.of(context).pop(false);
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

  Future<void> _openNoteInfoSheet() async {
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

  // ── 收藏 / 删除 ──

  Future<void> _toggleMark() async {
    final target = !_isMarked;
    setState(() => _isMarked = target); // 乐观更新 UI
    final ok = await _saveService.updateIsMarked(target);
    if (!ok && mounted) {
      setState(() => _isMarked = !target); // 失败回滚
    }
  }

  Future<void> _confirmDelete() async {
    if (_isDeleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除笔记"),
        content: const Text("确定要删除这篇笔记吗？删除后不可恢复。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeleting = true);
    final ok = await _saveService.deleteNote();
    if (!mounted) return;
    if (ok) {
      ToastUtil.success(context, title: "已删除");
      _allowPop = true;
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isDeleting = false);
    }
  }

  // ── Build ──

  bool get _showLoadingMask =>
      _isLoading || _isRefreshing || _isLoadingNoteInfo || _isDeleting;

  @override
  Widget build(BuildContext context) {
    // 工具栏按钮行高度（V1 MobileToolbar 默认 toolbarHeight）
    const double toolbarH = 52;
    // 键盘高度 — resizeToAvoidBottomInset 已关闭，用它将浮层顶到工具栏上方
    final double kbH = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _flushAndPop();
      },
      child: Scaffold(
        // 关闭系统避让：让 V1 MobileToolbar 内部用 keyboardHeight 占位，
        //   避免与 resizeToAvoidBottomInset 双重避让导致溢出/错位
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _flushAndPop,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: _isDeleting ? null : _openNoteInfoSheet,
            ),
            IconButton(
              icon: Icon(
                _isMarked ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isMarked ? Colors.amber : null,
              ),
              onPressed: _isDeleting ? null : _toggleMark,
            ),
            PopupMenuButton<String>(
              enabled: !_isDeleting,
              onSelected: (value) {
                if (value == 'refresh') _onRefresh();
                if (value == 'notebook') _openNotebookSheet();
                if (value == 'delete') _confirmDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('刷新')),
                PopupMenuItem(value: 'notebook', child: Text('切换笔记本')),
                PopupMenuItem(value: 'delete', child: Text('删除笔记')),
              ],
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _onRefresh,
          child: Stack(
            children: [
              Column(
                children: [
                  // 标题 + 信息栏 — 下滑自动隐藏，上滑恢复
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: _hideHeader
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
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
                              Padding(
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
                                    _infoChip(
                                      Icons.text_fields,
                                      _wordCount.toString(),
                                    ),
                                    const SizedBox(width: 12),
                                    if (_notebookAbList != null)
                                      SelectNotebookButton(
                                        allNotebooks: _notebookAbList!,
                                        selectedNotebookId:
                                            _selectedNotebookId,
                                        onTap: _openNotebookSheet,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onEditorScroll,
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
                  ),
                  // 底部富文本工具栏 — V1 MobileToolbar 自带键盘占位（按钮行 + spacer），
                  // 键盘弹出时按钮行自动停在键盘上方，收起时贴屏幕底。
                  // KeyboardSafeToolbar 保证点击工具栏不丢编辑器焦点（不收起）。
                  KeyboardSafeToolbar(
                    child: MobileToolbar(
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
              // 顶到工具栏上方（按钮行 52 + 键盘高度）
              Padding(
                padding: EdgeInsets.only(bottom: toolbarH + kbH),
                child: SaveStatusOverlay(
                  isFlushingNotifier: _saveService.isFlushingNotifier,
                  lastSavedTime: _saveService.lastSavedTime,
                ),
              ),
              if (_showLoadingMask)
                Positioned.fill(
                  child: Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
