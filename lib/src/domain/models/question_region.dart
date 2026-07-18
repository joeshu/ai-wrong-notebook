import 'dart:ui';

/// A user-confirmed region of a worksheet page.
/// Coordinates are normalized (0..1) so they survive display scaling.
class QuestionRegion {
  const QuestionRegion({
    required this.id,
    required this.normalizedRect,
    this.detectedNumber,
    this.recognizedText,
    this.contentFormatHint,
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
  final double confidence;
  final QuestionRegionSource source;

  QuestionRegion copyWith({
    Rect? normalizedRect,
    String? detectedNumber,
    String? recognizedText,
    String? contentFormatHint,
    double? confidence,
    QuestionRegionSource? source,
  }) {
    return QuestionRegion(
      id: id,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      detectedNumber: detectedNumber ?? this.detectedNumber,
      recognizedText: recognizedText ?? this.recognizedText,
      contentFormatHint: contentFormatHint ?? this.contentFormatHint,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }
}

enum QuestionRegionSource { manual, layoutModel }
