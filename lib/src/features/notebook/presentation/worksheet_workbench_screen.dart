import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_options_dialog.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:uuid/uuid.dart';

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
  QuestionDisplayStatus? _statusFilter;
  bool _showFilters = false;

  /// 最近一次从已选区移除的题目（用于撤销）。
  /// 仅保留单次移除；连续移除时只可撤销最后一次。
  QuestionRecord? _lastRemoved;
  int? _lastRemovedIndex;

  /// 当前正在编辑的草稿 ID（从历史加载或保存后生成）。
  String? _currentDraftId;
  String? _currentDraftName;

  List<QuestionRecord> _selected(List<QuestionRecord> all) {
    final byId = {for (final item in all) item.id: item};
    return _order.map((id) => byId[id]).whereType<QuestionRecord>().toList();
  }

  void _toggle(QuestionRecord question) {
    setState(() {
      if (_selectedIds.remove(question.id)) {
        final idx = _order.indexOf(question.id);
        if (idx >= 0) {
          _lastRemoved = question;
          _lastRemovedIndex = idx;
          _order.removeAt(idx);
        }
      } else {
        _selectedIds.add(question.id);
        _order.add(question.id);
        _lastRemoved = null;
      }
    });
  }

  void _undoLastRemove() {
    if (_lastRemoved == null || _lastRemovedIndex == null) return;
    setState(() {
      _order.insert(
          _lastRemovedIndex!.clamp(0, _order.length), _lastRemoved!.id);
      _selectedIds.add(_lastRemoved!.id);
      _lastRemoved = null;
      _lastRemovedIndex = null;
    });
  }

  void _clearFilters() {
    setState(() {
      _query = '';
      _statusFilter = null;
    });
  }

  /// 简易估算预计页数：按每页约 5 题粗略计算，用于工作台提示。
  /// 实际页数取决于 PDF 排版和题目长度，导出后会显示真实页数。
  int _estimatedPages(int questionCount) {
    if (questionCount <= 0) return 0;
    return (questionCount / 5).ceil();
  }

  Future<void> _saveAsDraft() async {
    if (_order.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择题目')),
      );
      return;
    }
    final name = await _showNameDialog();
    if (name == null || name.trim().isEmpty) return;

    final now = DateTime.now();
    final draft = WorksheetDraft(
      id: _currentDraftId ?? const Uuid().v4(),
      name: name.trim(),
      questionIds: List<String>.from(_order),
      createdAt: now,
      updatedAt: now,
    );
    await ref.read(worksheetDraftRepositoryProvider).save(draft);
    ref.invalidate(savedWorksheetDraftsProvider);
    setState(() {
      _currentDraftId = draft.id;
      _currentDraftName = draft.name;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存组卷「${draft.name}」')),
      );
    }
  }

  Future<String?> _showNameDialog({String? initialName}) {
    final controller = TextEditingController(text: initialName ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(initialName == null ? '保存组卷' : '重命名组卷'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '组卷名称',
            hintText: '例如：期中复习卷',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistory() async {
    final drafts = await ref.read(worksheetDraftRepositoryProvider).loadAll();
    if (!mounted) return;
    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无历史组卷')),
      );
      return;
    }
    final action = await showDialog<({WorksheetDraft draft, _DraftAction type})>(
      context: context,
      builder: (ctx) => _WorksheetHistoryDialog(drafts: drafts),
    );
    if (action == null) return;

    switch (action.type) {
      case _DraftAction.load:
        await _loadDraft(action.draft, copy: false);
      case _DraftAction.copy:
        await _loadDraft(action.draft, copy: true);
      case _DraftAction.delete:
        await ref.read(worksheetDraftRepositoryProvider).delete(action.draft.id);
        ref.invalidate(savedWorksheetDraftsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除「${action.draft.name}」')),
          );
        }
    }
  }

  Future<void> _loadDraft(WorksheetDraft draft, {required bool copy}) async {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(draft.questionIds);
      _order
        ..clear()
        ..addAll(draft.questionIds);
      _lastRemoved = null;
      _currentDraftId = copy ? null : draft.id;
      _currentDraftName = copy ? '${draft.name} 副本' : draft.name;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(copy
              ? '已复制「${draft.name}」，可继续编辑后另存'
              : '已加载「${draft.name}」'),
        ),
      );
    }
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
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.folder_open),
            tooltip: '历史组卷',
            onPressed: _openHistory,
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.floppy_disk),
            tooltip: '保存组卷',
            onPressed: _saveAsDraft,
          ),
        ],
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

          final readyCount = questions
              .where((q) => inferQuestionDisplayStatus(q) == QuestionDisplayStatus.analyzed)
              .length;
          final recognizedCount = questions
              .where((q) => inferQuestionDisplayStatus(q) == QuestionDisplayStatus.recognized)
              .length;
          final processingCount = questions
              .where((q) => inferQuestionDisplayStatus(q).isInProgress)
              .length;
          final failedCount = questions
              .where((q) => inferQuestionDisplayStatus(q).isFailed)
              .length;

          final filtered = questions.where((question) {
            final text = '${question.normalizedQuestionText} '
                '${question.subject.label} ${question.learningStage ?? ''} '
                '${question.source ?? ''}'.toLowerCase();
            final matchesQuery = text.contains(_query.toLowerCase());
            final matchesStatus = _statusFilter == null ||
                inferQuestionDisplayStatus(question) == _statusFilter;
            return matchesQuery && matchesStatus;
          }).toList();
          final selected = _selected(questions);

          final hasActiveFilters = _query.isNotEmpty || _statusFilter != null;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  if (_currentDraftName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: <Widget>[
                        const Icon(CupertinoIcons.bookmark_fill,
                            size: 14, color: AppColors.primaryDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '当前组卷：$_currentDraftName',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.primaryDark),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(CupertinoIcons.search),
                      hintText: '搜索题干、学科、来源或年级',
                      border: const OutlineInputBorder(),
                      suffixText:
                          '已选 ${selected.length} 题 · 预计 ${_estimatedPages(selected.length)} 页',
                      suffixIcon: hasActiveFilters
                          ? IconButton(
                              icon: const Icon(CupertinoIcons.xmark),
                              onPressed: _clearFilters,
                            )
                          : null,
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Text('筛选（共 ${questions.length} 题）',
                          style: Theme.of(context).textTheme.labelMedium),
                      const Spacer(),
                      if (_lastRemoved != null)
                        TextButton.icon(
                          icon: const Icon(CupertinoIcons.arrow_uturn_left,
                              size: 14),
                          label: const Text('撤销移除',
                              style: TextStyle(fontSize: 12)),
                          onPressed: _undoLastRemove,
                        )
                      else
                        TextButton(
                          onPressed: () =>
                              setState(() => _showFilters = !_showFilters),
                          child:
                              Text(_showFilters ? '收起筛选' : '展开筛选'),
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
                          onSelected: () =>
                              setState(() => _statusFilter = null),
                        ),
                        _FilterChip(
                          label: '已分析',
                          count: readyCount,
                          color: AppColors.success,
                          selected: _statusFilter == QuestionDisplayStatus.analyzed,
                          onSelected: () => setState(() =>
                              _statusFilter = QuestionDisplayStatus.analyzed),
                        ),
                        _FilterChip(
                          label: '待 AI',
                          count: recognizedCount,
                          color: AppColors.primary,
                          selected: _statusFilter == QuestionDisplayStatus.recognized,
                          onSelected: () => setState(() =>
                              _statusFilter = QuestionDisplayStatus.recognized),
                        ),
                        _FilterChip(
                          label: '处理中',
                          count: processingCount,
                          color: AppColors.warning,
                          selected: _statusFilter != null &&
                              _statusFilter!.isInProgress,
                          onSelected: () => setState(() =>
                              _statusFilter = QuestionDisplayStatus.recognizing),
                        ),
                        _FilterChip(
                          label: '失败',
                          count: failedCount,
                          color: AppColors.danger,
                          selected: _statusFilter != null &&
                              _statusFilter!.isFailed,
                          onSelected: () => setState(() =>
                              _statusFilter = QuestionDisplayStatus.recognitionFailed),
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
                      if (question.learningStage != null)
                        question.learningStage!,
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

/// 历史组卷操作类型。
enum _DraftAction { load, copy, delete }

class _WorksheetHistoryDialog extends StatelessWidget {
  const _WorksheetHistoryDialog({required this.drafts});
  final List<WorksheetDraft> drafts;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('历史组卷'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: drafts.length,
          itemBuilder: (context, index) {
            final draft = drafts[index];
            return ListTile(
              leading: const Icon(CupertinoIcons.doc_text),
              title: Text(draft.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${draft.questionIds.length} 题 · ${_formatDate(draft.updatedAt)}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: PopupMenuButton<_DraftAction>(
                icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
                onSelected: (action) =>
                    Navigator.pop(context, (draft: draft, type: action)),
                itemBuilder: (ctx) => const <PopupMenuEntry<_DraftAction>>[
                  PopupMenuItem(
                    value: _DraftAction.load,
                    child: Row(children: <Widget>[
                      Icon(CupertinoIcons.folder_open, size: 18),
                      SizedBox(width: 8),
                      Text('加载'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: _DraftAction.copy,
                    child: Row(children: <Widget>[
                      Icon(CupertinoIcons.doc_on_doc, size: 18),
                      SizedBox(width: 8),
                      Text('复制'),
                    ]),
                  ),
                  PopupMenuItem(
                    value: _DraftAction.delete,
                    child: Row(children: <Widget>[
                      Icon(CupertinoIcons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('删除', style: TextStyle(color: Colors.red)),
                    ]),
                  ),
                ],
              ),
              onTap: () => Navigator.pop(
                  context, (draft: draft, type: _DraftAction.load)),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
