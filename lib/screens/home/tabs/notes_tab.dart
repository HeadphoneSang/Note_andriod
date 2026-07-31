import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:note_for_android/models/note.dart';
import 'package:note_for_android/models/page_result.dart';
import 'package:note_for_android/screens/note/note_editor.dart';
import '../../../core/network/http_client.dart';
import 'widgets/notebook_sidebar.dart';
import 'widgets/note_list.dart';
import '../../../models/notebook.dart';

/// 笔记列表 Tab
///
/// 首页底部导航「笔记」对应的页面。
/// 包含顶部工具栏 + 左侧笔记本切换侧栏。
class NotesTab extends StatefulWidget {
  const NotesTab({super.key});

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab>
    with SingleTickerProviderStateMixin {
  // ──────────────────────────────────────────────
  //  侧栏动画
  // ──────────────────────────────────────────────

  bool _sidebarOpen = false;
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  final _noteListPageSize = 5;

  int _noteListRefreshKey = 0;
  // ──────────────────────────────────────────────
  //  笔记本数据
  // ──────────────────────────────────────────────

  List<Notebook> _notebooks = [];

  /// 当前选中的笔记本 id（null = 全部笔记）
  int? _selectedNotebookId;

  /// 取消上一次笔记本详情请求的令牌
  CancelToken? _detailCancelToken;

  /// 取消上一次请求笔记列表的令牌
  CancelToken? _pageNoteCancelToken;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(-1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _loadNotebooks();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  /// 拉取笔记本列表
  Future<void> _loadNotebooks() async {
    try {
      final page = await Notebook.listByPage(page: 1, size: 999);
      if (!mounted) return;
      setState(() => _notebooks = page.records);
    } catch (e) {
      debugPrint('[NotesTab] 加载笔记本列表失败: $e');
    }
  }

  /// 新建笔记本成功后，刷新列表并选中它
  void _onNotebookCreated(Notebook notebook) {
    _loadNotebooks();
    setState(() => _selectedNotebookId = notebook.id);
  }

  /// 切换侧栏
  void _toggleSidebar() {
    if (_sidebarOpen) {
      _animCtrl.reverse();
    } else {
      _animCtrl.forward();
    }
    setState(() => _sidebarOpen = !_sidebarOpen);
  }

  /// 关闭侧栏
  void _closeSidebar() {
    if (!_sidebarOpen) return;
    _animCtrl.reverse();
    setState(() => _sidebarOpen = false);
  }

  Future<PageResult<Note>> _getPageNotes(
    int pageNumber,
    int pageSize,
    int? notebookId,
  ) async {
    _pageNoteCancelToken?.cancel();
    _pageNoteCancelToken = CancelToken();
    try {
      final params = <String, dynamic>{
        'page': pageNumber,
        'pageSize': pageSize,
        'notebookId': notebookId,
      };
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/note/list',
        queryParameters: params,
        cancelToken: _pageNoteCancelToken,
      );
      if (res.code == 200 && res.data != null) {
        return PageResult.fromJson(res.data!, Note.fromJson);
      }
      debugPrint('[NotesTab] 笔记本为空: ${res.message}');
      return PageResult(
        current: 1,
        size: _noteListPageSize,
        total: 0,
        pages: 1,
        records: [],
      );
    } on DioException catch (e) {
      // 主动取消的不算异常，静默忽略
      if (e.type == DioExceptionType.cancel) {
        return PageResult(
          current: 1,
          size: _noteListPageSize,
          total: 0,
          pages: 1,
          records: [],
        );
      }
      debugPrint('[NotesTab] 获取笔记本中断: $e');
      return PageResult(
        current: 1,
        size: _noteListPageSize,
        total: 0,
        pages: 1,
        records: [],
      );
    } catch (e, stackTrace) {
      debugPrint('[NotesTab] 获取笔记本详情异常: $e');
      debugPrint('堆栈详情: $stackTrace');
      return PageResult(
        current: 1,
        size: _noteListPageSize,
        total: 0,
        pages: 1,
        records: [],
      );
    }
  }

  Future<PageResult<Note>> _getPageNotesByUserId(
    int pageNumber,
    int pageSize,
    int? notebookId,
  ) async {
    _pageNoteCancelToken?.cancel();
    _pageNoteCancelToken = CancelToken();
    try {
      final params = <String, dynamic>{'page': pageNumber, 'size': pageSize};
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/note/notes',
        queryParameters: params,
        cancelToken: _pageNoteCancelToken,
      );
      if (res.code == 200 && res.data != null) {
        return PageResult.fromJson(res.data!, Note.fromJson);
      }
      debugPrint('[NotesTab] 笔记本为空: ${res.message}');
      return PageResult(
        current: 1,
        size: _noteListPageSize,
        total: 0,
        pages: 1,
        records: [],
      );
    } on DioException catch (e) {
      // 主动取消的不算异常，静默忽略
      if (e.type == DioExceptionType.cancel) {
        return PageResult(
          current: 1,
          size: _noteListPageSize,
          total: 0,
          pages: 1,
          records: [],
        );
      }
      debugPrint('[NotesTab] 获取笔记本中断: $e');
      return PageResult(
        current: 1,
        size: _noteListPageSize,
        total: 0,
        pages: 1,
        records: [],
      );
    } catch (e, stackTrace) {
      debugPrint('[NotesTab] 获取笔记本详情异常: $e');
      debugPrint('堆栈详情: $stackTrace');
      return PageResult(
        current: 1,
        size: _noteListPageSize,
        total: 0,
        pages: 1,
        records: [],
      );
    }
  }

