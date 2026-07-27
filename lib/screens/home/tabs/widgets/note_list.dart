import 'package:flutter/material.dart';
import '../../../../models/note.dart';
import '../../../../models/page_result.dart';

/// 笔记列表组件
///
/// 支持触底加载更多 + 下拉刷新。
/// [notebookId] 当前选中的笔记本 id（null = 全部笔记）
/// [getPageNotes] 由父组件提供的分页查询函数
/// [onNoteTap] 点击笔记名片时的回调
class NoteList extends StatefulWidget {
  const NoteList({
    super.key,
    required this.notebookId,
    required this.getPageNotes,
    this.onNoteTap,
  });

  final int? notebookId;
  final Future<PageResult<Note>> Function(
    int pageNumber,
    int pageSize,
    int? notebookId,
  )
  getPageNotes;
  final void Function(Note note)? onNoteTap;

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  final _scrollCtrl = ScrollController();
  final List<Note> _notes = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadNotes();
  }

  @override
  void didUpdateWidget(NoteList old) {
    super.didUpdateWidget(old);
    // 笔记本切换时重新加载
    if (old.notebookId != widget.notebookId) {
      _resetAndLoad();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 触底检测
  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// 初始加载 / 下拉刷新
  Future<void> _loadNotes() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final page = await widget.getPageNotes(1, _pageSize, widget.notebookId);
      if (!mounted) return;
      setState(() {
        _notes
          ..clear()
          ..addAll(page.records);
        _currentPage = 1;
        _hasMore = page.records.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// 触底加载更多
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final nextPage = _currentPage + 1;
      final page = await widget.getPageNotes(
        nextPage,
        _pageSize,
        widget.notebookId,
      );
      if (!mounted) return;
      setState(() {
        _notes.addAll(page.records);
        _currentPage = nextPage;
        _hasMore = page.records.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  /// 切换笔记本时重置
  void _resetAndLoad() {
    setState(() {
      _notes.clear();
      _currentPage = 1;
      _hasMore = true;
    });
    _loadNotes();
  }

  // ──────────────────────────────────────────────
  //  UI
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? _buildEmpty()
          : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            '暂无笔记',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadNotes,
      child: ListView.builder(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // 给一个固定高度，让 ListView 跳过测量直接布局
        itemExtent: 145,
        itemCount: _notes.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _notes.length) {
            return _buildLoadingIndicator();
          }
          return RepaintBoundary(child: _buildNoteCard(_notes[i]));
        },
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildNoteCard(Note note) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: widget.onNoteTap != null ? () => widget.onNoteTap!(note) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行（含标记星标）
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? '无标题' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (note.isMarked)
                    const Icon(
                      Icons.star_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
                ],
              ),

              // 摘要
              if (note.summary != null && note.summary!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  note.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],

              // 标签
              if (note.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: note.tags.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tag.color != null
                            ? _parseColor(tag.color!).withValues(alpha: 0.15)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tag.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: tag.color != null
                              ? _parseColor(tag.color!)
                              : Colors.grey.shade600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // 更新时间
              const SizedBox(height: 8),
              Text(
                _formatTime(note.updatedAt),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 颜色字符串转 Color，结果缓存避免重复解析
  static final Map<String, Color> _colorCache = {};
  static Color _parseColor(String color) {
    return _colorCache.putIfAbsent(color, () {
      if (color.startsWith('#')) {
        final hex = color.replaceFirst('#', '');
        if (hex.length == 6) {
          return Color(int.parse('FF$hex', radix: 16));
        }
      }
      switch (color.toLowerCase()) {
        case 'red':
          return Colors.red;
        case 'blue':
          return Colors.blue;
        case 'green':
          return Colors.green;
        case 'orange':
          return Colors.orange;
        case 'purple':
          return Colors.purple;
        case 'yellow':
          return Colors.yellow;
        default:
          return Colors.grey;
      }
    });
  }

  /// 格式化时间为友好显示
  String _formatTime(DateTime? dt) {
    if (dt == null) return "无法获取时间";
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
