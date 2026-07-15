import 'dart:async';
import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/editor/note_document_convert.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/models/node_change_event.dart';
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
  late final EditorState _editorState;
  bool _isSaving = false;
  bool _isDirty = false;
  StreamSubscription? _txSub;

  @override
  void initState() {
    super.initState();
    _editorState = EditorState.blank(withInitialText: true);

    // 监听块的每一次变化
    _txSub = _editorState.transactionStream.listen((event) {
      final (time, transaction, options) = event;
      if (time != TransactionTime.after) return;

      _isDirty = true;

      for (final op in transaction.operations) {
        // final node = _editorState.document.nodeAtPath(op.path);
        switch (op) {
          case InsertOperation:
            op as InsertOperation;
            for (final node in op.nodes) {
              NodeChangeEvent event = new NodeChangeEvent(node: node);
            }
          case DeleteOperation:
        }
      }
      // if (node != null) {
      //   //可以通过path找到节点
      //   NodeChangeEvent nodeEvent = new NodeChangeEvent(node: node);
      // } else {
      //   //不能通过path找到节点

      // }
      // if (op is InsertOperation) {
      //   print('▸ 新增块 id=$nodeId type=$type path=${op.path}');
      //   for (final n in op.nodes) {
      //     print(
      //       '    → id=${n.id} type=${n.type}: "${n.delta?.toPlainText()}"',
      //     );
      //   }
      // } else if (op is DeleteOperation) {
      //   print('▸ 删除块 id=$nodeId type=$type path=${op.path}');
      //   for (final n in op.nodes) {
      //     print(
      //       '    → id=${n.id} type=${n.type}: "${n.delta?.toPlainText()}"',
      //     );
      //   }
      // } else if (op is UpdateTextOperation) {
      //   print('▸ 文本修改 id=$nodeId type=$type path=${op.path}');
      //   print('    ← "${op.inverted.toPlainText()}"');
      //   print('    → "${op.delta.toPlainText()}"');
      // } else if (op is UpdateOperation) {
      //   print('▸ 属性修改 id=$nodeId type=$type path=${op.path}');
      //   print('    new: ${op.attributes}');
      //   print('    old: ${op.oldAttributes}');
      // }
    });
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _editorState.dispose();
    _titleCtrl.dispose();
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

      // 将编辑器内容转为 JSON 存储
      final contentJson = jsonEncode(_editorState.document.toJson());

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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: MobileToolbarV2(
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
                ],
                child: AppFlowyEditor(editorState: _editorState),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
