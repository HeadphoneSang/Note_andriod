import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:note_for_android/models/notebook.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/screens/note/mixins/tag_service.dart';
import 'package:note_for_android/screens/note/widgets/floating_toolbar.dart';
import 'package:note_for_android/screens/note/widgets/keyboard_safe_toolbar.dart';
import 'package:note_for_android/screens/note/widgets/note_info_sheet.dart';
import 'package:note_for_android/screens/note/widgets/conflict_badge_block_builder.dart';
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

  /// 下滑隐藏标题/信息栏，只留编辑内容
  bool _hideHeader = false;
  double _lastScrollOffset = 0;
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
      _overrideTapInterceptor();
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

  /// 覆盖编辑器默认点击处理 + 缩小边缘自动滚动区域
  ///
  /// AppFlowy 默认在点击正文时调用 `textInputService.close()` 再重连，导致每次点击
  /// 输入法都闪烁一下、屏幕跟着跳动。这里换成只移动光标、不关闭输入法。
  ///
  /// 另外 AppFlowy 的 `ScrollServiceWidget` 在每次选区变化时调用
  /// `startAutoScroll(endTouchPoint, edgeOffset: autoScrollEdgeOffset)`，
  /// 默认 `autoScrollEdgeOffset = 220`——光标离边 220px 就触发自动滚动，
  /// 对手机来说过于灵敏，点任意位置屏幕都跟着动。这里把它缩到 50，
  /// 只有手指真正拖到边缘附近才会触发自动滚动，保证选区和编辑体验稳定。
  void _overrideTapInterceptor() {
    try {
      _editorState.service.selectionService.unregisterGestureInterceptor(
        'keyboard',
      );
      _editorState.service.selectionService.registerGestureInterceptor(
        SelectionGestureInterceptor(key: 'keyboard', canTap: (details) => true),
      );
      // 缩小边缘自动滚动区域：从默认 220 → 50
      _editorState.autoScrollEdgeOffset = 50;
    } catch (e) {
      debugPrint('覆盖点击拦截器失败: $e');
    }
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

    // 下滑隐藏：只在真实手指拖动时触发
    // （程序化滚动/键盘弹出 dragDetails == null 时不隐藏）
    if (notification.dragDetails != null) {
      final shouldHide = offset > 24 && delta > 0;
      if (shouldHide && !_hideHeader) {
        setState(() => _hideHeader = true);
      }
    }

    // 滑到顶部（offset <= 4）时显示标题栏，无论手指是否还在屏幕上
    // 这样快速回弹也能触发显示
    final shouldShow = offset <= 4;
    if (shouldShow && _hideHeader) {
      setState(() => _hideHeader = false);
    }
    return false;
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

  Widget get _toolbarWidget {
    // V1 MobileToolbar 自带键盘占位（按钮行 + spacer），配合 Scaffold 的
    // resizeToAvoidBottomInset: false 使用；KeyboardSafeToolbar 保证点击
    // 工具栏不丢编辑器焦点（不收起）。
    return KeyboardSafeToolbar(
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
    );
  }

  Widget get _metaBarWidget {
    if (_saveService.noteId != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            _infoChip(
              Icons.access_time_rounded,
              _formatDate(_saveService.currentNoteInfo?.createdAt),
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
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _infoChip(Icons.access_time_rounded, _formatDate(DateTime.now())),
          const SizedBox(width: 12),
          _infoChip(Icons.text_fields, _wordCount.toString()),
          const SizedBox(width: 12),
          if (_notebookAbList != null)
            SelectNotebookButton(
              allNotebooks: _notebookAbList!,
              selectedNotebookId: _selectedNotebookId,
              onTap: _openNotebookSheet,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 工具栏按钮行高度 + 键盘高度，用于把保存状态浮层顶到工具栏上方
    const double toolbarH = 52;
    final double kbH = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      // 关闭系统避让：让 V1 MobileToolbar 内部用 keyboardHeight 占位
      resizeToAvoidBottomInset: false,
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
                            _metaBarWidget,
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
                        // 冲突块右上角叠加"冲突"徽标提示
                        blockComponentBuilders:
                            buildConflictAwareBlockComponentBuilders(),
                        editorStyle: const EditorStyle.mobile(
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
                _toolbarWidget,
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
