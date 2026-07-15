import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:note_for_android/core/editor/note_document_convert.dart';

class NodeChangeEvent {
  late final Node node;

  late final EditorState _editorState;

  NodeChangeEvent(this._editorState, {required this.node});

  /// 返回根节点
  Node? _getRootNode() {
    List<int> path = [node.path[0]];
    return _editorState.document.nodeAtPath(path);
  }

  // Node对应持久化的块id
  int? get chunkId {
    return node.attributes[NoteDocumentConvert.attrBlockId];
  }

  /// 返回顶层父节点的前一个节点
  Node? get preNode {
    int prePath = node.path[0] - 1;
    if (prePath <= 0) return null;
    List<int> path = [prePath];
    return _editorState.document.nodeAtPath(path);
  }

  /// 返回顶层父节点的后一个节点
  Node? get nextNode {
    int prePath = node.path[0] + 1;
    if (prePath <= 0) return null;
    List<int> path = [prePath];
    return _editorState.document.nodeAtPath(path);
  }

  // Node的顶层root节点的对应持久化的块的版本号，没有的话设为1.0 并返回
  double? get chunkVersion {
    Node? rootNode = _getRootNode();
    double version =
        (rootNode?.attributes[NoteDocumentConvert.attrBlockVersion]) ?? 1.0;
    return version;
  }

  // Node的根节点的orderKey
  String get chunkOrderKey {
    return _getRootNode()?.attributes[NoteDocumentConvert.attrBlockOrderKey];
  }

  // Node对应的临时块id，字符串形式
  String? get nodeId {
    return _getRootNode()?.id;
  }

  // 块的类型
  String? get type {
    return _getRootNode()?.type;
  }
}
