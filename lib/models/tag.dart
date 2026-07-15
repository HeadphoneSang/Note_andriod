/// 标签模型 — 与服务端 Tag.java 对齐
class Tag {
  final int id;
  final String name;
  final String? color;
  final DateTime? createdAt;
  final int? userId;

  const Tag({
    required this.id,
    required this.name,
    this.color,
    required this.createdAt,
    required this.userId,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      color: json['color'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      userId: json['userId'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'createdAt': createdAt?.toIso8601String(),
      'userId': userId,
    };
  }

  Tag copyWith({
    int? id,
    String? name,
    String? color,
    DateTime? createdAt,
    int? userId,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
    );
  }

  @override
  String toString() => 'Tag(id: $id, name: $name, userId: $userId)';
}
