# 摘要保存功能实现计划

## Context

当前 `NoteEditor` 的笔记信息 sheet 已经展示了摘要编辑 UI，但点击"保存"按钮时只 flush 了标签，用户修改的摘要文本被丢弃。需要在前后端都补上摘要的持久化逻辑。

现状：
- [Note 模型](lib/models/note.dart) 已有 `summary` 字段，序列化/反序列化完整
- [IncrementalSaveService](lib/screens/note/mixins/incremental_save.dart) 已有 `_tryUpdateTitle` 方法可作为模式参考（POST + version 乐观锁 + 409 冲突处理）
- [note_info_sheet.dart](lib/screens/note/widgets/note_info_sheet.dart) 已有摘要 TextField，但保存按钮不处理摘要
- `_openNoteInfoSheet` 将 `currentNoteInfo.summary` 传给 sheet 作为初始值

## 改动清单

### 1. 后端 — 新增 `POST /note/summary` 接口

参考已有的 `POST /note/title` 模式：

**请求参数：**
| 参数 | 类型 | 说明 |
|------|------|------|
| noteId | int | 笔记 ID |
| summary | string | 摘要内容（可为空字符串） |
| version | int | 版本号（乐观锁） |

**成功响应 (200)：** 返回更新后的完整 Note JSON（与 `/note/getNote` 一致）

**冲突响应 (409)：** 版本冲突，返回最新版本号

### 2. IncrementalSaveService — 新增 `_tryUpdateSummary` 方法

在 [incremental_save.dart](lib/screens/note/mixins/incremental_save.dart) 中，参照 `_tryUpdateTitle`（第 656 行）的模式新增：

```dart
Future<bool> _tryUpdateSummary(String summary) async {
  try {
    final response = await HttpClient.instance.post<Map<String, dynamic>>(
      '/note/summary',
      queryParameters: {
        "noteId": _currentNoteInfo!.id,
        "summary": summary,
        "version": _currentNoteInfo!.version,
      },
    );
    if (response.code == 200 && response.data != null) {
      _currentNoteInfo = Note.fromJson(response.data!);
      lastSavedTime.value = DateTime.now();
      return true;
    } else if (response.code == 409) {
      ToastUtil.warning(
        provideContext(),
        title: "保存失败",
        description: "有用户修改了内容，请刷新后重试!",
        alignment: AlignmentGeometry.bottomRight,
      );
      return false;
    } else {
      ToastUtil.warning(
        provideContext(),
        title: "保存失败",
        description: "网络错误：${response.message}",
        alignment: AlignmentGeometry.bottomRight,
      );
      return false;
    }
  } catch (e) {
    debugPrint('摘要保存失败: $e');
    ToastUtil.error(provideContext(), title: '网络错误', description: '摘要保存失败');
    return false;
  }
}
```

暴露公开方法供 UI 调用：

```dart
Future<bool> updateSummary(String summary) async {
  if (_currentNoteInfo == null || _currentNoteInfo!.id == null) return false;
  if (_currentNoteInfo!.summary == summary) return true; // 无变化
  return await _tryUpdateSummary(summary);
}
```

### 3. note_info_sheet.dart — 保存按钮同步保存摘要

修改 [note_info_sheet.dart](lib/screens/note/widgets/note_info_sheet.dart)：

- `showNoteInfoSheet` 新增参数 `required IncrementalSaveService saveService`
- 保存按钮 `onPressed` 中：先 `await saveService.updateSummary(summaryCtrl.text.trim())`，再 `await tagService.flush()`
- 摘要保存失败时不阻塞标签保存，分别提示结果

### 4. note_editor.dart — 传递 saveService

在 `_openNoteInfoSheet` 调用 `showNoteInfoSheet` 时传入 `_saveService`：

```dart
await showNoteInfoSheet(
  context: context,
  tagService: _tagService,
  saveService: _saveService,
  initialSummary: _saveService.currentNoteInfo?.summary ?? "",
);
```

## 不需要做的

- **不需要**给摘要加防抖 — 摘要只有点保存按钮才提交，不是实时编辑场景
- **不需要**修改 `_tryCreateNote` — 新建笔记时摘要为空是合理的
- **不需要**修改 `tryLoadNote` — 已正确加载 summary

## 验证

1. 打开笔记信息 sheet → 修改摘要 → 点保存 → 摘要和标签同时保存成功
2. 再次打开 sheet → 摘要回显上次保存的值
3. 清空摘要保存 → 摘要变为空字符串
4. 摘要未修改时点保存 → 不发起摘要网络请求，仅保存标签
5. 版本冲突时 → toast 提示"有用户修改了内容，请刷新后重试"