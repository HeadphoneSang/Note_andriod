import 'package:note_for_android/models/note_block.dart';

class NoteBlockDiff {
  final List<NoteBlock> updateBlocks;
  final List<NoteBlock> deleteBlocks;
  final List<NoteBlock> insertBlocks;

  NoteBlockDiff({
    List<NoteBlock>? updateBlocks,
    List<NoteBlock>? deleteBlocks,
    List<NoteBlock>? insertBlocks,
  }) : updateBlocks = updateBlocks ?? [],
       deleteBlocks = deleteBlocks ?? [],
       insertBlocks = insertBlocks ?? [];

  void addUpdateBlock(NoteBlock block) {
    updateBlocks.add(block);
  }

  void addDeleteBlocks(NoteBlock block) {
    deleteBlocks.add(block);
  }

  void addInsertBlocks(NoteBlock block) {
    insertBlocks.add(block);
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
}
