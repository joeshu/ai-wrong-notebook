import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

/// 生成 CSV 格式的错题本导出。
///
/// - 表头：题号,学科,题干,知识点,错因,掌握度,难度,复习次数,收藏,
///   创建日期,上次复习日期,下次复习日期
/// - 字段用双引号包裹，正确处理逗号/换行/引号
/// - 题干截断到 200 字（避免 CSV 行太长）
/// - 日期格式 yyyy-MM-dd
/// - 写入文件时带 UTF-8 BOM，让 Excel 正确识别中文
class CsvExportService {
  /// 题干在 CSV 中保留的最大字符数。
  static const int questionTextLimit = 200;

  /// 生成 CSV 文本（不含 BOM，BOM 在写文件时由 [shareCsv] 添加）。
  Future<String> generateCsv({
    required List<QuestionRecord> questions,
  }) async {
    final buffer = StringBuffer();
    // 表头
    buffer.writeln([
      '题号',
      '学科',
      '题干',
      '知识点',
      '错因',
      '掌握度',
      '难度',
      '复习次数',
      '收藏',
      '创建日期',
      '上次复习日期',
      '下次复习日期',
    ].map(_escapeCsvField).join(','));

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final analysis = q.analysisResult;
      final rawQuestionText = q.normalizedQuestionText.isNotEmpty
          ? q.normalizedQuestionText
          : q.extractedQuestionText;
      final questionText = LatexNormalizer.normalizeLiteralNewlines(rawQuestionText)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final truncated = questionText.length > questionTextLimit
          ? '${questionText.substring(0, questionTextLimit)}…'
          : questionText;
      final kps = [...?analysis?.knowledgePoints, ...?analysis?.aiTags]
          .where((s) => s.isNotEmpty)
          .join('、');
      final mistakeReason = analysis?.mistakeReason ?? '';
      final mastery = _masteryLabel(q.masteryLevel);
      final difficulty = _difficultyLabel(q.difficulty);

      buffer.writeln([
        (i + 1).toString(),
        q.subject.label,
        truncated,
        kps,
        mistakeReason,
        mastery,
        difficulty,
        q.reviewCount.toString(),
        q.isFavorite ? '是' : '否',
        _formatDate(q.createdAt),
        _formatDate(q.lastReviewedAt),
        _formatDate(q.nextReviewAt),
      ].map(_escapeCsvField).join(','));
    }

    return buffer.toString();
  }

  /// 把 [content] 写入 .csv 文件（带 UTF-8 BOM）并调起系统分享。
  Future<void> shareCsv(String content, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/$fileName');
    // UTF-8 BOM，让 Excel 正确识别中文。
    const bom = '\uFEFF';
    await file.writeAsString(bom + content, flush: true, encoding: utf8);
    await Share.shareXFiles([XFile(file.path)]);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────

  /// CSV 字段转义：用双引号包裹，内部双引号转义为两个双引号。
  String _escapeCsvField(String input) {
    final escaped = input.replaceAll('"', '""');
    return '"$escaped"';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _masteryLabel(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '待学习',
        MasteryLevel.reviewing => '复习中',
        MasteryLevel.mastered => '已掌握',
      };

  String _difficultyLabel(QuestionDifficulty? difficulty) {
    if (difficulty == null) return '';
    return switch (difficulty) {
      QuestionDifficulty.foundation => '基础',
      QuestionDifficulty.advanced => '提高',
      QuestionDifficulty.challenge => '挑战',
      QuestionDifficulty.custom => '自定义',
    };
  }
}
