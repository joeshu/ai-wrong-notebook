import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/stats_chart.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_launcher.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionListProvider);
    final todayPlanAsync = ref.watch(todayReviewPlanProvider);
    final mistakeStatsAsync = ref.watch(mistakeCategoryStatsProvider);
    final worksheetSession = ref.watch(currentWorksheetImportProvider);
    final hasPendingBatch = worksheetSession?.pages.any((item) =>
            item.contentStatus == ContentStatus.processing ||
            item.contentStatus == ContentStatus.failed ||
            (item.contentStatus == ContentStatus.ready &&
                item.analysisResult == null)) ??
        false;

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
                    Text(AppStrings.homeGreeting,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpace.xs),
                    Text(AppStrings.homeSubtitle,
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
                  onTap: () => CaptureEntryLauncher.show(context),
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(CupertinoIcons.add),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasPendingBatch)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.lg),
              child: _BatchActionCard(
                session: worksheetSession!,
                onOpen: () => context.go('/worksheet/import'),
              ),
            )
          else
            todayPlanAsync.when(
              data: (plan) => Padding(
                padding: const EdgeInsets.only(top: AppSpace.lg),
                child: _TodayPlanCard(
                  plan: plan,
                  onOpenReview: () => context.go('/review'),
                  onCapture: () => CaptureEntryLauncher.show(context),
                ),
              ),
              loading: () => const _TodayPlanSkeleton(),
              error: (_, __) => AppErrorState(
                message: AppStrings.homePlanError,
                onRetry: () => ref.invalidate(todayReviewPlanProvider),
              ),
            ),
          const SizedBox(height: AppSpace.md),
          _QuickStartRow(
            onCapture: () => CaptureEntryLauncher.show(context),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(AppStrings.homeStatsTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.md),
          RepaintBoundary(
            child: questionsAsync.when(
              data: (questions) => _buildStatsSection(context, questions),
              loading: () => const _StatsGridSkeleton(),
              error: (_, __) => AppErrorState(message: AppStrings.homeStatsError, onRetry: () => ref.invalidate(questionListProvider)),
            ),
          ),
          mistakeStatsAsync.when(
            data: (stats) => stats.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpace.lg),
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
          const SizedBox(height: AppSpace.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(AppStrings.homeRecentTitle, style: Theme.of(context).textTheme.titleLarge),
              TextButton(
                onPressed: () => context.go('/notebook'),
                child: const Text(AppStrings.homeViewAll),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          questionsAsync.when(
            data: (questions) =>
                _RecentList(questions: questions.take(5).toList(), ref: ref),
            loading: () => const AppLoadingState(label: '正在加载最近错题…'),
            error: (e, _) => AppErrorState(
              error: e,
              onRetry: () => ref.invalidate(questionListProvider),
            ),
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
    final reviewing = questions
        .where((q) => q.masteryLevel == MasteryLevel.reviewing)
        .length;
    final newQ = questions
        .where((q) => q.masteryLevel == MasteryLevel.newQuestion)
        .length;
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
          const SizedBox(height: AppSpace.lg),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      AppStrings.homeMasterProgress,
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
                const SizedBox(height: AppSpace.md),
                SizedBox(
                  height: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: <Widget>[
                        if (mastered > 0)
                          Expanded(
                              flex: mastered,
                              child: Container(color: _kMasteredColor)),
                        if (reviewing > 0)
                          Expanded(
                              flex: reviewing,
                              child: Container(color: _kReviewingColor)),
                        if (newQ > 0)
                          Expanded(
                              flex: newQ, child: Container(color: _kNewColor)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: <Widget>[
                    _LegendDot(
                        color: _kMasteredColor, label: '已掌握 $mastered'),
                    const SizedBox(width: AppSpace.md),
                    _LegendDot(
                        color: _kReviewingColor, label: '复习中 $reviewing'),
                    const SizedBox(width: AppSpace.md),
                    _LegendDot(color: _kNewColor, label: '新题 $newQ'),
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

class _TodayPlanSkeleton extends StatelessWidget {
  const _TodayPlanSkeleton();
  @override
  Widget build(BuildContext context) => AppShimmer(
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      );
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({required this.onCapture});
  final VoidCallback onCapture;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    Text(AppStrings.homeQuickStart, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
    const SizedBox(height: AppSpace.sm),
    SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onCapture,
        icon: const Icon(CupertinoIcons.add),
        label: const Text(AppStrings.homeCapture),
      ),
    ),
  ]);
}

class _BatchActionCard extends StatelessWidget {
  const _BatchActionCard({required this.session, required this.onOpen});
  final WorksheetImportSession session;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final all = session.pages;
    final failed = all.where((item) => item.contentStatus == ContentStatus.failed).length;
    final drafts = all.where((item) => item.contentStatus == ContentStatus.ready && item.analysisResult == null).length;
    final pending = all.where((item) => item.contentStatus == ContentStatus.processing).length;
    final remaining = failed + drafts + pending;
    final primaryAction = failed > 0
        ? AppStrings.homeBatchRetry
        : drafts > 0
            ? AppStrings.homeBatchContinueCorrection
            : AppStrings.homeBatchContinueProcess;
    final primaryIcon = failed > 0
        ? CupertinoIcons.arrow_clockwise
        : drafts > 0
            ? CupertinoIcons.pencil
            : CupertinoIcons.arrow_right_circle;
    if (remaining == 0) return const SizedBox.shrink();
    return AppCard(
      borderRadius: AppRadius.large,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[Icon(CupertinoIcons.exclamationmark_circle_fill, color: AppColors.warning), const SizedBox(width: AppSpace.sm), Expanded(child: Text(AppStrings.homeBatchPriority, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))), Text('$remaining ${AppStrings.homeBatchRemaining}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))]),
        const SizedBox(height: AppSpace.md),
        if (failed > 0) _BatchTodoRow(icon: CupertinoIcons.exclamationmark_triangle_fill, color: AppColors.warning, text: '$failed ${AppStrings.homeBatchFailed}', action: AppStrings.homeBatchRetry),
        if (drafts > 0) _BatchTodoRow(icon: CupertinoIcons.sparkles, color: AppColors.info, text: '$drafts ${AppStrings.homeBatchDrafts}', action: AppStrings.homeBatchContinueCorrection),
        if (pending > 0) _BatchTodoRow(icon: CupertinoIcons.clock, color: AppColors.slate, text: '$pending ${AppStrings.homeBatchPending}', action: AppStrings.homeBatchContinueProcess),
        const SizedBox(height: AppSpace.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onOpen,
            icon: Icon(primaryIcon),
            label: Text(primaryAction),
          ),
        ),
      ]),
    );
  }
}

class _BatchTodoRow extends StatelessWidget {
  const _BatchTodoRow({required this.icon, required this.color, required this.text, required this.action});
  final IconData icon;
  final Color color;
  final String text;
  final String action;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: <Widget>[Icon(icon, size: 16, color: color), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(fontSize: 13))), Text(action, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))]));
}

