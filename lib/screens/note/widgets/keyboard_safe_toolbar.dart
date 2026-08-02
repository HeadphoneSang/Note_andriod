import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 工具栏点击焦点保护
///
/// AppFlowy 编辑器在失焦时会清空选区并关闭键盘（keyboard_service_widget 的
/// `_onFocusChanged`），而 MobileToolbar 依据选区渲染 —— 点击工具栏按钮抢占焦点后
/// 就会触发"工具栏 + 输入法一起收起"。
///
/// 解决方式：点击工具栏期间提升全局 [keepEditorFocusNotifier]，让编辑器失焦时跳过
/// 清选区和关键盘；焦点离开工具栏或延迟后自动释放。这同时兼容带菜单的按钮
/// （菜单里的 URL 输入框持有焦点时保持保护）。
class KeyboardSafeToolbar extends StatefulWidget {
  const KeyboardSafeToolbar({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardSafeToolbar> createState() => _KeyboardSafeToolbarState();
}

class _KeyboardSafeToolbarState extends State<KeyboardSafeToolbar> {
  final _focusNode = FocusNode();
  Timer? _releaseTimer;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _releaseHold();
    _focusNode.dispose();
    super.dispose();
  }

  /// 焦点离开工具栏（用户点了编辑器/其它区域）→ 立即释放保护
  /// [FocusNode.hasFocus]：本节点聚焦或位于 primaryFocus 祖先链上 = 焦点在本子树内
  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _holding) {
      _releaseHold();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _releaseTimer?.cancel();
    if (!_holding) {
      _holding = true;
      keepEditorFocusNotifier.increase();
    }
  }

  void _onPointerUp(PointerUpEvent event) => _scheduleRelease();

  void _onPointerCancel(PointerCancelEvent event) => _scheduleRelease();

  void _scheduleRelease() {
    // 延迟释放：给按钮 action / 菜单打开 / 输入框 autofocus 留出时间
    _releaseTimer?.cancel();
    _releaseTimer = Timer(const Duration(milliseconds: 250), _maybeRelease);
  }

  void _maybeRelease() {
    if (!_holding) return;
    // 焦点仍在工具栏内（如链接 URL 输入框）→ 继续持有
    if (_focusNode.hasFocus) return;
    _releaseHold();
  }

  void _releaseHold() {
    if (_holding) {
      _holding = false;
      keepEditorFocusNotifier.decrease();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: widget.child,
      ),
    );
  }
}
