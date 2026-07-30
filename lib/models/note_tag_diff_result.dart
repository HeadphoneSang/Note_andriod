/// 标签关联增量更新结果
///
/// 创建标签已是独立同步请求，这里只反映关联操作的冲突情况。
class NoteTagDiffResult {
  final List<int> failAddedTags;
  final List<int> failRemovedTags;

  const NoteTagDiffResult({
    this.failAddedTags = const [],
    this.failRemovedTags = const [],
  });

  bool get hasConflict =>
      failAddedTags.isNotEmpty || failRemovedTags.isNotEmpty;

  factory NoteTagDiffResult.fromJson(Map<String, dynamic> json) {
    return NoteTagDiffResult(
      failAddedTags: (json['failAddedTags'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      failRemovedTags: (json['failRemovedTags'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
  }

  @override
  String toString() =>
      'NoteTagDiffResult(failAdded: $failAddedTags, failRemoved: $failRemovedTags)';
}