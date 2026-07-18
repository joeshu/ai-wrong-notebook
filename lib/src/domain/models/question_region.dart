import 'dart:ui';

import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// A user-confirmed region of a worksheet page.
/// Coordinates are normalized (0..1) so they survive display scaling.
class QuestionRegion {
  const QuestionRegion({
    required this.id,
    required this.normalizedRect,
    this.detectedNumber,
    this.recognizedText,
    this.contentFormatHint,
    this.recognizedBlockTypes = const <String>[],
    this.subject,
    this.questionType,
    this.analyzeWithAi = true,
    this.confidence = 1,
    this.source = QuestionRegionSource.manual,
  });

  final String id;
  final Rect normalizedRect;
  final String? detectedNumber;

  /// Text reconstructed by the document service for this candidate question.
  /// It may contain Markdown/LaTex and is always user-reviewable.
  final String? recognizedText;
  final String? contentFormatHint;
  /// Detected content categories: text, formula, table, option, diagram.
  final List<String> recognizedBlockTypes;
  /// User-confirmed subject for this region; defaults to its source page.
  final Subject? subject;
  /// User-editable type, such as choice, fillBlank, calculation or proof.
  final String? questionType;
  /// False means keep OCR/document text as a ready local draft without AI analysis.
  final bool analyzeWithAi;
  final double confidence;
  final QuestionRegionSource source;

  QuestionRegion copyWith({
    Rect? normalizedRect,
    String? detectedNumber,
    String? recognizedText,
    String? contentFormatHint,
    List<String>? recognizedBlockTypes,
    Subject? subject,
    String? questionType,
    bool? analyzeWithAi,
    double? confidence,
    QuestionRegionSource? source,
  }) {
    return QuestionRegion(
      id: id,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      detectedNumber: detectedNumber ?? this.detectedNumber,
      recognizedText: recognizedText ?? this.recognizedText,
      contentFormatHint: contentFormatHint ?? this.contentFormatHint,
      recognizedBlockTypes: recognizedBlockTypes ?? this.recognizedBlockTypes,
      subject: subject ?? this.subject,
      questionType: questionType ?? this.questionType,
      analyzeWithAi: analyzeWithAi ?? this.analyzeWithAi,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }
}

enum QuestionRegionSource { manual, layoutModel }
