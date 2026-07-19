import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// Phase 1 worksheet importer: imports multiple pages and deliberately routes
/// them through the proven single-page crop/correct/analyse flow. This keeps
/// every page reviewable before any AI request is made.
class WorksheetImportScreen extends ConsumerStatefulWidget {
  const WorksheetImportScreen({super.key});

  @override
  ConsumerState<WorksheetImportScreen> createState() =>
      _WorksheetImportScreenState();
}

class _WorksheetImportScreenState extends ConsumerState<WorksheetImportScreen> {
  final Set<int> _selected = <int>{};
  bool _selectionInitialized = false;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      if (ref.read(currentWorksheetImportProvider) == null) {
        await restoreWorksheetImport(ref);
      }
      if (mounted) setState(() => _restoringSession = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentWorksheetImportProvider);
    final autoAnalyzing = ref.watch(worksheetAutoAnalyzeProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('试卷批量导入')),
        body: _restoringSession
            ? const AppLoadingState(label: '正在恢复导入批次…')
            : AppEmptyState(
                icon: CupertinoIcons.doc_on_clipboard,
                title: '没有待处理的试卷',
                description: '请从“拍照录题”中选择试卷批量导入，或返回首页重新开始。',
                action: FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(CupertinoIcons.house),
                  label: const Text('返回首页'),
                ),
              ),
      );
    }
    final pages = session.pages
        .where((page) => session.sourcePageIds.contains(page.id))
        .toList();
    final queuedQuestions = session.pages
        .where((page) => !session.sourcePageIds.contains(page.id))
        .toList();
    final readyCount = queuedQuestions
        .where((item) => item.contentStatus == ContentStatus.ready)
        .length;
    final ocrDraftCount = queuedQuestions
        .where((item) => item.contentStatus == ContentStatus.ready && item.analysisResult == null)
        .length;
    final failedCount = queuedQuestions
        .where((item) => item.contentStatus == ContentStatus.failed)
        .length;
    if (!_selectionInitialized && pages.isNotEmpty) {
      _selected.addAll(List<int>.generate(pages.length, (i) => i));
      _selectionInitialized = true;
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('试卷批量导入'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: autoAnalyzing ? null : _confirmCancelBatch,
        ),
        actions: <Widget>[
          if (queuedQuestions.isNotEmpty)
            TextButton(
              onPressed: autoAnalyzing ? null : _confirmCancelBatch,
              child: const Text('取消批次'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('第 1 步：确认导入页面',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 6),
                  Text('将逐页进入裁切、校对和 AI 分析流程。每页的题目仍可使用已有的文本拆分确认功能保存，避免自动切错题污染题库。',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ImportOverviewCard(
              pageCount: pages.length,
              selectedPageCount: _selected.length,
              questionCount: queuedQuestions.length,
              readyCount: readyCount,
              ocrDraftCount: ocrDraftCount,
              pendingCount: queuedQuestions.length - readyCount - failedCount,
              failedCount: failedCount,
            ),
            Row(
              children: <Widget>[
                Text('已选 ${_selected.length}/${pages.length} 页',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() =>
                      _selected.addAll(List<int>.generate(pages.length, (i) => i))),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...pages.asMap().entries.map((entry) => _PageTile(
                  page: entry.value,
                  index: entry.key,
                  selected: _selected.contains(entry.key),
                  onChanged: (value) => setState(() {
                    if (value) {
                      _selected.add(entry.key);
                    } else {
                      _selected.remove(entry.key);
                    }
                  }),
                  onTap: () => _startPage(entry.value),
                )),
            const SizedBox(height: 16),
            if (queuedQuestions.isNotEmpty)
              _QueueSummaryCard(
                questions: queuedQuestions,
                readyCount: readyCount,
                ocrDraftCount: ocrDraftCount,
                failedCount: failedCount,
                autoAnalyzing: autoAnalyzing,
                onStartOne: () => _startQueuedQuestion(queuedQuestions
                    .firstWhere((item) => item.contentStatus != ContentStatus.ready,
                        orElse: () => queuedQuestions.first)),
                onStartAll: () => _startAllQueuedQuestions(queuedQuestions),
                onStop: () => ref.read(worksheetAutoAnalyzeProvider.notifier).state = false,
                onSaveReady: () => _saveReadyQuestions(queuedQuestions),
                onRetryFailed: () => _retryFailedQuestions(queuedQuestions),
                onAnalyzeDrafts: () => _analyzeOcrDrafts(queuedQuestions),
                onOpen: _openQueuedQuestion,
              ),
            if (queuedQuestions.isNotEmpty) const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _startRegionEditor(pages),
              icon: const Icon(CupertinoIcons.square_on_square),
              label: Text('整页框选多题（${_selected.length} 页）'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _selected.isEmpty ? null : () => _startFirstSelected(pages),
              icon: const Icon(CupertinoIcons.crop),
              label: Text('开始处理已选页面 (${_selected.length})'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50)),
            ),
            const SizedBox(height: 8),
            Text('本切片先完成多页导入与逐页可控处理；图像级自动题框、批量后台队列将在后续切片接入。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelBatch() async {
    final session = ref.read(currentWorksheetImportProvider);
    if (session == null) {
      if (mounted) context.go('/');
      return;
    }
    final candidates = session.pages
        .where((item) => !session.sourcePageIds.contains(item.id))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消本次试卷导入？'),
        content: Text(candidates.isEmpty
            ? '将退出导入流程。原始试卷页面不会写入错题本。'
            : '将放弃 ${candidates.length} 道待确认题目，并清理本次裁切生成的临时题图。已经保存到错题本的题目不会受影响。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('继续导入')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('取消并清理')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final storage = ref.read(imageStorageServiceProvider);
    for (final candidate in candidates) {
      await storage.deleteImage(candidate.imagePath);
    }
    await persistWorksheetImport(ref, null);
    ref.read(worksheetAutoAnalyzeProvider.notifier).state = false;
    ref.read(currentQuestionProvider.notifier).state = null;
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _openQueuedQuestion(QuestionRecord question) async {
    if (question.contentStatus == ContentStatus.ready && question.analysisResult == null) {
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        final next = worksheet.pages.map((item) => item.id == question.id
            ? item.copyWith(contentStatus: ContentStatus.processing) : item).toList();
        await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
        question = next.firstWhere((item) => item.id == question.id);
      }
      ref.read(currentQuestionProvider.notifier).state = question;
      if (mounted) context.go('/analysis/loading');
      return;
    }
    ref.read(currentQuestionProvider.notifier).state = question;
    context.go(question.contentStatus == ContentStatus.ready
        ? '/analysis/result'
        : '/analysis/loading');
  }

  Future<void> _saveReadyQuestions(List<QuestionRecord> queuedQuestions) async {
    final ready = queuedQuestions
        .where((item) => item.contentStatus == ContentStatus.ready)
        .toList();
    if (ready.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(questionRepositoryProvider).saveDrafts(ready);
      invalidateQuestionList(ref);
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        await persistWorksheetImport(
          ref,
          worksheet.copyWith(pages: worksheet.pages
              .where((page) => !ready.any((item) => item.id == page.id))
              .toList()),
        );
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('已批量保存 ${ready.length} 道题到错题本')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('批量保存失败: $e')));
    }
  }

  Future<void> _retryFailedQuestions(List<QuestionRecord> queuedQuestions) async {
    final failed = queuedQuestions.where((item) => item.contentStatus == ContentStatus.failed).toList();
    if (failed.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('重试 ${failed.length} 道失败题？'),
        content: const Text('会保留当前裁切题图与人工校对文字，仅重新调用普通 AI 分析，不会重新 OCR 或裁切。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('开始重试')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null) return;
    final ids = failed.map((item) => item.id).toSet();
    final next = worksheet.pages.map((item) => ids.contains(item.id)
        ? item.copyWith(contentStatus: ContentStatus.processing) : item).toList();
    await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
    final first = next.firstWhere((item) => item.id == failed.first.id);
    ref.read(currentQuestionProvider.notifier).state = first;
    ref.read(worksheetAutoAnalyzeProvider.notifier).state = true;
    if (mounted) context.go('/analysis/loading');
  }

  Future<void> _analyzeOcrDrafts(List<QuestionRecord> queuedQuestions) async {
    final drafts = queuedQuestions.where((item) =>
        item.contentStatus == ContentStatus.ready && item.analysisResult == null).toList();
    if (drafts.isEmpty) return;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null) {
      final ids = drafts.map((item) => item.id).toSet();
      final next = worksheet.pages.map((item) => ids.contains(item.id)
          ? item.copyWith(contentStatus: ContentStatus.processing)
          : item).toList();
      await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
      final first = next.firstWhere((item) => item.id == drafts.first.id);
      ref.read(currentQuestionProvider.notifier).state = first;
      ref.read(worksheetAutoAnalyzeProvider.notifier).state = true;
      if (mounted) context.go('/analysis/loading');
    }
  }

  void _startAllQueuedQuestions(List<QuestionRecord> queuedQuestions) {
    final next = queuedQuestions.firstWhere(
      (item) => item.contentStatus != ContentStatus.ready &&
          item.contentStatus != ContentStatus.failed,
      orElse: () => queuedQuestions.firstWhere(
        (item) => item.contentStatus != ContentStatus.ready,
        orElse: () => queuedQuestions.first,
      ),
    );
    ref.read(worksheetAutoAnalyzeProvider.notifier).state = true;
    _startQueuedQuestion(next);
  }

  void _startQueuedQuestion(QuestionRecord question) {
    ref.read(currentQuestionProvider.notifier).state = question;
    context.go('/analysis/loading');
  }

  void _startRegionEditor(List<QuestionRecord> pages) {
    if (_selected.isEmpty) return;
    final index = _selected.reduce((a, b) => a < b ? a : b);
    ref.read(currentQuestionProvider.notifier).state = pages[index];
    context.go('/worksheet/regions');
  }

  void _startFirstSelected(List<QuestionRecord> pages) {
    final index = _selected.reduce((a, b) => a < b ? a : b);
    _startPage(pages[index]);
  }

  void _startPage(QuestionRecord page) {
    ref.read(currentQuestionProvider.notifier).state = page;
    context.go('/capture/crop');
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.page,
    required this.index,
    required this.selected,
    required this.onChanged,
    required this.onTap,
  });

  final QuestionRecord page;
  final int index;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = page.imagePath.isNotEmpty && File(page.imagePath).existsSync();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? const Color(0xFF0F766E) : scheme.outlineVariant),
          ),
          child: Row(children: <Widget>[
            Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 88,
                child: available
                    ? Image.file(File(page.imagePath), fit: BoxFit.cover)
                    : const ColoredBox(color: Color(0xFFE5E7EB)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('第 ${index + 1} 页', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(available ? '点击进入裁切和校对' : '原图不可用',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            )),
            const Icon(CupertinoIcons.chevron_right, size: 18),
          ]),
        ),
      ),
    );
  }
}


