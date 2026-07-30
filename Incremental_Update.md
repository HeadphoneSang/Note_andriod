# 怎么设计标签的增量更新：

## 效果是: 
标签：
> [标签一][X] [标签二][X] [标签三][X] | [未选中的标签四] [未选中的标签五] [新增标签]  

## 后端设计：

### Tag 表：
| id | user_id | color | created_at |
| --- | --- | --- | --- |
| 标签id | 用户id | 标签颜色(red,blue,green) | 创建时间 |

### NoteTag 表 (note和tag的关系表，多对多)
| note_id | tag_id  | updated_at |
| --- | --- | --- |
| 笔记id | 标签id  | 更新时间 |


## 前端设计（基于事件的增量更新设计，防抖的增量更新提交）：

> 设计理念：复用 NoteBlock 的"事件分发 → pending 缓存 → debounce → 批量提交"模式，
> 但把**标签关联**和**块内容**放在两个**独立**的服务里，把原来的_saveService重命名为_noteBlokcService，现在的服务命名为_tagService实现服务解耦。

---

### 一、整体架构对比

```
┌────────────────────────────────────────────────────────────────┐
│                    NoteEditor / SaveService          │
├─────────────────────────────┬──────────────────────────────────┤
│  Block 内容Service (已有)       │  Tag 关联Service (新增)             │
├─────────────────────────────┼──────────────────────────────────┤
│  触发：插入/删除/编辑块      │  触发：添加/移除标签             │
│  pending:_pending (Map)      │  pending:_pendingTags (Map)     │
│  debounce:_debounceTimer     │  debounce:_tagDebounceTimer     │
│  flush:_flushPending()       │  flush:_flushTags()             │
│  diff:NoteBlockDiff          │  diff:NoteTagDiff               │
│  endpoint:/noteBlock/batch   │  endpoint:/noteTag/batch        │
│  result:NoteDiffResult       │  result:NoteTagDiffResult       │
└─────────────────────────────┴──────────────────────────────────┘
```

两个通道**互相独立**：内容保存失败不影响标签提交，反之亦然。各自维护自己的冲突标记和 retry 逻辑。

---

### 二、数据模型

#### 1. NoteTagDiff（请求体，类似 NoteBlockDiff）

```dart
class NoteTagDiff {
  // 要新增的 (note_id, tag_id) 关联
  final List<int> addTagIds;       // [tagId1, tagId2, ...]
  // 要删除的 (note_id, tag_id) 关联
  final List<int> removeTagIds;    // [tagId3, tagId4, ...]
  // 需要创建的标签（前端临时生成的），提交时先创建再关联
  final List<Tag> newTags;
  // /lib/models/tag.dart ->Tag

  Map<String, dynamic> toJson() => {
        'addTagIds': addTagIds,
        'removeTagIds': removeTagIds,
        'newTags': newTags,
      };
}
```

#### 2. NoteTagDiffResult（响应体，类似 NoteDiffResult）

```dart
class NoteTagDiffResult {
  // 后端为每个 newTag 返回的 (临时代号 → 真实 tagId) 映射
  final Map<String, int> createdTagIds;
  // 创建失败的标签临时id
  final List<String> failCreatedTags;
  // 添加失败（关联已存在/版本冲突等）的 tagId
  final List<int> failAddedTags;
  // 删除失败（关联不存在/版本冲突等）的 tagId
  final List<int> failRemovedTags;

  bool get hasConflict =>
      failCreatedTags.isNotEmpty ||
      failAddedTags.isNotEmpty ||
      failRemovedTags.isNotEmpty;
}
```

#### 3. 新建标签的前端临时 ID

新增标签时没有服务端 tagId，需要一个**本地临时标识**来追踪：

```dart
// 每个新建标签用 "temp_${nanoid}" 作为临时 id
// 创建成功后，后端在 NoteTagDiffResult.createdTagIds 中返回 { 临时代号 → 真实 id }
// 用真实 id 替换本地缓存中的临时代号
```

---

### 三、事件模型

#### 1. TagOperation（类似 _PendingBlock）

```dart
enum TagChangeType { add, remove, create }

class _PendingTag {
  final int tagId;              // 已存在标签用真实 id；新建标签用 tempId（负数/字符串）
  final String? tempId;         // 仅新建标签有，用于接收后端返回的真实 id
  final String? tagName;        // 新建标签的名称
  final String? tagColor;       // 新建标签的颜色
  final TagChangeType changeType;
}
```

