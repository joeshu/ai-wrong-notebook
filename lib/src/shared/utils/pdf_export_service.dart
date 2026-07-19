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
/// 移动端利用原生 WebView 渲染，公式（KaTeX）和几何图片都能高保真输出；
/// 桌面端（Windows/macOS/Linux）`flutter_native_html_to_pdf` 不支持，
/// 自动降级为生成 HTML 并用系统浏览器打开，用户可在浏览器中打印为 PDF。
class PdfExportService {
  /// 生成 PDF 文件并返回。
  ///
  /// 桌面平台返回的是 HTML 文件（PDF 不可用），调用方应通过
  /// [isDesktopPlatform] 判断后再决定分享/打开方式。
  static Future<File> generatePdf(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
  }) async {
    final html = await HtmlExportService.generateHtmlString(
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
    final filename = 'wrong_notebook_${DateTime.now().millisecondsSinceEpoch}';

    if (HtmlExportService.isDesktopPlatform) {
      // 桌面端无原生 PDF 转换，保存 HTML 供浏览器打印。
      final htmlFile = File('${exportDir.path}/$filename.html');
      await htmlFile.writeAsString(html, flush: true);
      await HtmlExportService.cleanupExports(exportDir);
      return htmlFile;
    }

    final converter = HtmlToPdfConverter();
    final file = await converter.convertHtmlToPdf(
      html: html,
      targetDirectory: exportDir.path,
      targetName: filename,
      pageSize: PdfPageSize.a4,
    );
    await HtmlExportService.cleanupExports(exportDir);
    return file;
  }

  /// 调起系统分享 PDF 文件，并在生成期间显示进度。
  ///
  /// 桌面端自动降级为用系统浏览器打开 HTML。
  static Future<void> sharePdf(
    BuildContext context,
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
  }) async {
    if (HtmlExportService.isDesktopPlatform) {
      await _sharePdfDesktop(context, questions,
          title: title, mode: mode, studentInfo: studentInfo);
      return;
    }
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
                  // 图片预处理到 100% 后，generatePdf 还要调用
                  // convertHtmlToPdf 渲染 PDF（WebView，耗时数秒到十几秒），
                  // 这期间进度保持 1.0。切换文案避免用户误以为卡死。
                  if (v >= 1.0) {
                    return const Text('正在生成 PDF…');
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
      final file = await generatePdf(
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
          SnackBar(content: Text('导出 PDF 失败: $e')),
        );
      }
    }
  }

  /// 桌面端降级：生成 HTML 并用系统浏览器打开，提示用户打印为 PDF。
  static Future<void> _sharePdfDesktop(
    BuildContext context,
    List<QuestionRecord> questions, {
    required String title,
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
  }) async {
    try {
      final file = await HtmlExportService.generateHtml(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
      );
      await _openInDesktopBrowser(file);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('桌面端已用浏览器打开 HTML，可在浏览器中选择「打印」另存为 PDF'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 用系统默认浏览器/应用打开本地文件。
  static Future<void> _openInDesktopBrowser(File file) async {
    final path = file.path;
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      // Linux 及其它桌面环境。
      await Process.run('xdg-open', [path]);
    }
  }
}
