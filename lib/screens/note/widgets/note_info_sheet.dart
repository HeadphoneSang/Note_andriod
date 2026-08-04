import 'package:flutter/material.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/screens/note/mixins/tag_service.dart';
import 'package:note_for_android/screens/note/widgets/create_tag_dialog.dart';
import 'package:note_for_android/utils/toast_util.dart';

/// 笔记信息 bottom sheet（摘要、标签管理、保存）
Future<void> showNoteInfoSheet({
  required BuildContext context,
  required TagService tagService,
  required IncrementalSaveService saveService,
  required String initialSummary,
}) async {
  final summaryCtrl = TextEditingController(text: initialSummary);
  var isSaving = false;

  // 数据已在调用方加载完毕，这里不再做网络请求

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setInnerState) {
          final availableTags = tagService.availableTags
              .where((t) => !tagService.currentTags.any((ct) => ct.id == t.id))
              .toList();

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "笔记信息",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "摘要",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: summaryCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: "添加摘要...",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "标签",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        ...tagService.currentTags.map((tag) {
                          return Chip(
                            label: Text(
                              tag.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: tag.color != null
                                ? tag.toColor().withValues(alpha: 0.2)
                                : null,
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              tagService.removeTag(tag.id!);
                              setInnerState(() {});
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (availableTags.isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 50,
                                mainAxisSpacing: 1,
                                crossAxisSpacing: 1,
                              ),
                          itemBuilder: (ctx, index) {
                            final tag = availableTags[index];
                            return ActionChip(
                              label: Text(
                                tag.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: tag.color != null
                                  ? tag.toColor().withValues(alpha: 0.2)
                                  : null,
                              onPressed: () {
                                if (tag.id != null) {
                                  tagService.addTag(tag.id!);
                                }
                                setInnerState(() {});
                              },
                            );
                          },
                          itemCount: availableTags.length,
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("新增标签", style: TextStyle(fontSize: 13)),
                      onPressed: () async {
                        final result = await showCreateTagDialog(context);
                        if (result != null) {
                          await tagService.createAndAddTag(
                            result.name,
                            result.colorHex,
                          );
                          setInnerState(() {});
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          isSaving = true;
                          setInnerState(() {});
                          await saveService.updateSummary(
                            summaryCtrl.text.trim(),
                          );
                          await tagService.flush();
                          if (ctx.mounted) {
                            ToastUtil.success(ctx, title: '保存成功');
                            Navigator.pop(ctx);
                          }
                        },
                        child: const Text("保存"),
                      ),
                    ),
                  ],
                ),
                if (isSaving)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