class _StatsGridSkeleton extends StatelessWidget {
  const _StatsGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: <Widget>[
          Row(
            children: const <Widget>[
              Expanded(child: _StatCardSkeleton()),
              SizedBox(width: AppSpace.md, height: 70),
              Expanded(child: _StatCardSkeleton()),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: const <Widget>[
              Expanded(child: _StatCardSkeleton()),
              SizedBox(width: AppSpace.md, height: 70),
              Expanded(child: _StatCardSkeleton()),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(AppRadius.small),
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
      borderRadius: BorderRadius.circular(AppRadius.medium),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenReview,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(CupertinoIcons.calendar,
                    size: 18, color: colorScheme.onPrimaryContainer),
                const SizedBox(width: AppSpace.sm),
                Text(AppStrings.homeReviewPlan,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onPrimaryContainer)),
                const Spacer(),
                Icon(CupertinoIcons.chevron_right, size: 18, color: colorScheme.onPrimaryContainer),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              target == 0
                  ? AppStrings.homeNoReviewToday
                  : '${plan.dueCount}${AppStrings.homeReviewDue} · ${AppStrings.homeReviewEstimated.replaceFirst('{}', '${plan.estimatedMinutes}')}',
              style: TextStyle(fontSize: 13, color: colorScheme.onPrimaryContainer),
            ),
            if (target > 0) ...<Widget>[
              const SizedBox(height: AppSpace.sm),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(AppStrings.homeReviewCompleted.replaceFirst('{}', '${plan.completedCount}').replaceFirst('{}', '$target'),
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onPrimaryContainer)),
            ],
            if (plan.streakDays > 0) ...<Widget>[
              const SizedBox(height: AppSpace.xs),
              Text(AppStrings.homeStreakDays.replaceFirst('{}', '${plan.streakDays}'),
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onPrimaryContainer)),
            ],
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: target == 0 ? onCapture : onOpenReview,
                icon: Icon(target == 0
                    ? CupertinoIcons.add
                    : CupertinoIcons.play_fill),
                label: Text(target == 0 ? AppStrings.homeCapture : AppStrings.homeStartReview),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}

