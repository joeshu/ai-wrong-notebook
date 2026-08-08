import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_recovery_service.dart';

QuestionRecord _record({
  ContentStatus status = ContentStatus.analyzing,
  Object? analysisResult,
  String? lastAnalysisError,
}) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: 'q-1',
    imagePath: '/tmp/q-1.jpg',
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
    contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
    lastAnalysisError: lastAnalysisError,
  );
}

void main() {
  const service = AnalysisRecoveryService();

  test('marks interrupted analyzing records as analysisFailed', () {
    final recovered = service.recoverInterrupted(_record());

    expect(recovered.contentStatus, ContentStatus.analysisFailed);
    expect(recovered.lastAnalysisError, AnalysisRecoveryService.interruptedMessage);
  });

  test('does not change non-analyzing records', () {
    final ready = _record(status: ContentStatus.ready);

    expect(service.recoverInterrupted(ready), same(ready));
  });
}
