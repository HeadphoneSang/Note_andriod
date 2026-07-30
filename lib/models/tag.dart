import 'package:flutter/material.dart';

/// 标签模型 — 与服务端 Tag.java 对齐
class Tag {
  final int? id;
  final String name;
  final String? color;
  final DateTime? createdAt;
  final int? userId;

  const Tag({
    this.id,
    required this.name,
    this.color,
    this.createdAt,
    this.userId,
  });

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as int?,
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
      if (id != null) 'id': id,
      'name': name,
      if (color != null) 'color': color,
      if (createdAt != null) 'createdAt': createdAt?.toIso8601String(),
      if (userId != null) 'userId': userId,
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

  /// 将颜色字符串解析为 Flutter Color
  Color toColor() {
    if (color == null) return Colors.grey;
    if (color!.startsWith('#')) {
      final hex = color!.replaceFirst('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    }
    switch (color!.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'yellow':
        return Colors.yellow;
      default:
        return Colors.grey;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag && id != null && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Tag(id: $id, name: $name)';
}