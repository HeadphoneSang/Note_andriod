import 'package:flutter/material.dart';
import 'widgets/notebook_sidebar.dart';
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

  // ──────────────────────────────────────────────
  //  笔记本数据
  // ──────────────────────────────────────────────

  List<Notebook> _notebooks = [];
  bool _loading = true;
  String? _error;

  /// 当前选中的笔记本 id（null = 全部笔记）
  int? _selectedNotebookId;

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
      setState(() {
        _notebooks = page.records;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
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

  /// 选中笔记本
  void _onSelectNotebook(int? id, String name) {
    _closeSidebar();
    setState(() => _selectedNotebookId = id);
    // TODO: 根据选中的笔记本名加载对应笔记
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
        Column(
          children: [
            _buildToolbar(theme),
            _buildBody(),
          ],
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
                Text(
                  _selectedNotebookId == null
                      ? '全部笔记'
                      : _notebooks
                              .where((n) => n.id == _selectedNotebookId)
                              .firstOrNull
                              ?.name ??
                          '全部笔记',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
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

  /// 笔记列表区域
  Widget _buildBody() {
    if (_loading) {
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败: $_error'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadNotebooks();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return const Expanded(
      child: Center(child: Text('笔记列表', style: TextStyle(fontSize: 24))),
    );
  }
}