class _QueueSummaryCard extends StatelessWidget {
  const _QueueSummaryCard({
    required this.questions,
    required this.readyCount,
    required this.ocrDraftCount,
    required this.failedCount,
    required this.autoAnalyzing,
    required this.onStartOne,
    required this.onStartAll,
    required this.onStop,
    required this.onSaveReady,
    required this.onRetryFailed,
    required this.onAnalyzeDrafts,
    required this.onOpen,
  });

  final List<QuestionRecord> questions;
  final int readyCount;
  final int ocrDraftCount;
  final int failedCount;
  final bool autoAnalyzing;
  final VoidCallback onStartOne;
  final VoidCallback onStartAll;
  final VoidCallback onStop;
  final VoidCallback onSaveReady;
  final VoidCallback onRetryFailed;
  final VoidCallback onAnalyzeDrafts;
  final ValueChanged<QuestionRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final pending = questions.length - readyCount - failedCount;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Icon(CupertinoIcons.clock, color: Color(0xFF4F46E5)),
          const SizedBox(width: 10),
          Expanded(child: Text('题目队列 ${questions.length} 道 · 已分析 $readyCount 道${failedCount > 0 ? ' · 失败 $failedCount 道' : ''}${pending > 0 ? ' · 待处理 $pending 道' : ''}。')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          TextButton(
            onPressed: autoAnalyzing || pending == 0 ? null : onStartOne,
            child: const Text('单题开始'),
          ),
          FilledButton.tonalIcon(
            onPressed: autoAnalyzing || pending == 0 ? null : onStartAll,
            icon: Icon(autoAnalyzing ? CupertinoIcons.pause_circle : CupertinoIcons.play_circle),
            label: Text(autoAnalyzing ? '正在自动处理' : '开始全部'),
          ),
          if (autoAnalyzing)
            IconButton(
              tooltip: '停止自动处理',
              onPressed: onStop,
              icon: const Icon(CupertinoIcons.stop_circle),
            ),
          if (failedCount > 0)
            OutlinedButton.icon(
              onPressed: autoAnalyzing ? null : onRetryFailed,
              icon: const Icon(CupertinoIcons.arrow_clockwise, size: 16),
              label: Text('重试失败题 ($failedCount)'),
            ),
          if (ocrDraftCount > 0)
            OutlinedButton.icon(
              onPressed: autoAnalyzing ? null : onAnalyzeDrafts,
              icon: const Icon(CupertinoIcons.sparkles, size: 16),
              label: Text('分析 OCR 草稿 ($ocrDraftCount)'),
            ),
          if (readyCount > 0)
            FilledButton.icon(
              onPressed: onSaveReady,
              icon: const Icon(CupertinoIcons.tray_arrow_down, size: 16),
              label: Text('保存已分析题目 ($readyCount)'),
            ),
        ]),
        if (questions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          const Text('本批结果', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...questions.asMap().entries.map((entry) => _QueueQuestionTile(
                index: entry.key,
                question: entry.value,
                onOpen: () => onOpen(entry.value),
              )),
        ],
      ]),
    );
  }
}

