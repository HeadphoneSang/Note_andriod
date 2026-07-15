import 'package:note_for_android/models/note.dart';
import 'package:note_for_android/models/note_block.dart';

class NoteDetail {
  late final Note note;
  late final List<NoteBlock> blocks;

  NoteDetail({required this.note, required this.blocks});

  factory NoteDetail.fromJson(Map<String, dynamic> json) {
    return NoteDetail(
      note: Note.fromJson(json['note']),
      blocks: (json['blocks'] as List<dynamic>)
          .map((item) => NoteBlock.fromJson(item))
          .toList(),
    );
  }
}
