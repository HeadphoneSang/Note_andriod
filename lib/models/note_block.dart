/// 笔记块模型 — 与服务端 NoteBlock.java 对齐
class NoteBlock {
  final int? id;
  final int? noteId;
  final String? type;
  final String? orderKey;
  final dynamic deltaJson;
  final int version;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const NoteBlock({
    required this.id,
    required this.type,
    this.orderKey = 'a',
    this.deltaJson,
    this.version = 1,
    this.noteId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    return NoteBlock(
      id: json['id'] as int,
      noteId: json['noteId'] as int?,
      type: json['type'] as String? ?? '',
      orderKey: json['orderKey'] as String? ?? "a",
      deltaJson: json['deltaJson'],
      version: (json['version'] as num?)?.toInt() ?? 1,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'type': type,
      'orderKey': orderKey,
      'deltaJson': deltaJson,
      'version': version,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  NoteBlock copyWith({
    int? id,
    int? noteId,
    String? type,
    String? orderKey,
    dynamic deltaJson,
    int? version,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteBlock(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      type: type ?? this.type,
      orderKey: orderKey ?? this.orderKey,
      deltaJson: deltaJson ?? this.deltaJson,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'NoteBlock(id: $id, type: $type, orderKey: $orderKey)';
}
