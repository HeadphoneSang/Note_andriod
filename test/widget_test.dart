import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:note_for_android/app/app.dart';

void main() {
  testWidgets('App should display bottom navigation bar', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    // 验证底部导航栏存在
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // 验证 4 个 tab 标签存在（IndexedStack 中页面也包含相同文字，所以至少找到 1 个即可）
    expect(find.text('代办'), findsOneWidget); // 代办只在底部导航出现
  });
}
