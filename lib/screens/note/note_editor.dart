import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/screens/note/mixins/incremental_save.dart';
import 'package:note_for_android/screens/note/widgets/table_toolbar_items.dart';
import 'package:note_for_android/utils/toast_util.dart';
import '../../models/note.dart';

/// 新建笔记页面 — 从底部弹出
class NoteEditor extends StatefulWidget {
  final int? notebookId;

  const NoteEditor({super.key, this.notebookId});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _titleCtrl = TextEditingController();
  late final EditorState _editorState;
  late final _tableInsertItem = createTableInsertToolbarItem();
  late final _tableActionItem = createTableActionToolbarItem();
  late final IncrementalSaveService _saveService;
  bool _isSaving = false;
  StreamSubscription? _txSub;

  @override
  void initState() {
    super.initState();
    _editorState = EditorState.blank(withInitialText: true);

    _saveService = IncrementalSaveService(
      editorState: _editorState,
      titleCtrl: _titleCtrl,
      provideNotebookId: () => widget.notebookId,
      provideContext: () => context,
      notebookId: widget.notebookId,
    );

    _txSub = _editorState.transactionStream.listen((event) {
      final (time, transaction, _) = event;
      if (time != TransactionTime.after) return;
      for (final op in transaction.operations) {
        _saveService.dispatch(op);
      }
    });
  }

  @override
  void dispose() {
    _saveService.cancelDebounce();
    _txSub?.cancel();
    _editorState.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  // ── 保存 ──

  Future<void> _saveNote() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ToastUtil.warning(context, title: '请输入标题');
      return;
    }
    if (!_saveService.haveTotalChange) {
      ToastUtil.warning(context, title: '没有任何修改');
      return;
    }
    await _saveService.flush();

    if (_saveService.noteId == null) {
      if (!mounted) return;
      ToastUtil.error(context, title: '保存失败');
      return;
    }
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建笔记'),
        actions: [
          IconButton(
            onPressed: _isSaving ? null : _saveNote,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                    hintText: '标题',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      MobileToolbar(
                        editorState: _editorState,
                        toolbarItems: [
                          textDecorationMobileToolbarItem,
                          headingMobileToolbarItem,
                          blocksMobileToolbarItem,
                          listMobileToolbarItem,
                          todoListMobileToolbarItem,
                          codeMobileToolbarItem,
                          quoteMobileToolbarItem,
                          dividerMobileToolbarItem,
                          linkMobileToolbarItem,
                          _tableInsertItem,
                          _tableActionItem,
                          buildTextAndBackgroundColorMobileToolbarItem(),
                        ],
                      ),
                      Expanded(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 3.0,
                          child: AppFlowyEditor(
                            editorState: _editorState,
                            editorStyle: const EditorStyle.mobile(
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // ── 右下角上传动画 ──
          ValueListenableBuilder<bool>(
            valueListenable: _saveService.isFlushingNotifier,
            builder: (context, isFlushing, _) {
              return AnimatedOpacity(
                opacity: isFlushing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 16),
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
