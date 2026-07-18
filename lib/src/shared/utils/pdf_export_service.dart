import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

enum WorksheetExportMode { practice, answer, correction }

extension WorksheetExportModeLabel on WorksheetExportMode {
  String get label => switch (this) {
        WorksheetExportMode.practice => '练习卷',
        WorksheetExportMode.answer => '答案卷',
        WorksheetExportMode.correction => '订正卷',
      };
}

class PdfExportService {
  PdfExportService._();
  static pw.Font? _baseFont;

  static Future<pw.Font> _getFont() async {
    if (_baseFont != null) return _baseFont!;
    final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    _baseFont = pw.Font.ttf(data);
    return _baseFont!;
  }

  /// 清理 LaTeX 标记为 PDF 中可读的纯文本。
  ///
  /// PDF 导出不渲染数学公式，因此这里采用保守转换：保留公式含义，
  /// 但不把 LaTeX 控制字符直接输出。替换顺序必须让 `\\left` 等长命令
  /// 先于 `\\le` 处理，否则会产生 `≤ft` 之类的残片。
  static String _cleanLatex(String input) {
    var text = input
        .replaceAll(r'\[', '')
        .replaceAll(r'\]', '')
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'\left', '')
        .replaceAll(r'\right', '')
        .replaceAll(r'\Longrightarrow', '⇒')
        .replaceAll(r'\Rightarrow', '⇒')
        .replaceAll(r'\rightarrow', '→')
        .replaceAll(r'\cdots', '…')
        .replaceAll(r'\dots', '…')
        .replaceAll(r'\times', '×')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\div', '÷')
        .replaceAll(r'\geq', '≥')
        .replaceAll(r'\ge', '≥')
        .replaceAll(r'\leq', '≤')
        .replaceAll(r'\le', '≤')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\ne', '≠')
        .replaceAll(r'\pm', '±')
        .replaceAll(r'\mathrm', '')
        .replaceAll(r'\text', '')
        .replaceAll(r'\sqrt', '√')
        .replaceAll(r'\,', ' ')
        .replaceAll(r'\!', '')
        .replaceAll(r'\;', ' ')
        .replaceAll(r'\:', ' ')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', ' ');

    // 常见分式：\\frac{a+b}{ab} → (a+b)/(ab)。循环可处理相邻分式；
    // 更深的嵌套仍会退化为可读文本，而不会留下 LaTex 命令。
    final fraction = RegExp(r'\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}');
    while (fraction.hasMatch(text)) {
      text = text.replaceAllMapped(
        fraction,
        (match) => '(${match.group(1)})/(${match.group(2)})',
      );
    }

