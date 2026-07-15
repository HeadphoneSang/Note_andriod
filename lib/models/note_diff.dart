import 'package:note_for_android/models/note_block.dart';

class NoteBlockDiff {
  late final List<NoteBlock> updateBlocks;

  late final List<NoteBlock> deleteBlocks;

  late final List<NoteBlock> insertBlocks;

  NoteBlockDiff({
    required this.updateBlocks,
    required this.deleteBlocks,
    required this.insertBlocks,
  });
}
