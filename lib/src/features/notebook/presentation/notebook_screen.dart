import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_launcher.dart';
import 'package:smart_wrong_notebook/src/features/notebook/application/knowledge_point_practice_controller.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class NotebookScreen extends ConsumerStatefulWidget {
  const NotebookScreen({super.key});

  @override
  ConsumerState<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends ConsumerState<NotebookScreen> {
  final _searchController = TextEditingController();
  bool _buildingKnowledgePointPractice = false;
  bool _selectionMode = false;
  final Set<String> _selectedQuestionIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic question) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这道错题吗？'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ref.read(questionRepositoryProvider).delete(question.id);
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _startKnowledgePointPractice(
    BuildContext context,
    String knowledgePoint,
    List<QuestionRecord> questions,
  ) async {
    if (_buildingKnowledgePointPractice) return;
    setState(() => _buildingKnowledgePointPractice = true);
    try {
      final controller = KnowledgePointPracticeController(
        ref.read(aiAnalysisServiceProvider),
      );
      final prepared = await controller.buildRound(
        knowledgePoint: knowledgePoint,
        questions: questions,
      );
      await ref.read(questionRepositoryProvider).update(prepared);
      invalidateQuestionList(ref);
      ref.read(currentPracticeContextProvider.notifier).state =
          const PracticeContext(
        source: PracticeContextSource.notebook,
        returnRoute: '/notebook',
      );
      ref.read(currentQuestionProvider.notifier).state = prepared;
      if (!mounted) return;
      context.go('/exercise/practice');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('专项练习准备失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _buildingKnowledgePointPractice = false);
    }
  }

  void _applyMenuAction(WidgetRef ref, _NotebookMenuAction action) {
    switch (action) {
      case _NotebookMenuAction.dueOnly:
        final current = ref.read(dueOnlyFilterProvider);
        ref.read(dueOnlyFilterProvider.notifier).state = !current;
        break;
      case _NotebookMenuAction.favoritesOnly:
        final current = ref.read(favoritesOnlyFilterProvider);
        ref.read(favoritesOnlyFilterProvider.notifier).state = !current;
        break;
      case _NotebookMenuAction.failedOnly:
        final current = ref.read(failedOnlyFilterProvider);
        ref.read(failedOnlyFilterProvider.notifier).state = !current;
        break;
      case _NotebookMenuAction.allDates:
        ref.read(questionDateRangeProvider.notifier).state =
            QuestionDateRange.all;
        break;
      case _NotebookMenuAction.last7Days:
        ref.read(questionDateRangeProvider.notifier).state =
            QuestionDateRange.last7Days;
        break;
      case _NotebookMenuAction.last30Days:
        ref.read(questionDateRangeProvider.notifier).state =
            QuestionDateRange.last30Days;
        break;
      case _NotebookMenuAction.newest:
        ref.read(questionSortProvider.notifier).state = QuestionSort.newest;
        break;
      case _NotebookMenuAction.oldest:
        ref.read(questionSortProvider.notifier).state = QuestionSort.oldest;
        break;
      case _NotebookMenuAction.nextReview:
        ref.read(questionSortProvider.notifier).state = QuestionSort.nextReview;
        break;
    }
  }

  void _toggleSelection(String questionId) {
    setState(() {
      if (!_selectedQuestionIds.add(questionId)) {
        _selectedQuestionIds.remove(questionId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedQuestionIds.clear();
    });
  }

  void _openWorksheet(BuildContext context, WidgetRef ref) {
    if (_selectedQuestionIds.isEmpty) return;
    ref.read(worksheetDraftQuestionIdsProvider.notifier).state =
        _selectedQuestionIds.toList();
    _exitSelectionMode();
    context.go('/worksheet');
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref) async {
    if (_selectedQuestionIds.isEmpty) return;
    final count = _selectedQuestionIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除已选错题？'),
        content: Text('将永久删除 $count 道错题及其本地图片，无法恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final repository = ref.read(questionRepositoryProvider);
    for (final id in _selectedQuestionIds) {
      await repository.delete(id);
    }
    invalidateQuestionList(ref);
    if (mounted) _exitSelectionMode();
  }
  void _clearFilters(WidgetRef ref) {
    ref.read(selectedSubjectFilterProvider.notifier).state = null;
    ref.read(selectedMasteryFilterProvider.notifier).state = null;
    ref.read(unmasteredOnlyFilterProvider.notifier).state = false;
    ref.read(selectedMistakeCategoryFilterProvider.notifier).state = null;
    ref.read(selectedKnowledgePointFilterProvider.notifier).state = null;
    ref.read(selectedTagsFilterProvider.notifier).state = const <String>[];
    ref.read(dueOnlyFilterProvider.notifier).state = false;
    ref.read(favoritesOnlyFilterProvider.notifier).state = false;
    ref.read(failedOnlyFilterProvider.notifier).state = false;
    ref.read(questionDateRangeProvider.notifier).state = QuestionDateRange.all;
    ref.read(selectedSourceFilterProvider.notifier).state = null;
    ref.read(selectedLearningStageFilterProvider.notifier).state = null;
    ref.read(selectedDifficultyFilterProvider.notifier).state = null;
    ref.read(selectedAttemptStatusFilterProvider.notifier).state = null;
    ref.read(questionSortProvider.notifier).state = QuestionSort.newest;
  }

  _CardPrimaryAction? _cardPrimaryAction(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    if (question.contentStatus == ContentStatus.failed) {
      return _CardPrimaryAction(label: '重新分析', icon: CupertinoIcons.arrow_clockwise, onTap: () {
        ref.read(currentQuestionProvider.notifier).state = question;
        context.go('/notebook/question/${question.id}');
      });
    }
    if (question.analysisResult == null) {
      return _CardPrimaryAction(label: '继续校对', icon: CupertinoIcons.pencil, onTap: () {
        ref.read(currentQuestionProvider.notifier).state = question;
        context.go('/notebook/question/${question.id}');
      });
    }
    final due = question.nextReviewAt != null && !question.nextReviewAt!.isAfter(DateTime.now());
    if (due) return _CardPrimaryAction(label: '开始复习', icon: CupertinoIcons.play_fill, onTap: () => context.go('/review'));
    if (question.masteryLevel == MasteryLevel.newQuestion) {
      return _CardPrimaryAction(label: '开始练习', icon: CupertinoIcons.pencil_ellipsis_rectangle, onTap: () {
        ref.read(currentQuestionProvider.notifier).state = question;
        context.go('/notebook/question/${question.id}');
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final questionsAsync = ref.watch(filteredQuestionListProvider);
    final selectedSubject = ref.watch(selectedSubjectFilterProvider);
    final selectedMastery = ref.watch(selectedMasteryFilterProvider);
    final unmasteredOnly = ref.watch(unmasteredOnlyFilterProvider);
    final selectedMistakeCategory =
        ref.watch(selectedMistakeCategoryFilterProvider);
    final selectedTags = ref.watch(selectedTagsFilterProvider);
    final dueOnly = ref.watch(dueOnlyFilterProvider);
    final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
    final failedOnly = ref.watch(failedOnlyFilterProvider);
    final dateRange = ref.watch(questionDateRangeProvider);
    final selectedSource = ref.watch(selectedSourceFilterProvider);
    final sources = ref.watch(allSourcesProvider).valueOrNull ?? const <String>[];
    final stages = ref.watch(allLearningStagesProvider).valueOrNull ?? const <String>[];
    final selectedStage = ref.watch(selectedLearningStageFilterProvider);
    final selectedDifficulty = ref.watch(selectedDifficultyFilterProvider);
    final selectedAttemptStatus = ref.watch(selectedAttemptStatusFilterProvider);
    final sort = ref.watch(questionSortProvider);
    final selectedKnowledgePoint =
        ref.watch(selectedKnowledgePointFilterProvider);
    final activeFilterLabels = <String>[
      if (selectedSubject != null) selectedSubject.label,
      if (selectedMastery != null) _masteryFilterLabel(selectedMastery),
      if (unmasteredOnly) '未掌握',
      if (selectedMistakeCategory != null) selectedMistakeCategory.label,
      if (selectedKnowledgePoint != null) selectedKnowledgePoint,
      if (selectedTags.isNotEmpty) ...selectedTags,
      if (dueOnly) '待复习',
      if (favoritesOnly) '收藏',
      if (failedOnly) '待处理',
      if (dateRange == QuestionDateRange.last7Days) '近 7 天',
      if (dateRange == QuestionDateRange.last30Days) '近 30 天',
      if (selectedSource != null) '来源：$selectedSource',
      if (selectedStage != null) '年级：$selectedStage',
      if (selectedDifficulty != null) _difficultyFilterLabel(selectedDifficulty),
      if (selectedAttemptStatus != null) _attemptFilterLabel(selectedAttemptStatus),
      if (sort != QuestionSort.newest) _sortFilterLabel(sort),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selectedQuestionIds.length} 道' : '错题本'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(CupertinoIcons.xmark),
                tooltip: '取消选择',
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: _selectionMode
            ? <Widget>[
                IconButton(
                  icon: const Icon(CupertinoIcons.checkmark_square),
                  tooltip: '全选当前列表',
                  onPressed: () {
                    final items = questionsAsync.valueOrNull ?? const <QuestionRecord>[];
                    setState(() => _selectedQuestionIds.addAll(items.map((item) => item.id)));
                  },
                ),
              ]
            : <Widget>[
                IconButton(
                  icon: const Icon(CupertinoIcons.checkmark_square),
                  tooltip: '选择错题',
                  onPressed: () => setState(() => _selectionMode = true),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.camera),
                  onPressed: () => CaptureEntryLauncher.show(context),
                  tooltip: '录入错题',
                ),
                PopupMenuButton<_NotebookMenuAction>(
                  icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
                  tooltip: '筛选与排序',
                  onSelected: (action) => _applyMenuAction(ref, action),
                  itemBuilder: (_) => <PopupMenuEntry<_NotebookMenuAction>>[
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.dueOnly, checked: dueOnly, child: const Text('仅看待复习')),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.favoritesOnly, checked: favoritesOnly, child: const Text('仅看收藏')),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.failedOnly, checked: failedOnly, child: const Text('仅看待处理草稿')),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.last7Days, checked: dateRange == QuestionDateRange.last7Days, child: const Text('近 7 天录入')),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.last30Days, checked: dateRange == QuestionDateRange.last30Days, child: const Text('近 30 天录入')),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.allDates, checked: dateRange == QuestionDateRange.all, child: const Text('不限录入日期')),
                    const PopupMenuDivider(),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.newest, checked: sort == QuestionSort.newest, child: const Text('按最新录入')),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.oldest, checked: sort == QuestionSort.oldest, child: const Text('按最早录入')),
                    CheckedPopupMenuItem<_NotebookMenuAction>(value: _NotebookMenuAction.nextReview, checked: sort == QuestionSort.nextReview, child: const Text('按下次复习')),
                  ],
                ),
              ],
      ),
      body: Column(
        children: <Widget>[
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索错题',
                prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(CupertinoIcons.xmark_circle, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Theme.of(context).colorScheme.primary),
                ),
              ),
              onChanged: (v) {
                ref.read(searchQueryProvider.notifier).state = v;
                setState(() {});
              },
            ),
          ),
          // 高频筛选保留在首屏；低频条件收纳到高级筛选面板。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: <Widget>[
                _Chip(
                  label: '全部',
                  selected: activeFilterLabels.isEmpty,
                  onTap: () => _clearFilters(ref),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '待复习',
                  selected: dueOnly,
                  onTap: () => ref.read(dueOnlyFilterProvider.notifier).state = !dueOnly,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '未掌握',
                  selected: unmasteredOnly,
                  onTap: () => ref.read(unmasteredOnlyFilterProvider.notifier).state = !unmasteredOnly,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '收藏',
                  selected: favoritesOnly,
                  onTap: () => ref.read(favoritesOnlyFilterProvider.notifier).state = !favoritesOnly,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '筛选',
                  selected: activeFilterLabels.any((label) =>
                      label != '待复习' && label != '未掌握' && label != '收藏'),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => _AdvancedFilterSheet(
                      sources: sources,
                      stages: stages,
                      onClear: () => _clearFilters(ref),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (activeFilterLabels.isNotEmpty)
            _ActiveFilterSummary(
              labels: activeFilterLabels,
              onClear: () => _clearFilters(ref),
            ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: questionsAsync.when(
              data: (questions) {
                if (questions.isEmpty) {
                  return AppEmptyState(
                    icon: CupertinoIcons.question,
                    title: '还没有错题',
                    description: '拍照录入一道错题，或导入整页试卷开始整理。',
                    action: FilledButton.icon(
                      onPressed: () => CaptureEntryLauncher.show(context),
                      icon: const Icon(CupertinoIcons.add),
                      label: const Text('录入错题'),
                    ),
                  );
                }
                final hasPracticeAction =
                    selectedKnowledgePoint != null && questions.isNotEmpty;
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(questionListProvider);
                  },
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    itemCount:
                        questions.length + (hasPracticeAction ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasPracticeAction && index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _KnowledgePointPracticeCard(
                            knowledgePoint: selectedKnowledgePoint!,
                            isLoading: _buildingKnowledgePointPractice,
                            onStart: () => _startKnowledgePointPractice(
                              context,
                              selectedKnowledgePoint!,
                              questions,
                            ),
                          ),
                        );
                      }
                      final questionIndex = index - (hasPracticeAction ? 1 : 0);
                      final q = questions[questionIndex];
                      return RepaintBoundary(
                        child: _QuestionCard(
                          question: q,
                          selectionMode: _selectionMode,
                          selected: _selectedQuestionIds.contains(q.id),
                          onSelect: () => _toggleSelection(q.id),
                          onTap: () {
                            ref.read(currentQuestionProvider.notifier).state =
                                q;
                            context.go('/notebook/question/${q.id}');
                          },
                          onDelete: () => _confirmDelete(context, ref, q),
                          onKnowledgePointTap: (kp) {
                            ref
                                .read(selectedKnowledgePointFilterProvider
                                    .notifier)
                                .state = kp;
                          },
                          primaryAction: _selectionMode
                              ? null
                              : _cardPrimaryAction(context, ref, q),
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const AppLoadingState(label: '正在整理错题本…'),
              error: (_, __) => AppErrorState(onRetry: () => ref.invalidate(questionListProvider)),
            ),
          ),
          if (_selectionMode)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Row(children: <Widget>[
                  Expanded(child: OutlinedButton.icon(onPressed: _selectedQuestionIds.isEmpty ? null : () => _deleteSelected(context, ref), icon: const Icon(CupertinoIcons.trash), label: const Text('删除'))),
                  const SizedBox(width: 12),
                  Expanded(child: FilledButton.icon(onPressed: _selectedQuestionIds.isEmpty ? null : () => _openWorksheet(context, ref), icon: const Icon(CupertinoIcons.doc_text), label: const Text('加入组卷'))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

enum _NotebookMenuAction {
  dueOnly,
  favoritesOnly,
  failedOnly,
  allDates,
  last7Days,
  last30Days,
  newest,
  oldest,
  nextReview,
}

class _CardPrimaryAction {
  const _CardPrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _KnowledgePointPracticeCard extends StatelessWidget {
  const _KnowledgePointPracticeCard({
    required this.knowledgePoint,
    required this.isLoading,
    required this.onStart,
  });

  final String knowledgePoint;
  final bool isLoading;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.play_circle,
              color: colorScheme.onPrimaryContainer, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('专项练习：$knowledgePoint',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer)),
                const SizedBox(height: 3),
                Text('聚合关联错题的已有练习；没有练习时自动请求 AI 生成。',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onPrimaryContainer)),
              ],
            ),
          ),
          isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(onPressed: onStart, child: const Text('开始')),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color:
                selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.selectionMode,
    required this.selected,
    required this.onSelect,
    required this.onTap,
    required this.onDelete,
    required this.onKnowledgePointTap,
    required this.primaryAction,
  });

  final dynamic question;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(String knowledgePoint) onKnowledgePointTap;
  final _CardPrimaryAction? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final masteryColor = _masteryColor(context, question.masteryLevel);
    final aiTags = question.aiTags ?? <String>[];
    final customTags = question.customTags ?? <String>[];
    final allTags = [...aiTags, ...customTags];

    return Dismissible(
      key: ValueKey(question.id),
      direction: selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color:
              isDark ? Colors.red.withValues(alpha: 0.14) : Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(CupertinoIcons.trash, color: Colors.red),
      ),
      child: Semantics(
        button: true,
        label:
            '错题: ${question.correctedText}，科目: ${question.subject.label}，状态: ${_masteryLabel(question.masteryLevel)}，日期: ${_formatDate(question.createdAt)}，左滑删除',
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: selectionMode ? onSelect : onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.12 : 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                children: <Widget>[
                  if (selectionMode) ...<Widget>[
                    Checkbox(value: selected, onChanged: (_) => onSelect()),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: question.subject.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Hero(
                      tag: 'subject_icon_${question.id}',
                      child: Icon(question.subject.icon,
                          size: 20, color: question.subject.color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Hero(
                          tag: 'question_text_${question.id}',
                          child: Material(
                            color: Colors.transparent,
                            child: MathContentView(
                              question.correctedText,
                              contentFormat: question.contentFormat,
                              mode: MathContentViewMode.compact,
                              maxLines: 1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500, fontSize: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Text(
                              '${question.subject.label} · ${_formatDate(question.createdAt)}',
                              style: TextStyle(
                                  fontSize: 12, color: question.subject.color),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: masteryColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _masteryLabel(question.masteryLevel),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: masteryColor,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (question.contentStatus.toString().split('.').last == 'failed') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEA580C)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('待处理',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF9A3412),
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ],
                        ),
                        Row(
                          children: <Widget>[
                            Icon(_dueIcon(question), size: 13, color: _dueColor(context, question)),
                            const SizedBox(width: 4),
                            Expanded(child: Text(_dueLabel(question), style: TextStyle(fontSize: 11, color: _dueColor(context, question), fontWeight: FontWeight.w600))),
                            Text('复习 ${question.reviewCount} 次', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        if (question.mistakeCategory != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Row(children: <Widget>[
                            const Icon(CupertinoIcons.exclamationmark_circle, size: 13, color: Color(0xFFEA580C)),
                            const SizedBox(width: 4),
                            Text('错因：${question.mistakeCategory.label}', style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412))),
                          ]),
                        ],
                        const SizedBox(height: 5),
                        if (_batchLabel(question) != null) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            _batchLabel(question)!,
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                        // AI 知识点标签（有颜色区分 AI 生成和手动）
                        if (allTags.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: allTags.take(5).map((tag) {
                              final isAiTag = aiTags.contains(tag);
                              final tagColor = isAiTag
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF4F46E5);
                              final tagBackground = isDark
                                  ? tagColor.withValues(alpha: 0.14)
                                  : isAiTag
                                      ? const Color(0xFFFFF7ED)
                                      : const Color(0xFFEEF2FF);
                              return GestureDetector(
                                onTap: () => onKnowledgePointTap(tag),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tagBackground,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isDark
                                          ? tagColor.withValues(alpha: 0.22)
                                          : colorScheme.outlineVariant
                                              .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: MathContentView(
                                    tag,
                                    mode: MathContentViewMode.compact,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? colorScheme.onSurface
                                          : tagColor,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        if (primaryAction != null) ...<Widget>[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: primaryAction!.onTap,
                              icon: Icon(primaryAction!.icon, size: 15),
                              label: Text(primaryAction!.label),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                      size: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _dueIcon(QuestionRecord question) => question.nextReviewAt == null
      ? CupertinoIcons.calendar_badge_plus
      : !question.nextReviewAt!.isAfter(DateTime.now())
          ? CupertinoIcons.bell_fill : CupertinoIcons.calendar;

  Color _dueColor(BuildContext context, QuestionRecord question) => question.nextReviewAt != null && !question.nextReviewAt!.isAfter(DateTime.now())
      ? const Color(0xFFEA580C) : Theme.of(context).colorScheme.onSurfaceVariant;

  String _dueLabel(QuestionRecord question) {
    final next = question.nextReviewAt;
    if (next == null) return '尚未安排复习';
    final today = DateTime.now();
    if (!next.isAfter(today)) return '今天待复习';
    final days = DateTime(next.year, next.month, next.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    return days == 1 ? '明天复习' : '$days 天后复习';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}月${date.day}日';
  }

  Color _masteryColor(BuildContext context, MasteryLevel level) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (level) {
      case MasteryLevel.newQuestion:
        return colorScheme.onSurfaceVariant;
      case MasteryLevel.reviewing:
        return const Color(0xFFD97706);
      case MasteryLevel.mastered:
        return const Color(0xFF16A34A);
    }
  }

  String _masteryLabel(MasteryLevel level) {
    switch (level) {
      case MasteryLevel.newQuestion:
        return '新增';
      case MasteryLevel.reviewing:
        return '复习中';
      case MasteryLevel.mastered:
        return '已掌握';
    }
  }

  String? _batchLabel(QuestionRecord question) {
    if (question.parentQuestionId == null && question.rootQuestionId == null) {
      return null;
    }
    final order = question.splitOrder;
    return order == null ? '来自同一拍照批次' : '来自同一拍照批次 · 第 $order 题';
  }
}

String _difficultyFilterLabel(QuestionDifficulty value) => switch (value) {
      QuestionDifficulty.foundation => '基础题',
      QuestionDifficulty.advanced => '提高题',
      QuestionDifficulty.challenge => '压轴题',
      QuestionDifficulty.custom => '自定义层级',
    };

String _attemptFilterLabel(AttemptStatus value) => switch (value) {
      AttemptStatus.notAttempted => '不会做',
      AttemptStatus.wrongAttempt => '做错了',
      AttemptStatus.incomplete => '未完成',
      AttemptStatus.unknown => '作答未判断',
    };

String _masteryFilterLabel(MasteryLevel value) => switch (value) {
      MasteryLevel.newQuestion => '新题',
      MasteryLevel.reviewing => '学习中',
      MasteryLevel.mastered => '已掌握',
    };

String _sortFilterLabel(QuestionSort value) => switch (value) {
      QuestionSort.newest => '最新录入',
      QuestionSort.oldest => '最早录入',
      QuestionSort.nextReview => '下次复习',
    };

class _AdvancedFilterSheet extends ConsumerWidget {
  const _AdvancedFilterSheet({
    required this.sources,
    required this.stages,
    required this.onClear,
  });

  final List<String> sources;
  final List<String> stages;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subject = ref.watch(selectedSubjectFilterProvider);
    final category = ref.watch(selectedMistakeCategoryFilterProvider);
    final knowledge = ref.watch(selectedKnowledgePointFilterProvider);
    final dateRange = ref.watch(questionDateRangeProvider);
    final source = ref.watch(selectedSourceFilterProvider);
    final stage = ref.watch(selectedLearningStageFilterProvider);
    final difficulty = ref.watch(selectedDifficultyFilterProvider);
    final attempt = ref.watch(selectedAttemptStatusFilterProvider);
    final failedOnly = ref.watch(failedOnlyFilterProvider);
    final sort = ref.watch(questionSortProvider);
    final points = ref.watch(allKnowledgePointsProvider).valueOrNull ?? const <String>[];

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: .78,
        minChildSize: .45,
        maxChildSize: .94,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: <Widget>[
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: <Widget>[Text('高级筛选', style: Theme.of(context).textTheme.titleLarge), const Spacer(), TextButton(onPressed: onClear, child: const Text('清除全部'))]),
            _FilterOptionGroup<Subject>(title: '科目', values: Subject.values, selected: subject, label: (value) => value.label, onChanged: (value) => ref.read(selectedSubjectFilterProvider.notifier).state = value),
            _FilterOptionGroup<MistakeCategory>(title: '错因', values: MistakeCategory.values, selected: category, label: (value) => value.label, onChanged: (value) => ref.read(selectedMistakeCategoryFilterProvider.notifier).state = value),
            if (points.isNotEmpty) _FilterOptionGroup<String>(title: '知识点', values: points, selected: knowledge, label: (value) => value, onChanged: (value) => ref.read(selectedKnowledgePointFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionDateRange>(title: '录入日期', values: const <QuestionDateRange>[QuestionDateRange.all, QuestionDateRange.last7Days, QuestionDateRange.last30Days], selected: dateRange, label: _dateRangeLabel, onChanged: (value) => ref.read(questionDateRangeProvider.notifier).state = value ?? QuestionDateRange.all),
            if (sources.isNotEmpty) _FilterOptionGroup<String>(title: '来源批次', values: sources, selected: source, label: (value) => value, onChanged: (value) => ref.read(selectedSourceFilterProvider.notifier).state = value),
            if (stages.isNotEmpty) _FilterOptionGroup<String>(title: '年级 / 学习阶段', values: stages, selected: stage, label: (value) => value, onChanged: (value) => ref.read(selectedLearningStageFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionDifficulty>(title: '难度', values: QuestionDifficulty.values, selected: difficulty, label: _difficultyFilterLabel, onChanged: (value) => ref.read(selectedDifficultyFilterProvider.notifier).state = value),
            _FilterOptionGroup<AttemptStatus>(title: '作答状态', values: AttemptStatus.values, selected: attempt, label: _attemptFilterLabel, onChanged: (value) => ref.read(selectedAttemptStatusFilterProvider.notifier).state = value),
            _FilterOptionGroup<QuestionSort>(title: '排序', values: QuestionSort.values, selected: sort, label: _sortFilterLabel, onChanged: (value) => ref.read(questionSortProvider.notifier).state = value ?? QuestionSort.newest),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅看待处理草稿'),
              value: failedOnly,
              onChanged: (value) => ref.read(failedOnlyFilterProvider.notifier).state = value,
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('完成'))),
          ],
        ),
      ),
    );
  }
}

class _FilterOptionGroup<T> extends StatelessWidget {
  const _FilterOptionGroup({required this.title, required this.values, required this.selected, required this.label, required this.onChanged});
  final String title;
  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: values.map((value) => ChoiceChip(label: Text(label(value)), selected: selected == value, onSelected: (_) => onChanged(selected == value ? null : value))).toList()),
    ]),
  );
}

String _dateRangeLabel(QuestionDateRange value) => switch (value) {
      QuestionDateRange.all => '不限',
      QuestionDateRange.last7Days => '近 7 天',
      QuestionDateRange.last30Days => '近 30 天',
    };

class _ActiveFilterSummary extends StatelessWidget {
  const _ActiveFilterSummary({required this.labels, required this.onClear});

  final List<String> labels;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.line_horizontal_3_decrease_circle,
              size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              labels.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}
