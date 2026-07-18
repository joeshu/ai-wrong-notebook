import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';

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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentWorksheetImportProvider);
    final autoAnalyzing = ref.watch(worksheetAutoAnalyzeProvider);
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('试卷批量导入')),
        body: const Center(child: Text('未找到待导入的试卷页面')),
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
          onPressed: () {
            ref.read(currentWorksheetImportProvider.notifier).state = null;
            ref.read(worksheetAutoAnalyzeProvider.notifier).state = false;
            context.go('/');
          },
        ),
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
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(children: <Widget>[
                    const Icon(CupertinoIcons.clock, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('待分析 ${queuedQuestions.length} 道 · 已完成 $readyCount 道${failedCount > 0 ? ' · 失败 $failedCount 道（已保留草稿）' : ''}。')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: <Widget>[
                    TextButton(
                      onPressed: autoAnalyzing
                          ? null
                          : () => _startQueuedQuestion(queuedQuestions
                              .firstWhere((item) => item.contentStatus != ContentStatus.ready,
                                  orElse: () => queuedQuestions.first)),
                      child: Text(readyCount == queuedQuestions.length ? '查看结果' : '单题开始'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: autoAnalyzing || readyCount == queuedQuestions.length
                          ? null
                          : () => _startAllQueuedQuestions(queuedQuestions),
                      icon: Icon(autoAnalyzing
                          ? CupertinoIcons.pause_circle
                          : CupertinoIcons.play_circle),
                      label: Text(autoAnalyzing ? '正在自动处理' : '开始全部'),
                    ),
                    if (autoAnalyzing) ...<Widget>[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: '停止自动处理',
                        onPressed: () => ref.read(worksheetAutoAnalyzeProvider.notifier).state = false,
                        icon: const Icon(CupertinoIcons.stop_circle),
                      ),
                    ],
                  ]),
                ]),
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
