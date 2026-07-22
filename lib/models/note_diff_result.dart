/// 后端增量更新结果 — 对应 Java NoteDiffResult
class NoteDiffResult {
  final List<String> failUpdateBlocks;
  final List<String> failDeletedBlocks;
  final List<String> failCreatedBlocks;

  const NoteDiffResult({
    this.failUpdateBlocks = const [],
    this.failDeletedBlocks = const [],
    this.failCreatedBlocks = const [],
  });

  bool get hasConflict =>
      failUpdateBlocks.isNotEmpty ||
      failDeletedBlocks.isNotEmpty ||
      failCreatedBlocks.isNotEmpty;

  factory NoteDiffResult.fromJson(Map<String, dynamic> json) {
    return NoteDiffResult(
      failUpdateBlocks: (json['failUpdateBlocks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      failDeletedBlocks: (json['failDeletedBlocks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      failCreatedBlocks: (json['failCreatedBlocks'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'failUpdateBlocks': failUpdateBlocks,
      'failDeletedBlocks': failDeletedBlocks,
      'failCreatedBlocks': failCreatedBlocks,
    };
  }

  @override
  String toString() =>
      'NoteDiffResult(failUpdateBlocks: $failUpdateBlocks, '
      'failDeletedBlocks: $failDeletedBlocks, '
      'failCreatedBlocks: $failCreatedBlocks)';
}