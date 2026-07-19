import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 导出前的 HTML 预览页：用 WebView 渲染最终报告，并提供分享 HTML / 导出 PDF。
class HtmlPreviewScreen extends StatefulWidget {
  const HtmlPreviewScreen({
    super.key,
    required this.questions,
    this.title = '错题本整理报告',
    this.mode,
    this.studentInfo,
  });

  final List<QuestionRecord> questions;
  final String title;
  final WorksheetExportMode? mode;
  final ExportStudentInfo? studentInfo;

  @override
  State<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends State<HtmlPreviewScreen> {
  WebViewController? _controller;
  String? _filePath;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final file = await HtmlExportService.generateHtml(
        widget.questions,
        title: widget.title,
        mode: widget.mode,
        studentInfo: widget.studentInfo,
      );
      _filePath = file.path;
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadFile(file.path);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导出预览'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: '分享 HTML',
            onPressed: _loading || _error != null
                ? null
                : () => HtmlExportService.shareHtml(
                      context,
                      widget.questions,
                      title: widget.title,
                      mode: widget.mode,
                      studentInfo: widget.studentInfo,
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: '导出 PDF',
            onPressed: _loading || _error != null
                ? null
                : () => PdfExportService.sharePdf(
                      context,
                      widget.questions,
                      title: widget.title,
                      mode: widget.mode,
                      studentInfo: widget.studentInfo,
                    ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('预览生成失败：$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_controller == null) {
      return const Center(child: Text('无法初始化预览'));
    }
    return WebViewWidget(controller: _controller!);
  }
}
