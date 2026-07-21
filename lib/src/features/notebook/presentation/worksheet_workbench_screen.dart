import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_options_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';

import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';

/// Selects and orders a subset of the local question bank for export.
/// The next slice adds per-mode PDF layouts; this screen deliberately keeps
/// selection local and never uploads question data.
class WorksheetWorkbenchScreen extends ConsumerStatefulWidget {
  const WorksheetWorkbenchScreen({super.key});

  @override
  ConsumerState<WorksheetWorkbenchScreen> createState() =>
      _WorksheetWorkbenchScreenState();
}

class _WorksheetWorkbenchScreenState
    extends ConsumerState<WorksheetWorkbenchScreen> {
  final _selectedIds = <String>{};
  final _order = <String>[];
  String _query = '';
  bool _draftApplied = false;
  ContentStatus? _statusFilter;
  bool _showFilters = false;

  List<QuestionRecord> _selected(List<QuestionRecord> all) {
    final byId = {for (final item in all) item.id: item};
    return _order.map((id) => byId[id]).whereType<QuestionRecord>().toList();
  }

  void _toggle(QuestionRecord question) {
    setState(() {
      if (_selectedIds.remove(question.id)) {
        _order.remove(question.id);
      } else {
        _selectedIds.add(question.id);
        _order.add(question.id);
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _query = '';
      _statusFilter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    final draftIds = ref.watch(worksheetDraftQuestionIdsProvider);
    if (!_draftApplied) {
      _draftApplied = true;
      if (draftIds.isNotEmpty) {
        _selectedIds.addAll(draftIds);
        _order.addAll(draftIds);
        Future<void>.microtask(() {
          ref.read(worksheetDraftQuestionIdsProvider.notifier).state =
              const <String>[];
        });
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('组卷与打印'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.pop(),
        ),
      ),
      body: questionsAsync.when(
        loading: () => const AppListSkeleton(),
        error: (error, _) => AppErrorState(
          error: error,
          onRetry: () => ref.invalidate(questionListProvider),
        ),
        data: (questions) {
          if (questions.isEmpty) {
            return _EmptyWorkbenchState(onAdd: () => context.go('/'));
          }

          final readyCount = questions.where((q) => q.contentStatus == ContentStatus.ready).length;
          final processingCount = questions.where((q) => q.contentStatus == ContentStatus.processing).length;
          final failedCount = questions.where((q) => q.contentStatus == ContentStatus.failed).length;

          final filtered = questions.where((question) {
            final text = '${question.normalizedQuestionText} '
                '${question.subject.label} ${question.learningStage ?? ''} '
                '${question.source ?? ''}'.toLowerCase();
            final matchesQuery = text.contains(_query.toLowerCase());
            final matchesStatus = _statusFilter == null || question.contentStatus == _statusFilter;
            return matchesQuery && matchesStatus;
          }).toList();
          final selected = _selected(questions);

          final hasActiveFilters = _query.isNotEmpty || _statusFilter != null;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(CupertinoIcons.search),
                      hintText: '搜索题干、学科、来源或年级',
                      border: const OutlineInputBorder(),
                      suffixText: '已选 ${selected.length} 题',
                      suffixIcon: hasActiveFilters
                          ? IconButton(
                              icon: const Icon(CupertinoIcons.xmark),
                              onPressed: _clearFilters,
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text('筛选（共 ${questions.length} 题）', style: Theme.of(context).textTheme.labelMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _showFilters = !_showFilters),
                        child: Text(_showFilters ? '收起筛选' : '展开筛选'),
                      ),
                    ],
                  ),
                  if (_showFilters) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        _FilterChip(
                          label: '全部',
                          count: questions.length,
                          selected: _statusFilter == null,
                          onSelected: () => setState(() => _statusFilter = null),
                        ),
                        _FilterChip(
                          label: '已识别',
                          count: readyCount,
                          color: AppColors.success,
                          selected: _statusFilter == ContentStatus.ready,
                          onSelected: () => setState(() => _statusFilter = ContentStatus.ready),
                        ),
                        _FilterChip(
                          label: '分析中',
                          count: processingCount,
                          color: AppColors.warning,
                          selected: _statusFilter == ContentStatus.processing,
                          onSelected: () => setState(() => _statusFilter = ContentStatus.processing),
                        ),
                        _FilterChip(
                          label: '识别失败',
                          count: failedCount,
                          color: AppColors.danger,
                          selected: _statusFilter == ContentStatus.failed,
                          onSelected: () => setState(() => _statusFilter = ContentStatus.failed),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (selected.isNotEmpty)
              _SelectedStrip(
                questions: selected,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final id = _order.removeAt(oldIndex);
                    _order.insert(newIndex, id);
                  });
                },
                onRemove: _toggle,
              ),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final question = filtered[index];
                  final selected = _selectedIds.contains(question.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (_) => _toggle(question),
                    title: Text(question.normalizedQuestionText,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      question.subject.label,
                      if (question.learningStage != null) question.learningStage!,
                      if (question.source != null) question.source!,
                    ].join(' · ')),
                    secondary: CircleAvatar(child: Text('${index + 1}')),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () => _export(context, selected, isPdf: false),
                      icon: const Icon(CupertinoIcons.printer),
                      label: const Text('可打印 HTML'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () => _export(context, selected, isPdf: true),
                      icon: const Icon(CupertinoIcons.doc_text),
                      label: const Text('选择试卷 PDF'),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
  Future<void> _export(
    BuildContext context,
    List<QuestionRecord> questions, {
    required bool isPdf,
  }) async {
    final options = await showExportOptionsDialog(
      context,
      questions,
      allowFilter: false,
    );
    if (options == null || !context.mounted) return;
    if (isPdf) {
      await PdfExportService.sharePdf(
        context,
        options.filtered,
        mode: options.mode,
        studentInfo: options.studentInfo,
        layoutOptions: options.layoutOptions,
      );
    } else {
      await HtmlExportService.shareHtml(
        context,
        options.filtered,
        mode: options.mode,
        studentInfo: options.studentInfo,
        templateType: options.templateType,
        layoutOptions: options.layoutOptions,
      );
    }
  }
}

class _SelectedStrip extends StatelessWidget {
  const _SelectedStrip({
    required this.questions,
    required this.onReorder,
    required this.onRemove,
  });

  final List<QuestionRecord> questions;
  final ReorderCallback onReorder;
  final ValueChanged<QuestionRecord> onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 82,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: questions.length,
          onReorder: onReorder,
          itemBuilder: (context, index) {
            final question = questions[index];
            return Padding(
              key: ValueKey(question.id),
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                label: Text('${index + 1}. ${question.subject.label}'),
                onDeleted: () => onRemove(question),
              ),
            );
          },
        ),
      );
}


class _EmptyWorkbenchState extends StatelessWidget {
  const _EmptyWorkbenchState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const Icon(CupertinoIcons.doc_text_search, size: 64, color: Color(0xFF94A3B8)),
        const SizedBox(height: 16),
        const Text('还没有可组卷的错题', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        const Text('先从拍照录题或试卷批量导入添加错题，之后可以在这里筛选、排序并导出练习卷、答案卷和订正卷。', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B))),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(CupertinoIcons.camera), label: const Text('去添加错题')),
      ]),
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = selected ? Colors.white : (color ?? scheme.onSurface);
    final bgColor = selected ? (color ?? scheme.primary) : Colors.transparent;
    final borderColor = selected ? (color ?? scheme.primary) : scheme.outlineVariant;

    return ActionChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: TextStyle(fontSize: 12, color: textColor)),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontSize: 11, color: selected ? Colors.white : scheme.onSurfaceVariant)),
        ],
      ),
      backgroundColor: bgColor,
      side: BorderSide(color: borderColor),
      onPressed: onSelected,
    );
  }
}