    text = text.replaceAll('{', '').replaceAll('}', '');
    // 移除任何剩余的 LaTex 命令。注意这里必须匹配单个反斜杠。
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+\*?'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // PDF/TTF 不接受孤立 UTF-16 代理项；保留合法 Unicode 字符。
    final codes = <int>[];
    for (final rune in text.runes) {
      if (rune == 0x09 || rune == 0x0a || rune == 0x0d ||
          rune >= 0x20 && rune <= 0x10ffff) {
        codes.add(rune);
      }
    }
    return String.fromCharCodes(codes);
  }

  static Future<File> generatePdf(
    List<QuestionRecord> questions, {
    WorksheetExportMode mode = WorksheetExportMode.answer,
  }) async {
    final pdf = pw.Document();
    final font = await _getFont();
    final theme = pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
    );

    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // 封面页
    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) {
          return <pw.Widget>[
            pw.SizedBox(height: 120),
            pw.Center(
              child: pw.Text(
                '${mode.label} · 错题本',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0x6366F1),
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text(
                'AI Wrong Notebook',
                style: pw.TextStyle(
                  fontSize: 14,
                  color: PdfColors.grey600,
                ),
              ),
            ),
            pw.SizedBox(height: 40),
            pw.Divider(color: PdfColors.grey300),
            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text(
                '共 ${questions.length} 道错题',
                style: pw.TextStyle(fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.Text(
                '导出时间：$dateStr',
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Center(
              child: pw.Text(
                '涵盖 ${sortedSubjects.length} 个学科',
                style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
              ),
            ),
          ];
        },
      ),
    );

    // 目录页
    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) {
          final tocItems = <pw.Widget>[
            pw.Text(
              '目  录',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 20),
          ];
          for (final subject in sortedSubjects) {
            final list = grouped[subject]!;
            tocItems.add(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${subject.label}（${list.length} 题）',
                      style: pw.TextStyle(fontSize: 14),
                    ),
                    pw.Text(
                      '第 ${_subjectPageLabel(sortedSubjects, subject)} 页',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          tocItems.addAll([
            pw.SizedBox(height: 20),
            pw.Divider(color: PdfColors.grey200),
            pw.SizedBox(height: 12),
            pw.Text(
              '掌握程度说明：● 待学习（New）  ● 复习中（Reviewing）  ● 已掌握（Mastered）',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
            pw.Text(
              '内容状态说明：● 处理中（Processing）  ● 已完成（Ready）  ● 失败（Failed）',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ]);
          return tocItems;
        },
      ),
    );

    // 各学科详细内容
    int globalIndex = 0;
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      final subjectColor = _subjectPdfColor(subject);
      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (pw.Context ctx) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                subject.label,
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey400,
                ),
              ),
            );
          },
          footer: (pw.Context ctx) {
            return pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                '— ${ctx.pageNumber} —',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey400,
                ),
              ),
            );
          },
          build: (ctx) {
            final widgets = <pw.Widget>[
              pw.Row(
                children: [
                  pw.Container(
                    width: 4,
                    height: 24,
                    color: subjectColor,
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    '${subject.label}（${list.length} 题）',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
            ];

            for (final q in list) {
              globalIndex++;
              widgets.addAll(_buildQuestionEntry(globalIndex, q, mode));
              widgets.add(pw.SizedBox(height: 12));
            }

            return widgets;
          },
        ),
      );
    }

    // 写入文件
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }

    final now = DateTime.now();
    final filename =
        'wrong_notebook_pdf_${now.millisecondsSinceEpoch}.pdf';
    final file = File('${exportDir.path}/$filename');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static PdfColor _subjectPdfColor(Subject subject) {
    final c = subject.color;
    return PdfColor.fromInt(
      (c.r.toInt() & 0xFF) << 16 |
      (c.g.toInt() & 0xFF) << 8 |
      (c.b.toInt() & 0xFF),
    );
  }

  static List<pw.Widget> _buildQuestionEntry(
    int index,
    QuestionRecord q,
    WorksheetExportMode mode,
  ) {
    final widgets = <pw.Widget>[];

    final labelParts = <pw.InlineSpan>[];
    labelParts.add(pw.TextSpan(
      text: '#$index  ',
      style: pw.TextStyle(
        fontSize: 16,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromInt(0x6366F1),
      ),
    ));

    if (q.isFavorite) {
      labelParts.add(pw.TextSpan(
        text: '★ ',
        style: pw.TextStyle(
          fontSize: 14,
          color: PdfColor.fromInt(0xD97706),
        ),
      ));
    }

    final masterLabel = _masteryLabel(q.masteryLevel);
    final masterColor = _masteryColor(q.masteryLevel);
    labelParts.add(pw.TextSpan(
      text: '[$masterLabel] ',
      style: pw.TextStyle(
        fontSize: 11,
        color: PdfColor.fromInt(masterColor),
      ),
    ));

    if (q.contentStatus.name != 'ready') {
      final statusLabel = _statusLabel(q.contentStatus);
      labelParts.add(pw.TextSpan(
        text: '[$statusLabel] ',
        style: pw.TextStyle(fontSize: 11, color: PdfColors.grey500),
      ));
    }

    if (q.reviewCount > 0) {
      labelParts.add(pw.TextSpan(
        text: '已复习 ${q.reviewCount} 次 ',
        style: pw.TextStyle(fontSize: 11, color: PdfColors.grey500),
      ));
    }

    final createDateStr = DateFormat('MM/dd').format(q.createdAt);
    labelParts.add(pw.TextSpan(
      text: createDateStr,
      style: pw.TextStyle(fontSize: 11, color: PdfColors.grey400),
    ));

    widgets.add(pw.RichText(
      text: pw.TextSpan(
        children: labelParts,
      ),
    ));

    widgets.add(pw.SizedBox(height: 8));

    final questionText = _cleanLatex(q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText);
    if (questionText.isNotEmpty) {
      widgets.add(pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xF5F3FF),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Text(
          questionText,
          style: pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
        ),
      ));
      widgets.add(pw.SizedBox(height: 6));
    }

    if (mode == WorksheetExportMode.practice) {
      widgets.add(pw.Container(
        height: 126,
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text('答题区',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey400)),
      ));
      widgets.add(pw.Divider(color: PdfColors.grey200));
      return widgets;
    }

    if (mode == WorksheetExportMode.correction) {
      final category = q.mistakeCategory?.label ?? '待分类';
      widgets.add(pw.Text('错因：$category',
          style: pw.TextStyle(fontSize: 11, color: PdfColor.fromInt(0xD97706))));
      if (q.studentWork?.isNotEmpty == true) {
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(pw.Text('我的作答：${_cleanLatex(q.studentWork!)}',
            style: pw.TextStyle(fontSize: 11)));
      }
      final advice = q.analysisResult?.studyAdvice ?? '';
      if (advice.isNotEmpty) {
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(pw.Text('订正提示：${_cleanLatex(advice)}',
            style: pw.TextStyle(fontSize: 11, color: PdfColor.fromInt(0x16A34A))));
      }
      widgets.add(pw.Container(
        height: 100,
        margin: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
      ));
      widgets.add(pw.Divider(color: PdfColors.grey200));
      return widgets;
    }

    final analysis = q.analysisResult;
    if (analysis != null) {
      if (analysis.knowledgePoints.isNotEmpty || analysis.aiTags.isNotEmpty) {
        final kps = [
          ...analysis.knowledgePoints.map(_cleanLatex),
          ...analysis.aiTags.map(_cleanLatex),
        ].take(5).join('  ·  ');
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: pw.Text(
            '[知识点] $kps',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromInt(0x7C3AED),
            ),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      if (analysis.mistakeReason.isNotEmpty) {
        final text = _cleanLatex(analysis.mistakeReason);
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '错因分析：$text',
            style: pw.TextStyle(fontSize: 11),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      if (analysis.finalAnswer.isNotEmpty) {
        final text = _cleanLatex(analysis.finalAnswer);
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '正确答案：$text',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromInt(0x16A34A),
            ),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      if (analysis.steps.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.only(left: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(
                color: PdfColor.fromInt(0x6366F1),
                width: 2,
              ),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '解题步骤：',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              ...analysis.steps.asMap().entries.map((entry) {
                final stepText = _cleanLatex(entry.value);
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Text(
                    '${entry.key + 1}. $stepText',
                    style: pw.TextStyle(fontSize: 11),
                  ),
                );
              }),
            ],
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      if (analysis.studyAdvice.isNotEmpty) {
        final text = _cleanLatex(analysis.studyAdvice);
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '学习建议：$text',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromInt(0xD97706),
            ),
          ),
        ));
      }
    }

    widgets.add(pw.Divider(color: PdfColors.grey200));
    return widgets;
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

  static int _masteryColor(dynamic masteryLevel) {
    final name = masteryLevel is String
        ? masteryLevel
        : '${masteryLevel}'.split('.').last;
    switch (name) {
      case 'newQuestion':
        return 0xDC2626;
      case 'reviewing':
        return 0xD97706;
      case 'mastered':
        return 0x16A34A;
      default:
        return 0x6366F1;
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
        return contentStatus.name;
    }
  }

  static String _subjectPageLabel(
      List<Subject> subjects, Subject target) {
    final idx = subjects.indexOf(target);
    return '${idx + 3}';
  }

  static Future<void> sharePdf(
    BuildContext context,
    List<QuestionRecord> questions, {
    WorksheetExportMode mode = WorksheetExportMode.answer,
  }) async {
    try {
      final file = await generatePdf(questions, mode: mode);

      if (!context.mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      // iOS 的部分分享目标会把附带文字误当成 URI 解析；中文内容
      // （例如“共 9 题”）会因此抛出 FormatException。PDF 本身已含标题和题数，
      // 所以只分享文件，并显式使用 ASCII 文件名，避免路径/标题编码问题。
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Wrong notebook PDF',
        fileNameOverrides: ['wrong-notebook-report.pdf'],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出PDF失败: $e')),
        );
      }
    }
  }
}
