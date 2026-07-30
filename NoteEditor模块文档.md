# NoteEditor 模块文档

解耦后 `note_editor.dart` 从 1072 行瘦身到 ~480 行，各职责按 UI 边界拆分到独立文件。

## 文件结构

```
lib/screens/note/
├── note_editor.dart              # 主页面骨架，状态管理 + 协调逻辑
├── mixins/
│   ├── incremental_save.dart     # 增量保存服务（内容 + 摘要）
│   └── tag_service.dart          # 标签增量更新服务
└── widgets/
    ├── table_toolbar_items.dart  # 表格工具栏按钮（原有）
    ├── table_action_menu.dart    # 表格操作菜单（原有）
    ├── table_size_picker.dart    # 表格尺寸选择器（原有）
    ├── floating_toolbar.dart     # 选中文本浮动工具栏
    ├── create_tag_dialog.dart    # 新增标签弹窗
    ├── note_info_sheet.dart      # 笔记信息 bottom sheet
    ├── notebook_sheet.dart       # 笔记本选择/新建 bottom sheet
    └── save_status_overlay.dart  # 保存状态指示器
```

## 各文件职责

### `note_editor.dart`
主页面 StatefulWidget，保留核心骨架：
- 初始化 `EditorState`、`IncrementalSaveService`、`TagService`
- 编辑器事务流订阅、选区状态管理
- 剪贴板操作（复制/剪切/粘贴/全选）
- `_saveNote()` — 同时 flush 内容 + 标签
- `_onRefresh()` — 刷新笔记内容、chunks、标签
- `build()` — AppBar + 标题输入 + 信息栏 + 编辑器 + 组装子 Widget
- 作为两个 sheet 的入口，负责数据预加载和遮罩状态控制

### `mixins/incremental_save.dart`
增量保存服务（已有，未改动），负责笔记正文、摘要、笔记本的本地缓存 + 防抖 + 批量提交到后端。

### `mixins/tag_service.dart`
标签增量更新服务（已有，未改动），负责标签关联的本地缓存 + 防抖 + 批量提交，以及同步创建新标签的 `createAndAddTag`。

### `widgets/floating_toolbar.dart`
**`EditorFloatingToolbar`** — 选中文本时在选区上方显示的浮动菜单：
- 4 个按钮：复制、剪切、粘贴、全选
- 根据选区 `selectionRects` 自动定位
- 所有操作通过构造函数回调传入，无内部依赖

### `widgets/create_tag_dialog.dart`
**`showCreateTagDialog(context)`** — 新增标签弹窗：
- 名称输入（TextField，非空校验）
- 7 色圆点颜色选择器（红/橙/黄/绿/蓝/紫/灰）
- 返回 `CreateTagResult?`（name + colorHex），取消返回 null
- 不直接调用 API，由调用方拿到结果后自行处理

### `widgets/note_info_sheet.dart`
**`showNoteInfoSheet(...)`** — 笔记信息 bottom sheet：
- 摘要编辑（TextField，maxLines:3）
- 当前标签列表（Chip，可删除）
- 可添加标签列表（ActionChip，可点击添加）
- "新增标签"按钮 → 调起 `showCreateTagDialog` → `createAndAddTag`
- "保存"按钮 → flush 标签 → 显示保存遮罩 → pop
- 数据（`tryLoadTags` / `tryLoadAllUserTags`）由调用方预加载后传入

### `widgets/notebook_sheet.dart`
**`showNotebookSheet(...)`** — 笔记本 bottom sheet：
- 笔记本列表（单选 radio 样式），点击切换 → 确认弹窗 → 调用 `/note/editNotebook`
- "新建笔记本"入口 → 弹窗输入名称 → 调用 `/notebook/add` → 刷新列表
- 切换/新建成功后的状态回调由调用方通过 `onSelectedNotebookChanged` / `onReloadNotebooks` 处理

**`SelectNotebookButton`** — 底部信息栏中显示当前笔记本名称的下拉按钮，点击触发 `showNotebookSheet`

### `widgets/save_status_overlay.dart`
**`SaveStatusOverlay`** — 右下角保存状态指示器：
- 保存中：带淡入淡出动画的圆形进度指示器
- 保存后：底部居中显示"最近一次保存: HH:mm:ss"
- 接收两个 `ValueNotifier` 参数，纯展示，无业务逻辑
