import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:note_for_android/core/editor/note_document_convert.dart';

/// 块变化事件类型
enum NodeChangeType {
  insert, // 新增块
  delete, // 删除块
  updateText, // 文本修改
  updateAttr, // 属性修改
}

/// 编辑器块变化事件
///
/// 包装变化的 Node，并提供便捷 getter 获取数据库字段。
class NodeChangeEvent {
  final NodeChangeType changeType;
  final Node node;
  final EditorState editorState;
  final Operation operation;

  const NodeChangeEvent({
    required this.changeType,
    required this.node,
    required this.editorState,
    required this.operation,
  });

  /// 克隆当前对象，可指定修改部分属性
  NodeChangeEvent copyWith({
    NodeChangeType? changeType,
    Node? node,
    EditorState? editorState,
    Operation? operation,
  }) {
    return NodeChangeEvent(
      changeType: changeType ?? this.changeType,
      node: node ?? this.node,
      editorState: editorState ?? this.editorState,
      operation: operation ?? this.operation,
    );
  }

  Node? get rootNode {
    return _topLevelNode;
  }

  /// 当前节点是否为嵌套子节点（非顶层块）
  bool get isSubNode {
    final top = _topLevelNode;
    return top != null && node != top;
  }

  /// 当前节点所属的顶层块（root.children[path[0]]），
  /// 节点已从树中移除时返回 null。
  Node? get _topLevelNode {
    if (node.path.isEmpty) return null;
    return editorState.document.nodeAtPath([node.path.first]);
  }

  /// 数据库块 ID
  int? get chunkId => node.attributes[NoteDocumentConvert.attrBlockId] as int?;

  /// 数据库块版本号
  double get chunkVersion =>
      (_topLevelNode?.attributes[NoteDocumentConvert.attrBlockVersion] as num?)
          ?.toDouble() ??
      1.0;

  /// 排序键
  String? get chunkOrderKey =>
      _topLevelNode?.attributes[NoteDocumentConvert.attrBlockOrderKey]
          as String?;

  /// 前一个顶层块
  Node? get previousNode {
    final index = node.path.first - 1;
    if (index < 0) return null;
    return editorState.document.nodeAtPath([index]);
  }

  /// 后一个顶层块
  Node? get nextNode {
    final index = node.path.first + 1;
    return editorState.document.nodeAtPath([index]);
  }

  /// AppFlowyEditor 临时块 ID
  String get nodeId => node.id;

  /// 块类型
  String get type => node.type;

  /// delta 中的纯文本
  String get plainText => node.delta?.toPlainText() ?? '';

  @override
  String toString() {
    final detail = StringBuffer()
      ..write('NodeChangeEvent($changeType')
      ..write(', chunkId=$chunkId')
      ..write(', version=$chunkVersion')
      ..write(', orderKey=$chunkOrderKey')
      ..write(', type=$type')
      ..write(', path=${node.path}');
    if (isSubNode) {
      detail.write(', topPath=[${node.path.first}]');
    }
    detail.write(
      ', text="${plainText.length > 50 ? '${plainText.substring(0, 50)}…' : plainText}"',
    );
    detail.write(', nodeId=${node.id}');
    if (operation is UpdateTextOperation) {
      final upd = operation as UpdateTextOperation;
      detail.write(', old="${upd.inverted.toPlainText()}"');
      detail.write(', new="${upd.delta.toPlainText()}"');
    }
    detail.write(')');
    return detail.toString();
  }
}
