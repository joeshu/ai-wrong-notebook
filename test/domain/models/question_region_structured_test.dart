import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  QuestionRegion region() => const QuestionRegion(
    id: 'q1',
    normalizedRect: Rect.fromLTWH(.1, .2, .5, .3),
    recognizedText: '原始题干\n\$x+y\$',
    originalRecognizedText: '原始题干\n\$x+y\$',
    questionStem: '校对后的题干',
    formulas: <String>['\$x+y\$'],
    tables: <String>['|A|B|\n|-|-|\n|1|2|'],
    subject: Subject.math,
  );

  test('copyWith keeps structured content while updating review status', () {
    final ignored = region().copyWith(
      reviewStatus: QuestionRegionReviewStatus.ignored,
    );

    expect(ignored.reviewStatus, QuestionRegionReviewStatus.ignored);
    expect(ignored.originalRecognizedText, '原始题干\n\$x+y\$');
    expect(ignored.questionStem, '校对后的题干');
    expect(ignored.formulas, <String>['\$x+y\$']);
    expect(ignored.tables, hasLength(1));
  });

  test('copyWith restores structured draft to original recognition text', () {
    final restored = region().copyWith(
      questionStem: '原始题干\n\$x+y\$',
      formulas: const <String>[],
      tables: const <String>[],
      recognizedText: '原始题干\n\$x+y\$',
      reviewStatus: QuestionRegionReviewStatus.accepted,
    );

    expect(restored.reviewStatus, QuestionRegionReviewStatus.accepted);
    expect(restored.recognizedText, restored.originalRecognizedText);
    expect(restored.formulas, isEmpty);
    expect(restored.tables, isEmpty);
  });
}
