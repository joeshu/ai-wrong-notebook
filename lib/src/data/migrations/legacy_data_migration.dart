import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';

/// Imports pre-Drift app data exactly once, without deleting the legacy copy.
/// Completion markers are written only after a full successful migration.
class LegacyDataMigration {
  LegacyDataMigration({
    required this.settings,
    required this.questions,
    required this.legacyQuestions,
    required this.reviewLogs,
    required this.legacyReviewLogs,
  });

  static const questionMigrationKey = 'legacy_questions_to_drift_v1';
  static const reviewLogMigrationKey = 'legacy_review_logs_to_drift_v1';

  final SettingsRepository settings;
  final QuestionRepository questions;
  final QuestionRepository legacyQuestions;
  final ReviewLogRepository reviewLogs;
  final ReviewLogRepository legacyReviewLogs;

  Future<void> migrateIfNeeded() async {
    await _migrateQuestions();
    await _migrateReviewLogs();
  }

  Future<void> _migrateQuestions() async {
    if (await settings.getString(questionMigrationKey) == 'done') return;
    try {
      if ((await questions.listAll()).isEmpty) {
        final legacy = await legacyQuestions.listAll();
        if (legacy.isNotEmpty) await questions.saveDrafts(legacy);
      }
      await settings.setString(questionMigrationKey, 'done');
    } catch (_) {
      // Keep the marker unset so a transient failure can retry next launch.
    }
  }

  Future<void> _migrateReviewLogs() async {
    if (await settings.getString(reviewLogMigrationKey) == 'done') return;
    try {
      if ((await reviewLogs.listAll()).isEmpty) {
        final legacy = await legacyReviewLogs.listAll();
        for (final log in legacy) {
          await reviewLogs.insert(log);
        }
      }
      await settings.setString(reviewLogMigrationKey, 'done');
    } catch (_) {
      // Keep the marker unset so a transient failure can retry next launch.
    }
  }
}
