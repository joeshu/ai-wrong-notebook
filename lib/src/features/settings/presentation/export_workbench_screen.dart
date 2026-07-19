import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/anki_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/csv_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_options_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_preview_screen.dart';
import 'package:smart_wrong_notebook/src/shared/utils/json_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/markdown_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';

/// 导出工作台支持的输出格式。
enum ExportFormat { html, pdf, markdown, anki, csv, json }

/// 导出工作台：集中所有导出能力的统一入口页。
///
/// 页面分区（自上而下）：
/// 1. 模板选择：错题报告 / 学习报告 / 复习卡
/// 2. 格式选择：HTML / PDF / Markdown / Anki / CSV / JSON（HTML 与 PDF 互斥）
/// 3. 筛选与内容选项：调用 [showExportOptionsDialog] 复用既有对话框
/// 4. 排版选项：仅当选中 PDF 时展示，复用 [PdfLayoutOptions]
/// 5. 预览：仅当选中 HTML 时可用，跳转 [HtmlPreviewScreen]
/// 6. 导出：底部 sticky 按钮，按选中格式依次调用对应导出服务
class ExportWorkbenchScreen extends ConsumerStatefulWidget {
  const ExportWorkbenchScreen({super.key});

  @override
  ConsumerState<ExportWorkbenchScreen> createState() =>
      _ExportWorkbenchScreenState();
}

