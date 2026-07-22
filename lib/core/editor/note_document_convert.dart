import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:note_for_android/models/note_block.dart';
import 'package:note_for_android/models/note_detail.dart';

/// NoteDetail ↔ AppFlowyEditor Document 转换工具
///
/// 将后端返回的笔记块列表转为 EditorState 可用的 Document，
/// 同时将每个块的数据库 id 和 version 存入 Node.attributes，
/// 以便在 transactionStream 中追踪变化并回写后端。
class NoteDocumentConvert {
  NoteDocumentConvert._();

  // ---- 自定义属性 key，避免与 AppFlowyEditor 内置 key 冲突 ----

  /// 数据库主键 NoteBlock.id
  static const String attrBlockId = 'chunkId';

  /// 乐观锁版本号 NoteBlock.version
  static const String attrBlockVersion = 'chunkVersion';

  /// 持久化块的排序键
  static const String attrBlockOrderKey = 'chunkOrderKey';

  // ---- 构建 ----

  /// 从 NoteDetail 构建 EditorState
  static EditorState toEditorState(NoteDetail detail) {
    return EditorState(document: toDocument(detail.blocks));
  }

  /// 从 NoteBlock 列表构建 Document
  static Document toDocument(List<NoteBlock> blocks) {
    final children = <Node>[];
    for (final block in blocks) {
      children.add(_blockToNode(block));
    }
    return Document(
      root: Node(type: 'page', children: children),
    );
  }

  // ---- 转换 ----

  /// NoteBlock → AppFlowyEditor Node
  ///
  /// 如果 deltaJson 是完整的 Node JSON 格式（{type, data, children}），
  /// 直接用 Node.fromJson 还原整棵子树，嵌套的子块也会被还原。
  static Node _blockToNode(NoteBlock block) {
    if (block.deltaJson is Map<String, Object>) {
      final node = Node.fromJson(block.deltaJson as Map<String, Object>);
      // 注入数据库 id / version / orderKey
      node.updateAttributes({
        attrBlockId: block.id,
        attrBlockVersion: block.version,
        attrBlockOrderKey: block.orderKey,
      });
      return node;
    }

    // 兜底：deltaJson 是纯 delta 列表（旧格式/平铺格式）
    return _legacyBlockToNode(block);
  }

  /// 兼容旧格式：deltaJson 是纯 delta 列表，只构建单个节点
  static Node _legacyBlockToNode(NoteBlock block) {
    final attributes = <String, dynamic>{
      attrBlockId: block.id,
      attrBlockVersion: block.version,
      attrBlockOrderKey: block.orderKey,
    };

    if (block.deltaJson != null) {
      attributes[blockComponentDelta] = _parseDelta(block.deltaJson);
    }

    // 根据块类型补充额外属性
    final type = _mapType(block.type!);
    if (type == HeadingBlockKeys.type) {
      final level = _parseHeadingLevel(block.deltaJson);
      if (level != null) {
        attributes[HeadingBlockKeys.level] = level;
      }
    } else if (type == TodoListBlockKeys.type) {
      final checked = _parseTodoChecked(block.deltaJson);
      attributes[TodoListBlockKeys.checked] = checked;
    }

    return Node(type: type, attributes: attributes);
  }

  /// 解析 deltaJson 为 AppFlowyEditor 的 delta List 格式
  ///
  /// deltaJson 可能有多种形态：
  ///   - List: 直接作为 delta 内容
  ///   - Map with "ops" key: 提取 ops 数组
  ///   - null: 返回空段落
  static List<dynamic> _parseDelta(dynamic deltaJson) {
    if (deltaJson == null) {
      return [
        {'insert': '\n'},
      ];
    }
    if (deltaJson is List) {
      return deltaJson;
    }
    if (deltaJson is Map && deltaJson['ops'] is List) {
      return deltaJson['ops'] as List;
    }
    return [
      {'insert': '\n'},
    ];
  }

  /// 从 heading 块的 deltaJson 中解析 heading level
  static int? _parseHeadingLevel(dynamic deltaJson) {
    // heading level 通常来自 attributes 而非 deltaJson
    // 返回 null 让 AppFlowyEditor 使用默认值
    return null;
  }

  /// 从 todo 块的 deltaJson 中解析 checked 状态
  static bool _parseTodoChecked(dynamic deltaJson) {
    return false;
  }

  /// 映射后端块类型 → AppFlowyEditor 块类型
  static String _mapType(String dbType) {
    switch (dbType) {
      case 'paragraph':
        return ParagraphBlockKeys.type;
      case 'heading':
        return HeadingBlockKeys.type;
      case 'bulleted_list':
        return BulletedListBlockKeys.type;
      case 'numbered_list':
        return NumberedListBlockKeys.type;
      case 'todo_list':
        return TodoListBlockKeys.type;
      case 'quote':
        return QuoteBlockKeys.type;
      case 'divider':
        return 'divider';
      default:
        return ParagraphBlockKeys.type;
    }
  }

  // ---- 反向转换（Document → NoteBlock 列表） ----

