import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

import 'export_content_options.dart';
import 'worksheet_export_mode.dart';

/// 生成 Markdown 格式的错题本导出。
///
/// 输出结构：
/// - `# 错题本整理报告` + 元信息
/// - 按学科分一级标题 `## 数学`
/// - 每题一个 `### 题 N：题干前 30 字...`
/// - 题干用纯文本，[QuestionContentFormat.latexMixed] 时保留 `$...$` 语法
/// - 末尾统计：总题数、按学科分布、按掌握度分布
class MarkdownExportService {
  /// 生成 Markdown 文本，调用方负责后续分享或写文件。
  Future<String> generateMarkdown({
    required List<QuestionRecord> questions,
    required WorksheetExportMode mode,
    required ExportContentOptions contentOptions,
    String? studentName,
    String? className,
  }) async {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final buffer = StringBuffer();

    // ── 文件头 ──────────────────────────────────────────────────────────
    buffer.writeln('# 错题本整理报告');
    buffer.writeln();
    if (studentName != null && studentName.isNotEmpty) {
      buffer.writeln('- **学生姓名：** $studentName');
    }
    if (className != null && className.isNotEmpty) {
      buffer.writeln('- **班级：** $className');
    }
    buffer.writeln('- **导出日期：** $dateStr');
    buffer.writeln('- **题目总数：** ${questions.length} 道');
    buffer.writeln('- **导出模式：** ${mode.label}');
    buffer.writeln();

    // ── 按学科分组 ─────────────────────────────────────────────────────
    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    int globalIndex = 0;
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      buffer.writeln('## ${subject.label}（${list.length} 题）');
      buffer.writeln();
      for (final q in list) {
        globalIndex++;
        _writeQuestion(buffer, globalIndex, q,
            mode: mode, contentOptions: contentOptions);
      }
    }

    // ── 末尾统计 ──────────────────────────────────────────────────────
    _writeStatistics(buffer, questions, grouped);

    return buffer.toString();
  }

  /// 把 [content] 写入临时 .md 文件并调起系统分享。
  Future<void> shareMarkdown(String content, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final file = File('${exportDir.path}/$fileName');
    await file.writeAsString(content, flush: true);
    await Share.shareXFiles([XFile(file.path)]);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 题目块
  // ─────────────────────────────────────────────────────────────────────

  void _writeQuestion(
    StringBuffer buffer,
    int index,
    QuestionRecord q, {
    required WorksheetExportMode mode,
    required ExportContentOptions contentOptions,
  }) {
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    final preview = _takePreview(questionText, 30);
    buffer.writeln('### 题 $index：$preview');
    buffer.writeln();

    // 题干
    if (questionText.isNotEmpty) {
      buffer.writeln(_formatQuestionText(q, questionText));
      buffer.writeln();
    }

    // 题图
    if (contentOptions.includeImage && q.imagePath.isNotEmpty) {
      buffer.writeln('![题目](${q.imagePath})');
      buffer.writeln();
    }

    final analysis = q.analysisResult;
    if (analysis != null) {
      // 知识点（所有模式都输出，便于复习时定位）
      if (contentOptions.includeKnowledgePoints) {
        final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
            .where((s) => s.isNotEmpty)
            .take(8)
            .toList();
        if (kps.isNotEmpty) {
          buffer.writeln('**知识点：** ${kps.join('、')}');
          buffer.writeln();
        }
      }

      // 错因
      if (contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buffer.writeln('**错因：** ${analysis.mistakeReason}');
        buffer.writeln();
      }

      // 正确答案：practice 不输出；answer/correction 输出
      if (contentOptions.includeCorrectAnswer &&
          mode != WorksheetExportMode.practice &&
          analysis.finalAnswer.isNotEmpty) {
        buffer.writeln('**正确答案：** ${analysis.finalAnswer}');
        buffer.writeln();
      }

      // 解题步骤：仅 correction 模式输出
      if (contentOptions.includeSolutionSteps &&
          mode == WorksheetExportMode.correction &&
          analysis.steps.isNotEmpty) {
        buffer.writeln('**解题步骤：**');
        buffer.writeln();
        for (var i = 0; i < analysis.steps.length; i++) {
          buffer.writeln('${i + 1}. ${analysis.steps[i]}');
        }
        buffer.writeln();
      }

      // 学习建议
      if (contentOptions.includeStudyAdvice &&
          analysis.studyAdvice.isNotEmpty) {
        buffer.writeln('**学习建议：** ${analysis.studyAdvice}');
        buffer.writeln();
      }
    }

    // 复习次数
    if (contentOptions.includeReviewCount && q.reviewCount > 0) {
      buffer.writeln('**复习次数：** ${q.reviewCount}');
      buffer.writeln();
    }

    // 收藏标记
    if (contentOptions.includeFavoriteMark && q.isFavorite) {
      buffer.writeln('**收藏：** ★');
      buffer.writeln();
    }

    // 日期
    if (contentOptions.includeDates) {
      buffer.writeln(
          '**创建日期：** ${DateFormat('yyyy-MM-dd').format(q.createdAt)}');
      if (q.lastReviewedAt != null) {
        buffer.writeln(
            '**上次复习：** ${DateFormat('yyyy-MM-dd').format(q.lastReviewedAt!)}');
      }
      if (q.nextReviewAt != null) {
        buffer.writeln(
            '**下次复习：** ${DateFormat('yyyy-MM-dd').format(q.nextReviewAt!)}');
      }
      buffer.writeln();
    }

    buffer.writeln('---');
    buffer.writeln();
  }

  void _writeStatistics(
    StringBuffer buffer,
    List<QuestionRecord> questions,
    Map<Subject, List<QuestionRecord>> grouped,
  ) {
    buffer.writeln('## 统计');
    buffer.writeln();
    buffer.writeln('- **总题数：** ${questions.length} 道');
    buffer.writeln();
    buffer.writeln('### 按学科分布');
    buffer.writeln();
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    for (final subject in sortedSubjects) {
      buffer.writeln('- ${subject.label}：${grouped[subject]!.length} 道');
    }
    buffer.writeln();
    buffer.writeln('### 按掌握度分布');
    buffer.writeln();
    final masteryCount = <MasteryLevel, int>{
      for (final level in MasteryLevel.values) level: 0,
    };
    for (final q in questions) {
      masteryCount[q.masteryLevel] = masteryCount[q.masteryLevel]! + 1;
    }
    for (final level in MasteryLevel.values) {
      buffer.writeln('- ${_masteryLabel(level)}：${masteryCount[level]} 道');
    }
    buffer.writeln();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────

  /// 取题干前 [length] 字作为标题预览，去除换行避免破坏 Markdown 标题。
  String _takePreview(String text, int length) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= length) return flat;
    return '${flat.substring(0, length)}…';
  }

  /// 题干文本输出，[QuestionContentFormat.latexMixed] 时保留 `$...$` 语法。
  String _formatQuestionText(QuestionRecord q, String text) {
    if (q.contentFormat == QuestionContentFormat.latexMixed) {
      // 题干本身已带 `$...$`，原样输出。
      return text;
    }
    return text;
  }

  String _masteryLabel(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '待学习',
        MasteryLevel.reviewing => '复习中',
        MasteryLevel.mastered => '已掌握',
      };
}
