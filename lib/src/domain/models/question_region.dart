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
    this.originalRecognizedText,
    this.questionStem,
    this.formulas = const <String>[],
    this.tables = const <String>[],
    this.options = const <String>[],
    this.documentBlocks = const <DocumentBlock>[],
    this.contentFormatHint,
    this.recognizedBlockTypes = const <String>[],
    this.subject,
    this.questionType,
    this.analyzeWithAi = true,
    this.reviewStatus = QuestionRegionReviewStatus.accepted,
    this.confidence = 1,
    this.source = QuestionRegionSource.manual,
    this.diagramNote,
  });

  final String id;
  final Rect normalizedRect;
  final String? detectedNumber;

  /// Text reconstructed by the document service for this candidate question.
  /// It may contain Markdown/LaTex and is always user-reviewable.
  final String? recognizedText;
  /// Immutable source text from the document service; enables comparison/reset.
  final String? originalRecognizedText;
  /// User-reviewed question stem, separated from formula and table blocks.
  final String? questionStem;
  final List<String> formulas;
  final List<String> tables;
  /// User-edited choice options (one entry per option, e.g. "A. 选项一").
  /// Empty list means user hasn't opened the option editor yet; the UI then
  /// falls back to auto-parsing option lines from [recognizedText].
  final List<String> options;
  /// Ordered source blocks, preserving the reading order of text/formulas/tables.
  final List<DocumentBlock> documentBlocks;
  final String? contentFormatHint;
  /// Detected content categories: text, formula, table, option, diagram.
  final List<String> recognizedBlockTypes;
  /// User-confirmed subject for this region; defaults to its source page.
  final Subject? subject;
  /// User-editable type, such as choice, fillBlank, calculation or proof.
  final String? questionType;
  /// False means keep OCR/document text as a ready local draft without AI analysis.
  final bool analyzeWithAi;
  /// Ignored regions stay visible and can be restored before batch confirmation.
  final QuestionRegionReviewStatus reviewStatus;
  final double confidence;
  final QuestionRegionSource source;
  /// Free-form note describing the diagram/figure for regions where the layout
  /// service only flagged a "图形" block but didn't extract textual content.
  /// Used as a manual cross-check entry; empty string clears the note.
  final String? diagramNote;

  QuestionRegion copyWith({
    Rect? normalizedRect,
    String? detectedNumber,
    String? recognizedText,
    String? originalRecognizedText,
    String? questionStem,
    List<String>? formulas,
    List<String>? tables,
    List<String>? options,
    List<DocumentBlock>? documentBlocks,
    String? contentFormatHint,
    List<String>? recognizedBlockTypes,
    Subject? subject,
    String? questionType,
    bool? analyzeWithAi,
    QuestionRegionReviewStatus? reviewStatus,
    double? confidence,
    QuestionRegionSource? source,
    String? diagramNote,
  }) {
    return QuestionRegion(
      id: id,
      normalizedRect: normalizedRect ?? this.normalizedRect,
      detectedNumber: detectedNumber ?? this.detectedNumber,
      recognizedText: recognizedText ?? this.recognizedText,
      originalRecognizedText: originalRecognizedText ?? this.originalRecognizedText,
      questionStem: questionStem ?? this.questionStem,
      formulas: formulas ?? this.formulas,
      tables: tables ?? this.tables,
      options: options ?? this.options,
      documentBlocks: documentBlocks ?? this.documentBlocks,
      contentFormatHint: contentFormatHint ?? this.contentFormatHint,
      recognizedBlockTypes: recognizedBlockTypes ?? this.recognizedBlockTypes,
      subject: subject ?? this.subject,
      questionType: questionType ?? this.questionType,
      analyzeWithAi: analyzeWithAi ?? this.analyzeWithAi,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      diagramNote: diagramNote ?? this.diagramNote,
    );
  }
}

enum DocumentBlockType { text, formula, table }

class DocumentBlock {
  const DocumentBlock({required this.type, required this.content});
  final DocumentBlockType type;
  final String content;

  DocumentBlock copyWith({DocumentBlockType? type, String? content}) =>
      DocumentBlock(type: type ?? this.type, content: content ?? this.content);
}

enum QuestionRegionReviewStatus { accepted, ignored }

enum QuestionRegionSource { manual, layoutModel }
