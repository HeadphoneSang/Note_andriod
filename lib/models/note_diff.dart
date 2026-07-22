import 'package:note_for_android/models/note_block.dart';

class NoteBlockDiff {
  final List<NoteBlock> updateBlocks;
  final List<NoteBlock> deleteBlocks;
  final List<NoteBlock> insertBlocks;
  final Map<String, String> _chunkIdToNodeId = {};

  NoteBlockDiff({
    List<NoteBlock>? updateBlocks,
    List<NoteBlock>? deleteBlocks,
    List<NoteBlock>? insertBlocks,
  }) : updateBlocks = updateBlocks ?? [],
       deleteBlocks = deleteBlocks ?? [],
       insertBlocks = insertBlocks ?? [];

  String? getNodeId(String chunkId) {
    return _chunkIdToNodeId[chunkId];
  }

  void addUpdateBlock(NoteBlock block, String nodeId) {
    updateBlocks.add(block);
    _chunkIdToNodeId[block.id!] = nodeId;
  }

  void addDeleteBlocks(NoteBlock block, String nodeId) {
    deleteBlocks.add(block);
    _chunkIdToNodeId[block.id!] = nodeId;
  }

  void addInsertBlocks(NoteBlock block, String nodeId) {
    insertBlocks.add(block);
    _chunkIdToNodeId[block.id!] = nodeId;
  }

  /// 转为 JSON，供 POST 提交时使用
  ///
  /// 调用方需在顶层补充 noteId / version：
  /// ```dart
  /// final data = {
  ///   'noteId': note.id,
  ///   'version': note.version,
  ///   ...diff.toJson(),
  /// };
  /// ```
  Map<String, dynamic> toJson() {
    return {
      'insertedBlocks': insertBlocks.map((b) => b.toJson()).toList(),
      'updatedBlocks': updateBlocks.map((b) => b.toJson()).toList(),
      'deletedBlocks': deleteBlocks.map((b) => b.toJson()).toList(),
    };
  }

  int get opertionsCnt {
    return updateBlocks.length + deleteBlocks.length + insertBlocks.length;
  }

  @override
  String toString() {
    final buf = StringBuffer('NoteBlockDiff(\n');
    buf.writeln('  insertedBlocks (${insertBlocks.length}):');
    for (final b in insertBlocks) {
      buf.writeln('    - $b');
    }
    buf.writeln('  updatedBlocks (${updateBlocks.length}):');
    for (final b in updateBlocks) {
      buf.writeln('    - $b');
    }
    buf.writeln('  deletedBlocks (${deleteBlocks.length}):');
    for (final b in deleteBlocks) {
      buf.writeln('    - $b');
    }
    buf.write(')');
    return buf.toString();
  }
}
