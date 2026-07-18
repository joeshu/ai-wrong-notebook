import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';

/// Keeps an unfinished worksheet import recoverable across app restarts.
class WorksheetImportRepository {
  static const _key = 'worksheet_import_session_v1';

  Future<WorksheetImportSession?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return WorksheetImportSession(
        id: json['id'] as String,
        pages: (json['pages'] as List)
            .map((item) => QuestionRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
        sourcePageIds: ((json['sourcePageIds'] as List?) ?? const <Object>[])
            .map((item) => '$item')
            .toSet(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(WorksheetImportSession session) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode({
      'id': session.id,
      'pages': session.pages.map((page) => page.toJson()).toList(),
      'sourcePageIds': session.sourcePageIds.toList(),
      'createdAt': session.createdAt.toIso8601String(),
    }));
  }

  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}
