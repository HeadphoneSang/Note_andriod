import 'package:flutter/material.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/core/store/user_store.dart';
import 'package:note_for_android/models/notebook.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/utils/toast_util.dart';
import 'package:provider/provider.dart';

/// 选择/新建笔记本 bottom sheet
Future<void> showNotebookSheet({
  required BuildContext context,
  required IncrementalSaveService saveService,
  required int? selectedNotebookId,
  required List<Notebook> allNotebooks,
  required Future<void> Function() onReloadNotebooks,
  required void Function(int?) onSelectedNotebookChanged,
}) async {
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text(
                    "选择笔记本",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.35,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),

                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: allNotebooks.map((nb) {
                    final selected = nb.id == selectedNotebookId;
                    return ListTile(
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected ? Theme.of(context).primaryColor : null,
                      ),
                      title: Text(nb.name),
                      onTap: () async {
                        if (nb.id == saveService.currentNoteInfo?.notebookId &&
                            nb.id != null)
                          return;
                        if (nb.id == saveService.currentNoteInfo?.notebookId)
                          return;
                        if (nb.id == null || nb.id == -1) {
                          ToastUtil.warning(context, title: "请选择有效笔记本");
                          return;
                        }
                        final noteId = saveService.currentNoteInfo?.id;
                        if (noteId == null) {
                          ToastUtil.warning(context, title: "请先保存笔记");
                          return;
                        }
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text("切换笔记本"),
                            content: Text("是否切换到 ${nb.name}？"),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text("取消"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text("确定"),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          final response = await HttpClient.instance
                              .post<String>(
                                "/note/editNotebook",
                                queryParameters: {
                                  "noteId": noteId,
                                  "notebookId": nb.id,
                                },
                              );
                          if (response.code == 200) {
                            if (context.mounted) {
                              await saveService.tryLoadNote();
                              if (context.mounted) {
                                onSelectedNotebookChanged(nb.id);
                                ToastUtil.success(context, title: "切换成功");
                                Navigator.pop(context);
                                Navigator.pop(context);
                              }
                            }
                          } else {
                            if (context.mounted) Navigator.pop(context);
                            ToastUtil.error(
                              context,
                              title: "切换失败",
                              description: response.message,
                            );
                            if (context.mounted) Navigator.pop(context);
                          }
                        } catch (e) {
                          ToastUtil.error(
                            context,
                            title: "网络错误",
                            description: "切换笔记本失败",
                          );
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text("新建笔记本"),
              onTap: () async {
                Navigator.pop(ctx);
                final nameCtrl = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("新建笔记本"),
                    content: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: "请输入笔记本名称"),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text("取消"),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, nameCtrl.text.trim()),
                        child: const Text("确定"),
                      ),
                    ],
                  ),
                );
                if (name == null || name.isEmpty) return;
                try {
                  final userId = context.read<UserStore>().user?.id;
                  if (userId == null) {
                    ToastUtil.error(context, title: "无法获取用户信息");
                    return;
                  }
                  final response = await HttpClient.instance
                      .post<Map<String, dynamic>>(
                        "/notebook/add",
                        data: {
                          "name": name,
                          "description": "",
                          "userId": userId,
                        },
                      );
                  if (response.code == 200) {
                    final newNotebookId = response.data?["id"] as int?;
                    ToastUtil.success(context, title: "创建成功");
                    await onReloadNotebooks();
                    if (newNotebookId != null && context.mounted) {
                      onSelectedNotebookChanged(newNotebookId);
                    }
                  } else {
                    ToastUtil.error(
                      context,
                      title: "创建失败",
                      description: response.message,
                    );
                  }
                } catch (e) {
                  ToastUtil.error(
                    context,
                    title: "网络错误",
                    description: "创建笔记本失败",
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 底部信息栏中选择笔记本的按钮
class SelectNotebookButton extends StatelessWidget {
  final List<Notebook> allNotebooks;
  final int? selectedNotebookId;
  final VoidCallback onTap;

  const SelectNotebookButton({
    super.key,
    required this.allNotebooks,
    required this.selectedNotebookId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_rounded, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              allNotebooks
                      .where((n) => n.id == selectedNotebookId)
                      .firstOrNull
                      ?.name ??
                  "-",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}