  /// 获取笔记本详情信息（不包含笔记列表）
  Future<Notebook?> _getNotebookDetails(int notebookId) async {
    // 取消上一次还在路上的请求
    _detailCancelToken?.cancel();
    _detailCancelToken = CancelToken();

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/notebook/detail',
        queryParameters: {'id': notebookId},
        cancelToken: _detailCancelToken,
      );
      if (res.code == 200 && res.data != null) {
        return Notebook.fromJson(res.data!);
      }
      debugPrint('[NotesTab] 获取笔记本详情失败: ${res.message}');
      return null;
    } on DioException catch (e) {
      // 主动取消的不算异常，静默忽略
      if (e.type == DioExceptionType.cancel) return null;
      debugPrint('[NotesTab] 获取笔记本详情异常: $e');
      return null;
    } catch (e) {
      debugPrint('[NotesTab] 获取笔记本详情异常: $e');
      return null;
    }
  }

  Future<void> _getAndInitNotebook(int id) async {
    final notebook = await _getNotebookDetails(id);
    if (notebook == null) {
      debugPrint('[NotesTab] 获取笔记本详情失败，id=$id');
      return;
    }
    if (id == _selectedNotebookId && mounted) {
      debugPrint('[NotesTab] 获取笔记本详情成功: ${notebook.name}');
    }
  }

  void _onSelectNotebook(int? id, String name) {
    _closeSidebar();
    setState(() => _selectedNotebookId = id);
    // 选中具体笔记本时同步拉取详情
    if (id != null) {
      _getAndInitNotebook(id);
    }
    // TODO: 根据选中的笔记本名加载对应笔记
  }

  /// 打开新建笔记界面（从底部弹出全屏页面）
  Future<void> _openAddNoteDialog(int? notebookId, BuildContext context) async {
    final result = await Navigator.push<Note>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => NoteEditor(notebookId: notebookId),
        transitionsBuilder: (_, animation, _, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
    if (mounted) {
      setState(() => _noteListRefreshKey++);
      await _loadNotebooks();
    }
  }

  // ──────────────────────────────────────────────
  //  UI 构建
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        // ─── ① 主内容区 ─────────────────────────
        Column(children: [_buildToolbar(theme), _buildBody()]),
        Positioned(
          right: 20,
          bottom: 20,
          child: GestureDetector(
            onTap: () => _openAddNoteDialog(_selectedNotebookId, context),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 174, 0),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.add_rounded, color: Colors.white, size: 32),
              ],
            ),
          ),
        ),
        // ─── ② 侧栏遮罩 ─────────────────────────
        if (_sidebarOpen)
          GestureDetector(
            onTap: _closeSidebar,
            child: AnimatedOpacity(
              opacity: _sidebarOpen ? 0.4 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(color: Colors.black),
            ),
          ),

        // ─── ③ 左侧笔记本侧栏 ────────────────────
        NotebookSidebar(
          slideAnim: _slideAnim,
          onClose: _closeSidebar,
          notebooks: _notebooks,
          selectedId: _selectedNotebookId,
          onSelectNotebook: _onSelectNotebook,
          onCreated: _onNotebookCreated,
        ),
      ],
    );
  }

  /// 构建笔记本图标 + 名称行
  Widget _buildNotebookIconBox(String? avatarUrl) {
    return Row(
      children: [
        // 方形图标背景，无头像时显示默认 SVG
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color.fromARGB(235, 78, 29, 7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: avatarUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(avatarUrl, fit: BoxFit.cover),
                )
              : Padding(
                  padding: const EdgeInsets.all(7),
                  child: SvgPicture.asset(
                    'assets/images/notebook_default.svg',
                    fit: BoxFit.contain,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedNotebookId == null
                  ? '全部笔记'
                  : _notebooks
                            .where((n) => n.id == _selectedNotebookId)
                            .firstOrNull
                            ?.name ??
                        '全部笔记',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              "填充位",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  /// 顶部工具栏
  Widget _buildToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // 左侧：当前笔记本名称 → 点击弹出侧栏
          GestureDetector(
            onTap: _toggleSidebar,
            child: Row(
              children: [
                _buildNotebookIconBox(
                  _selectedNotebookId == null
                      ? null
                      : _notebooks
                            .where((n) => n.id == _selectedNotebookId)
                            .firstOrNull
                            ?.avatar,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_right_rounded,
                  size: 20,
                  color: const Color.fromARGB(255, 0, 0, 0),
                  fontWeight: FontWeight.bold,
                ),
              ],
            ),
          ),
          const Spacer(),
          // 右侧：搜索
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.search_rounded, color: Colors.grey.shade700),
          ),
          // 右侧：排序
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.sort_rounded, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return NoteList(
      key: ValueKey(_noteListRefreshKey),
      notebookId: _selectedNotebookId,
      getPageNotes: _selectedNotebookId != null
          ? _getPageNotes
          : _getPageNotesByUserId,
      onNoteTap: (note) => {debugPrint("点击了${note.title}")},
    );
  }
}
