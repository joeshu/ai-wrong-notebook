import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as image;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 封面上的学生信息栏数据。
class ExportStudentInfo {
  const ExportStudentInfo({this.name, this.className, this.date});

  final String? name;
  final String? className;

  /// 已格式化的日期字符串，为空时使用导出当前时间。
  final String? date;
}

/// 生成完全自包含的 HTML 错题报告。
///
/// 特点：
/// - 内联 KaTeX 的 CSS/JS/字体（woff2），不需要网络。
/// - 题目文本、答案、解析中的 LaTeX 会被 KaTeX 渲染，支持 `$$`、`$`、
///   `\(...\)`、`\[...\]` 以及 `\begin{env}...\end{env}` 环境。
/// - 错题原图（如果存在）会被缩放压缩后以 base64 内嵌，几何图形可直接查看。
class HtmlExportService {
  static String? _cachedKatexCss;
  static String? _cachedKatexJs;

  /// exports 目录最多保留的文件数，超出按时间倒序清理。
  static const int maxKeptExports = 20;

  /// 是否为桌面平台（Windows / macOS / Linux），用于 PDF 降级判断。
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 生成 HTML 字符串（可用于直接写入文件或转 PDF）。
  ///
  /// [onProgress] 在预处理图片时回调，用于显示进度。
  static Future<String> generateHtmlString(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
  }) async {
    final katexCss = await _loadKatexCss();
    final katexJs = await _loadKatexJs();

    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    // 预处理所有图片（并行压缩编码），避免逐题 await 阻塞。
    final imageUris = await _preloadImages(questions, onProgress);

    final dateStr = studentInfo?.date ??
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
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
    // 打印时的页眉页脚（fixed 元素，支持的平台会在每页重复）。
    buffer.writeln('  <div class="print-header">${_escapeHtml(title)}</div>');
    buffer.writeln('  <div class="print-footer"></div>');
    buffer.writeln('<div class="page">');

    // 封面
    buffer.writeln('  <div class="cover">');
    buffer.writeln('    <h1>${_escapeHtml(title)}</h1>');
    buffer.writeln('    <div class="subtitle">AI Wrong Notebook</div>');
    buffer.writeln('    <div class="divider"></div>');
    buffer.writeln('    <div class="info">共 ${questions.length} 道错题</div>');
    buffer.writeln('    <div class="info">导出时间：$dateStr</div>');
    buffer.writeln(
        '    <div class="info">涵盖 ${sortedSubjects.length} 个学科</div>');
    buffer.writeln('    <div class="name-row">');
    buffer.writeln(
        '      <span>姓&emsp;名：${_escapeHtml(studentInfo?.name ?? '____________')}</span>');
    buffer.writeln(
        '      <span>班&emsp;级：${_escapeHtml(studentInfo?.className ?? '____________')}</span>');
    buffer.writeln('    </div>');
    buffer.writeln('    <div class="name-row">');
    buffer.writeln('      <span>日&emsp;期：$dateStr</span>');
    buffer.writeln('      <span>得&emsp;分：____________</span>');
    buffer.writeln('    </div>');
    buffer.writeln('  </div>');

    // 目录
    buffer.writeln('  <div class="toc">');
    buffer.writeln('    <h2>目&emsp;录</h2>');
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      buffer.writeln('    <div class="toc-item">');
      buffer.writeln('      <span>${_escapeHtml(subject.label)}</span>');
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
        _writeQuestionBlock(buffer, globalIndex, q,
            mode: mode, imageUris: imageUris);
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
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
  }) async {
    final html = await generateHtmlString(
      questions,
      title: title,
      mode: mode,
      studentInfo: studentInfo,
      onProgress: onProgress,
    );
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final filename =
        'wrong_notebook_${DateTime.now().millisecondsSinceEpoch}.html';
    final file = File('${exportDir.path}/$filename');
    await file.writeAsString(html, flush: true);
    await cleanupExports(exportDir);
    return file;
  }

  /// 调起系统分享 HTML 文件，并在生成期间显示进度。
  static Future<void> shareHtml(
    BuildContext context,
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
  }) async {
    final progress = ValueNotifier<double>(0);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, v, __) {
                  if (v <= 0) {
                    return const Text('正在准备导出…');
                  }
                  // 图片预处理到 100% 后，generateHtml 还要写文件 +
                  // 调起系统分享（几秒），这期间进度保持 1.0。
                  // 切换文案避免用户误以为卡死。
                  if (v >= 1.0) {
                    return const Text('正在生成 HTML…');
                  }
                  return Text('正在处理图片 ${(v * 100).round()}%');
                },
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final file = await generateHtml(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        onProgress: (done, total) {
          progress.value = total == 0 ? 1 : done / total;
        },
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
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
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 HTML 失败: $e')),
        );
      }
    }
  }

  /// 清理 exports 目录，只保留最近 [maxKeptExports] 个文件。
  static Future<void> cleanupExports(Directory exportDir) async {
    try {
      if (!exportDir.existsSync()) return;
      final files = exportDir.listSync().whereType<File>().toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final file in files.skip(maxKeptExports)) {
        await file.delete();
      }
    } catch (_) {
      // 清理失败不影响导出。
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 题目块
  // ─────────────────────────────────────────────────────────────────────────

  static void _writeQuestionBlock(
    StringBuffer buffer,
    int index,
    QuestionRecord q, {
    WorksheetExportMode? mode,
    Map<String, String?> imageUris = const {},
  }) {
    final createDateStr = DateFormat('MM/dd').format(q.createdAt);
    final mastery = _masteryLabel(q.masteryLevel);

    buffer.writeln('    <div class="question-block">');
    buffer.writeln('      <div class="question-header">');
    buffer.writeln('        <span class="question-index">#$index</span>');
    if (q.isFavorite) {
      buffer.writeln('        <span style="color:#d97706">★</span>');
    }
    buffer.writeln(
        '        <span class="badge ${_masteryBadgeClass(q.masteryLevel)}">${_escapeHtml(mastery)}</span>');
    if (q.contentStatus != ContentStatus.ready) {
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
    final imageUri = imageUris[q.id];
    if (imageUri != null) {
      buffer.writeln(
          '      <img class="question-image" src="$imageUri" alt="错题图片">');
    }

    if (mode == WorksheetExportMode.practice) {
      final blankHeight = _practiceBlankHeight(questionText);
      buffer.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    } else {
      _writeAnalysisBlock(buffer, q, mode);
    }

    buffer.writeln('    </div>');
  }

  static void _writeAnalysisBlock(
    StringBuffer buffer,
    QuestionRecord q,
    WorksheetExportMode? mode,
  ) {
    final analysis = q.analysisResult;
    if (analysis == null) return;

    if (mode == null || mode == WorksheetExportMode.answer) {
      final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
          .take(5)
          .join('  ·  ');
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
    } else if (mode == WorksheetExportMode.correction) {
      if (analysis.mistakeReason.isNotEmpty) {
        buffer.writeln(
            '      <div class="analysis-row"><span class="analysis-label">错因分析</span>：${_mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      if (analysis.studyAdvice.isNotEmpty) {
        buffer.writeln(
            '      <div class="analysis-row"><span class="analysis-label orange">订正提示</span>：${_mixedTextToHtml(analysis.studyAdvice)}</div>');
      }
      final blankHeight = _practiceBlankHeight(q.normalizedQuestionText);
      buffer.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    }
  }

  /// 练习卷/订正卷答题留白高度，按题干长度自适应。
  static int _practiceBlankHeight(String questionText) {
    if (questionText.isEmpty) return 80;
    final lines = (questionText.length / 40).ceil();
    final height = (lines + 3) * 28;
    return height.clamp(60, 220).toInt();
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
    // 同时匹配 `$$...$$` 与 `\begin{env}...\end{env}` 两种 display 数学块。
    final displayOrEnv = RegExp(
      r'\$\$([\s\S]*?)\$\$|\\begin\{([A-Za-z]+\*?)\}([\s\S]*?)\\end\{\2\}',
    );
    var cursor = 0;
    for (final m in displayOrEnv.allMatches(v)) {
      if (m.start > cursor) {
        spans.addAll(_splitInlineMath(v.substring(cursor, m.start)));
      }
      final math = m.group(1) ?? m.group(3)!;
      spans.add(_MathSpan(math.trim(), isMath: true, display: true));
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
  // 图片预处理（并行压缩）
  // ─────────────────────────────────────────────────────────────────────────

  static Future<Map<String, String?>> _preloadImages(
    List<QuestionRecord> questions,
    void Function(int done, int total)? onProgress,
  ) async {
    final entries = questions.where((q) => q.imagePath.isNotEmpty).toList();
    final total = entries.length;
    if (total == 0) {
      if (onProgress != null) onProgress(0, 0);
      return const {};
    }
    var done = 0;
    final results = await Future.wait(entries.map((q) async {
      final uri = await _encodeImage(q.imagePath);
      final current = ++done;
      if (onProgress != null) onProgress(current, total);
      return MapEntry(q.id, uri);
    }));
    return {for (final e in results) e.key: e.value};
  }

  /// 读取图片文件，缩放到最大宽度 1200px 并重新编码，返回 data URI。
  /// 解码/缩放/编码在后台 isolate 执行，避免大图阻塞 UI。
  /// PNG 保留 PNG 编码（保留透明），其余转 JPEG(quality 80)。
  static Future<String?> _encodeImage(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return null;
      final result = await compute(
        _encodeImageIsolate,
        _EncodeRequest(raw, path),
      );
      if (result == null) {
        // 无法解码，回退原文件 base64。
        final ext = path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        return 'data:$mime;base64,${base64Encode(raw)}';
      }
      return result;
    } catch (_) {
      return null;
    }
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
    // 1. 内联 woff2 字体为 base64。
    final woff2Re =
        RegExp(r'''url\(['"]?fonts/([A-Za-z0-9_\-]+\.woff2)['"]?\)''');
    final filenames = woff2Re.allMatches(css).map((m) => m.group(1)!).toSet();
    for (final filename in filenames) {
      try {
        final data = await rootBundle.load('assets/katex/fonts/$filename');
        final base64 = base64Encode(data.buffer.asUint8List());
        final uri = "data:font/woff2;base64,$base64";
        css = css.replaceAllMapped(
          RegExp(
              r'''url\(['"]?fonts/''' + RegExp.escape(filename) + r'''['"]?\)'''),
          (_) => "url('$uri')",
        );
      } catch (_) {
        // 如果某个字体未打包，保留原链接，浏览器会继续尝试加载。
      }
    }
    // 2. 删除 woff/ttf fallback，避免离线 404（woff2 已足够现代浏览器使用）。
    css = css.replaceAll(
      RegExp(r''',\s*url\(fonts/[^)]+\.woff\)\s*format\("woff"\)'''),
      '',
    );
    css = css.replaceAll(
      RegExp(r''',\s*url\(fonts/[^)]+\.ttf\)\s*format\("truetype"\)'''),
      '',
    );
    return css;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 样式与脚本
  // ─────────────────────────────────────────────────────────────────────────

  static String _reportCss() {
    return '''
@page {
  size: A4;
  margin: 22mm 16mm 20mm 16mm;
  @bottom-center {
    content: "第 " counter(page) " 页 / 共 " counter(pages) " 页";
    font-size: 9pt;
    color: #999;
  }
}
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

.print-header, .print-footer { display: none; }
@media print {
  .print-header {
    display: block;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 9pt;
    color: #999;
    border-bottom: 1px solid #eee;
    padding: 4px 0;
  }
  .print-footer {
    display: block;
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 9pt;
    color: #999;
  }
}

.cover {
  text-align: center;
  padding-top: 60mm;
  page-break-after: always;
}
.cover h1 { font-size: 26pt; font-weight: 700; color: #6366F1; margin-bottom: 12px; }
.cover .subtitle { font-size: 13pt; color: #888; margin-bottom: 36px; }
.cover .divider { width: 60%; height: 1px; background: #ddd; margin: 0 auto 24px; }
.cover .info { font-size: 12pt; color: #555; margin-bottom: 6px; }
.name-row {
  display: flex;
  justify-content: space-around;
  margin-top: 18px;
  font-size: 12pt;
  color: #444;
}

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
.blank-area {
  border: 1px dashed #c7c3ff;
  border-radius: 6px;
  background: #fafaff;
  margin-top: 8px;
}

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

  static String _masteryLabel(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '待学习',
        MasteryLevel.reviewing => '复习中',
        MasteryLevel.mastered => '已掌握',
      };

  static String _masteryBadgeClass(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => 'badge-new',
        MasteryLevel.reviewing => 'badge-reviewing',
        MasteryLevel.mastered => 'badge-mastered',
      };

  static String _statusLabel(ContentStatus status) => switch (status) {
        ContentStatus.processing => '处理中',
        ContentStatus.ready => '已完成',
        ContentStatus.failed => '识别失败',
      };
}

class _MathSpan {
  _MathSpan(this.text, {this.isMath = false, this.display = false});
  final String text;
  final bool isMath;
  final bool display;
}

class _EncodeRequest {
  const _EncodeRequest(this.bytes, this.path);
  final Uint8List bytes;
  final String path;
}

/// 在后台 isolate 执行图片解码、缩放、重编码，返回 data URI 字符串。
/// 返回 null 表示解码失败（调用方回退原文件 base64）。
String? _encodeImageIsolate(_EncodeRequest req) {
  final decoded = image.decodeImage(req.bytes);
  if (decoded == null) return null;
  const maxWidth = 1200;
  image.Image scaled = decoded;
  if (decoded.width > maxWidth) {
    scaled = image.copyResize(decoded, width: maxWidth);
  }
  final ext = req.path.split('.').last.toLowerCase();
  if (ext == 'png') {
    final encoded = image.encodePng(scaled, level: 6);
    return 'data:image/png;base64,${base64Encode(encoded)}';
  }
  final encoded = image.encodeJpg(scaled, quality: 80);
  return 'data:image/jpeg;base64,${base64Encode(encoded)}';
}
