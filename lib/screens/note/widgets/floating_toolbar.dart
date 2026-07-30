import 'package:flutter/material.dart';

/// 选中文本时显示的浮动工具栏（复制/剪切/粘贴/全选）
class EditorFloatingToolbar extends StatelessWidget {
  final List<Rect> selectionRects;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onPaste;
  final VoidCallback onSelectAll;

  const EditorFloatingToolbar({
    super.key,
    required this.selectionRects,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    double top = 8;
    if (selectionRects.isNotEmpty) {
      top = selectionRects.first.topLeft.dy - 50;
    }
    if (top < 0) top = 8;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          color: Colors.grey.shade800,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _contextMenuButton(Icons.content_copy, '复制', onCopy),
              _contextMenuButton(Icons.content_cut, '剪切', onCut),
              _contextMenuButton(Icons.content_paste, '粘贴', onPaste),
              _contextMenuButton(Icons.select_all_rounded, '全选', onSelectAll),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contextMenuButton(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
