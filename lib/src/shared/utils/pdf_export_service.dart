import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

import 'html_export_service.dart';
import 'worksheet_export_mode.dart';

/// 把自包含 HTML 错题报告转成 PDF 并分享。
///
/// 利用原生 WebView 渲染，因此公式（KaTeX）和几何图片都能高保真输出，
/// 且不需要在 Dart 层引入中文字体文件。
class PdfExportService {
  /// 生成 PDF 文件并返回。
  static Future<File> generatePdf(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
  }) async {
    final html = await HtmlExportService.generateHtmlString(
      questions,
      title: title,
      mode: mode,
    );
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final filename = 'wrong_notebook_${DateTime.now().millisecondsSinceEpoch}';
    final converter = HtmlToPdfConverter();
    final file = await converter.convertHtmlToPdf(
      html: html,
      targetDirectory: exportDir.path,
      targetName: filename,
      pageSize: PdfPageSize.a4,
    );
    return file;
  }

  /// 调起系统分享 PDF 文件。
  static Future<void> sharePdf(
    BuildContext context,
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
  }) async {
    try {
      final file = await generatePdf(questions, title: title, mode: mode);
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
          SnackBar(content: Text('导出 PDF 失败: $e')),
        );
      }
    }
  }
}
