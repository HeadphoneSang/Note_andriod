import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 节点属性中标记冲突的 key（与 incremental_save.dart 中的一致）
const String chunkErrorAttribute = 'chunkError';

/// 将标准文本块构建器包装成"冲突提示"构建器
///
/// 当块节点的 `chunkError` 属性为 true（保存冲突）时，在块右上角叠加一个
/// "冲突"徽标，让用户一眼看到哪部分内容没保存成功，而不是只有背景色。
/// 非冲突块直接透传标准构建结果，不额外包裹，避免影响渲染与手势。
class ConflictBadgeBlockBuilder extends BlockComponentBuilder {
  ConflictBadgeBlockBuilder(this._inner) {
    // 代理标准构建器的所有配置字段
    configuration = _inner.configuration;
    validate = _inner.validate;
    showActions = _inner.showActions;
    actionBuilder = _inner.actionBuilder;
    actionTrailingBuilder = _inner.actionTrailingBuilder;
  }

  /// 被包装的标准块构建器（paragraph/heading/quote/todo/list 等）
  final BlockComponentBuilder _inner;

  @override
  BlockComponentWidget build(BlockComponentContext context) {
    final inner = _inner.build(context);
    if (context.node.attributes[chunkErrorAttribute] != true) {
      return inner;
    }
    return _ConflictBadgeStack(
      node: inner.node,
      configuration: inner.configuration,
      showActions: inner.showActions,
      actionBuilder: inner.actionBuilder,
      actionTrailingBuilder: inner.actionTrailingBuilder,
      child: inner,
    );
  }
}

/// 冲突块外层：在块右上角叠加"冲突"徽标，同时实现 [BlockComponentWidget]
/// 接口，让 AppFlowy 渲染器仍能正常识别该块（node/configuration 等）。
class _ConflictBadgeStack extends StatelessWidget
    implements BlockComponentWidget {
  const _ConflictBadgeStack({
    required this.child,
    required this.node,
    required this.configuration,
    required this.showActions,
    this.actionBuilder,
    this.actionTrailingBuilder,
  });

  /// 标准构建器返回的块组件
  final Widget child;

  @override
  final Node node;

  @override
  final BlockComponentConfiguration configuration;

  @override
  final bool showActions;

  @override
  final BlockComponentActionBuilder? actionBuilder;

  @override
  final BlockComponentActionTrailingBuilder? actionTrailingBuilder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        const Positioned(top: 6, right: 6, child: _ConflictBadge()),
      ],
    );
  }
}

/// 冲突块的"冲突"徽标 — 红色警示图标 + 文字，不拦截触摸事件
class _ConflictBadge extends StatelessWidget {
  const _ConflictBadge();

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFD32F2F);
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF44336).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFFF44336).withValues(alpha: 0.45),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 12, color: red),
            SizedBox(width: 3),
            Text('冲突', style: TextStyle(fontSize: 10, color: red)),
          ],
        ),
      ),
    );
  }
}

/// 需要叠加冲突徽标的文本块类型
const Set<String> _conflictAwareBlockTypes = {
  ParagraphBlockKeys.type,
  HeadingBlockKeys.type,
  QuoteBlockKeys.type,
  TodoListBlockKeys.type,
  BulletedListBlockKeys.type,
  NumberedListBlockKeys.type,
};

/// 生成支持冲突徽标的标准块构建器集合
///
/// 直接作为 [AppFlowyEditor.blockComponentBuilders] 传入即可，例如：
/// ```dart
/// AppFlowyEditor(
///   blockComponentBuilders: buildConflictAwareBlockComponentBuilders(),
///   ...
/// )
/// ```
Map<String, BlockComponentBuilder> buildConflictAwareBlockComponentBuilders({
  Map<String, BlockComponentBuilder>? builders,
}) {
  final source = builders ?? standardBlockComponentBuilderMap;
  final result = <String, BlockComponentBuilder>{...source};
  for (final type in _conflictAwareBlockTypes) {
    final inner = source[type];
    if (inner != null) {
      result[type] = ConflictBadgeBlockBuilder(inner);
    }
  }
  return result;
}
