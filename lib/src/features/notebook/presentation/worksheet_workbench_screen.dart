import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(questionListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('组卷与打印'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.pop(),
        ),
      ),
      body: questionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('题库加载失败：$error')),
        data: (questions) {
          final filtered = questions.where((question) {
            final text = '${question.normalizedQuestionText} '
                '${question.subject.label} ${question.learningStage ?? ''} '
                '${question.source ?? ''}'.toLowerCase();
            return text.contains(_query.toLowerCase());
          }).toList();
          final selected = _selected(questions);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(CupertinoIcons.search),
                  hintText: '搜索题干、学科、来源或年级',
                  border: const OutlineInputBorder(),
                  suffixText: '已选 ${selected.length} 题',
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
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
                          : () => HtmlExportService.shareHtml(context, selected),
                      icon: const Icon(CupertinoIcons.printer),
                      label: const Text('可打印 HTML'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () => PdfExportService.sharePdf(context, selected),
                      icon: const Icon(CupertinoIcons.doc_text),
                      label: const Text('导出答案卷 PDF'),
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