#### 2. dispatch 事件分发（新增到 IncrementalSaveService）

```dart
// 添加标签关联
void addTag(int tagId);
// 移除标签关联
void removeTag(int tagId);
// 创建新标签并关联（用户输入新标签名时调用）
void createAndAddTag(String name, String? color);
```

每个操作都会：
1. 把 `_PendingTag` 写入 `_pendingTags` 缓存（Map，key 用 tagId 或 tempId）
2. 启动 `_tagDebounceTimer`
3. 防抖时间到后调用 `_flushTags()`

**合并优化**：同一标签的 add → remove 会互相抵消（从 pending 中移除），减少无效提交。**(有tag_id的add操作是不是应该移除掉，因为说明后端还有他的记录，可能只是一次幂等操作)**

```dart
void _dispatchTag(TagChangeType type, int tagId,
    {String? tempId, String? tagName, String? tagColor}) {
  if (type == TagChangeType.remove && _pendingTags[tagId]?.changeType == TagChangeType.add) {
    _pendingTags.remove(tagId);   // add + remove 抵消
    if (_pendingTags.isNotEmpty) _tagDebounce();
    return;
  }
  if (type == TagChangeType.add && _pendingTags[tagId]?.changeType == TagChangeType.remove) {
    _pendingTags.remove(tagId);
    if (_pendingTags.isNotEmpty) _tagDebounce();
    return;
  }
  _pendingTags[tagId] = _PendingTag(...);
  _tagDebounce();
}
```

---

### 四、防抖与批量提交（复用 _flushPending 模式）

#### _flushTags() 流程

```
1. 取出 _pendingTags 的快照，清空 _pendingTags
2. 如果快照为空，跳过
3. 分类：
   - 新建标签（has tempId）→ 构建 newTags 列表
   - add 操作     → 构建 addTagIds 列表
   - remove 操作  → 构建 removeTagIds 列表
4. POST /noteTag/batch 提交 NoteTagDiff(noteId: _noteId, diff)
5. 处理响应：
   - 全部成功：
     · 用 createdTagIds 把本地 tempId 映射为真实 tagId
     · 更新 NoteInfoSheet 中显示的标签列表
     · 标记最近保存时间
   - 有冲突/失败：
     · 失败的 _PendingTag 重新放回 _pendingTags（等下次 debounce 重试）
     · 显示 "部分标签保存失败，请刷新" Toast
```

**时序示意**：

```
用户点击标签 → dispatch → _pendingTags[{tagId:1, add}] → 启动 3s 防抖
用户再点另一个 → dispatch → _pendingTags[{1:add, 4:add}]
用户点移除 → dispatch → _pendingTags[{1:add}] (4 抵消)
... 3s 后 → _flushTags() → POST /noteTag/batch
```

---

### 五、UI 层集成（NoteInfoSheet）

#### 5.1 弹窗打开时加载当前标签

```dart
_showNoteInfoSheet() {
  // 加载笔记的最新标签列表
  _saveService.tryLoadTags();
  // 弹窗中显示的标签来自 _saveService.currentTags
  // 用户操作（点击 Chip deleteIcon / 点击 + 添加）→ 调用 saveService 的 dispatch 方法
}
```

#### 5.2 标签列表 UI

```dart
// 已选中的标签：显示为带 [X] 的 Chip，点击 X 触发 removeTag
// 可添加标签：从常用标签列表选择，或输入框新建
Wrap(
  children: [
    // 已选标签
    ..._saveService.currentTags.map((tag) => Chip(
      label: Text(tag.name),
      backgroundColor: tag.colorToColor(),
      deleteIcon: Icon(Icons.close, size: 16),
      onDeleted: () => _saveService.removeTag(tag.id),
    )),
    // 可添加标签（未选中的）
    ..._availableTags.map((tag) => ActionChip(
      label: Text(tag.name),
      onPressed: () => _saveService.addTag(tag.id),
    )),
  ],
)
```

#### 5.3 弹窗关闭时强制提交

```dart
// 用户点击"保存"或关闭弹窗时
_saveService.flushTags();   // 类似 _saveService.flush()，取消防抖并立即提交
// 然后才关闭弹窗
```

---

### 六、后端 API 设计

#### 1. POST /noteTag/batch — 批量更新标签关联

