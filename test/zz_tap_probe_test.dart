import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap in editor changes scroll offset?', (tester) async {
    final editorState = EditorState(
      document: Document(
        root: Node(
          type: 'page',
          children: [
            for (var i = 0; i < 40; i++)
              paragraphNode(text: '第${i + 1}段内容，比较长的文字用来撑开高度让编辑器可以滚动'),
          ],
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: editorState,
            editorStyle: const EditorStyle.mobile(),
          ),
        ),
      ),
    );
    await tester.pump();

    double dy() => editorState.service.scrollService?.dy ?? -1;
    debugPrint('INITIAL dy: ${dy()}');

    // Tap in the middle of the editor.
    final editorCenter = tester.getCenter(find.byType(AppFlowyEditor));
    await tester.tapAt(editorCenter);
    await tester.pumpAndSettle();
    debugPrint('AFTER MIDDLE TAP dy: ${dy()}');
    debugPrint('SELECTION: ${editorState.selection}');

    // Tap near the bottom of the editor.
    final bottom = tester.getBottomLeft(find.byType(AppFlowyEditor)) - const Offset(0, 30);
    await tester.tapAt(bottom);
    await tester.pumpAndSettle();
    debugPrint('AFTER BOTTOM TAP dy: ${dy()}');
  });
}
