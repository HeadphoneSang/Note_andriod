import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/models/node_change_event.dart';
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
  bool _isSaving = false;
  bool _isDirty = false;
  StreamSubscription? _txSub;

  /// 表格工具栏项
  late final _tableToolbarItem = MobileToolbarItem.withMenu(
    itemIconBuilder: (context, editorState, service) => Icon(
      Icons.table_chart_outlined,
      color: MobileToolbarTheme.of(context).iconColor,
      size: 20,
    ),
    itemMenuBuilder: (context, editorState, service) {
      return _TableSizePicker(editorState: editorState);
    },
  );

  /// 表格操作工具栏项（增删行列、设颜色、删除表格）
  late final _tableActionToolbarItem = MobileToolbarItem.withMenu(
    itemIconBuilder: (context, editorState, service) {
      final inTable = _findTableNode(editorState) != null;
      return Icon(
        Icons.table_restaurant,
        color: inTable
            ? MobileToolbarTheme.of(context).iconColor
            : MobileToolbarTheme.of(context).iconColor.withValues(alpha: 0.3),
        size: 20,
      );
    },
    itemMenuBuilder: (context, editorState, service) {
      final tableNode = _findTableNode(editorState);
      if (tableNode == null) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('请先点击表格内的单元格'),
          ),
        );
      }
      return _TableActionMenu(
        tableNode: tableNode,
        editorState: editorState,
        onAction: () => service.closeItemMenu(),
      );
    },
  );

  /// 查找光标所在的表格节点
  Node? _findTableNode(EditorState editorState) {
    final selection = editorState.selection;
    if (selection == null) return null;
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) return null;
    var current = node.parent;
    while (current != null) {
      if (current.type == TableBlockKeys.type) return current;
      current = current.parent;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _editorState = EditorState.blank(withInitialText: true);

    // 监听块的每一次变化
    _txSub = _editorState.transactionStream.listen((event) {
      final (time, transaction, options) = event;
      if (time != TransactionTime.after) return;

      _isDirty = true;

      for (final op in transaction.operations) {
        _dispatch(op);
      }
    });
  }

  /// 新增块
  void _onInsert(NodeChangeEvent event) {
    debugPrint('$event');
    debugPrint('${event.isSubNode}');
  }

  /// 删除块
  void _onDelete(NodeChangeEvent event) {
    debugPrint('$event');
    debugPrint('${event.isSubNode}');
  }

  /// 文本修改
  void _onUpdateText(NodeChangeEvent event) {
    debugPrint('$event');
    debugPrint('${event.isSubNode}');
  }

  /// 属性修改
  void _onUpdateAttr(NodeChangeEvent event) {
    debugPrint('$event');
    debugPrint('${event.isSubNode}');
  }

  /// 分发操作到对应的事件处理方法
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

  @override
  void dispose() {
    _txSub?.cancel();
    _editorState.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = context.read<UserStore>().user?.id;
      if (userId == null) throw Exception('用户未登录');

      // 将编辑器内容转为 JSON 存储
      final contentJson = jsonEncode(_editorState.document.toJson());

      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/note',
        data: {
          'title': title,
          'content': contentJson,
          'userId': userId,
          'notebookId': widget.notebookId,
        },
      );

      if (response.code == 200 && response.data != null) {
        final note = Note.fromJson(response.data!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('笔记「${note.title}」已保存'),
            backgroundColor: Colors.green,
          ),
        );
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
          // 标题输入
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

          // 编辑器
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: MobileToolbarV2(
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
                  _tableToolbarItem,
                  _tableActionToolbarItem,
                  buildTextAndBackgroundColorMobileToolbarItem(),
                ],
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
            ),
          ),
        ],
      ),
    );
  }
}

/// 表格尺寸选择器
class _TableSizePicker extends StatefulWidget {
  final EditorState editorState;

  const _TableSizePicker({required this.editorState});

  @override
  State<_TableSizePicker> createState() => _TableSizePickerState();
}

