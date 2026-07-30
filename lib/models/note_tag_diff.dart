/// 标签关联增量更新请求体 —— 与服务端 NoteTagDiff 对齐
///
/// 一次提交包含两类操作：
/// - addTagIds：要新增 (note_id, tag_id) 关联的已有标签
/// - removeTagIds：要删除 (note_id, tag_id) 关联的标签
class NoteTagDiff {
  final List<int> addTagIds;
  final List<int> removeTagIds;

  NoteTagDiff({
    List<int>? addTagIds,
    List<int>? removeTagIds,
  }) : addTagIds = addTagIds ?? [],
       removeTagIds = removeTagIds ?? [];

  Map<String, dynamic> toJson() {
    return {
      'addTagIds': addTagIds,
      'removeTagIds': removeTagIds,
    };
  }

  int get operationCount => addTagIds.length + removeTagIds.length;

  bool get isEmpty => addTagIds.isEmpty && removeTagIds.isEmpty;

  @override
  String toString() {
    return 'NoteTagDiff(add: ${addTagIds.length}, remove: ${removeTagIds.length})';
  }
}