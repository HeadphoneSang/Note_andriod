import '../core/network/http_client.dart';
import 'page_result.dart';

/// 笔记本模型 — 与服务端 Notebook.java 对齐
class Notebook {
  final int id;
  final String name;
  final String? description;
  final String? color;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int userId;

  const Notebook({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
  });

  factory Notebook.fromJson(Map<String, dynamic> json) {
    return Notebook(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      color: json['color'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      userId: json['userId'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'userId': userId,
    };
  }

  /// 带部分字段变更的复制
  Notebook copyWith({
    int? id,
    String? name,
    String? description,
    String? color,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? userId,
  }) {
    return Notebook(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
    );
  }

  @override
  String toString() =>
      'Notebook(id: $id, name: $name, userId: $userId)';

  // ──────────────────────────────────────────────
  //  分页查询
  // ──────────────────────────────────────────────

  /// 分页获取当前用户的笔记本列表
  ///
  /// [page] 页码，从 1 开始
  /// [size] 每页条数
  ///
  /// 使用示例：
  /// ```dart
  /// final result = await Notebook.listByPage(page: 1, size: 10);
  /// print('共 ${result.total} 条，${result.pages} 页');
  /// for (final nb in result.records) {
  ///   print(nb.name);
  /// }
  /// ```
  static Future<PageResult<Notebook>> listByPage({
    int page = 1,
    int size = 10,
  }) async {
    final res = await HttpClient.instance.get<Map<String, dynamic>>(
      '/notebook/list',
      queryParameters: {'page': page, 'size': size},
    );

    if (res.code == 200 && res.data != null) {
      return PageResult.fromJson(res.data!, Notebook.fromJson);
    }
    throw Exception(res.message ?? '获取笔记本列表失败');
  }
}