  /// 从 EditorState 的 Document 提取 NoteBlock 列表
  /// 用于全量保存时重建 blocks
  static List<NoteBlock> toBlockList(Document document, {required int noteId}) {
    final blocks = <NoteBlock>[];
    final now = DateTime.now();
    int i = 0;
    for (final node in document.root.children) {
      if (node.type == 'page') continue;

      blocks.add(
        _nodeToBlock(
          node,
          noteId: noteId,
          orderKey: _orderKeyForIndex(i),
          now: now,
        ),
      );
      i++;
    }

    return blocks;
  }

  /// AppFlowyEditor Node → NoteBlock
  ///
  /// 将整个节点（含子节点）保存为 deltaJson，格式为 {type, data, children}，
  /// 与 AppFlowyEditor 的 Node.toJson() 一致，以便下次加载时完整还原嵌套结构。
  static NoteBlock _nodeToBlock(
    Node node, {
    required int noteId,
    required String orderKey,
    required DateTime now,
  }) {
    final blockId = node.attributes[attrBlockId] as String?;
    final version = (node.attributes[attrBlockVersion] as num?)?.toInt() ?? 1;

    // 保存完整的 Node JSON（含 type / data / children）
    final deltaJson = node.toJson();

    // 反向映射类型
    final type = _reverseMapType(node.type);

    return NoteBlock(
      id: blockId,
      type: type,
      orderKey: orderKey,
      deltaJson: deltaJson,
      version: version,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// AppFlowyEditor 块类型 → 后端块类型
  static String _reverseMapType(String editorType) {
    switch (editorType) {
      case 'paragraph':
        return 'paragraph';
      case 'heading':
        return 'heading';
      case 'bulleted_list':
        return 'bulleted_list';
      case 'numbered_list':
        return 'numbered_list';
      case 'todo_list':
        return 'todo_list';
      case 'quote':
        return 'quote';
      case 'divider':
        return 'divider';
      default:
        return 'paragraph';
    }
  }

  /// 根据索引生成简单的 orderKey
  static String orderKeyForIndex(int index) {
    return _orderKeyForIndex(index);
  }

  /// 根据索引生成简单的 orderKey
  static String _orderKeyForIndex(int index) {
    if (index < 26) {
      return String.fromCharCode(97 + index); // a, b, c, ...
    }
    // 超过 26 个块时用 aa, ab, ac ...
    return 'a${String.fromCharCode(97 + (index - 26))}';
  }

  // ────────────────────────────────────────────────────────────────
  //  orderKey 生成器 — 基于 lexicographic midpoint 算法
  // ────────────────────────────────────────────────────────────────

  /// 在两个相邻块的 orderKey 之间生成一个新 key
  ///
  /// [prev]  前一个块的 orderKey，`null` 表示插入到开头
  /// [next]  后一个块的 orderKey，`null` 表示插入到末尾
  ///
  /// 保证返回的字符串满足 `prev < result < next`（仅使用 a-z 字符）。
  ///
  /// 算法：将字符串视为 base-26 分数，取两个邻居之间的中点。
  /// 如果 prev 和 next 之间已经没有空隙（相邻），抛出 [StateError]，
  /// 此时需要对一批块重新分配 orderKey（rebalance）。
  static String generateOrderKey(String? prev, String? next) {
    // 空列表 → 从中间开始
    if (prev == null && next == null) return 'n';

    final buf = StringBuffer();
    int i = 0;

    while (true) {
      // 字符编码：a=0, b=1, ..., z=25
      // 超出字符串长度：prev 用 -1（最小），next 用 26（最大）
      final ca = (prev != null && i < prev.length)
          ? prev.codeUnitAt(i) - 97
          : -1;
      final cb = (next != null && i < next.length)
          ? next.codeUnitAt(i) - 97
          : 26;

      // 相同字符（且在有效范围内）→ 保留，继续下一位
      if (ca == cb && ca >= 0 && ca <= 25) {
        buf.writeCharCode(ca + 97);
        i++;
        continue;
      }

      // ------- prev 已到末尾 -------
      if (ca == -1) {
        // 在 'a'(0) 和 cb 之间取中点
        final mid = (0 + cb) ~/ 2;
        if (mid == 0 && cb == 0) {
          // prev 和 next 相邻，没有空隙 → 需要 rebalance
          throw StateError(
            'orderKey 已耗尽: prev="$prev", next="$next" 之间没有空隙，'
            '需要 rebalance',
          );
        }
        buf.writeCharCode(mid + 97);
        break;
      }

      // ------- 正常情况：ca 和 cb 不同 -------
      final mid = (ca + cb) ~/ 2;
      if (mid == ca) {
        // 中点和 ca 相同，说明 ca 和 cb 相邻，保留 ca 继续下一位
        buf.writeCharCode(ca + 97);
        i++;
        continue;
      }

      buf.writeCharCode(mid + 97);
      break;
    }

    return buf.toString();
  }

  /// 当 orderKey 耗尽时，对一批块重新分配 key
  ///
  /// 把 [blocks] 从 startIndex 开始重新分配为 "a", "b", "c", ... 的间隔，
  /// 留出未来插入的空隙。返回新的列表。
  static List<NoteBlock> rebalanceOrderKeys(
    List<NoteBlock> blocks, {
    int startIndex = 0,
  }) {
    final now = DateTime.now();
    return blocks.asMap().entries.map((entry) {
      final i = entry.key;
      final block = entry.value;
      return block.copyWith(
        orderKey: _orderKeyForIndex(i - startIndex),
        updatedAt: now,
      );
    }).toList();
  }
}
