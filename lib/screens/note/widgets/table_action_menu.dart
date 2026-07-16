import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 表格操作菜单 — 增删行列、设背景色、删除表格
class TableActionMenu extends StatefulWidget {
  final Node tableNode;
  final EditorState editorState;
  final VoidCallback onAction;

  const TableActionMenu({
    required this.tableNode,
    required this.editorState,
    required this.onAction,
  });

  @override
  State<TableActionMenu> createState() => _TableActionMenuState();
}

class _TableActionMenuState extends State<TableActionMenu> {
  int get _colsLen =>
      widget.tableNode.attributes[TableBlockKeys.colsLen] as int;

  @override
  Widget build(BuildContext context) {
    final style = MobileToolbarTheme.of(context);

    return Padding(
      padding: EdgeInsets.all(style.buttonSpacing),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('列操作'),
          _actionRow(context, [
            _actionBtn(context, '前插入列', Icons.first_page, () {
              TableActions.add(
                  widget.tableNode, 0, widget.editorState, TableDirection.col);
              widget.onAction();
            }),
            _actionBtn(context, '后插入列', Icons.last_page, () {
              TableActions.add(widget.tableNode, _colsLen, widget.editorState,
                  TableDirection.col);
              widget.onAction();
            }),
            _actionBtn(context, '删除列', Icons.delete_outline, () {
              final cell = _currentCell();
              if (cell != null) {
                final col =
                    cell.attributes[TableCellBlockKeys.colPosition] as int;
                TableActions.delete(
                    widget.tableNode, col, widget.editorState, TableDirection.col);
              }
              widget.onAction();
            }),
          ]),
          const SizedBox(height: 8),
          _sectionTitle('行操作'),
          _actionRow(context, [
            _actionBtn(context, '前插入行', Icons.vertical_align_top, () {
              final cell = _currentCell();
              if (cell != null) {
                final row =
                    cell.attributes[TableCellBlockKeys.rowPosition] as int;
                TableActions.add(
                    widget.tableNode, row, widget.editorState, TableDirection.row);
              }
              widget.onAction();
            }),
            _actionBtn(context, '后插入行', Icons.vertical_align_bottom, () {
              final cell = _currentCell();
              if (cell != null) {
                final row =
                    (cell.attributes[TableCellBlockKeys.rowPosition] as int) + 1;
                TableActions.add(
                    widget.tableNode, row, widget.editorState, TableDirection.row);
              }
              widget.onAction();
            }),
            _actionBtn(context, '删除行', Icons.remove_circle_outline, () {
              final cell = _currentCell();
              if (cell != null) {
                final row =
                    cell.attributes[TableCellBlockKeys.rowPosition] as int;
                TableActions.delete(
                    widget.tableNode, row, widget.editorState, TableDirection.row);
              }
              widget.onAction();
            }),
          ]),
          const SizedBox(height: 8),
          _sectionTitle('背景色'),
          _actionRow(context, [
            _actionBtn(context, '设置列背景', Icons.format_color_fill, () {
              final cell = _currentCell();
              if (cell != null) {
                final col =
                    cell.attributes[TableCellBlockKeys.colPosition] as int;
                _showColorPicker(context, (color) {
                  TableActions.setBgColor(widget.tableNode, col,
                      widget.editorState, color, TableDirection.col);
                  widget.onAction();
                });
              }
            }),
            _actionBtn(context, '设置行背景', Icons.format_color_fill, () {
              final cell = _currentCell();
              if (cell != null) {
                final row =
                    cell.attributes[TableCellBlockKeys.rowPosition] as int;
                _showColorPicker(context, (c) {
                  TableActions.setBgColor(widget.tableNode, row,
                      widget.editorState, c, TableDirection.row);
                  widget.onAction();
                });
              }
            }),
          ]),
          const Divider(height: 16),
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
          color: MobileToolbarTheme.of(context)
              .foregroundColor
              .withValues(alpha: 0.6),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context, List<Widget> buttons) {
    return Row(
      children: buttons
          .map((b) => Expanded(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: b,
          )))
          .toList(),
    );
  }

  Widget _actionBtn(
      BuildContext context, String label, IconData icon, VoidCallback onTap) {
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
      null,
      '#FF0000',
      '#FF4500',
      '#FF8C00',
      '#FFD700',
      '#ADFF2F',
      '#00FF00',
      '#00CED1',
      '#1E90FF',
      '#4169E1',
      '#8A2BE2',
      '#FF69B4',
      '#C0C0C0',
      '#808080',
    ];

    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: EdgeInsets.all(style.buttonSpacing),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('选择颜色',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: style.foregroundColor)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors
                  .map((hex) => GestureDetector(
                        onTap: () {
                          onColor(hex);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hex != null
                                ? Color(int.parse(
                                    hex.replaceFirst('#', '0xFF')))
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: style.itemOutlineColor),
                          ),
                          child: hex == null
                              ? Icon(Icons.close,
                                  size: 16, color: style.foregroundColor)
                              : null,
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}