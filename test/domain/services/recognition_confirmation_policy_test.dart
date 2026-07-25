import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_confirmation_policy.dart';

QuestionRegion _region({
  double confidence = .95,
  String text = '已识别题干',
  Set<String> confirmed = const <String>{},
}) =>
    QuestionRegion(
      id: 'r1',
      normalizedRect: const Rect.fromLTWH(.1, .1, .8, .3),
      recognizedText: text,
      confidence: confidence,
      source: QuestionRegionSource.layoutModel,
      confirmedFields: confirmed,
    );

void main() {
  const policy = RecognitionConfirmationPolicy();

  test('auto confirm only accepts high-confidence risk-free question', () {
    expect(policy.canAutoConfirm(_region(), const <String>[]), isTrue);
    expect(policy.canAutoConfirm(_region(confidence: .7), const <String>[]), isFalse);
    expect(policy.canAutoConfirm(_region(), const <String>['公式可能损坏']), isFalse);
    expect(policy.canAutoConfirm(_region(text: ''), const <String>[]), isFalse);
  });

  test('low confidence requires explicit stem confirmation', () {
    final low = _region(confidence: .6);
    expect(policy.canProceed(low, const <String>[]), isFalse);
    expect(
      policy.canProceed(
        _region(
          confidence: .6,
          confirmed: const <String>{RecognitionReviewField.stem},
        ),
        const <String>[],
      ),
      isTrue,
    );
  });

  test('structural fields are confirmed independently', () {
    const risks = <String>['公式可能损坏', '选择题缺少选项'];
    expect(
      policy.fieldsRequiringConfirmation(_region(), risks),
      containsAll(<String>[
        RecognitionReviewField.formulas,
        RecognitionReviewField.options,
      ]),
    );
    expect(
      policy.canProceed(
        _region(confirmed: const <String>{
          RecognitionReviewField.formulas,
          RecognitionReviewField.options,
        }),
        risks,
      ),
      isTrue,
    );
  });

  test('spatial risk cannot be bypassed by field confirmation', () {
    expect(
      policy.canProceed(
        _region(confirmed: RecognitionReviewField.all),
        const <String>['题框贴边'],
      ),
      isFalse,
    );
  });
}
