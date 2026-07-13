import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/core/store/user_store.dart';
import 'package:note_for_android/models/notebook.dart';

/// 笔记本侧栏组件
///
/// 从左侧滑入的半屏面板，显示笔记本列表。
/// [slideAnim] 控制滑入/滑出动画
/// [onClose]   关闭侧栏的回调
/// [notebooks] 后端获取的笔记本列表
/// [selectedId] 当前选中的笔记本 id（null 表示「全部笔记」）
/// [onSelectNotebook] 选中笔记本的回调
/// [onCreated] 新建笔记本成功后的回调
class NotebookSidebar extends StatelessWidget {
  const NotebookSidebar({
    super.key,
    required this.slideAnim,
    required this.onClose,
    this.notebooks = const [],
    this.selectedId,
    this.onSelectNotebook,
    this.onCreated,
  });

  final Animation<Offset> slideAnim;
  final VoidCallback onClose;
  final List<Notebook> notebooks;
  final int? selectedId;
  final void Function(int? id, String name)? onSelectNotebook;
  final void Function(Notebook notebook)? onCreated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FractionallySizedBox(
      widthFactor: 0.7,
      alignment: Alignment.centerLeft,
      child: SlideTransition(
        position: slideAnim,
        child: Material(
          elevation: 8,
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(theme),
                _buildNotebookList(theme),
                _buildFooter(theme, context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 侧栏标题 ───────────────────────────────

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.inversePrimary.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Text(
            '笔记本',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }

  // ─── 笔记本列表 ─────────────────────────────

  Widget _buildNotebookList(ThemeData theme) {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 顶部固定项：「全部笔记」
          _NotebookItem(
            name: '全部笔记',
            selected: selectedId == null,
            theme: theme,
            onTap: () => onSelectNotebook?.call(null, '全部笔记'),
          ),
          // 从后端获取的笔记本
          ...notebooks.map(
            (nb) => _NotebookItem(
              name: nb.name,
              selected: selectedId == nb.id,
              theme: theme,
              onTap: () => onSelectNotebook?.call(nb.id, nb.name),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 新建笔记本 ─────────────────────────────

  Widget _buildFooter(ThemeData theme, BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.add_rounded),
          title: const Text('新建笔记本'),
          onTap: () => _showCreateDialog(context),
        ),
      ],
    );
  }

  /// 弹出新建笔记本对话框
  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var loading = false;

    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: const Text('新建笔记本'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '笔记本名称',
                      hintText: '请输入名称',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: '描述（可选）',
                      hintText: '简单描述这个笔记本的用途',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () => _createNotebook(
                            ctx,
                            setDialogState,
                            () => loading,
                            (v) => loading = v,
                            nameCtrl,
                            descCtrl,
                          ),
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  /// 调用后端创建笔记本
  Future<void> _createNotebook(
    BuildContext dialogContext,
    void Function(void Function()) setDialogState,
    bool Function() getLoading,
    void Function(bool) setLoading,
    TextEditingController nameCtrl,
    TextEditingController descCtrl,
  ) async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text('请输入笔记本名称'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setDialogState(() => setLoading(true));

    try {
      // 从 UserStore 获取当前用户 ID
      final userId = dialogContext.read<UserStore>().user?.id;
      if (userId == null) {
        throw Exception('用户未登录，无法创建笔记本');
      }

      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/notebook/add',
        data: {
          'name': name,
          'description': descCtrl.text.trim(),
          'userId': userId,
        },
      );

      if (response.code == 200 && response.data != null) {
        final notebook = Notebook.fromJson(response.data!);

        if (dialogContext.mounted) {
          Navigator.pop(dialogContext);
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            SnackBar(
              content: Text('笔记本「${notebook.name}」创建成功'),
              backgroundColor: Colors.green,
            ),
          );
          onCreated?.call(notebook);
        }
      } else {
        throw Exception(response.message ?? '创建失败');
      }
    } catch (e) {
      if (dialogContext.mounted) {
        setDialogState(() => setLoading(false));
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// 单个笔记本列表项
class _NotebookItem extends StatelessWidget {
  const _NotebookItem({
    required this.name,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? Icons.book_rounded : Icons.book_outlined,
        color: selected ? theme.colorScheme.primary : Colors.grey.shade600,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? theme.colorScheme.primary : null,
        ),
      ),
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      onTap: onTap,
    );
  }
}