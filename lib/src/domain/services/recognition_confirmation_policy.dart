import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

/// Recognition fields shared by single-question and worksheet review flows.
abstract final class RecognitionReviewField {
  static const stem = 'stem';
  static const options = 'options';
  static const studentAnswer = 'studentAnswer';
  static const formulas = 'formulas';
  static const tables = 'tables';
  static const diagram = 'diagram';

  static const all = <String>{
    stem,
    options,
    studentAnswer,
    formulas,
    tables,
    diagram,
  };
}

/// Pure gate policy. UI code must use this before auto/batch confirmation.
class RecognitionConfirmationPolicy {
  const RecognitionConfirmationPolicy({this.highConfidenceThreshold = .85});

  static const requiredTag = '__system_recognition_confirmation_required';
  final double highConfidenceThreshold;

  bool isHighConfidence(QuestionRegion region) =>
      region.confidence >= highConfidenceThreshold;

  Set<String> fieldsRequiringConfirmation(
    QuestionRegion region,
    List<String> risks,
  ) {
    final fields = <String>{};
    final text = (region.recognizedText ?? '').trim();
    if (text.isEmpty || region.confidence < highConfidenceThreshold) {
      fields.add(RecognitionReviewField.stem);
    }
    for (final risk in risks) {
      if (risk.contains('题干') || risk.contains('文字') || risk.contains('为空')) {
        fields.add(RecognitionReviewField.stem);
      }
      if (risk.contains('选项')) fields.add(RecognitionReviewField.options);
      if (risk.contains('公式')) fields.add(RecognitionReviewField.formulas);
      if (risk.contains('表格')) fields.add(RecognitionReviewField.tables);
      if (risk.contains('图形')) fields.add(RecognitionReviewField.diagram);
      if (risk.contains('作答') || risk.contains('答案')) {
        fields.add(RecognitionReviewField.studentAnswer);
      }
    }
    return fields;
  }

  bool hasSpatialRisk(List<String> risks) => risks.any((risk) =>
      risk.contains('边缘') ||
      risk.contains('贴边') ||
      risk.contains('重叠') ||
      risk.contains('面积') ||
      risk.contains('宽高比'));

  bool canAutoConfirm(QuestionRegion region, List<String> risks) =>
      region.reviewStatus != QuestionRegionReviewStatus.ignored &&
      isHighConfidence(region) &&
      (region.recognizedText ?? '').trim().isNotEmpty &&
      risks.isEmpty;

  bool canProceed(QuestionRegion region, List<String> risks) {
    if (region.reviewStatus == QuestionRegionReviewStatus.ignored) return false;
    if (hasSpatialRisk(risks)) return false;
    final required = fieldsRequiringConfirmation(region, risks);
    return required.every(region.confirmedFields.contains);
  }
}
