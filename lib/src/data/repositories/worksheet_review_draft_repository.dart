import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// Isolated, recoverable review state for an unconfirmed worksheet page.
class WorksheetReviewDraftRepository {
  static const _prefix = 'worksheet_review_draft_v1_';

  Future<List<QuestionRegion>?> load(String sourcePageId) async {
    final raw = (await SharedPreferences.getInstance()).getString('$_prefix$sourcePageId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final values = jsonDecode(raw) as List;
      return values.map((item) => _decode(Map<String, dynamic>.from(item as Map))).toList();
    } catch (_) {
      await clear(sourcePageId);
      return null;
    }
  }

  Future<void> save(String sourcePageId, List<QuestionRegion> regions) async {
    await (await SharedPreferences.getInstance()).setString(
      '$_prefix$sourcePageId', jsonEncode(regions.map(_encode).toList()),
    );
  }

  Future<void> clear(String sourcePageId) async =>
      (await SharedPreferences.getInstance()).remove('$_prefix$sourcePageId');

  Map<String, Object?> _encode(QuestionRegion region) => <String, Object?>{
    'id': region.id, 'rect': <double>[region.normalizedRect.left, region.normalizedRect.top, region.normalizedRect.width, region.normalizedRect.height],
    'number': region.detectedNumber, 'text': region.recognizedText, 'original': region.originalRecognizedText,
    'stem': region.questionStem, 'formulas': region.formulas, 'tables': region.tables, 'options': region.options,
    'blocks': region.documentBlocks.map((block) => <String, Object?>{'type': block.type.index, 'content': block.content}).toList(),
    'format': region.contentFormatHint, 'types': region.recognizedBlockTypes, 'subject': region.subject?.index,
    'questionType': region.questionType, 'ai': region.analyzeWithAi, 'review': region.reviewStatus.index,
    'confidence': region.confidence, 'source': region.source.index, 'diagramNote': region.diagramNote,
  };

  QuestionRegion _decode(Map<String, dynamic> json) {
    final rect = (json['rect'] as List).cast<num>();
    return QuestionRegion(
      id: json['id'] as String, normalizedRect: Rect.fromLTWH(rect[0].toDouble(), rect[1].toDouble(), rect[2].toDouble(), rect[3].toDouble()),
      detectedNumber: json['number'] as String?, recognizedText: json['text'] as String?, originalRecognizedText: json['original'] as String?, questionStem: json['stem'] as String?,
      formulas: ((json['formulas'] as List?) ?? const <Object>[]).map((item) => '$item').toList(), tables: ((json['tables'] as List?) ?? const <Object>[]).map((item) => '$item').toList(),
      options: ((json['options'] as List?) ?? const <Object>[]).map((item) => '$item').toList(),
      documentBlocks: ((json['blocks'] as List?) ?? const <Object>[]).map((item) { final block = Map<String, dynamic>.from(item as Map); return DocumentBlock(type: DocumentBlockType.values[block['type'] as int], content: block['content'] as String); }).toList(),
      contentFormatHint: json['format'] as String?, recognizedBlockTypes: ((json['types'] as List?) ?? const <Object>[]).map((item) => '$item').toList(),
      subject: json['subject'] == null ? null : Subject.values[json['subject'] as int], questionType: json['questionType'] as String?,
      analyzeWithAi: json['ai'] as bool? ?? true, reviewStatus: QuestionRegionReviewStatus.values[json['review'] as int? ?? 0],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1, source: QuestionRegionSource.values[json['source'] as int? ?? 0],
      diagramNote: json['diagramNote'] as String?,
    );
  }
}