class _QueueQuestionTile extends StatelessWidget {
  const _QueueQuestionTile({required this.index, required this.question, required this.onOpen});
  final int index;
  final QuestionRecord question;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = question.contentStatus;
    final isOcrDraft = status == ContentStatus.ready && question.analysisResult == null;
    final color = isOcrDraft
        ? const Color(0xFF2563EB)
        : status == ContentStatus.ready
        ? const Color(0xFF16A34A)
        : status == ContentStatus.failed
            ? const Color(0xFFEA580C)
            : const Color(0xFF64748B);
    final label = isOcrDraft
        ? 'OCR 草稿'
        : status == ContentStatus.ready
        ? '已分析'
        : status == ContentStatus.failed
            ? '待处理'
            : '待分析';
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: <Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
            child: Text('${index + 1}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(question.correctedText.trim().isEmpty ? '题图待识别' : question.correctedText.trim(),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
          const Icon(CupertinoIcons.chevron_right, size: 14),
        ]),
      ),
    );
  }
}


class _ImportOverviewCard extends StatelessWidget {
  const _ImportOverviewCard({required this.pageCount, required this.selectedPageCount, required this.questionCount, required this.readyCount, required this.ocrDraftCount, required this.pendingCount, required this.failedCount});
  final int pageCount;
  final int selectedPageCount;
  final int questionCount;
  final int readyCount;
  final int ocrDraftCount;
  final int pendingCount;
  final int failedCount;

