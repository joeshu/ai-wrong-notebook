import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';

QuestionRecord _question({DateTime? nextReviewAt, ContentStatus status = ContentStatus.ready}) {
  final createdAt = DateTime(2026, 7, 17, 9);
  return QuestionRecord(
    id: 'q-1',
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: 'x',
    normalizedQuestionText: 'x',
    contentFormat: QuestionContentFormat.plain,
    tags: const [],
    createdAt: createdAt,
    updatedAt: createdAt,
    lastReviewedAt: null,
    nextReviewAt: nextReviewAt,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

void main() {
  const service = ReviewScheduleService();
  final now = DateTime(2026, 7, 17, 10);

  test('legacy question without a schedule is immediately due', () {
    expect(service.isDue(_question(), now: now), isTrue);
  });

  test('legacy mastered question without a schedule stays out of queue', () {
    final question = _question().copyWith(masteryLevel: MasteryLevel.mastered);
    expect(service.isDue(question, now: now), isFalse);
  });

  test('legacy JSON keeps mastered questions unscheduled', () {
    final legacy = _question().copyWith(masteryLevel: MasteryLevel.mastered).toJson()
      ..remove('nextReviewAt');
    final restored = QuestionRecord.fromJson(legacy);
    expect(restored.nextReviewAt, isNull);
    expect(service.isDue(restored, now: now), isFalse);
  });

  test('future and unfinished questions are excluded from due queue', () {
    expect(
      service.isDue(_question(nextReviewAt: now.add(const Duration(minutes: 1))), now: now),
      isFalse,
    );
    expect(service.isDue(_question(status: ContentStatus.processing), now: now), isFalse);
  });

  test('forgot schedules one hour later', () {
    final updated = service.apply(_question(), ReviewRating.forgot, reviewedAt: now);
    expect(updated.masteryLevel, MasteryLevel.reviewing);
    expect(updated.reviewCount, 1);
    expect(updated.lastReviewedAt, now);
    expect(updated.nextReviewAt, now.add(const Duration(hours: 1)));
  });

  test('easy reviews expand interval progressively', () {
    var question = _question();
    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    expect(question.nextReviewAt, now.add(const Duration(days: 3)));

    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    expect(question.nextReviewAt, now.add(const Duration(days: 7)));
    expect(question.masteryLevel, MasteryLevel.mastered);
  });

  test('reset makes a question due again without losing review count', () {
    final source = service.apply(_question(), ReviewRating.easy, reviewedAt: now);
    final reset = service.reset(source, now: now);
    expect(reset.masteryLevel, MasteryLevel.newQuestion);
    expect(reset.reviewCount, 1);
    expect(reset.nextReviewAt, now);
    expect(service.isDue(reset, now: now), isTrue);
  });
}
