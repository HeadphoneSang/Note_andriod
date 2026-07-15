/// 笔记块模型 — 与服务端 NoteBlock.java 对齐
class NoteBlock {
  final int id;
  final String type;
  final String orderKey;
  final dynamic deltaJson;
  final double version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteBlock({
    required this.id,
    required this.type,
    this.orderKey = 'a',
    this.deltaJson,
    this.version = 1.0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NoteBlock.fromJson(Map<String, dynamic> json) {
    return NoteBlock(
      id: json['id'] as int,
      type: json['type'] as String? ?? '',
      orderKey: json['orderKey'] as String? ?? "a",
      deltaJson: json['deltaJson'],
      version: (json['version'] as num?)?.toDouble() ?? 1.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'orderKey': orderKey,
      'deltaJson': deltaJson,
      'version': version,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  NoteBlock copyWith({
    int? id,
    String? type,
    String? orderKey,
    dynamic deltaJson,
    double? version,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteBlock(
      id: id ?? this.id,
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
