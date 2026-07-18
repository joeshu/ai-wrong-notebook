import 'dart:ui';

/// A user-confirmed region of a worksheet page.
/// Coordinates are normalized (0..1) so they survive display scaling.
class QuestionRegion {
  const QuestionRegion({
    required this.id,
    required this.normalizedRect,
    this.detectedNumber,
    this.confidence = 1,
    this.source = QuestionRegionSource.manual,
  });

  final String id;
  final Rect normalizedRect;
  final String? detectedNumber;
  final double confidence;
  final QuestionRegionSource source;

  QuestionRegion copyWith({
    Rect? normalizedRect,
    String? detectedNumber,
    double? confidence,
    QuestionRegionSource? source,
  }) {
    return QuestionRegion(
      id: id,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      detectedNumber: detectedNumber ?? this.detectedNumber,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }
}

enum QuestionRegionSource { manual, layoutModel }
