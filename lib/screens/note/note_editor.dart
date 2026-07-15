import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:provider/provider.dart';
import '../../core/store/user_store.dart';
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
  final _quillCtrl = QuillController.basic();
  bool _isSaving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _quillCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = context.read<UserStore>().user?.id;
      if (userId == null) throw Exception('用户未登录');

      final contentJson = jsonEncode(_quillCtrl.document.toDelta().toJson());

      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/note',
        data: {
          'title': title,
          'content': contentJson,
          'userId': userId,
          'notebookId': widget.notebookId,
        },
      );

      if (response.code == 200 && response.data != null) {
        final note = Note.fromJson(response.data!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('笔记「${note.title}」已保存'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, note);
      } else {
        throw Exception(response.message ?? '保存失败');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

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
      body: Column(
        children: [
          // 标题输入
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
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          const Divider(height: 1),

          // 编辑器
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: QuillEditor(
                controller: _quillCtrl,
                focusNode: FocusNode(),
                scrollController: ScrollController(),
                config: const QuillEditorConfig(
                  placeholder: '开始写点什么...',
                  padding: EdgeInsets.only(top: 12),
                ),
              ),
            ),
          ),
          // 工具栏
          QuillSimpleToolbar(
            controller: _quillCtrl,
            config: const QuillSimpleToolbarConfig(
              showHeaderStyle: false,
              showListCheck: false,
              multiRowsDisplay: false,
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
