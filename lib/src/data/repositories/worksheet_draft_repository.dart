import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';

/// 组卷草稿与历史组卷持久化仓库。
///
/// 使用 SharedPreferences 存储一个列表。每次 [save] 会：
/// - 同 ID 已存在则更新（保留 createdAt，刷新 updatedAt）
/// - 否则插入新条目
///
/// [loadAll] 返回按 updatedAt 降序排列的列表，最近编辑的在前。
class WorksheetDraftRepository {
  static const _key = 'worksheet_drafts_v1';

  Future<List<WorksheetDraft>> loadAll() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return const <WorksheetDraft>[];
    try {
      final list = jsonDecode(raw) as List;
      final drafts = list
          .map((item) =>
              WorksheetDraft.fromJson(item as Map<String, dynamic>))
          .toList();
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return drafts;
    } catch (_) {
      await clear();
      return const <WorksheetDraft>[];
    }
  }

  Future<void> save(WorksheetDraft draft) async {
    final all = await loadAll();
    final existingIdx = all.indexWhere((d) => d.id == draft.id);
    if (existingIdx >= 0) {
      // 更新：保留原 createdAt
      all[existingIdx] = draft.copyWith(
        createdAt: all[existingIdx].createdAt,
        updatedAt: DateTime.now(),
      );
    } else {
      all.add(draft);
    }
    await _writeAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((d) => d.id == id);
    await _writeAll(all);
  }

  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }

  Future<void> _writeAll(List<WorksheetDraft> drafts) async {
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(drafts.map((d) => d.toJson()).toList()),
    );
  }
}
