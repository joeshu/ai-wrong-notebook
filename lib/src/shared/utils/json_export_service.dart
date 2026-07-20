import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

/// 生成 JSON 格式的错题本导出。
///
/// 输出结构化 JSON：
/// ```
/// {
///   "appVersion": "1.0",
///   "exportedAt": "2025-01-01T00:00:00",
///   "questions": [...],
///   "reviewLogs": [...]
/// }
/// ```
///
/// 每个 question 用 [QuestionRecord.toJson] 序列化，不包含题图附件。
class JsonExportService {
  /// 应用版本号，写入 JSON 元信息。
  static const String appVersion = '1.0';

  /// 生成 JSON 文本。
  ///
  /// [includeReviewLogs] 为 true 时附带 [reviewLogs]；否则 reviewLogs 字段
  /// 为空数组。
  Future<String> generateJson({
    required List<QuestionRecord> questions,
    bool includeReviewLogs = false,
    List<ReviewLog>? reviewLogs,
  }) async {
    final data = <String, dynamic>{
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'questionCount': questions.length,
      // 归一化字面量 \n（反斜杠+n 两字符，AI 输出残留）为真正换行，
      // 避免导入端或下游工具看到选项 ABCD 前的字面量 \n 文本。
      'questions': questions
          .map((q) => _normalizeQuestionRecordJson(q.toJson()))
          .toList(growable: false),
    };
    if (includeReviewLogs) {
      data['reviewLogs'] = (reviewLogs ?? const <ReviewLog>[])
          .map(_reviewLogToJson)
          .toList(growable: false);
    } else {
      data['reviewLogs'] = const <Map<String, dynamic>>[];
    }

    // 使用 prettyPrint 让导出文件可读，便于调试与二次加工。
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }

  /// 把 [content] 写入 .json 文件并调起系统分享。
  Future<void> shareJson(String content, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(content, flush: true, encoding: utf8);
    await Share.shareXFiles([XFile(file.path)]);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────

  /// [ReviewLog] 没有自带 toJson，这里手动序列化。
  Map<String, dynamic> _reviewLogToJson(ReviewLog log) {
    return {
      'id': log.id,
      'questionRecordId': log.questionRecordId,
      'reviewedAt': log.reviewedAt.toIso8601String(),
      'result': log.result,
      'masteryAfter': log.masteryAfter.name,
    };
  }

  /// 归一化 [QuestionRecord.toJson] 输出中的文本字段，统一字面量 `\n` →
  /// 真正换行符。覆盖题干、AI 解析等所有字符串字段，确保 JSON 导出在
  /// 下游工具（Excel/Notion/再导入）中显示正常。
  Map<String, dynamic> _normalizeQuestionRecordJson(Map<String, dynamic> json) {
    const textFields = <String>{
      'extractedQuestionText',
      'normalizedQuestionText',
      'studentAnswer',
      'expectedAnswer',
      'reflectionNote',
    };
    return json.map((key, value) {
      if (textFields.contains(key) && value is String) {
        return MapEntry(key, LatexNormalizer.normalizeLiteralNewlines(value));
      }
      return MapEntry(key, value);
    });
  }
}
