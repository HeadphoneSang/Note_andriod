import 'dart:async';
import 'package:flutter/material.dart';
import 'package:note_for_android/core/network/http_client.dart';
import 'package:note_for_android/models/note_tag_diff.dart';
import 'package:note_for_android/models/note_tag_diff_result.dart';
import 'package:note_for_android/models/tag.dart';
import 'package:note_for_android/utils/toast_util.dart';

/// 标签增量更新服务
class TagService {
  final int? Function() provideNotebookId;
  final BuildContext Function() provideContext;
  void Function() onFlushCompleted = () {};

  /// 当前笔记的 noteId（创建后才有）
  final int? Function() noteIdProvider;

  TagService({
    required this.provideNotebookId,
    required this.provideContext,
    required this.noteIdProvider,
  });

  // ── 状态 ──

  Timer? _tagDebounceTimer;
  static const _debounceDuration = Duration(milliseconds: 3000);
  bool _isFlushing = false;

  /// pending 缓存：key 为 tagId 字符串
  final Map<String, _PendingTag> _pendingTags = {};

  /// 当前笔记的标签列表（本地缓存）
  List<Tag> _currentTags = [];

  /// 用户的所有标签列表（用于"可添加"列表）
  List<Tag> _availableTags = [];

  /// 是否正在进行上传
  final isFlushingNotifier = ValueNotifier<bool>(false);

  ValueNotifier<DateTime?> lastSavedTime = ValueNotifier<DateTime?>(null);

  List<Tag> get currentTags => List.unmodifiable(_currentTags);
  List<Tag> get availableTags => List.unmodifiable(_availableTags);

  bool get hasPendingChanges => _pendingTags.isNotEmpty;

  // ── 暴露给 UI 的入口 ──

  /// 添加标签关联（已有标签）
  void addTag(int tagId) {
    _dispatchTag(TagChangeType.add, tagId);
  }

  /// 移除标签关联
  void removeTag(int tagId) {
    _dispatchTag(TagChangeType.remove, tagId);
  }

  /// 创建新标签并关联（同步请求，立即拿到真实 id）
  Future<Tag?> createAndAddTag(String name, String? color) async {
    print("22222222");
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    // 避免重名
    final existsInAvailable = _availableTags.any(
      (t) => t.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (existsInAvailable) {
      ToastUtil.warning(
        provideContext(),
        title: '提示',
        description: '该标签已存在',
        alignment: AlignmentGeometry.center,
      );
      return null;
    }

    try {
      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/tag/create',
        queryParameters: {'name': trimmed, if (color != null) 'color': color},
      );
      if (response.isSuccess && response.data != null) {
        final newTag = Tag.fromJson(response.data!);
        if (newTag.id == null) {
          debugPrint('创建标签成功但返回缺少 id');
          return null;
        }
        // 加入可用列表
        _availableTags = [..._availableTags, newTag];
        // 通过 addTag 走统一的 pending 流程
        addTag(newTag.id!);
        return newTag;
      } else {
        if (provideContext().mounted) {
          ToastUtil.error(provideContext(), title: response.message ?? "创建失败");
        }
        return null;
      }
    } catch (e) {
      debugPrint('创建标签失败: $e');
      if (provideContext().mounted) {
        ToastUtil.error(provideContext(), title: '网络错误', description: '创建标签失败');
      }
      return null;
    }
  }

  /// 等待当前刷新完成
  Future<void> flush() async {
    _tagDebounceTimer?.cancel();
    await _flushTags();
  }

  void cancelDebounce() => _tagDebounceTimer?.cancel();

  // ── 加载 ──

  Future<List<Tag>> tryLoadTags() async {
    final noteId = noteIdProvider();
    if (noteId == null) return [];
    try {
      final response = await HttpClient.instance.get<List>(
        '/noteTag/list',
        queryParameters: {'noteId': noteId},
      );
      if (response.isSuccess && response.data != null) {
        final list = response.data!;
        _currentTags = list
            .map((e) => Tag.fromJson(e as Map<String, dynamic>))
            .toList();
        // 重新加载时清空 pending，避免上次未提交的操作残留
        _pendingTags.clear();
        return _currentTags;
      }
      return [];
    } catch (e) {
      debugPrint('加载标签失败: $e');
      return [];
    }
  }

  Future<List<Tag>> tryLoadAllUserTags() async {
    try {
      final response = await HttpClient.instance.get<List>('/tag/list');
      if (response.isSuccess && response.data != null) {
        final list = response.data!;
        _availableTags = list
            .map((e) => Tag.fromJson(e as Map<String, dynamic>))
            .toList();
        return _availableTags;
      }
      return [];
    } catch (e) {
      debugPrint('加载用户标签列表失败: $e');
      return [];
    }
  }

  // ── 事件分发 ──

