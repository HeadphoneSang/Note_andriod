import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 表格尺寸选择器 — 拖动选择行列数
class TableSizePicker extends StatefulWidget {
  final EditorState editorState;

  const TableSizePicker({required this.editorState});

  @override
  State<TableSizePicker> createState() => _TableSizePickerState();
}

class _TableSizePickerState extends State<TableSizePicker> {
  int _rows = 1;
  int _cols = 1;
  static const int _maxRows = 8;
  static const int _maxCols = 8;

  void _insertTable() {
    final selection = widget.editorState.selection;
    if (selection == null) return;

    // 计算每列宽度：屏幕宽度 ÷ 列数，留出边框间距
    final screenWidth = MediaQuery.of(context).size.width;
    final borderWidth = 1.0;
    final colWidth = ((screenWidth - borderWidth * (_cols + 1)) / _cols)
        .clamp(40.0, 200.0);

    final rows = List.generate(_rows, (_) => List.filled(_cols, ''));
    final table = TableNode.fromList<String>(rows);

    // 设置列宽，让表格适配屏幕宽度
    table.node.attributes[TableBlockKeys.colDefaultWidth] = colWidth;
    table.node.attributes[TableBlockKeys.colMinimumWidth] = 40.0;
    table.node.attributes[TableBlockKeys.borderWidth] = borderWidth;
    for (final cell in table.node.children) {
      cell.attributes[TableCellBlockKeys.width] = colWidth;
    }

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
          Text(
            '$_rows × $_cols',
            style: TextStyle(
              fontSize: 14,
              color: style.foregroundColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
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
    const totalCell = 27.0;
    final col = (localPos.dx / totalCell).floor().clamp(0, _maxCols - 1);
    final row = (localPos.dy / totalCell).floor().clamp(0, _maxRows - 1);
    setState(() {
      _rows = row + 1;
      _cols = col + 1;
    });
  }
}