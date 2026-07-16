import 'dart:io';

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

  static Future<File> generatePdf(List<QuestionRecord> questions) async {
    final pdf = pw.Document();

    // 按学科分组并排序
    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

    // 封面/标题页
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.SizedBox(height: 120),
          pw.Center(
            child: pw.Text(
              '错题本整理报告',
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF6366F1),
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
              style: const pw.TextStyle(fontSize: 16),
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
        ],
      ),
    );

    // 目录页
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.Text(
            '目  录',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 20),
          ...sortedSubjects.map((subject) {
            final list = grouped[subject]!;
            return pw.Padding(
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
            );
          }),
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
        ],
      ),
    );

    // 各学科详细内容
    int globalIndex = 0;
    for (final subject in sortedSubjects) {
      final list = grouped[subject]!;
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(
              subject.label,
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey400,
              ),
            ),
          ),
          footer: (ctx, pageCount) => pw.Container(
            alignment: pw.Alignment.center,
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              '— $pageCount —',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey400,
              ),
            ),
          ),
          build: (ctx) {
            final widgets = <pw.Widget>[
              pw.Row(
                children: [
                  pw.Container(
                    width: 4,
                    height: 24,
                    color: PdfColor.fromInt(subject.color.value),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Text(
                    '${subject.label}（${list.length} 题）',
                    style: const pw.TextStyle(
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

  static List<pw.Widget> _buildQuestionEntry(
      int index, QuestionRecord q) {
    final widgets = <pw.Widget>[];

    // 题号 + 标签
    final labelParts = <pw.InlineSpan>[];
    labelParts.add(pw.TextSpan(
      text: '#$index  ',
      style: pw.TextStyle(
        fontSize: 16,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromInt(0xFF6366F1),
      ),
    ));

    if (q.isFavorite) {
      labelParts.add(pw.TextSpan(
        text: '★ ',
        style: pw.TextStyle(
          fontSize: 14,
          color: PdfColor.fromInt(0xFFD97706),
        ),
      ));
    }

    // 掌握程度标签
    final masterLabel = _masteryLabel(q.masteryLevel);
    final masterColor = _masteryColor(q.masteryLevel);
    labelParts.add(pw.TextSpan(
      text: '[$masterLabel] ',
      style: pw.TextStyle(
        fontSize: 11,
        color: PdfColor.fromInt(masterColor),
      ),
    ));

    // 内容状态标签
    if (q.contentStatus.name != 'ready') {
      final statusLabel = _statusLabel(q.contentStatus);
      labelParts.add(pw.TextSpan(
        text: '[$statusLabel] ',
        style: pw.TextStyle(fontSize: 11, color: PdfColors.grey500),
      ));
    }

    // 复习次数
    if (q.reviewCount > 0) {
      labelParts.add(pw.TextSpan(
        text: '已复习 ${q.reviewCount} 次 ',
        style: pw.TextStyle(fontSize: 11, color: PdfColors.grey500),
      ));
    }

    // 创建时间
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

    // 题目内容
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (questionText.isNotEmpty) {
      widgets.add(pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF5F3FF),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Text(
          questionText,
          style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
        ),
      ));
      widgets.add(pw.SizedBox(height: 6));
    }

    // 错题分析
    final analysis = q.analysisResult;
    if (analysis != null) {
      // 知识点标签
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
              color: PdfColor.fromInt(0xFF7C3AED),
            ),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      // 错因
      if (analysis.mistakeReason.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '❌ 错因分析：${analysis.mistakeReason}',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      // 正确答案
      if (analysis.finalAnswer.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '✅ 正确答案：${analysis.finalAnswer}',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromInt(0xFF16A34A),
            ),
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      // 解答步骤
      if (analysis.steps.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.all(8),
          margin: const pw.EdgeInsets.only(left: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(
                color: PdfColor.fromInt(0xFF6366F1),
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
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                );
              }),
            ],
          ),
        ));
        widgets.add(pw.SizedBox(height: 4));
      }

      // 学习建议
      if (analysis.studyAdvice.isNotEmpty) {
        widgets.add(pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: pw.Text(
            '💡 学习建议：${analysis.studyAdvice}',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromInt(0xFFD97706),
            ),
          ),
        ));
      }
    }

    // 分隔线
    widgets.add(pw.Divider(color: PdfColors.grey200));
    return widgets;
  }

  static String _masteryLabel(masteryLevel) {
    switch (masteryLevel.name) {
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

  static int _masteryColor(masteryLevel) {
    switch (masteryLevel.name) {
      case 'newQuestion':
        return 0xFFDC2626;
      case 'reviewing':
        return 0xFFD97706;
      case 'mastered':
        return 0xFF16A34A;
      default:
        return 0xFF6366F1;
    }
  }

  static String _statusLabel(contentStatus) {
    switch (contentStatus.name) {
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
    // 目录占1页，封面1页，所以每个学科起始页 = 2 + 被索引在列表中的位置
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
