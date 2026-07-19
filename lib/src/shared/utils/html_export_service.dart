import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 生成完全自包含的 HTML 错题报告。
///
/// 特点：
/// - 内联 KaTeX 的 CSS/JS/字体，不需要网络。
/// - 题目文本、答案、解析中的 LaTeX 会被 KaTeX 渲染。
/// - 错题原图（如果存在）以 base64 内嵌，几何图形等可直接查看。
class HtmlExportService {
  HtmlExportService._();

  static String? _cachedKatexCss;
  static String? _cachedKatexJs;

  /// 生成 HTML 字符串（可用于直接写入文件或转 PDF）。
  static Future<String> generateHtmlString(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
  }) async {
    final katexCss = await _loadKatexCss();
    final katexJs = await _loadKatexJs();

    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="zh-CN">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<title>${_escapeHtml(title)}</title>');
    buffer.writeln('<style>');
    buffer.writeln(_reportCss());
    buffer.writeln(katexCss);
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');
    buffer.writeln('<div class="page">');

    // 封面
    buffer.writeln('  <div class="cover">');
    buffer.writeln('    <h1>${_escapeHtml(title)}</h1>');
    buffer.writeln('    <div class="subtitle">AI Wrong Notebook</div>');
    buffer.writeln('    <div class="divider"></div>');
    buffer.writeln('    <div class="info">共 ${questions.length} 道错题</div>');
    buffer.writeln('    <div class="info">导出时间：$_escapeHtml(dateStr)</div>');
    buffer.writeln(
        '    <div class="info">涵盖 ${sortedSubjects.length} 个学科</div>');
    buffer.writeln('  </div>');

    // 目录
    buffer.writeln('  <div class="toc">');
    buffer.writeln('    <h2>目&emsp;录</h2>');
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      buffer.writeln('    <div class="toc-item">');
      buffer.writeln(
          '      <span>${_escapeHtml(subject.label)}</span>');
      buffer.writeln('      <span class="count">${list.length} 题</span>');
      buffer.writeln('    </div>');
    }
    buffer.writeln('    <div class="legend">');
    buffer.writeln(
        '      掌握程度：● 待学习&emsp;● 复习中&emsp;● 已掌握');
    buffer.writeln('    </div>');
    buffer.writeln('  </div>');

    // 各学科详情
    int globalIndex = 0;
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      final color = _subjectColorHex(subject);
      buffer.writeln('  <div class="subject-section">');
      buffer.writeln('    <div class="subject-header">');
      buffer.writeln(
          '      <div class="subject-bar" style="background:$color"></div>');
      buffer.writeln(
          '      <div class="subject-title">${_escapeHtml(subject.label)}（${list.length} 题）</div>');
      buffer.writeln('    </div>');

      for (final q in list) {
        globalIndex++;
        await _writeQuestionBlock(buffer, globalIndex, q);
      }

      buffer.writeln('  </div>');
    }

    buffer.writeln('</div>');
    buffer.writeln('<script>');
    buffer.writeln(katexJs);
    buffer.writeln(_renderMathJs());
    buffer.writeln('</script>');
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  /// 生成 HTML 文件并返回。
  static Future<File> generateHtml(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
  }) async {
    final html = await generateHtmlString(questions, title: title);
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final filename =
        'wrong_notebook_${DateTime.now().millisecondsSinceEpoch}.html';
    final file = File('${exportDir.path}/$filename');
    await file.writeAsString(html, flush: true);
    return file;
  }

  /// 调起系统分享 HTML 文件。
  static Future<void> shareHtml(
    BuildContext context,
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
  }) async {
    try {
      final file = await generateHtml(questions, title: title);
      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$title（共 ${questions.length} 题）',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 HTML 失败: $e')),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 题目块
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> _writeQuestionBlock(
    StringBuffer buffer,
    int index,
    QuestionRecord q,
  ) async {
    final createDateStr = DateFormat('MM/dd').format(q.createdAt);
    final mastery = _masteryLabel(q.masteryLevel);

    buffer.writeln('    <div class="question-block">');
    buffer.writeln('      <div class="question-header">');
    buffer.writeln('        <span class="question-index">#$index</span>');
    if (q.isFavorite) {
      buffer.writeln('        <span style="color:#d97706">★</span>');
    }
    buffer.writeln('        <span class="badge ${_masteryBadgeClass(q.masteryLevel)}">$_escapeHtml(mastery)</span>');
    if (q.contentStatus.toString().split('.').last != 'ready') {
      buffer.writeln(
          '        <span class="badge badge-status">${_statusLabel(q.contentStatus)}</span>');
    }
    if (q.reviewCount > 0) {
      buffer.writeln(
          '        <span class="meta">已复习 ${q.reviewCount} 次</span>');
    }
    buffer.writeln(
        '        <span class="meta" style="margin-left:auto">$createDateStr</span>');
    buffer.writeln('      </div>');

    // 题干
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (questionText.isNotEmpty) {
      buffer.writeln('      <div class="question-body">');
      buffer.write(_mixedTextToHtml(questionText));
      buffer.writeln('      </div>');
    }

    // 原题图片（几何图、手写痕迹等）
    final imageUri = await _imageDataUri(q.imagePath);
    if (imageUri != null) {
      buffer.writeln(
          '      <img class="question-image" src="$imageUri" alt="错题图片">');
    }

    // 解析信息
    final analysis = q.analysisResult;
    if (analysis != null) {
      final kps = [
        ...analysis.knowledgePoints,
        ...analysis.aiTags,
      ].take(5).join('  ·  ');
      if (kps.isNotEmpty) {
        buffer.writeln(
            '      <div class="analysis-row"><span class="analysis-label purple">知识点</span>：${_mixedTextToHtml(kps)}</div>');
      }
      if (analysis.mistakeReason.isNotEmpty) {
        buffer.writeln(
            '      <div class="analysis-row"><span class="analysis-label">错因分析</span>：${_mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      if (analysis.finalAnswer.isNotEmpty) {
        buffer.writeln(
            '      <div class="analysis-row"><span class="analysis-label green">正确答案</span>：${_mixedTextToHtml(analysis.finalAnswer)}</div>');
      }
      if (analysis.steps.isNotEmpty) {
        buffer.writeln('      <div class="steps-box">');
        buffer.writeln(
            '        <div class="analysis-label blue" style="margin-bottom:4px">解题步骤</div>');
        for (var i = 0; i < analysis.steps.length; i++) {
          buffer.writeln(
              '        <div class="step-item">${i + 1}. ${_mixedTextToHtml(analysis.steps[i])}</div>');
        }
        buffer.writeln('      </div>');
      }
      if (analysis.studyAdvice.isNotEmpty) {
        buffer.writeln(
            '      <div class="analysis-row"><span class="analysis-label orange">学习建议</span>：${_mixedTextToHtml(analysis.studyAdvice)}</div>');
      }
    }

    buffer.writeln('    </div>');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 文字 + LaTeX 混合转 HTML
  // ─────────────────────────────────────────────────────────────────────────

  static String _mixedTextToHtml(String input) {
    final normalized = _normalizeDelimiters(input);
    final spans = _splitMathSpans(normalized);
    final buffer = StringBuffer();
    for (final span in spans) {
      if (span.isMath) {
        final cls = span.display ? 'math-display' : 'math-inline';
        buffer.write('<span class="$cls">${_escapeHtml(span.text)}</span>');
      } else {
        final text = span.text
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('\n', '<br>');
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  static String _normalizeDelimiters(String v) {
    return v
        .replaceAllMapped(
          RegExp(r'\\\['),
          (_) => r'$$',
        )
        .replaceAllMapped(
          RegExp(r'\\\]'),
          (_) => r'$$',
        )
        .replaceAllMapped(
          RegExp(r'\\\('),
          (_) => r'$',
        )
        .replaceAllMapped(
          RegExp(r'\\\)'),
          (_) => r'$',
        );
  }

  static List<_MathSpan> _splitMathSpans(String v) {
    final spans = <_MathSpan>[];
    final displayRe = RegExp(r'\$\$([\s\S]*?)\$\$');
    var cursor = 0;
    for (final m in displayRe.allMatches(v)) {
      if (m.start > cursor) {
        spans.addAll(_splitInlineMath(v.substring(cursor, m.start)));
      }
      spans.add(_MathSpan(m.group(1)!.trim(), isMath: true, display: true));
      cursor = m.end;
    }
    if (cursor < v.length) {
      spans.addAll(_splitInlineMath(v.substring(cursor)));
    }
    return spans.where((s) => s.text.isNotEmpty).toList();
  }

  static List<_MathSpan> _splitInlineMath(String v) {
    final spans = <_MathSpan>[];
    final inlineRe = RegExp(r'\$([^\$]+)\$');
    var cursor = 0;
    for (final m in inlineRe.allMatches(v)) {
      if (m.start > cursor) {
        spans.add(_MathSpan(v.substring(cursor, m.start), isMath: false));
      }
      spans.add(_MathSpan(m.group(1)!.trim(), isMath: true));
      cursor = m.end;
    }
    if (cursor < v.length) {
      spans.add(_MathSpan(v.substring(cursor), isMath: false));
    }
    return spans.where((s) => s.text.isNotEmpty).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KaTeX 资源内联
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String> _loadKatexCss() async {
    if (_cachedKatexCss != null) return _cachedKatexCss!;
    var css = await rootBundle.loadString('assets/katex/katex.min.css');
    css = await _inlineAllFontFaces(css);
    _cachedKatexCss = css;
    return css;
  }

  static Future<String> _loadKatexJs() async {
    _cachedKatexJs ??=
        await rootBundle.loadString('assets/katex/katex.min.js');
    return _cachedKatexJs!;
  }

  static Future<String> _inlineAllFontFaces(String css) async {
    final re = RegExp(r"url\(['\"]?fonts/([A-Za-z0-9_\-]+\.woff2)['\"]?\)");
    final filenames = re.allMatches(css).map((m) => m.group(1)!).toSet();
    for (final filename in filenames) {
      try {
        final data = await rootBundle.load('assets/katex/fonts/$filename');
        final base64 = base64Encode(data.buffer.asUint8List());
        final uri = "data:font/woff2;base64,$base64";
        css = css.replaceAllMapped(
          RegExp(r"url\(['\"]?fonts/" + RegExp.escape(filename) + r"['\"]?\)"),
          (_) => "url('$uri')",
        );
      } catch (_) {
        // 如果某个字体未打包，保留原链接，浏览器会继续尝试加载。
      }
    }
    return css;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 图片 base64
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String?> _imageDataUri(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final ext = path.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final base64 = base64Encode(bytes);
      return 'data:$mime;base64,$base64';
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 样式与脚本
  // ─────────────────────────────────────────────────────────────────────────

  static String _reportCss() {
    return '''
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
* { box-sizing: border-box; }
body {
  font-family: -apple-system, 'PingFang SC', 'Microsoft YaHei', 'Hiragino Sans GB', sans-serif;
  font-size: 11pt;
  line-height: 1.7;
  color: #1f2937;
  margin: 0;
  padding: 0;
}
.page { max-width: 190mm; margin: 0 auto; }

.cover {
  text-align: center;
  padding-top: 70mm;
  page-break-after: always;
}
.cover h1 { font-size: 26pt; font-weight: 700; color: #6366F1; margin-bottom: 12px; }
.cover .subtitle { font-size: 13pt; color: #888; margin-bottom: 36px; }
.cover .divider { width: 60%; height: 1px; background: #ddd; margin: 0 auto 24px; }
.cover .info { font-size: 12pt; color: #555; margin-bottom: 6px; }

.toc { page-break-after: always; }
.toc h2 { font-size: 20pt; font-weight: 700; margin-bottom: 20px; }
.toc-item { display: flex; justify-content: space-between; padding: 6px 0; font-size: 12pt; }
.toc-item .count { color: #888; font-size: 10.5pt; }
.legend { font-size: 10pt; color: #888; margin-top: 18px; line-height: 2; }

.subject-section { page-break-before: always; }
.subject-header { display: flex; align-items: center; gap: 8px; margin-bottom: 16px; }
.subject-bar { width: 4px; height: 22px; border-radius: 2px; }
.subject-title { font-size: 18pt; font-weight: 700; }

.question-block {
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid #e5e7eb;
  break-inside: avoid;
}
.question-header { display: flex; align-items: center; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
.question-index { font-size: 13pt; font-weight: 700; color: #6366F1; margin-right: 2px; }
.badge {
  display: inline-block;
  font-size: 8.5pt;
  padding: 1px 7px;
  border-radius: 999px;
  font-weight: 500;
}
.badge-new { background: #fee2e2; color: #dc2626; }
.badge-reviewing { background: #fef3c7; color: #d97706; }
.badge-mastered { background: #dcfce7; color: #16a34a; }
.badge-status { background: #f3f4f6; color: #6b7280; }
.meta { font-size: 9pt; color: #9ca3af; }

.question-body {
  background: #f5f3ff;
  border-radius: 6px;
  padding: 10px 12px;
  margin: 8px 0;
  font-size: 11pt;
  line-height: 1.8;
}
.question-image {
  max-width: 100%;
  max-height: 260px;
  object-fit: contain;
  border-radius: 6px;
  margin-top: 8px;
  display: block;
}

.analysis-row { font-size: 10.5pt; margin-top: 4px; }
.analysis-label { font-weight: 600; }
.analysis-label.green { color: #16a34a; }
.analysis-label.purple { color: #7c3aed; }
.analysis-label.orange { color: #d97706; }
.analysis-label.blue { color: #6366F1; }
.steps-box {
  border-left: 2px solid #6366F1;
  padding-left: 10px;
  margin-top: 6px;
}
.step-item { font-size: 10pt; margin-bottom: 3px; }

.math-inline { display: inline; }
.math-display { display: block; margin: 6px 0; }
.katex { font-size: 1.06em; }

@media print {
  .page { max-width: none; }
  .question-block { break-inside: avoid; }
  .subject-section { break-before: page; }
}
''';
  }

  static String _renderMathJs() {
    return '''
document.addEventListener('DOMContentLoaded', function() {
  function render(el, display) {
    try {
      katex.render(el.textContent, el, {
        throwOnError: false,
        strict: false,
        trust: true,
        displayMode: display
      });
    } catch(e) {}
  }
  document.querySelectorAll('.math-inline').forEach(function(el) { render(el, false); });
  document.querySelectorAll('.math-display').forEach(function(el) { render(el, true); });
});
''';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────────

  static String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _subjectColorHex(Subject subject) {
    final c = subject.color;
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
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

  static String _masteryBadgeClass(dynamic masteryLevel) {
    final name = masteryLevel is String
        ? masteryLevel
        : '${masteryLevel}'.split('.').last;
    switch (name) {
      case 'newQuestion':
        return 'badge-new';
      case 'reviewing':
        return 'badge-reviewing';
      case 'mastered':
        return 'badge-mastered';
      default:
        return 'badge-new';
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
        return name;
    }
  }
}

class _MathSpan {
  _MathSpan(this.text, {this.isMath = false, this.display = false});
  final String text;
  final bool isMath;
  final bool display;
}
