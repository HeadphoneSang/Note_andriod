# 基于 Flutter + Spring Boot 的 Block 笔记系统设计方案

## 1. 目标

构建一个支持富文本、块级编辑、历史版本、分页加载和后续协同编辑能力的笔记系统。

技术栈：

-   前端：Flutter（flutter_quill）
-   后端：Spring Boot
-   数据库：MySQL
-   缓存：Redis

------------------------------------------------------------------------

## 2. 总体架构

    Flutter
       │
    HTTP/WebSocket
       │
    Spring Boot
       ├── Redis（缓存）
       └── MySQL（持久化）

数据结构：

    Notebook
     └── Note
          ├── Block
          ├── Block
          ├── Block
          └── ...

Note 只保存元数据，正文全部由 Block 组成。

------------------------------------------------------------------------

## 3. Block 设计

### 3.1 Block 粒度

采用**语义块（Semantic Block）**。

一个块代表一个块级元素，而不是固定字数。

  类型         是否独立 Block
  ------------ --------------------------
  Heading      是
  Paragraph    是（一个段落一个 Block）
  Code Block   是
  Image        是
  Quote        是
  Divider      是
  Table        是
  Todo/List    建议每个列表项一个 Block

普通段落内部可以包含多行（Shift+Enter），仍属于同一个 Block。

### 3.2 Block 内容

Block 内部使用 Quill Delta 保存格式。

示例：

``` json
{
  "id":1,
  "type":"paragraph",
  "order":1000,
  "delta":{
    "ops":[
      {"insert":"今天学习 "},
      {"attributes":{"bold":true},"insert":"Spring Boot"},
      {"insert":"\n"}
    ]
  }
}
```

------------------------------------------------------------------------

## 4. 数据库设计

### note

  字段          说明
  ------------- ----------
  id            主键
  title         标题
  summary       摘要
  cover         封面
  user_id       用户
  create_time   创建时间
  update_time   更新时间

### note_block

  字段          说明
  ------------- -------------
  id            主键
  note_id       所属笔记
  order_key     排序键
  type          Block 类型
  delta_json    Quill Delta
  version       版本号
  create_time   创建时间
  update_time   更新时间

建议 order_key 使用带间隔整数（1000、2000......）或 LexoRank。

------------------------------------------------------------------------

## 5. 编辑流程

加载：

1.  获取 Note 元数据
2.  查询 Block 列表
3.  Block 转换为 Quill Document
4.  Flutter 渲染

保存：

1.  前端比较 Block 变化
2.  仅提交新增、修改、删除的 Block
3.  后端更新 MySQL
4.  同步 Redis

避免每次保存整篇文档。

------------------------------------------------------------------------

## 6. Redis 缓存

Key：

    note:{noteId}

缓存：

    [
     Block1,
     Block2,
     Block3
    ]

更新 Block 时同步刷新缓存对应内容。

------------------------------------------------------------------------

## 7. API

### 获取笔记

GET /api/notes/{id}

### 新增 Block

POST /api/blocks

### 修改 Block

PUT /api/blocks/{id}

### 删除 Block

DELETE /api/blocks/{id}

### 调整顺序

PATCH /api/blocks/{id}/order

------------------------------------------------------------------------

## 8. 图片

图片上传对象存储（MinIO、OSS、S3 等），Block 保存图片 URL
及尺寸信息，不保存 Base64。

------------------------------------------------------------------------

## 9. 历史版本（可选）

增加 note_block_history：

-   block_id
-   version
-   delta_json
-   operator
-   create_time

支持撤销、恢复和版本查看。

------------------------------------------------------------------------

## 10. 后续扩展

-   全文搜索
-   标签
-   双向链接
-   Block 引用
-   AI 总结指定 Block
-   WebSocket 协同编辑（OT/CRDT）
-   Markdown 导入导出

------------------------------------------------------------------------

## 11. 推荐原则

-   Note 保存元数据。
-   Block 是最小编辑单元。
-   一个段落对应一个 Paragraph Block。
-   Block 内部保存完整 Quill Delta。
-   仅同步变化 Block，提高性能并降低冲突。
