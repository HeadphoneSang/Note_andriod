/// 分页结果模型 — 与服务端分页响应对齐
class PageResult<T> {
  final int current;
  final int size;
  final int total;
  final int pages;
  final List<T> records;

  const PageResult({
    required this.current,
    required this.size,
    required this.total,
    required this.pages,
    required this.records,
  });

  /// 从 JSON Map 构建分页结果
  ///
  /// [json] 是 data 字段内的 Map，如 {"current":1, "size":10, "records":[...]}
  /// [fromJson] 将 records 中的每一项从 JSON 转为具体模型
  factory PageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return PageResult(
      current: json['current'] as int? ?? 1,
      size: json['size'] as int? ?? 10,
      total: json['total'] as int? ?? 0,
      pages: json['pages'] as int? ?? 0,
      records: (json['records'] as List<dynamic>?)
              ?.map((e) => fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}