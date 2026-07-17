import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// 弹窗提示工具类 — 基于 toastification 封装
///
/// 使用前需在 MaterialApp 外层包裹 [ToastificationWrapper]：
/// ```dart
/// ToastificationWrapper(
///   child: MaterialApp(...),
/// )
/// ```
///
/// 使用示例：
/// ```dart
/// ToastUtil.success(context, title: '操作成功');
/// ToastUtil.error(context, title: '网络错误', description: '请检查网络连接');
/// ```
class ToastUtil {
  ToastUtil._();

  /// 成功提示（底部居中，绿色）
  static void success(
    BuildContext context, {
    required String title,
    String? description,
    AlignmentGeometry alignment = Alignment.bottomCenter,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      type: ToastificationType.success,
      title: title,
      description: description,
      alignment: alignment,
      duration: duration,
    );
  }

  /// 错误提示（底部居中，红色，默认显示 4 秒）
  static void error(
    BuildContext context, {
    required String title,
    String? description,
    AlignmentGeometry alignment = Alignment.bottomCenter,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      type: ToastificationType.error,
      title: title,
      description: description,
      alignment: alignment,
      duration: duration,
    );
  }

  /// 警告提示（顶部居中，黄色/橙色）
  static void warning(
    BuildContext context, {
    required String title,
    String? description,
    AlignmentGeometry alignment = Alignment.topCenter,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      type: ToastificationType.warning,
      title: title,
      description: description,
      alignment: alignment,
      duration: duration,
    );
  }

  /// 信息提示（底部居中，蓝色）
  static void info(
    BuildContext context, {
    required String title,
    String? description,
    AlignmentGeometry alignment = Alignment.bottomCenter,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      type: ToastificationType.info,
      title: title,
      description: description,
      alignment: alignment,
      duration: duration,
    );
  }

  /// 底层调用
  static void _show(
    BuildContext context, {
    required ToastificationType type,
    required String title,
    String? description,
    AlignmentGeometry alignment = Alignment.bottomCenter,
    Duration duration = const Duration(seconds: 3),
  }) {
    toastification.show(
      context: context,
      type: type,
      style: ToastificationStyle.flat,
      alignment: alignment,
      autoCloseDuration: duration,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      description: description != null
          ? Text(
              description,
              style: const TextStyle(fontSize: 13),
            )
          : null,
      showProgressBar: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}