class _ExportWorkbenchScreenState extends ConsumerState<ExportWorkbenchScreen> {
  ExportTemplateType _selectedTemplate = ExportTemplateType.mistakeReport;
  final Set<ExportFormat> _selectedFormats = <ExportFormat>{
    ExportFormat.html,
  };
  ExportOptions? _exportOptions;
  PdfLayoutOptions _layoutOptions = const PdfLayoutOptions();
  bool _isExporting = false;
  double _exportProgress = 0;

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('导出工作台'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: questionsAsync.when(
        data: (questions) => _buildBody(context, questions),
        loading: () => const AppListSkeleton(),
        error: (e, _) => AppErrorState(
          error: e,
          onRetry: () => ref.invalidate(questionListProvider),
        ),
      ),
      bottomNavigationBar: _buildExportBar(context),
    );
  }

  Widget _buildBody(BuildContext context, List<QuestionRecord> questions) {
    final showLayoutOptions = _selectedFormats.contains(ExportFormat.pdf);
    final showPreview = _selectedFormats.contains(ExportFormat.html);
    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _buildTemplateSection(context)),
        SliverToBoxAdapter(child: _buildFormatSection(context)),
        SliverToBoxAdapter(child: _buildFilterSection(context, questions)),
        if (showLayoutOptions)
          SliverToBoxAdapter(child: _buildLayoutSection(context)),
        SliverToBoxAdapter(child: _buildPreviewSection(context, showPreview)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 模板选择区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildTemplateSection(BuildContext context) {
    return _Section(
      title: '选择模板',
      description: '不同模板预设了内容字段，可在下方继续微调',
      child: SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: ExportTemplateType.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final template = ExportTemplateType.values[index];
            return _TemplateCard(
              template: template,
              selected: _selectedTemplate == template,
              onTap: () => setState(() => _selectedTemplate = template),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 格式选择区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildFormatSection(BuildContext context) {
    return _Section(
      title: '导出格式',
      description: '可多选；HTML 与 PDF 互斥，选其中一个会自动取消另一个',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final format in ExportFormat.values)
              FilterChip(
                label: Text(_formatLabel(format)),
                avatar: Icon(_formatIcon(format), size: 16),
                selected: _selectedFormats.contains(format),
                onSelected: (_) => _toggleFormat(format),
              ),
          ],
        ),
      ),
    );
  }

  void _toggleFormat(ExportFormat format) {
    setState(() {
      if (_selectedFormats.contains(format)) {
        _selectedFormats.remove(format);
      } else {
        _selectedFormats.add(format);
        // HTML 与 PDF 互斥：选 HTML 自动取消 PDF，反之亦然。
        if (format == ExportFormat.html) {
          _selectedFormats.remove(ExportFormat.pdf);
        } else if (format == ExportFormat.pdf) {
          _selectedFormats.remove(ExportFormat.html);
        }
      }
    });
  }

  String _formatLabel(ExportFormat format) => switch (format) {
        ExportFormat.html => 'HTML',
        ExportFormat.pdf => 'PDF',
        ExportFormat.markdown => 'Markdown',
        ExportFormat.anki => 'Anki',
        ExportFormat.csv => 'CSV',
        ExportFormat.json => 'JSON',
      };

  IconData _formatIcon(ExportFormat format) => switch (format) {
        ExportFormat.html => CupertinoIcons.doc_text,
        ExportFormat.pdf => CupertinoIcons.doc_richtext,
        ExportFormat.markdown => CupertinoIcons.text_badge_plus,
        ExportFormat.anki => CupertinoIcons.rectangle_stack,
        ExportFormat.csv => CupertinoIcons.table,
        ExportFormat.json => CupertinoIcons.square_stack_3d_up,
      };

  // ─────────────────────────────────────────────────────────────────────
  // 筛选与内容选项区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildFilterSection(
    BuildContext context,
    List<QuestionRecord> questions,
  ) {
    final options = _exportOptions;
    return _Section(
      title: '筛选与内容选项',
      description: '点击下方按钮配置学科、掌握度、时间范围与导出字段',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FilledButton.icon(
              onPressed: questions.isEmpty
                  ? null
                  : () => _openOptionsDialog(context, questions),
              icon: const Icon(CupertinoIcons.slider_horizontal_3),
              label: const Text('筛选与内容选项'),
            ),
            const SizedBox(height: 12),
            if (options == null)
              _SummaryBox(
                icon: CupertinoIcons.info,
                text: '尚未配置：将默认导出全部题目（${questions.length} 题）'
                    '${questions.isEmpty ? '，题库为空时无法导出' : ''}',
              )
            else ...<Widget>[
              _SummaryBox(
                icon: CupertinoIcons.line_horizontal_3_decrease,
                title: '当前筛选',
                text: _buildFilterSummary(options, questions.length),
              ),
              const SizedBox(height: 8),
              _SummaryBox(
                icon: CupertinoIcons.list_bullet,
                title: '内容选项',
                text: _buildContentSummary(options.contentOptions),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openOptionsDialog(
    BuildContext context,
    List<QuestionRecord> questions,
  ) async {
    final result = await showExportOptionsDialog(context, questions);
    if (result == null || !mounted) return;
    setState(() => _exportOptions = result);
  }

  String _buildFilterSummary(ExportOptions options, int totalCount) {
    final parts = <String>[];
    parts.add(options.mode.label);
    parts.add('${options.filtered.length} / $totalCount 题');
    if (options.onlyFavorite) parts.add('仅收藏');
    if (options.selectedKnowledgePoints.isNotEmpty) {
      parts.add('${options.selectedKnowledgePoints.length} 个知识点');
    }
    if (options.selectedMistakeCategories.isNotEmpty) {
      parts.add('${options.selectedMistakeCategories.length} 类错因');
    }
    if (options.selectedDifficulties.isNotEmpty) {
      parts.add('${options.selectedDifficulties.length} 种难度');
    }
    if (options.selectedLearningStages.isNotEmpty) {
      parts.add('${options.selectedLearningStages.length} 个学习阶段');
    }
    if (options.selectedSources.isNotEmpty) {
      parts.add('${options.selectedSources.length} 个来源');
    }
    if (options.dateRange != null) {
      parts.add(
          '${_formatDate(options.dateRange!.start)}~${_formatDate(options.dateRange!.end)}');
    }
    return parts.join(' · ');
  }

  String _buildContentSummary(ExportContentOptions o) {
    final parts = <String>[];
    if (o.includeImage) parts.add('含题图');
    if (o.includeCorrectAnswer) parts.add('含答案');
    if (o.includeSolutionSteps) parts.add('含解析');
    if (o.includeKnowledgePoints) parts.add('含知识点');
    if (o.includeMistakeReason) parts.add('含错因');
    if (o.includeStudyAdvice) parts.add('含学习建议');
    if (o.includeReviewCount) parts.add('含复习次数');
    if (o.includeFavoriteMark) parts.add('含收藏标记');
    if (o.includeDates) parts.add('含日期');
    if (o.includeExercises) parts.add('含 AI 练习题');
    if (parts.isEmpty) parts.add('无内容字段');
    return parts.join(' / ');
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ─────────────────────────────────────────────────────────────────────
  // 排版选项区（仅 PDF）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildLayoutSection(BuildContext context) {
    final o = _layoutOptions;
    return _Section(
      title: 'PDF 排版选项',
      description: '仅作用于 PDF 导出；其它格式忽略此处的设置',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildDropdownRow<PdfPageSize>(
              label: '纸张大小',
              value: o.pageSize,
              values: PdfPageSize.values,
              onChanged: (v) => setState(
                  () => _layoutOptions = _layoutOptions.copyWith(pageSize: v)),
            ),
            _buildDropdownRow<PdfOrientation>(
              label: '方向',
              value: o.orientation,
              values: PdfOrientation.values,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(orientation: v)),
            ),
            _buildDropdownRow<PdfMargin>(
              label: '边距',
              value: o.margin,
              values: PdfMargin.values,
              onChanged: (v) => setState(
                  () => _layoutOptions = _layoutOptions.copyWith(margin: v)),
            ),
            _buildDropdownRow<PdfFontSize>(
              label: '字号',
              value: o.fontSize,
              values: PdfFontSize.values,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(fontSize: v)),
            ),
            const Divider(height: 24),
            _buildSwitchRow(
              label: '含封面',
              value: o.includeCover,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(includeCover: v)),
            ),
            _buildSwitchRow(
              label: '含目录',
              value: o.includeToc,
              onChanged: (v) => setState(
                  () => _layoutOptions = _layoutOptions.copyWith(includeToc: v)),
            ),
            _buildSwitchRow(
              label: '含页眉',
              value: o.includeHeader,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(includeHeader: v)),
            ),
            _buildSwitchRow(
              label: '含页脚（含页码）',
              value: o.includeFooter,
              onChanged: (v) => setState(() =>
                  _layoutOptions = _layoutOptions.copyWith(includeFooter: v)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required T value,
    required List<T> values,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: <DropdownMenuItem<T>>[
                for (final v in values)
                  DropdownMenuItem<T>(
                    value: v,
                    child: Text(_enumLabel(v)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _enumLabel<T>(T value) {
    if (value is PdfPageSize) return value.label;
    if (value is PdfOrientation) return value.label;
    if (value is PdfMargin) return value.label;
    if (value is PdfFontSize) return value.label;
    return value.toString();
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: value,
      onChanged: onChanged,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 预览区
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildPreviewSection(BuildContext context, bool showPreview) {
    return _Section(
      title: '预览',
      description: '仅 HTML 格式可用：先在 WebView 中预览，再决定是否导出',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FilledButton.tonalIcon(
          onPressed: showPreview && _exportOptions != null
              ? () => _previewHtml(context)
              : null,
          icon: const Icon(CupertinoIcons.eye),
          label: const Text('预览 HTML'),
        ),
      ),
    );
  }

  Future<void> _previewHtml(BuildContext context) async {
    final options = _exportOptions;
    if (options == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HtmlPreviewScreen(
          questions: options.filtered,
          mode: options.mode,
          studentInfo: options.studentInfo,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 导出按钮区（底部 sticky）
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildExportBar(BuildContext context) {
    final canExport =
        _selectedFormats.isNotEmpty && !_isExporting && _exportOptions != null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
        child: FilledButton.icon(
          onPressed: canExport ? () => _startExport(context) : null,
          icon: _isExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(CupertinoIcons.arrow_up_doc),
          label: Text(_isExporting
              ? '正在导出 ${(_exportProgress * 100).round()}%'
              : '导出（${_selectedFormats.length} 种格式）'),
        ),
      ),
    );
  }

  Future<void> _startExport(BuildContext context) async {
    final options = _exportOptions;
    if (options == null) return;
    if (_selectedFormats.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一种导出格式')),
      );
      return;
    }
    final questions = options.filtered;
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前筛选下没有可导出的题目')),
      );
      return;
    }

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
    });

    final progress = ValueNotifier<double>(0);
    if (!mounted) return;
    // 在 async gap 之前捕获 messenger / navigator，避免
    // use_build_context_synchronously 警告。
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
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
                  if (v <= 0) return const Text('正在准备导出…');
                  if (v >= 1) return const Text('导出完成');
                  final formats = _selectedFormats.toList();
                  if (formats.isEmpty) return const Text('正在导出…');
                  final idx =
                      (v * formats.length).floor().clamp(0, formats.length - 1);
                  final label = _formatLabel(formats[idx]);
                  return Text('正在导出 $label（${(v * 100).round()}%）');
                },
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final formats = _selectedFormats.toList();
      for (var i = 0; i < formats.length; i++) {
        progress.value = i / formats.length;
        if (mounted) setState(() => _exportProgress = progress.value);
        await _exportFormat(formats[i], options);
      }
      progress.value = 1;
      if (mounted) setState(() => _exportProgress = 1);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        navigator.pop();
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportFormat(
    ExportFormat format,
    ExportOptions options,
  ) async {
    final questions = options.filtered;
    final mode = options.mode;
    final studentInfo = options.studentInfo;
    final watermark = studentInfo?.watermark;
    final contentOptions = options.contentOptions;
    switch (format) {
      case ExportFormat.html:
        await HtmlExportService.shareHtml(
          context,
          questions,
          mode: mode,
          studentInfo: studentInfo,
          contentOptions: contentOptions,
          watermark: watermark,
        );
        break;
      case ExportFormat.pdf:
        await PdfExportService.sharePdf(
          context,
          questions,
          mode: mode,
          studentInfo: studentInfo,
          watermark: watermark,
        );
        break;
      case ExportFormat.markdown:
        final md = await MarkdownExportService().generateMarkdown(
          questions: questions,
          mode: mode,
          contentOptions: contentOptions,
          studentName: studentInfo?.name,
          className: studentInfo?.className,
        );
        await MarkdownExportService().shareMarkdown(md, _buildFileName('md'));
        break;
      case ExportFormat.anki:
        final ankiText = await AnkiExportService().generateAnkiImportText(
          questions: questions,
          contentOptions: contentOptions,
        );
        await AnkiExportService().shareAnkiExport(ankiText, _buildFileName('txt'));
        break;
      case ExportFormat.csv:
        final csv = await CsvExportService().generateCsv(questions: questions);
        await CsvExportService().shareCsv(csv, _buildFileName('csv'));
        break;
      case ExportFormat.json:
        final json = await JsonExportService().generateJson(
          questions: questions,
          includeReviewLogs: true,
        );
        await JsonExportService().shareJson(json, _buildFileName('json'));
        break;
    }
  }

  String _buildFileName(String extension) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return 'wrong-notebook-$stamp.$extension';
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 私有 UI 组件
// ─────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(description,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final ExportTemplateType template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor =
        selected ? colorScheme.primary : colorScheme.outlineVariant;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 168,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(template.icon,
                      size: 22,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant),
                  const Spacer(),
                  if (selected)
                    Icon(CupertinoIcons.checkmark_circle_fill,
                        size: 18, color: colorScheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Text(template.label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  template.description,
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBox extends StatelessWidget {
  const _SummaryBox({
    required this.icon,
    required this.text,
    this.title,
  });

  final IconData icon;
  final String text;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(title!,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                ],
                Text(text,
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