class _TableSizePickerState extends State<_TableSizePicker> {
  int _rows = 1;
  int _cols = 1;
  static const int _maxRows = 8;
  static const int _maxCols = 8;

  void _insertTable() {
    final selection = widget.editorState.selection;
    if (selection == null) return;

    final rows = List.generate(_rows, (_) => List.filled(_cols, ''));
    final table = TableNode.fromList<String>(rows);

    final transaction = widget.editorState.transaction;
    transaction.insertNode(selection.start.path.next, table.node);
    widget.editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final style = MobileToolbarTheme.of(context);
    const spacing = 3.0;

    return Padding(
      padding: EdgeInsets.all(style.buttonSpacing),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 网格
          GestureDetector(
            onPanStart: (d) => _updateSize(d.localPosition),
            onPanUpdate: (d) => _updateSize(d.localPosition),
            onPanEnd: (_) => _insertTable(),
            child: GridView.count(
              crossAxisCount: _maxCols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: 1,
              children: List.generate(_maxRows * _maxCols, (i) {
                final row = i ~/ _maxCols;
                final col = i % _maxCols;
                final selected = row < _rows && col < _cols;

                return Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? style.primaryColor.withValues(alpha: 0.3)
                        : style.itemOutlineColor,
                    borderRadius: BorderRadius.circular(3),
                    border: selected
                        ? Border.all(color: style.primaryColor, width: 1.5)
                        : null,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          // 文字提示
          Text(
            '${_rows} × $_cols',
            style: TextStyle(
              fontSize: 14,
              color: style.foregroundColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // 确认按钮
          SizedBox(
            width: double.infinity,
            height: style.buttonHeight,
            child: ElevatedButton(
              onPressed: _insertTable,
              style: ElevatedButton.styleFrom(
                backgroundColor: style.primaryColor,
                foregroundColor: style.onPrimaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(style.borderRadius),
                ),
              ),
              child: const Text(
                '插入表格',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _updateSize(Offset localPos) {
    const totalCell = 27.0; // cellSize + spacing
    final col = (localPos.dx / totalCell).floor().clamp(0, _maxCols - 1);
    final row = (localPos.dy / totalCell).floor().clamp(0, _maxRows - 1);
    setState(() {
      _rows = row + 1;
      _cols = col + 1;
    });
  }
}

/// 表格操作菜单
class _TableActionMenu extends StatefulWidget {
  final Node tableNode;
  final EditorState editorState;
  final VoidCallback onAction;

  const _TableActionMenu({
    required this.tableNode,
    required this.editorState,
    required this.onAction,
  });

  @override
  State<_TableActionMenu> createState() => _TableActionMenuState();
}

class _TableActionMenuState extends State<_TableActionMenu> {
  int get _colsLen => widget.tableNode.attributes[TableBlockKeys.colsLen] as int;

  @override
  Widget build(BuildContext context) {
    final style = MobileToolbarTheme.of(context);

    return Padding(
      padding: EdgeInsets.all(style.buttonSpacing),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 列操作
          _sectionTitle('列操作'),
          _actionRow(context, [
            _actionBtn(context, '前插入列', Icons.first_page, () {
              TableActions.add(widget.tableNode, 0, widget.editorState, TableDirection.col);
              widget.onAction();
            }),
            _actionBtn(context, '后插入列', Icons.last_page, () {
              TableActions.add(widget.tableNode, _colsLen, widget.editorState, TableDirection.col);
              widget.onAction();
            }),
            _actionBtn(context, '删除列', Icons.delete_outline, () {
              final cell = _currentCell();
              if (cell != null) {
                final col = cell.attributes[TableCellBlockKeys.colPosition] as int;
                TableActions.delete(widget.tableNode, col, widget.editorState, TableDirection.col);
              }
              widget.onAction();
            }),
          ]),
          const SizedBox(height: 8),
          // 行操作
          _sectionTitle('行操作'),
          _actionRow(context, [
            _actionBtn(context, '前插入行', Icons.vertical_align_top, () {
              final cell = _currentCell();
              if (cell != null) {
                final row = cell.attributes[TableCellBlockKeys.rowPosition] as int;
                TableActions.add(widget.tableNode, row, widget.editorState, TableDirection.row);
              }
              widget.onAction();
            }),
            _actionBtn(context, '后插入行', Icons.vertical_align_bottom, () {
              final cell = _currentCell();
              if (cell != null) {
                final row = (cell.attributes[TableCellBlockKeys.rowPosition] as int) + 1;
                TableActions.add(widget.tableNode, row, widget.editorState, TableDirection.row);
              }
              widget.onAction();
            }),
            _actionBtn(context, '删除行', Icons.remove_circle_outline, () {
              final cell = _currentCell();
              if (cell != null) {
                final row = cell.attributes[TableCellBlockKeys.rowPosition] as int;
                TableActions.delete(widget.tableNode, row, widget.editorState, TableDirection.row);
              }
              widget.onAction();
            }),
          ]),
          const SizedBox(height: 8),
          // 背景色
          _sectionTitle('背景色'),
          _actionRow(context, [
            _actionBtn(context, '设置列背景', Icons.format_color_fill, () {
              final cell = _currentCell();
              if (cell != null) {
                final col = cell.attributes[TableCellBlockKeys.colPosition] as int;
                _showColorPicker(context, (color) {
                  TableActions.setBgColor(widget.tableNode, col, widget.editorState, color, TableDirection.col);
                  widget.onAction();
                });
              }
            }),
            _actionBtn(context, '设置行背景', Icons.format_color_fill, () {
              final cell = _currentCell();
              if (cell != null) {
                final row = cell.attributes[TableCellBlockKeys.rowPosition] as int;
                _showColorPicker(context, (c) {
                  TableActions.setBgColor(widget.tableNode, row, widget.editorState, c, TableDirection.row);
                  widget.onAction();
                });
              }
            }),
          ]),
          const Divider(height: 16),
          // 删除表格
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                final transaction = widget.editorState.transaction;
                if (widget.editorState.document.root.children.length == 1) {
                  transaction.insertNode(widget.tableNode.path, paragraphNode());
                }
                transaction.deleteNode(widget.tableNode);
                widget.editorState.apply(transaction);
                widget.onAction();
              },
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text('删除表格', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: MobileToolbarTheme.of(context).foregroundColor.withValues(alpha: 0.6),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context, List<Widget> buttons) {
    return Row(
      children: buttons
          .map((b) => Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: b,
          )))
          .toList(),
    );
  }

  Widget _actionBtn(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    final style = MobileToolbarTheme.of(context);
    return SizedBox(
      height: style.buttonHeight,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          side: BorderSide(color: style.itemOutlineColor),
          foregroundColor: style.foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(style.borderRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Node? _currentCell() {
    final selection = widget.editorState.selection;
    if (selection == null) return null;
    final node = widget.editorState.getNodeAtPath(selection.start.path);
    if (node == null) return null;
    var current = node.parent;
    while (current != null) {
      if (current.type == TableCellBlockKeys.type) return current;
      current = current.parent;
    }
    return null;
  }

  void _showColorPicker(BuildContext context, void Function(String?) onColor) {
    final style = MobileToolbarTheme.of(context);
    final colors = [
      null, '#FF0000', '#FF4500', '#FF8C00', '#FFD700',
      '#ADFF2F', '#00FF00', '#00CED1', '#1E90FF', '#4169E1',
      '#8A2BE2', '#FF69B4', '#C0C0C0', '#808080',
    ];

    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: EdgeInsets.all(style.buttonSpacing),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选择颜色', style: TextStyle(fontWeight: FontWeight.w600, color: style.foregroundColor)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((hex) => GestureDetector(
                onTap: () {
                  onColor(hex);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: hex != null ? Color(int.parse(hex.replaceFirst('#', '0xFF'))) : Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: style.itemOutlineColor),
                  ),
                  child: hex == null
                      ? Icon(Icons.close, size: 16, color: style.foregroundColor)
                      : null,
                ),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