**请求**：
```json
{
  "noteId": 123,
  "addTagIds": [4, 5],
  "removeTagIds": [3],
  "newTags": [
    {"name": "工作", "color": "blue"}
  ]
}
```

**响应**（成功）：
```json
{
  "code": 200,
  "data": {
    "createdTagIds": {"temp_abc123": 42},
    "failCreatedTags": [],
    "failAddedTags": [],
    "failRemovedTags": []
  }
}
```

**响应**（有冲突）：
```json
{
  "code": 200,
  "data": {
    "createdTagIds": {"temp_abc123": 42},
    "failCreatedTags": ["重名标签"],
    "failAddedTags": [],
    "failRemovedTags": [3]
  }
}
```

**后端逻辑**：
1. 创建 newTags → 写入 Tag 表，记录 (临时代号, 真实 id) 映射
2. 添加 addTagIds → 写入 NoteTag 表（已存在则忽略，不算冲突）
3. 删除 removeTagIds → 从 NoteTag 表删除
4. 记录失败的项到对应字段

#### 2. GET /noteTag/list — 获取笔记的标签列表

```
GET /noteTag/list?noteId=123
→ [{"id": 1, "name": "标签一", "color": "red"}, ...]
```

#### 3. GET /tag/list — 获取用户的标签列表（用于"可添加"列表）

```
GET /tag/list?userId=1
→ [{"id": 1, "name": "标签一", "color": "red"}, ...]
```

---

### 七、与 NoteBlock 通道的交互

| 操作 | 影响通道 | 说明 |
|------|----------|------|
| 编辑正文 | Block 通道 | 不变 |
| 修改标题 | Block 通道（已有） | 不变 |
| 刷新 | 两个通道都刷新 | `_onRefresh` 先 `flushTags()`，再 `tryLoadTags()` |
| 保存（check 按钮） | 两个通道都 flush | `_saveNote` 改为同时 `await flushTags()` |
| 切换笔记本 | 只影响 Block 通道 | 不变 |

---

### 八、冲突处理与重试（复用 NoteBlock 模式）

- **冲突时**：失败项重新放入 `_pendingTags`，下次 debounce 自动重试
- **版本冲突**（409）：整个 batch 失败，全部放回 pending + 提示用户刷新
- **提示**：`"有 X 个标签保存失败，请刷新页面"`，类似 NoteBlock 的 `"有 N 个块冲突"`
- **刷新时**：先 flush 所有 pending，再从服务端重新加载最新状态覆盖本地缓存

---

### 九、文件结构规划

```
lib/models/
  tag.dart                           # (已有) Tag 模型
  note_tag_diff.dart                 # 新增：NoteTagDiff
  note_tag_diff_result.dart          # 新增：NoteTagDiffResult

lib/screens/note/mixins/
  incremental_save.dart              # 原来的NoteBlock 通道 
  note_tag_save.dart                 # 新增的NoteTag通道

lib/screens/note/note_editor.dart    # 修改：UI 接入标签操作
```

---

### 十、关键约束与注意事项

1. **标签与块内容通道独立**：不共享 version，互不干扰
2. **新建标签的 ID 映射**：前端用临时代号，后端在响应中返回真实 id，下次操作使用真实 id
3. **重复标签处理**：同一标签重复 add 应幂等（忽略重复，不报错）
4. **标签创建失败**：如果后端返回创建失败（如重名），前端重新放回 pending 并提示用户
5. **刷新优先级**：刷新时先 flush pending，再加载服务端最新，避免本地 pending 与服务端不一致
6. **弹窗关闭清理**：关闭弹窗前必须 flush，防止 pending 丢失

---

### 附录：与 NoteBlock 模式对照表

| NoteBlock 模式 | Tag 模式对应 |
|---|---|
| `_PendingBlock` | `_PendingTag` |
| `_pending` (Map) | `_pendingTags` (Map) |
| `_debounceTimer` | `_tagDebounceTimer` |
| `_flushPending()` | `_flushTags()` |
| `NoteBlockDiff` | `NoteTagDiff` |
| `NoteDiffResult` | `NoteTagDiffResult` |
| `/noteBlock/batchUpdate` | `/noteTag/batch` |
| `Transaction` / `apply` | 无（标签是纯 API 操作） |
| `_assignOrderKey` | 无（标签关联有序键，由后端管理） |
| `_markNodeError` | 无（标签错误在 UI 层标记） |
