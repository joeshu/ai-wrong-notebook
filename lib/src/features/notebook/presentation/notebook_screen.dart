import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final questionsAsync = ref.watch(filteredQuestionListProvider);
    final selectedSubject = ref.watch(selectedSubjectFilterProvider);
    final selectedMastery = ref.watch(selectedMasteryFilterProvider);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题本'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.camera),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const CaptureEntrySheet(),
            ),
            tooltip: '添加错题',
          ),
          PopupMenuButton<_NotebookMenuAction>(
            icon: const Icon(CupertinoIcons.line_horizontal_3_decrease),
            tooltip: '筛选与排序',
            onSelected: (action) => _applyMenuAction(ref, action),
            itemBuilder: (_) => <PopupMenuEntry<_NotebookMenuAction>>[
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.dueOnly,
                checked: dueOnly,
                child: const Text('仅看待复习'),
              ),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.favoritesOnly,
                checked: favoritesOnly,
                child: const Text('仅看收藏'),
              ),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.failedOnly,
                checked: failedOnly,
                child: const Text('仅看待处理草稿'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.last7Days,
                checked: dateRange == QuestionDateRange.last7Days,
                child: const Text('近 7 天录入'),
              ),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.last30Days,
                checked: dateRange == QuestionDateRange.last30Days,
                child: const Text('近 30 天录入'),
              ),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.allDates,
                checked: dateRange == QuestionDateRange.all,
                child: const Text('不限录入日期'),
              ),
              const PopupMenuDivider(),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.newest,
                checked: sort == QuestionSort.newest,
                child: const Text('按最新录入'),
              ),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.oldest,
                checked: sort == QuestionSort.oldest,
                child: const Text('按最早录入'),
              ),
              CheckedPopupMenuItem<_NotebookMenuAction>(
                value: _NotebookMenuAction.nextReview,
                checked: sort == QuestionSort.nextReview,
                child: const Text('按下次复习'),
              ),
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
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: <Widget>[
                _Chip(
                  label: '全部',
                  selected: selectedSubject == null &&
                      selectedMastery == null &&
                      selectedMistakeCategory == null &&
                      selectedTags.isEmpty &&
                      !dueOnly &&
                      !favoritesOnly &&
                      !failedOnly &&
                      dateRange == QuestionDateRange.all &&
                      selectedSource == null &&
                      selectedStage == null &&
                      selectedDifficulty == null &&
                      selectedAttemptStatus == null &&
                      sort == QuestionSort.newest &&
                      selectedKnowledgePoint == null,
                  onTap: () {
                    ref.read(selectedSubjectFilterProvider.notifier).state =
                        null;
                    ref.read(selectedMasteryFilterProvider.notifier).state =
                        null;
                    ref
                        .read(selectedMistakeCategoryFilterProvider.notifier)
                        .state = null;
                    ref
                        .read(selectedKnowledgePointFilterProvider.notifier)
                        .state = null;
                    ref.read(selectedTagsFilterProvider.notifier).state = const <String>[];
                    ref.read(dueOnlyFilterProvider.notifier).state = false;
                    ref.read(favoritesOnlyFilterProvider.notifier).state = false;
                    ref.read(failedOnlyFilterProvider.notifier).state = false;
                    ref.read(questionDateRangeProvider.notifier).state =
                        QuestionDateRange.all;
                    ref.read(selectedSourceFilterProvider.notifier).state = null;
                    ref.read(selectedLearningStageFilterProvider.notifier).state = null;
                    ref.read(selectedDifficultyFilterProvider.notifier).state = null;
                    ref.read(selectedAttemptStatusFilterProvider.notifier).state = null;
                    ref.read(questionSortProvider.notifier).state =
                        QuestionSort.newest;
                  },
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '待复习',
                  selected: dueOnly,
                  onTap: () => ref.read(dueOnlyFilterProvider.notifier).state =
                      !dueOnly,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '收藏',
                  selected: favoritesOnly,
                  onTap: () => ref
                      .read(favoritesOnlyFilterProvider.notifier)
                      .state = !favoritesOnly,
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: '近7天',
                  selected: dateRange == QuestionDateRange.last7Days,
                  onTap: () => ref
                      .read(questionDateRangeProvider.notifier)
                      .state = dateRange == QuestionDateRange.last7Days
                      ? QuestionDateRange.all
                      : QuestionDateRange.last7Days,
                ),
                const SizedBox(width: 8),
                ...Subject.values.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: s.label,
                        selected: selectedSubject == s,
                        onTap: () {
                          ref
                              .read(selectedSubjectFilterProvider.notifier)
                              .state = selectedSubject == s ? null : s;
                        },
                      ),
                    )),
                ...MistakeCategory.values.map((category) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: category.label,
                        selected: selectedMistakeCategory == category,
                        onTap: () {
                          ref
                              .read(selectedMistakeCategoryFilterProvider
                                  .notifier)
                              .state = selectedMistakeCategory == category
                              ? null
                              : category;
                        },
                      ),
                    )),
                ...sources.map((source) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: '来源：$source',
                        selected: selectedSource == source,
                        onTap: () {
                          ref.read(selectedSourceFilterProvider.notifier).state =
                              selectedSource == source ? null : source;
                        },
                      ),
                    )),
                ...stages.map((stage) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: '年级：$stage',
                        selected: selectedStage == stage,
                        onTap: () => ref.read(selectedLearningStageFilterProvider.notifier).state =
                            selectedStage == stage ? null : stage,
                      ),
                    )),
                ...QuestionDifficulty.values.map((difficulty) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: _difficultyFilterLabel(difficulty),
                        selected: selectedDifficulty == difficulty,
                        onTap: () => ref.read(selectedDifficultyFilterProvider.notifier).state =
                            selectedDifficulty == difficulty ? null : difficulty,
                      ),
                    )),
                ...AttemptStatus.values.map((status) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: _attemptFilterLabel(status),
                        selected: selectedAttemptStatus == status,
                        onTap: () => ref.read(selectedAttemptStatusFilterProvider.notifier).state =
                            selectedAttemptStatus == status ? null : status,
                      ),
                    )),
                // AI 知识点过滤
                if (selectedKnowledgePoint != null) ...<Widget>[
                  const SizedBox(width: 8),
                  _Chip(
                    label: '📚 $selectedKnowledgePoint',
                    selected: true,
                    onTap: () {
                      ref
                          .read(selectedKnowledgePointFilterProvider.notifier)
                          .state = null;
                    },
                  ),
                ],
              ],
            ),
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
                    action: FilledButton.icon(onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const CaptureEntrySheet()), icon: const Icon(CupertinoIcons.camera), label: const Text('拍照录题')),
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
    required this.onTap,
    required this.onDelete,
    required this.onKnowledgePointTap,
  });

  final dynamic question;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final void Function(String knowledgePoint) onKnowledgePointTap;

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
      direction: DismissDirection.endToStart,
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
            onTap: onTap,
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
                          const SizedBox(height: 4),
                          Text(
                            _batchLabel(question)!,
                            style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant),
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
