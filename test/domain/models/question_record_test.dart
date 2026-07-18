import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  test('copyWith replaces image path while retaining question data', () {
    final now = DateTime(2026, 7, 18);
    final source = QuestionRecord(
      id: 'q-1',
      imagePath: '/old/image.jpg',
      subject: Subject.math,
      extractedQuestionText: '题目',
      normalizedQuestionText: '题目',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>['tag'],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 2,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.reviewing,
      analysisResult: null,
    );

    final restored = source.copyWith(imagePath: '/new/imported-image.jpg');

    expect(restored.imagePath, '/new/imported-image.jpg');
    expect(restored.id, source.id);
    expect(restored.reviewCount, source.reviewCount);
    expect(restored.normalizedQuestionText, source.normalizedQuestionText);
  });

  test('favorite uses a durable system tag and survives JSON restore', () {
    final now = DateTime(2026, 7, 18);
    final source = QuestionRecord(
      id: 'q-favorite',
      imagePath: '',
      subject: Subject.math,
      extractedQuestionText: '题目',
      normalizedQuestionText: '题目',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>['tag'],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: null,
    );

    final favorite = source.withFavorite(true);
    final restored = QuestionRecord.fromJson(favorite.toJson());

    expect(favorite.isFavorite, isTrue);
    expect(favorite.persistentTags, contains(QuestionRecord.favoriteTag));
    expect(restored.isFavorite, isTrue);
    expect(restored.withFavorite(false).persistentTags,
        isNot(contains(QuestionRecord.favoriteTag)));
  });
}