  void _dispatchTag(TagChangeType type, int tagId) {
    if (type == TagChangeType.remove) {
      _currentTags.removeWhere((t) => t.id == tagId);
      if (provideContext().mounted) onFlushCompleted();

      if (_pendingTags[tagId.toString()]?.changeType == TagChangeType.add) {
        _pendingTags.remove(tagId.toString());
        if (_pendingTags.isNotEmpty) _tagDebounce();
        return;
      }
    } else if (type == TagChangeType.add) {
      final tag = _availableTags.firstWhere(
        (t) => t.id == tagId,
        orElse: () => Tag(id: tagId, name: ''),
      );
      // 如果当前选中的标签已经有了，就不加了
      if (_currentTags.any((item) => item.id == tagId)) return;
      _currentTags = [..._currentTags, tag];

      if (_pendingTags[tagId.toString()]?.changeType == TagChangeType.remove) {
        _pendingTags.remove(tagId.toString());
        if (_pendingTags.isNotEmpty) _tagDebounce();
        return;
      }
    }

    _pendingTags[tagId.toString()] = _PendingTag(
      tagId: tagId,
      changeType: type,
    );
    _tagDebounce();
  }

  // ── 防抖与批量提交 ──

  void _tagDebounce() {
    _tagDebounceTimer?.cancel();
    _tagDebounceTimer = Timer(_debounceDuration, _flushTags);
  }

  Future<void> _flushTags() async {
    if (_isFlushing) return;
    if (_pendingTags.isEmpty) return;

    _isFlushing = true;
    isFlushingNotifier.value = true;

    final flushStopwatch = Stopwatch()..start();
    final batch = Map<String, _PendingTag>.from(_pendingTags);
    _pendingTags.clear();

    bool flushSucceeded = false;
    try {
      final addIds = <int>{};
      final removeIds = <int>{};

      for (final entry in batch.entries) {
        final pending = entry.value;
        switch (pending.changeType) {
          case TagChangeType.add:
            addIds.add(pending.tagId);
            break;
          case TagChangeType.remove:
            removeIds.add(pending.tagId);
            break;
        }
      }

      final diff = NoteTagDiff(
        addTagIds: addIds.toList(),
        removeTagIds: removeIds.toList(),
      );

      if (diff.isEmpty) {
        _isFlushing = false;
        isFlushingNotifier.value = false;
        onFlushCompleted();
        return;
      }

      final noteId = noteIdProvider();
      if (noteId == null) {
        _pendingTags.addAll(batch);
        _tagDebounce();
        return;
      }

      flushSucceeded = await _tryUpdateTags(noteId, diff, batch);
      debugPrint("是否更新成功:$flushSucceeded");
    } finally {
      if (!flushSucceeded) {
        _pendingTags.addAll(batch);
        _tagDebounce();
      }
      final elapsed = flushStopwatch.elapsedMilliseconds;
      if (elapsed < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsed));
      }
      _isFlushing = false;
      isFlushingNotifier.value = false;
      onFlushCompleted();
    }
  }

  Future<bool> _tryUpdateTags(
    int noteId,
    NoteTagDiff diff,
    Map<String, _PendingTag> batch,
  ) async {
    try {
      final response = await HttpClient.instance.post<Map<String, dynamic>>(
        '/noteTag/batch',
        data: {'noteId': noteId, ...diff.toJson()},
      );
      if (response.code == 200 && response.data != null) {
        lastSavedTime.value = DateTime.now();
        // if (provideContext().mounted) {
        //   await tryLoadTags();
        // }
        return true;
      } else if (response.code == 409) {
        final result = NoteTagDiffResult.fromJson(response.data!);
        final failCount =
            result.failAddedTags.length + result.failRemovedTags.length;
        if (provideContext().mounted) {
          ToastUtil.warning(
            provideContext(),
            title: '部分保存失败',
            description: '有 $failCount 个标签失败，请刷新页面',
            alignment: AlignmentGeometry.bottomRight,
          );
        }
        for (final entry in batch.entries) {
          final pending = entry.value;
          if (result.failAddedTags.contains(pending.tagId) ||
              result.failRemovedTags.contains(pending.tagId)) {
            _pendingTags[entry.key] = pending;
          }
        }
        return false;
      } else {
        _pendingTags.addAll(batch);
        return false;
      }
    } catch (e) {
      debugPrint('标签保存失败: $e');
      _pendingTags.addAll(batch);
      if (provideContext().mounted) {
        ToastUtil.error(
          provideContext(),
          title: '网络错误',
          description: '标签保存失败',
          alignment: AlignmentGeometry.bottomRight,
        );
      }
      return false;
    }
  }
}

enum TagChangeType { add, remove }

class _PendingTag {
  final int tagId;
  final TagChangeType changeType;

  _PendingTag({required this.tagId, required this.changeType});
}
