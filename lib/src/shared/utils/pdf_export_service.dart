import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

class PdfExportService {
  PdfExportService._();
  static pw.Font? _baseFont;

  static Future<pw.Font> _getFont() async {
    if (_baseFont != null) return _baseFont!;
    final data = await rootBundle.load('assets/fonts/MaShanZheng-Regular.ttf');
    _baseFont = pw.Font.ttf(data.buffer.asUint8List());
    return _baseFont!;
  }

  static Future<File> generatePdf(List<QuestionRecord> questions) async {
    final pdf = pw.Document();
    final font = await _getFont();
    final theme = pw.ThemeData.withFont(base: font);

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
                '错题本整理报告',
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
              widgets.addAll(_buildQuestionEntry(globalIndex, q));
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
      int index, QuestionRecord q) {
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

    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
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

    final analysis = q.analysisResult;
    if (analysis != null) {
      if (analysis.knowledgePoints.isNotEmpty || analysis.aiTags.isNotEmpty) {
        final kps = [
          ...analysis.knowledgePoints,
          ...analysis.aiTags,
        ].take(5).join('  ·  ');
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: pw.Text(
            '📌 知识点：$kps',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromInt(0x7C3AED),
            ),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      if (analysis.mistakeReason.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '❌ 错因分析：${analysis.mistakeReason}',
            style: pw.TextStyle(fontSize: 11),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      if (analysis.finalAnswer.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '✅ 正确答案：${analysis.finalAnswer}',
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
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Text(
                    '${entry.key + 1}. ${entry.value}',
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
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '💡 学习建议：${analysis.studyAdvice}',
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
      BuildContext context, List<QuestionRecord> questions) async {
    try {
      final file = await generatePdf(questions);

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
          SnackBar(content: Text('导出PDF失败: $e')),
        );
      }
    }
  }
}
