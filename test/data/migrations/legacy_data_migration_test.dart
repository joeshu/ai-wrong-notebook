import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/migrations/legacy_data_migration.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';

QuestionRecord _question(String id) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目',
    normalizedQuestionText: '题目',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

ReviewLog _log(String id, String questionId) => ReviewLog(
      id: id,
      questionRecordId: questionId,
      reviewedAt: DateTime(2026),
      result: 'reviewing',
      masteryAfter: MasteryLevel.reviewing,
    );

class _FailOnceQuestionRepository extends InMemoryQuestionRepository {
  var shouldFail = true;
  @override
  Future<void> saveDrafts(List<QuestionRecord> records) async {
    if (shouldFail) {
      shouldFail = false;
      throw StateError('temporary write failure');
    }
    await super.saveDrafts(records);
  }
}

void main() {
  LegacyDataMigration migration({
    required SettingsRepository settings,
    required QuestionRepository questions,
    required QuestionRepository legacyQuestions,
    required ReviewLogRepository reviewLogs,
    required ReviewLogRepository legacyReviewLogs,
  }) => LegacyDataMigration(
        settings: settings,
        questions: questions,
        legacyQuestions: legacyQuestions,
        reviewLogs: reviewLogs,
        legacyReviewLogs: legacyReviewLogs,
      );

  test('imports legacy questions and review logs once', () async {
    final settings = InMemorySettingsRepository();
    final legacyQuestions = InMemoryQuestionRepository();
    final legacyLogs = InMemoryReviewLogRepository();
    final questions = InMemoryQuestionRepository();
    final logs = InMemoryReviewLogRepository();
    await legacyQuestions.saveDraft(_question('legacy-question'));
    await legacyLogs.insert(_log('legacy-log', 'legacy-question'));

    await migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: legacyLogs).migrateIfNeeded();

    expect((await questions.listAll()).single.id, 'legacy-question');
    expect((await logs.listAll()).single.id, 'legacy-log');
    expect(await settings.getString(LegacyDataMigration.questionMigrationKey), 'done');
    expect(await settings.getString(LegacyDataMigration.reviewLogMigrationKey), 'done');

    await migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: legacyLogs).migrateIfNeeded();
    expect(await questions.listAll(), hasLength(1));
    expect(await logs.listAll(), hasLength(1));
  });

  test('does not overwrite populated Drift stores', () async {
    final settings = InMemorySettingsRepository();
    final questions = InMemoryQuestionRepository();
    final logs = InMemoryReviewLogRepository();
    await questions.saveDraft(_question('new-question'));
    await logs.insert(_log('new-log', 'new-question'));
    final legacyQuestions = InMemoryQuestionRepository();
    final legacyLogs = InMemoryReviewLogRepository();
    await legacyQuestions.saveDraft(_question('old-question'));
    await legacyLogs.insert(_log('old-log', 'old-question'));

    await migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: legacyLogs).migrateIfNeeded();

    expect((await questions.listAll()).single.id, 'new-question');
    expect((await logs.listAll()).single.id, 'new-log');
  });

  test('failed migration keeps completion marker unset for retry', () async {
    final settings = InMemorySettingsRepository();
    final questions = _FailOnceQuestionRepository();
    final legacyQuestions = InMemoryQuestionRepository();
    await legacyQuestions.saveDraft(_question('legacy-question'));
    final logs = InMemoryReviewLogRepository();

    final job = migration(settings: settings, questions: questions, legacyQuestions: legacyQuestions, reviewLogs: logs, legacyReviewLogs: InMemoryReviewLogRepository());
    await job.migrateIfNeeded();
    expect(await settings.getString(LegacyDataMigration.questionMigrationKey), isNull);

    await job.migrateIfNeeded();
    expect((await questions.listAll()).single.id, 'legacy-question');
    expect(await settings.getString(LegacyDataMigration.questionMigrationKey), 'done');
  });
}
