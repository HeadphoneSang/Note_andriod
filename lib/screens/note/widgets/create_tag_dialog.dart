import 'package:flutter/material.dart';

/// 新增标签弹窗的结果
class CreateTagResult {
  final String name;
  final String colorHex;

  const CreateTagResult({required this.name, required this.colorHex});
}

const _tagColors = [
  Colors.red,
  Colors.orange,
  Colors.yellow,
  Colors.green,
  Colors.blue,
  Colors.purple,
  Colors.grey,
];

/// 显示新增标签弹窗，返回 [CreateTagResult] 或 null
Future<CreateTagResult?> showCreateTagDialog(BuildContext context) async {
  final nameCtrl = TextEditingController();
  Color selectedColor = _tagColors.first;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text("新增标签"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: "输入标签名称",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _tagColors
                  .map(
                    (c) => GestureDetector(
                      onTap: () => setState(() => selectedColor = c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: selectedColor == c
                              ? Border.all(color: Colors.black, width: 3)
                              : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(const SnackBar(content: Text("请输入标签名称")));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text("确认"),
          ),
        ],
      ),
    ),
  );

  if (result == true) {
    final name = nameCtrl.text.trim();
    final colorHex =
        '#${(selectedColor.toARGB32() & 0x00FFFFFF).toRadixString(16).padLeft(6, '0')}';
    return CreateTagResult(name: name, colorHex: colorHex);
  }
  return null;
}
