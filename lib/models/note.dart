import 'tag.dart';

/// 笔记模型 — 与服务端 Note.java 对齐
class Note {
  final int id;
  final String title;
  final String? summary;
  final bool isMarked;
  final bool isDelete;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int? userId;
  final int? notebookId;
  final List<Tag> tags;
  final double? version;

  const Note({
    required this.id,
    required this.title,
    this.summary,
    this.isMarked = false,
    this.isDelete = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.userId,
    this.notebookId,
    this.tags = const [],
    this.version,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String?,
      isMarked: json['isMarked'] as bool? ?? false,
      isDelete: json['isDelete'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      userId: (json['userId'] as int?)?.toInt(),
      notebookId: (json['notebookId'] as int?)?.toInt(),
      tags:
          (json['tags'] as List<dynamic>?)
              ?.map((e) => Tag.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      version: (json['version'] as double?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'isMarked': isMarked,
      'isDelete': isDelete,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'userId': userId,
      'notebookId': notebookId,
      'tags': tags.map((e) => e.toJson()).toList(),
      'version': version,
    };
  }

  Note copyWith({
    int? id,
    String? title,
    String? content,
    String? summary,
    bool? isMarked,
    bool? isDelete,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? userId,
    int? notebookId,
    List<Tag>? tags,
    double? version,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      isMarked: isMarked ?? this.isMarked,
      isDelete: isDelete ?? this.isDelete,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      userId: userId ?? this.userId,
      notebookId: notebookId ?? this.notebookId,
      tags: tags ?? this.tags,
      version: version ?? this.version,
    );
  }

  @override
  String toString() => 'Note(id: $id, title: $title, userId: $userId)';
}