const Color _kMasteredColor = Color(0xFF22C55E);
const Color _kReviewingColor = Color(0xFFF59E0B);
const Color _kNewColor = Color(0xFF9CA3AF);

Color _mistakeCategoryColor(MistakeCategory category) {
  switch (category) {
    case MistakeCategory.calculation:
      return const Color(0xFFEF4444);
    case MistakeCategory.concept:
      return const Color(0xFFF59E0B);
    case MistakeCategory.careless:
      return const Color(0xFF3B82F6);
    case MistakeCategory.comprehension:
    case MistakeCategory.strategy:
    case MistakeCategory.format:
      return const Color(0xFF9CA3AF);
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
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
    final total = stats.values.fold(0, (int sum, int v) => sum + v);
    final ranked = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(3).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(AppStrings.homeMistakeCategories, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpace.md),
          if (total == 0 || top.isEmpty)
            AppEmptyState(
              icon: CupertinoIcons.chart_bar,
              title: '暂无错因分析数据',
            )
          else
            ...top.map((entry) => _MistakeCategoryBar(
                  category: entry.key,
                  count: entry.value,
                  maxValue: top.first.value.toDouble(),
                  total: total,
                  onTap: () => onSelect(entry.key),
                )),
        ],
      ),
    );
  }
}

class _MistakeCategoryBar extends StatelessWidget {
  const _MistakeCategoryBar({
    required this.category,
    required this.count,
    required this.maxValue,
    required this.total,
    required this.onTap,
  });

  final MistakeCategory category;
  final int count;
  final double maxValue;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _mistakeCategoryColor(category);
    final widthRatio =
        maxValue == 0 ? 0.0 : (count / maxValue).clamp(0.0, 1.0);
    final percent = total == 0 ? 0 : (count * 100 / total).round();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: <Widget>[
            Text(
              category.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widthRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Text(
              '$count 题 ($percent%)',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
    if (questions.isEmpty) {
      return AppCard(
        child: AppEmptyState(
          icon: CupertinoIcons.question,
          title: AppStrings.homeEmptyTip,
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
    final aiTags = question.aiTags;
    final customTags = question.customTags;
    final allTags = [...aiTags, ...customTags];

    return Semantics(
      button: true,
      label: '错题: ${question.correctedText}，科目: ${question.subject.label}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.large),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
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
            subtitle: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: <Widget>[
                AppTag(
                  label: question.subject.label,
                  textColor: question.subject.color,
                  backgroundColor: question.subject.color.withValues(alpha: 0.08),
                  fontSize: 10,
                ),
                ...allTags.take(2).map((tag) {
                  final isAiTag = aiTags.contains(tag);
                  return AppTag(
                    label: tag,
                    textColor: isAiTag ? AppColors.accentAmber : AppColors.primary,
                    backgroundColor: isAiTag
                        ? AppColors.accentAmberContainerLight
                        : AppColors.primaryContainerLight,
                    fontSize: 10,
                  );
                }),
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