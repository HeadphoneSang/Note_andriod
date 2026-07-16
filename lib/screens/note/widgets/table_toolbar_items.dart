import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/screens/note/widgets/table_size_picker.dart';
import 'package:note_for_android/screens/note/widgets/table_action_menu.dart';

/// 查找光标所在的表格节点
Node? findTableNode(EditorState editorState) {
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

/// 创建表格新建工具栏项
MobileToolbarItem createTableInsertToolbarItem() {
  return MobileToolbarItem.withMenu(
    itemIconBuilder: (context, editorState, service) => Icon(
      Icons.table_chart_outlined,
      color: MobileToolbarTheme.of(context).iconColor,
      size: 20,
    ),
    itemMenuBuilder: (context, editorState, service) {
      return TableSizePicker(editorState: editorState);
    },
  );
}

/// 创建表格操作工具栏项（增删行列、设颜色、删除表格）
MobileToolbarItem createTableActionToolbarItem() {
  return MobileToolbarItem.withMenu(
    itemIconBuilder: (context, editorState, service) {
      final inTable = findTableNode(editorState) != null;
      return Icon(
        Icons.table_restaurant,
        color: inTable
            ? MobileToolbarTheme.of(context).iconColor
            : MobileToolbarTheme.of(context).iconColor.withValues(alpha: 0.3),
        size: 20,
      );
    },
    itemMenuBuilder: (context, editorState, service) {
      final tableNode = findTableNode(editorState);
      if (tableNode == null) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('请先点击表格内的单元格'),
          ),
        );
      }
      return TableActionMenu(
        tableNode: tableNode,
        editorState: editorState,
        onAction: () => service.closeItemMenu(),
      );
    },
  );
}