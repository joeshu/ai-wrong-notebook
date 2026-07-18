import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/stats_chart.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionListProvider);
    final todayPlanAsync = ref.watch(todayReviewPlanProvider);
    final mistakeStatsAsync = ref.watch(mistakeCategoryStatsProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('今天，开始学习',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('先完成计划，再记录新的错题',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
              Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const CaptureEntrySheet(),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(CupertinoIcons.camera),
                  ),
                ),
              ),
            ],
          ),
          todayPlanAsync.when(
            data: (plan) => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _TodayPlanCard(
                plan: plan,
                onOpenReview: () => context.go('/review'),
                onCapture: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const CaptureEntrySheet(),
                ),
              ),
            ),
            loading: () => const SizedBox(height: 156),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          Text('学习统计', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          RepaintBoundary(
            child: questionsAsync.when(
              data: (questions) => _buildStatsSection(context, questions),
              loading: () => const _StatsGridSkeleton(),
              error: (e, _) => Text('加载失败: $e'),
            ),
          ),
          mistakeStatsAsync.when(
            data: (stats) => stats.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _MistakeCategorySummary(
                      stats: stats,
                      onSelect: (category) {
                        ref
                            .read(selectedMistakeCategoryFilterProvider.notifier)
                            .state = category;
                        context.go('/notebook');
                      },
                    ),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('最近新增', style: Theme.of(context).textTheme.titleLarge),
              TextButton(
                onPressed: () => context.go('/notebook'),
                child: const Text('查看全部'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          questionsAsync.when(
            data: (questions) =>
                _RecentList(questions: questions.take(5).toList(), ref: ref),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('加载失败: $e'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(
      BuildContext context, List<QuestionRecord> questions) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = questions.length;
    final mastered =
        questions.where((q) => q.masteryLevel == MasteryLevel.mastered).length;
    final pending = total - mastered;
    final now = DateTime.now();
    final todayNew = questions.where((q) {
      final createdAt = q.createdAt;
      return createdAt.year == now.year &&
          createdAt.month == now.month &&
          createdAt.day == now.day;
    }).length;
    final progress = total == 0 ? 0.0 : mastered / total;
    final percent = (progress * 100).round();

    return Column(
      children: <Widget>[
        StatsGrid(
          total: total,
          todayNew: todayNew,
          pending: pending,
          mastered: mastered,
        ),
        if (total > 0) ...<Widget>[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '掌握进度',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$percent%',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      '$mastered / $total 已掌握',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$pending 待复习',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatsGridSkeleton extends StatelessWidget {
  const _StatsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: _StatCardSkeleton()),
            SizedBox(width: 12, height: 70),
            Expanded(child: _StatCardSkeleton()),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(child: _StatCardSkeleton()),
            SizedBox(width: 12, height: 70),
            Expanded(child: _StatCardSkeleton()),
          ],
        ),
      ],
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

class _TodayPlanCard extends StatelessWidget {
  const _TodayPlanCard({
    required this.plan,
    required this.onOpenReview,
    required this.onCapture,
  });

  final TodayReviewPlan plan;
  final VoidCallback onOpenReview;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final target = plan.targetCount;
    final progress = target == 0 ? 0.0 : plan.completedCount / target;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenReview,
        borderRadius: BorderRadius.circular(12),
        child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(CupertinoIcons.calendar,
                    size: 18, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Text('今日复习计划',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer)),
                const Spacer(),
                const Icon(CupertinoIcons.chevron_right, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              target == 0
                  ? '今天暂无待复习题'
                  : '${plan.dueCount} 题待复习 · 预计 ${plan.estimatedMinutes} 分钟',
              style: TextStyle(fontSize: 13, color: colorScheme.onPrimaryContainer),
            ),
            if (target > 0) ...<Widget>[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
              ),
              const SizedBox(height: 6),
              Text('已完成 ${plan.completedCount} / $target',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onPrimaryContainer)),
            ],
            if (plan.streakDays > 0) ...<Widget>[
              const SizedBox(height: 6),
              Text('连续学习 ${plan.streakDays} 天',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onPrimaryContainer)),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: target == 0 ? onCapture : onOpenReview,
                    icon: Icon(target == 0
                        ? CupertinoIcons.camera
                        : CupertinoIcons.play_fill),
                    label: Text(target == 0 ? '拍照录题' : '开始今日复习'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: target == 0 ? null : onCapture,
                  child: const Text('录入错题'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _MistakeCategorySummary extends StatelessWidget {
  const _MistakeCategorySummary({
    required this.stats,
    required this.onSelect,
  });

  final Map<MistakeCategory, int> stats;
  final ValueChanged<MistakeCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ranked = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('常见错因', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: top
                .map((entry) => ActionChip(
                      label: Text('${entry.key.label} ${entry.value} 题'),
                      onPressed: () => onSelect(entry.key),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.questions, required this.ref});

  final List<QuestionRecord> questions;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (questions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          children: <Widget>[
            Icon(CupertinoIcons.question,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45)),
            const SizedBox(height: 12),
            Text('暂无错题，拍照开始添加',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return Column(
      children: List.generate(questions.length, (index) {
        final q = questions[index];
        return _RecentQuestionCard(
          key: ValueKey(q.id),
          question: q,
          onTap: () {
            ref.read(currentQuestionProvider.notifier).state = q;
            context.go('/notebook/question/${q.id}');
          },
        );
      }),
    );
  }
}

class _RecentQuestionCard extends StatelessWidget {
  const _RecentQuestionCard(
      {super.key, required this.question, required this.onTap});

  final QuestionRecord question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiTags = question.aiTags;
    final customTags = question.customTags;
    final allTags = [...aiTags, ...customTags];

    return Semantics(
      button: true,
      label: '错题: ${question.correctedText}，科目: ${question.subject.label}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: question.subject.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(question.subject.icon,
                  size: 16, color: question.subject.color),
            ),
            title: MathContentView(
              question.correctedText,
              contentFormat: question.contentFormat,
              mode: MathContentViewMode.compact,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface),
            ),
            subtitle: Row(
              children: <Widget>[
                Text(question.subject.label,
                    style:
                        TextStyle(fontSize: 12, color: question.subject.color)),
                if (allTags.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  ...allTags.take(2).map((tag) {
                    final isAiTag = aiTags.contains(tag);
                    final tagColor = isAiTag
                        ? const Color(0xFFD97706)
                        : const Color(0xFF4F46E5);
                    final tagBackground = isDark
                        ? tagColor.withValues(alpha: 0.14)
                        : isAiTag
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFEEF2FF);
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
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
                            color: isDark ? colorScheme.onSurface : tagColor),
                      ),
                    );
                  }),
                ],
              ],
            ),
            trailing: Icon(CupertinoIcons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65)),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}