  @override
  Widget build(BuildContext context) {
    final analyzedCount = readyCount - ocrDraftCount;
    final total = analyzedCount + ocrDraftCount + pendingCount + failedCount;
    return Card(
      margin: EdgeInsets.zero,
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            const Icon(CupertinoIcons.chart_bar_square, color: Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            Expanded(child: Text('本次导入总览 · $pageCount 页 / $questionCount 道题', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('已选 $selectedPageCount 页', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 4, runSpacing: 8, children: <Widget>[
            SizedBox(width: 76, child: _OverviewMetric(label: '已分析', value: analyzedCount, color: const Color(0xFF16A34A))),
            SizedBox(width: 76, child: _OverviewMetric(label: 'OCR 草稿', value: ocrDraftCount, color: const Color(0xFF2563EB))),
            SizedBox(width: 76, child: _OverviewMetric(label: '待处理', value: pendingCount, color: const Color(0xFF64748B))),
            SizedBox(width: 76, child: _OverviewMetric(label: '失败/重试', value: failedCount, color: const Color(0xFFEA580C))),
          ]),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: analyzedCount / total, minHeight: 7, backgroundColor: const Color(0xFFE2E8F0), color: const Color(0xFF16A34A))),
          ] else
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('确认题框后，题目会出现在这里并显示分析进度。', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),),
        ]),
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
    Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: const TextStyle(fontSize: 11)),
  ]);
}
