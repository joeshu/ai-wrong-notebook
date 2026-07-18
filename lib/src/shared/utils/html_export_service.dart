import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

class HtmlExportService {
  HtmlExportService._();

  /// 清理 LaTeX 标记为可读文本（与 PdfExportService 共享同一逻辑）
  static String _cleanLatex(String input) {
    // 移除 LaTeX 标记和花括号
    // 注意：长命令名必须排在短命令名前，避免前缀误匹配
    var text = input
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'\mathrm', ' ')
        .replaceAll(r'\text', ' ')
        .replaceAll(r'\frac', '/')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\times', '×')
        .replaceAll(r'\div', '÷')
        .replaceAll(r'\rightarrow', '→')
        .replaceAll(r'\Rightarrow', '⇒')
        .replaceAll(r'\Longrightarrow', '⇒')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\ne', '≠')
        .replaceAll(r'\cdots', '...')
        .replaceAll(r'\dots', '...')
        .replaceAll(r'\n', '\\\\n')
        .replaceAll(r'\t', ' ')
        .replaceAll('  ', ' ');
    // 逐字符过滤：移除残余 LaTeX 命令和不可见字符
    final codes = <int>[];
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      final ch = text[i];
      // 跳过反斜杠+字母序列（残余 LaTeX 命令）
      if (ch == r'\' && i + 1 < text.length) {
        final nextCode = text.codeUnitAt(i + 1);
        final a = 'a'.codeUnitAt(0), z = 'z'.codeUnitAt(0);
        final A = 'A'.codeUnitAt(0), Z = 'Z'.codeUnitAt(0);
        if ((nextCode >= a && nextCode <= z) ||
            (nextCode >= A && nextCode <= Z)) {
          i++;
          while (i + 1 < text.length) {
            final cCode = text.codeUnitAt(i + 1);
            if ((cCode >= a && cCode <= z) ||
                (cCode >= A && cCode <= Z) ||
                cCode == '*'.codeUnitAt(0)) {
              i++;
            } else {
              break;
            }
          }
          continue;
        }
      }
      // 先处理 surrogate pair
      if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
        final next = text.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          codes.add(code);
          codes.add(next);
          i++;
        }
        continue;
      }
      // 保留可打印字符 / 允许的控制字符
      if (code == 0x09 || code == 0x0A || code == 0x0D ||
          code >= 0x20 && code <= 0xD7FF ||
          code >= 0xE000 && code <= 0xFFFD) {
        codes.add(code);
      }
    }
    return String.fromCharCodes(codes).trim();
  }

  /// 将选择题文本中的选项段分行，添加 A. B. C. D. 前缀
  static String _formatOptions(String text) {
    // 匹配 "（ ）" 或 "（\s*）" 后的选项序列
    // 选项序列特征：被 ". " 或 ".(" 分隔的短文本段
    final escaped = _escapeHtml(text);
    final regex = RegExp(r'（\s*）\.');
    final match = regex.firstMatch(escaped);
    if (match == null) return escaped;

    final after = escaped.substring(match.end);
    final parts = after.split(RegExp(r'\.\s+'));
    if (parts.length < 2) return escaped;

    final options = parts.where((s) => s.trim().isNotEmpty).toList();
    if (options.length < 2) return escaped;

    final prefix = escaped.substring(0, match.end);
    final letters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
    final buf = StringBuffer();
    buf.write(prefix);
    for (var i = 0; i < options.length && i < letters.length; i++) {
      final opt = options[i].trim();
      if (opt.isEmpty) continue;
      // 如果选项本身已有字母前缀（如 "A. 选项"），不再重复加
      if (opt.startsWith(RegExp(r'[A-Z]\.\s'))) {
        buf.write('<br> $opt');
      } else {
        buf.write('<br> <b>${letters[i]}.</b> $opt');
      }
    }
    return buf.toString();
  }

  static String _masteryLabel(dynamic masteryLevel) {
    final name = masteryLevel is String
        ? masteryLevel
        : '${masteryLevel}'.split('.').last;
    switch (name) {
      case 'newQuestion':
        return '待学习';
      case 'reviewing':
        return '复习中';
      case 'mastered':
        return '已掌握';
      default:
        return '待学习';
    }
  }

  static String _statusLabel(dynamic contentStatus) {
    final name = contentStatus is String
        ? contentStatus
        : '${contentStatus}'.split('.').last;
    switch (name) {
      case 'processing':
        return '处理中';
      case 'ready':
        return '已完成';
      case 'failed':
        return '识别失败';
      default:
        return contentStatus.toString().split('.').last;
    }
  }

  static String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _masteryBadge(dynamic masteryLevel) {
    final name = masteryLevel is String
        ? masteryLevel
        : '${masteryLevel}'.split('.').last;
    switch (name) {
      case 'newQuestion':
        return '<span class="badge badge-new">待学习</span>';
      case 'reviewing':
        return '<span class="badge badge-reviewing">复习中</span>';
      case 'mastered':
        return '<span class="badge badge-mastered">已掌握</span>';
      default:
        return '<span class="badge badge-new">待学习</span>';
    }
  }

  static String _generateHtml(
      List<QuestionRecord> questions, String dateStr) {
    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final buf = StringBuffer();
    buf.writeln('''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>错题本整理报告</title>
<style>
  @page {
    size: A4;
    margin: 20mm 18mm 20mm 18mm;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, 'PingFang SC', 'Noto Sans SC', 'Microsoft YaHei', 'Hiragino Sans GB', sans-serif;
    font-size: 12pt;
    line-height: 1.7;
    color: #1a1a1a;
    background: #fff;
    padding: 0;
  }
  .page { max-width: 190mm; margin: 0 auto; padding: 0; }

  /* 封面 */
  .cover {
    text-align: center;
    padding: 80mm 0 0 0;
    page-break-after: always;
  }
  .cover h1 {
    font-size: 28pt;
    font-weight: 700;
    color: #6366F1;
    margin-bottom: 12px;
  }
  .cover .subtitle {
    font-size: 14pt;
    color: #888;
    margin-bottom: 40px;
  }
  .cover .divider { width: 60%; height: 1px; background: #ddd; margin: 0 auto 24px; }
  .cover .info { font-size: 13pt; color: #555; margin-bottom: 6px; line-height: 2; }

  /* 目录 */
  .toc {
    page-break-after: always;
  }
  .toc h2 {
    font-size: 22pt;
    font-weight: 700;
    margin-bottom: 20px;
    color: #333;
  }
  .toc-item {
    display: flex; justify-content: space-between; align-items: center;
    padding: 6px 0;
    font-size: 13pt;
  }
  .toc-item .count { color: #888; font-size: 11pt; }

  /* 学科分区 */
  .subject-section {
    page-break-before: always;
  }
  .subject-header {
    display: flex; align-items: center; gap: 8px; margin-bottom: 16px;
  }
  .subject-bar {
    width: 4px; height: 24px; border-radius: 2px;
  }
  .subject-title {
    font-size: 20pt; font-weight: 700;
  }

  /* 题目块 */
  .question-block {
    margin-bottom: 18px;
    padding-bottom: 14px;
    border-bottom: 1px solid #e5e7eb;
  }
  .question-header {
    display: flex; align-items: center; flex-wrap: wrap; gap: 6px;
    margin-bottom: 8px;
  }
  .question-index {
    font-size: 14pt; font-weight: 700; color: #6366F1;
    margin-right: 4px;
  }
  .badge {
    display: inline-block;
    font-size: 9pt; padding: 1px 8px; border-radius: 10px;
    font-weight: 500;
  }
  .badge-new { background: #fee2e2; color: #dc2626; }
  .badge-reviewing { background: #fef3c7; color: #d97706; }
  .badge-mastered { background: #dcfce7; color: #16a34a; }

  .question-text {
    background: #f5f3ff; border-radius: 6px; padding: 10px 14px;
    margin-bottom: 8px; font-size: 11.5pt; line-height: 1.8;
  }
  .question-text .opt { display: block; padding-left: 0.5em; }
  .meta-row {
    font-size: 10pt; color: #888; margin-bottom: 4px;
  }

  /* 分析块 */
  .analysis-section { margin-top: 6px; padding-left: 8px; }
  .analysis-item {
    margin-bottom: 4px; font-size: 11pt; line-height: 1.6;
  }
  .analysis-label { font-weight: 600; }
  .analysis-label.green { color: #16a34a; }
  .analysis-label.purple { color: #7c3aed; }
  .analysis-label.orange { color: #d97706; }
  .analysis-label.blue { color: #6366F1; }

  .steps-box {
    border-left: 2px solid #6366F1; padding-left: 10px; margin-top: 6px;
  }
  .step-item { margin-bottom: 3px; font-size: 10.5pt; }

  .page-footer {
    text-align: center; font-size: 9pt; color: #aaa;
    margin-top: 12px;
  }

  /* 提示页 */
  .legend {
    font-size: 10pt; color: #888; margin-top: 16px; line-height: 2;
  }

  @media print {
    .page { max-width: none; }
    .cover { padding-top: 60mm; }
    .question-block { break-inside: avoid; }
    .subject-section { break-before: page; }
  }
</style>
</head>
<body>
<div class="page">
  <div class="cover">
    <h1>错题本整理报告</h1>
    <div class="subtitle">AI Wrong Notebook</div>
    <div class="divider"></div>
    <div class="info">共 ${questions.length} 道错题</div>
    <div class="info">导出时间：$dateStr</div>
    <div class="info">涵盖 ${sortedSubjects.length} 个学科</div>
  </div>

  <div class="toc">
    <h2>目&emsp;录</h2>
''');

    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      buf.writeln('    <div class="toc-item">');
      buf.writeln('      <span>${_escapeHtml(subject.label)}</span>');
      buf.writeln(
          '      <span class="count">${list.length} 题</span>');
      buf.writeln('    </div>');
    }
    buf.writeln('''
    <div class="legend">
      掌握程度说明：● 待学习（New）&emsp;● 复习中（Reviewing）&emsp;● 已掌握（Mastered）
    </div>
  </div>
''');

    int globalIndex = 0;
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      buf.writeln('''
  <div class="subject-section">
    <div class="subject-header">
      <div class="subject-bar" style="background:${_subjectColor(subject)}"></div>
      <div class="subject-title">${_escapeHtml(subject.label)}（${list.length} 题）</div>
    </div>
''');

      for (final q in list) {
        globalIndex++;
        final questionText = _cleanLatex(
          q.normalizedQuestionText.isNotEmpty
              ? q.normalizedQuestionText
              : q.extractedQuestionText,
        );
        // 选择题选项格式化（返回已含 HTML 标签的内容，不再过 _escapeHtml）
        final questionHtml = _formatOptions(questionText);
        final createDateStr = DateFormat('MM/dd').format(q.createdAt);

        buf.writeln('    <div class="question-block">');
        buf.writeln('      <div class="question-header">');
        buf.writeln(
            '        <span class="question-index">#$globalIndex</span>');
        if (q.isFavorite) {
          buf.writeln('        <span style="color:#d97706">★</span>');
        }
        buf.writeln('        ${_masteryBadge(q.masteryLevel)}');
        if (q.contentStatus.toString().split('.').last != 'ready') {
          buf.writeln(
              '        <span class="badge" style="background:#eee;color:#888">${_statusLabel(q.contentStatus)}</span>');
        }
        if (q.reviewCount > 0) {
          buf.writeln(
              '        <span class="meta-row">已复习 ${q.reviewCount} 次</span>');
        }
        buf.writeln(
            '        <span class="meta-row" style="margin-left:auto">$createDateStr</span>');
        buf.writeln('      </div>');

        if (questionHtml.isNotEmpty) {
          buf.writeln(
              '      <div class="question-text">$questionHtml</div>');
        }

        final analysis = q.analysisResult;
        if (analysis != null) {
          final kps = [
            ...analysis.knowledgePoints.map(_cleanLatex),
            ...analysis.aiTags.map(_cleanLatex),
          ].take(5).join('  ·  ');
          if (kps.isNotEmpty) {
            buf.writeln('      <div class="analysis-item">');
            buf.writeln(
                '        <span class="analysis-label purple">知识点</span>：${_escapeHtml(kps)}');
            buf.writeln('      </div>');
          }

          final mistake = _cleanLatex(analysis.mistakeReason);
          if (mistake.isNotEmpty) {
            buf.writeln('      <div class="analysis-item">');
            buf.writeln(
                '        <span class="analysis-label">错因分析</span>：${_escapeHtml(mistake)}');
            buf.writeln('      </div>');
          }

          final answer = _cleanLatex(analysis.finalAnswer);
          if (answer.isNotEmpty) {
            buf.writeln('      <div class="analysis-item">');
            buf.writeln(
                '        <span class="analysis-label green">正确答案</span>：${_escapeHtml(answer)}');
            buf.writeln('      </div>');
          }

          if (analysis.steps.isNotEmpty) {
            buf.writeln('      <div class="steps-box">');
            buf.writeln(
                '        <div class="analysis-label blue" style="margin-bottom:4px">解题步骤</div>');
            for (var i = 0; i < analysis.steps.length; i++) {
              final step = _cleanLatex(analysis.steps[i]);
              if (step.isNotEmpty) {
                buf.writeln(
                    '        <div class="step-item">${i + 1}. ${_escapeHtml(step)}</div>');
              }
            }
            buf.writeln('      </div>');
          }

          final advice = _cleanLatex(analysis.studyAdvice);
          if (advice.isNotEmpty) {
            buf.writeln('      <div class="analysis-item">');
            buf.writeln(
                '        <span class="analysis-label orange">学习建议</span>：${_escapeHtml(advice)}');
            buf.writeln('      </div>');
          }
        }

        buf.writeln('    </div>');
      }

      buf.writeln('  </div>');
    }

    buf.writeln('''
</div>
</body>
</html>''');

    return buf.toString();
  }

  static String _subjectColor(Subject subject) {
    final c = subject.color;
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  static Future<File> generateHtml(List<QuestionRecord> questions) async {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final html = _generateHtml(questions, dateStr);

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }

    final now = DateTime.now();
    final filename = 'wrong_notebook_${now.millisecondsSinceEpoch}.html';
    final file = File('${exportDir.path}/$filename');
    await file.writeAsString(html, flush: true);
    return file;
  }

  static Future<void> shareHtml(
      BuildContext context, List<QuestionRecord> questions) async {
    try {
      final file = await generateHtml(questions);

      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '错题本整理报告（共 ${questions.length} 题）',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出HTML失败: $e')),
        );
      }
    }
  }
}
