import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/stats_chart.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_launcher.dart';
import 'package:smart_wrong_notebook/src/features/notebook/application/knowledge_point_practice_controller.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
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
    final hasPendingBatch = worksheetSession?.pages.any((item) {
          final status = inferQuestionDisplayStatus(item);
          return status.isInProgress || status.isFailed || status == QuestionDisplayStatus.recognized;
        }) ??
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
            onImportPdf: () => context.push('/worksheet/import'),
          ),
          const SizedBox(height: AppSpace.md),
          questionsAsync.when(
            data: (questions) {
              // 待 AI 分析：OCR 已成功且置信度不低（不需要再人工校对）
              final pendingAi = questions.where((q) {
                if (inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.recognized) return false;
                // 排除低置信度（低置信度归入"待校对"）
                return q.ocrConfidence == null || q.ocrConfidence! >= 0.7;
              }).length;
              // 待校对：OCR 已成功但低置信度，需要人工确认
              final pendingProofread = questions.where((q) {
                if (inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.recognized) return false;
                return q.ocrConfidence != null && q.ocrConfidence! < 0.7;
              }).length;
              // 识别失败（ContentStatus.failed）
              final recognitionFailed = questions.where((q) =>
                  inferQuestionDisplayStatus(q) ==
                  QuestionDisplayStatus.recognitionFailed).length;
              // AI 分析失败（ContentStatus.analysisFailed）
              final analysisFailed = questions.where((q) =>
                  inferQuestionDisplayStatus(q) ==
                  QuestionDisplayStatus.analysisFailed).length;
              if (pendingAi == 0 &&
                  pendingProofread == 0 &&
                  recognitionFailed == 0 &&
                  analysisFailed == 0) {
                return const SizedBox.shrink();
              }
              return _PendingTaskCard(
                pendingAi: pendingAi,
                pendingProofread: pendingProofread,
                recognitionFailed: recognitionFailed,
                analysisFailed: analysisFailed,
                onOpenNotebook: () => context.go('/notebook'),
                onOpenPendingAi: () {
                  ref.read(pendingAiOnlyFilterProvider.notifier).state = true;
                  ref.read(pendingProofreadOnlyFilterProvider.notifier).state = false;
                  ref.read(lowConfidenceOnlyFilterProvider.notifier).state = false;
                  ref.read(failedOnlyFilterProvider.notifier).state = false;
                  ref.read(recognitionFailedOnlyFilterProvider.notifier).state = false;
                  ref.read(analysisFailedOnlyFilterProvider.notifier).state = false;
                  context.go('/notebook');
                },
                onOpenPendingProofread: () {
                  ref.read(pendingProofreadOnlyFilterProvider.notifier).state = true;
                  ref.read(pendingAiOnlyFilterProvider.notifier).state = false;
                  ref.read(lowConfidenceOnlyFilterProvider.notifier).state = false;
                  ref.read(failedOnlyFilterProvider.notifier).state = false;
                  ref.read(recognitionFailedOnlyFilterProvider.notifier).state = false;
                  ref.read(analysisFailedOnlyFilterProvider.notifier).state = false;
                  context.go('/notebook');
                },
                onOpenRecognitionFailed: () {
                  ref.read(recognitionFailedOnlyFilterProvider.notifier).state = true;
                  ref.read(analysisFailedOnlyFilterProvider.notifier).state = false;
                  ref.read(failedOnlyFilterProvider.notifier).state = false;
                  ref.read(pendingAiOnlyFilterProvider.notifier).state = false;
                  ref.read(pendingProofreadOnlyFilterProvider.notifier).state = false;
                  ref.read(lowConfidenceOnlyFilterProvider.notifier).state = false;
                  context.go('/notebook');
                },
                onOpenAnalysisFailed: () {
                  ref.read(analysisFailedOnlyFilterProvider.notifier).state = true;
                  ref.read(recognitionFailedOnlyFilterProvider.notifier).state = false;
                  ref.read(failedOnlyFilterProvider.notifier).state = false;
                  ref.read(pendingAiOnlyFilterProvider.notifier).state = false;
                  ref.read(pendingProofreadOnlyFilterProvider.notifier).state = false;
                  ref.read(lowConfidenceOnlyFilterProvider.notifier).state = false;
                  context.go('/notebook');
                },
                onRetry: () => ref.invalidate(questionListProvider),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
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
          questionsAsync.when(
            data: (questions) {
              final lowConfidenceCount = questions
                  .where((q) => q.ocrConfidence != null && q.ocrConfidence! < 0.7)
                  .length;
              if (lowConfidenceCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.lg),
                child: _LowConfidenceHintCard(
                  count: lowConfidenceCount,
                  onTap: () {
                    ref.read(unmasteredOnlyFilterProvider.notifier).state = false;
                    ref.read(favoritesOnlyFilterProvider.notifier).state = false;
                    context.go('/notebook');
                  },
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
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
          questionsAsync.when(
            data: (questions) {
              final counts = <String, int>{};
              for (final question in questions.where((q) => q.masteryLevel != MasteryLevel.mastered)) {
                for (final point in question.aiKnowledgePoints) {
                  counts[point] = (counts[point] ?? 0) + 1;
                }
              }
              final ranked = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              if (ranked.isEmpty) {
                // 无薄弱知识点数据：若是空错题本则隐藏；若有错题但无 AI 知识点
                // 关联，给出引导空状态。
                if (questions.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpace.lg),
                  child: AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md, vertical: AppSpace.md),
                      child: Column(
                        children: <Widget>[
                          const Icon(CupertinoIcons.scope,
                              size: 28, color: AppColors.slate),
                          const SizedBox(height: AppSpace.sm),
                          const Text('暂无薄弱知识点数据',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            '完成 AI 分析后，薄弱知识点会自动汇总到这里。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.lg),
                child: _WeakPointSection(
                  ranked: ranked,
                  questions: questions,
                ),
              );
            },
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
  const _QuickStartRow({required this.onCapture, required this.onImportPdf});
  final VoidCallback onCapture;
  final VoidCallback onImportPdf;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(AppStrings.homeQuickStart, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: AppSpace.sm),
      Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: onCapture,
              icon: const Icon(CupertinoIcons.add, size: 18),
              label: const Text(AppStrings.homeCapture),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onImportPdf,
              icon: Icon(CupertinoIcons.doc_richtext, size: 18, color: AppColors.accentPurple),
              label: Text('导入 PDF', style: TextStyle(color: AppColors.accentPurple)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outlineVariant),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    ]);
  }
}

class _BatchActionCard extends StatelessWidget {
  const _BatchActionCard({required this.session, required this.onOpen});
  final WorksheetImportSession session;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final all = session.pages;
    final failed = all.where((item) => inferQuestionDisplayStatus(item).isFailed).length;
    final drafts = all.where((item) =>
        inferQuestionDisplayStatus(item) == QuestionDisplayStatus.recognized).length;
    final pending = all.where((item) =>
        inferQuestionDisplayStatus(item).isInProgress).length;
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
    final scheme = Theme.of(context).colorScheme;
    final total = stats.values.fold(0, (int sum, int v) => sum + v);
    final ranked = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(3).toList();

    return AppCard(
      backgroundColor: scheme.surfaceContainerHighest,
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

/// 首页「薄弱知识点与推荐练习」入口卡片。每行支持两件事：
/// - 点击题数文本区域 → 跳到错题本并按该知识点筛选；
/// - 点击右侧「专项练习」按钮 → 走 [KnowledgePointPracticeController]
///   聚合本知识点下所有错题的已有练习题；缺失时由 AI 生成。
///
/// 将原本只做"筛选跳转"的入口补成清单要求的"薄弱知识点和推荐练习入口"。
///
/// 优先展示 [weakPointRecommendationsProvider] 返回的可解释推荐
/// （含掌握度、推荐原因）；无结构化关联数据时回退到旧的字符串
/// aiKnowledgePoints 统计。
class _WeakPointSection extends ConsumerStatefulWidget {
  const _WeakPointSection({required this.ranked, required this.questions});
  final List<MapEntry<String, int>> ranked;
  final List<QuestionRecord> questions;

  @override
  ConsumerState<_WeakPointSection> createState() => _WeakPointSectionState();
}

class _WeakPointSectionState extends ConsumerState<_WeakPointSection> {
  String? _practicingPoint;

  Future<void> _startPractice({
    required String knowledgePointId,
    required String displayName,
    bool useControlledId = false,
  }) async {
    if (_practicingPoint != null) return;
    setState(() => _practicingPoint = knowledgePointId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      List<QuestionRecord> related;
      if (useControlledId) {
        // 通过结构化关联查题
        final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
        final questionIds = await linkRepo.questionIdsForKnowledgePoint(knowledgePointId);
        final idSet = questionIds.toSet();
        related = widget.questions
            .where((q) => q.masteryLevel != MasteryLevel.mastered && idSet.contains(q.id))
            .toList(growable: false);
      } else {
        // 回退：字符串匹配旧 aiKnowledgePoints
        related = widget.questions
            .where((q) =>
                q.masteryLevel != MasteryLevel.mastered &&
                q.aiKnowledgePoints.contains(knowledgePointId))
            .toList(growable: false);
      }
      if (related.isEmpty) {
        throw StateError('该知识点暂无错题可生成练习');
      }
      final controller = KnowledgePointPracticeController(
        ref.read(aiAnalysisServiceProvider),
      );
      final prepared = await controller.buildRound(
        knowledgePoint: displayName,
        questions: related,
      );
      await ref.read(questionRepositoryProvider).update(prepared);
      invalidateQuestionList(ref);
      ref.read(currentPracticeContextProvider.notifier).state = const PracticeContext(
        source: PracticeContextSource.notebook,
        returnRoute: '/',
      );
      ref.read(currentQuestionProvider.notifier).state = prepared;
      if (!mounted) return;
      context.go('/exercise/practice');
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('专项练习准备失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _practicingPoint = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendationsAsync = ref.watch(weakPointRecommendationsProvider);
    return recommendationsAsync.when(
      data: (recommendations) {
        if (recommendations.isEmpty) {
          // 无结构化关联数据，回退到字符串统计
          return _WeakPointCard(
            rows: widget.ranked
                .take(3)
                .map((entry) => _WeakPointRow(
                      key: entry.key,
                      displayName: entry.key,
                      questionCount: entry.value,
                      masteryPercentage: null,
                      reason: null,
                      pendingReviewCount: null,
                      useControlledId: false,
                    ))
                .toList(),
            practicingPoint: _practicingPoint,
            onSelect: (point) {
              ref.read(selectedKnowledgePointFilterProvider.notifier).state = point;
              context.go('/notebook');
            },
            onPractice: (row) => _startPractice(
              knowledgePointId: row.key,
              displayName: row.displayName,
              useControlledId: row.useControlledId,
            ),
          );
        }
        // 优先用可解释推荐
        return _WeakPointCard(
          rows: recommendations
              .take(3)
              .map((rec) => _WeakPointRow(
                    key: rec.recommendation.knowledgePointId,
                    displayName: rec.knowledgePointName,
                    questionCount: rec.recommendation.relatedQuestionIds.length,
                    masteryPercentage: rec.mastery?.masteryPercentage,
                    reason: rec.recommendation.reasons.isNotEmpty
                        ? rec.recommendation.reasons.first
                        : null,
                    pendingReviewCount: rec.pendingReviewCount,
                    useControlledId: true,
                    lastReviewedAt: rec.mastery?.lastReviewedAt,
                  ))
              .toList(),
          practicingPoint: _practicingPoint,
          onSelect: (point) {
            ref.read(selectedKnowledgePointFilterProvider.notifier).state = point;
            context.go('/notebook');
          },
          onPractice: (row) => _startPractice(
            knowledgePointId: row.key,
            displayName: row.displayName,
            useControlledId: row.useControlledId,
          ),
        );
      },
      loading: () => _WeakPointCard(
        rows: widget.ranked
            .take(3)
            .map((entry) => _WeakPointRow(
                  key: entry.key,
                  displayName: entry.key,
                  questionCount: entry.value,
                  masteryPercentage: null,
                  reason: null,
                  pendingReviewCount: null,
                  useControlledId: false,
                ))
            .toList(),
        practicingPoint: _practicingPoint,
        onSelect: (point) {
          ref.read(selectedKnowledgePointFilterProvider.notifier).state = point;
          context.go('/notebook');
        },
        onPractice: (row) => _startPractice(
          knowledgePointId: row.key,
          displayName: row.displayName,
          useControlledId: row.useControlledId,
        ),
      ),
      error: (_, __) => _WeakPointCard(
        rows: widget.ranked
            .take(3)
            .map((entry) => _WeakPointRow(
                  key: entry.key,
                  displayName: entry.key,
                  questionCount: entry.value,
                  masteryPercentage: null,
                  reason: null,
                  pendingReviewCount: null,
                  useControlledId: false,
                ))
            .toList(),
        practicingPoint: _practicingPoint,
        onSelect: (point) {
          ref.read(selectedKnowledgePointFilterProvider.notifier).state = point;
          context.go('/notebook');
        },
        onPractice: (row) => _startPractice(
          knowledgePointId: row.key,
          displayName: row.displayName,
          useControlledId: row.useControlledId,
        ),
      ),
    );
  }
}

/// 薄弱知识点行数据（统一推荐模式和字符串回退模式）。
class _WeakPointRow {
  const _WeakPointRow({
    required this.key,
    required this.displayName,
    required this.questionCount,
    required this.masteryPercentage,
    required this.reason,
    required this.pendingReviewCount,
    required this.useControlledId,
    this.lastReviewedAt,
  });
  final String key;
  final String displayName;
  final int questionCount;
  final double? masteryPercentage;
  final String? reason;
  final int? pendingReviewCount;
  final bool useControlledId;
  /// 该知识点最近一次复习时间（来自 KnowledgePointMastery.lastReviewedAt）。
  /// null 表示尚未复习过。
  final DateTime? lastReviewedAt;
}

class _WeakPointCard extends StatelessWidget {
  const _WeakPointCard({
    required this.rows,
    required this.onSelect,
    required this.onPractice,
    required this.practicingPoint,
  });
  final List<_WeakPointRow> rows;
  final ValueChanged<String> onSelect;
  final ValueChanged<_WeakPointRow> onPractice;
  final String? practicingPoint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Icon(CupertinoIcons.scope, size: 18, color: AppColors.warningDark),
          const SizedBox(width: AppSpace.sm),
          const Expanded(child: Text('优先巩固薄弱知识点', style: TextStyle(fontWeight: FontWeight.w700))),
          Text('点击筛选 / 专项练习', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ]),
        const SizedBox(height: AppSpace.sm),
        ...rows.map((row) {
          final isPracticing = practicingPoint == row.key;
          return InkWell(
            onTap: () => onSelect(row.displayName),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(row.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: <Widget>[
                          Text(
                            '${row.questionCount} 题',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          if (row.masteryPercentage != null)
                            Text(
                              '掌握度 ${row.masteryPercentage!.toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          if (row.pendingReviewCount != null && row.pendingReviewCount! > 0)
                            Text(
                              '待复习 ${row.pendingReviewCount} 题',
                              style: TextStyle(fontSize: 12, color: AppColors.warningDark),
                            ),
                          // 显示最近复习时间；未复习过时给出"尚未复习"提示，
                          // 帮助用户判断是否需要立即开始。
                          Text(
                            row.lastReviewedAt != null
                                ? '最近复习 ${_formatRelativeTime(row.lastReviewedAt!)}'
                                : '尚未复习',
                            style: TextStyle(
                              fontSize: 12,
                              color: row.lastReviewedAt == null
                                  ? AppColors.warningDark
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (row.reason != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          row.reason!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                TextButton.icon(
                  onPressed: isPracticing ? null : () => onPractice(row),
                  icon: isPracticing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.play_circle, size: 16),
                  label: Text(isPracticing ? '准备中' : '专项练习'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(CupertinoIcons.chevron_right, size: 14),
              ]),
            ),
          );
        }),
      ]),
    );
  }
}

/// 格式化为相对时间文案：刚刚 / N 分钟前 / N 小时前 / N 天前 / YYYY-MM-DD。
///
/// 用于薄弱知识点的"最近复习"展示，让用户一眼判断复习间隔。
String _formatRelativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  // 超过 30 天直接显示日期，避免"90 天前"这种歧义文案
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
}

class _GoalEntryCard extends StatelessWidget {
  const _GoalEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: AppSpace.md),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Icon(
                  CupertinoIcons.checkmark_seal,
                  color: colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '学习目标与打卡',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '设置每日目标，坚持打卡，养成学习习惯',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right,
                  size: 18, color: colorScheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页「低置信度题目」提示卡。当存在 OCR 置信度 < 0.7 的题目时显示，
/// 引导用户进入错题本校对，避免错误识别内容污染复习流程。
class _LowConfidenceHintCard extends StatelessWidget {
  const _LowConfidenceHintCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: AppColors.semanticContainer(AppColors.warning, isDark: isDark),
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: isDark ? 0.24 : 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: AppColors.warning,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$count 道题识别置信度较低',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warningDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '建议进入错题本校对，避免错题内容有误',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.warningDark.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: AppColors.warningDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskActionRow extends StatelessWidget {
  const _TaskActionRow({required this.label, required this.icon, required this.color, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
            const Icon(CupertinoIcons.chevron_right, size: 14),
          ]),
        ),
      );
}

class _PendingTaskCard extends StatelessWidget {
  const _PendingTaskCard({
    required this.pendingAi,
    required this.pendingProofread,
    required this.recognitionFailed,
    required this.analysisFailed,
    required this.onOpenNotebook,
    required this.onOpenPendingAi,
    required this.onOpenPendingProofread,
    required this.onOpenRecognitionFailed,
    required this.onOpenAnalysisFailed,
    required this.onRetry,
  });

  final int pendingAi;
  final int pendingProofread;
  final int recognitionFailed;
  final int analysisFailed;
  final VoidCallback onOpenNotebook;
  final VoidCallback onOpenPendingAi;
  final VoidCallback onOpenPendingProofread;
  final VoidCallback onOpenRecognitionFailed;
  final VoidCallback onOpenAnalysisFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: scheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(CupertinoIcons.checkmark_square, color: scheme.primary),
              const SizedBox(width: AppSpace.sm),
              const Expanded(
                child: Text('待处理任务', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: onRetry, child: const Text('刷新')),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          if (pendingAi > 0)
            _TaskActionRow(
              label: '$pendingAi 道待 AI 分析',
              icon: CupertinoIcons.sparkles,
              color: scheme.primary,
              onTap: onOpenPendingAi,
            ),
          if (pendingProofread > 0)
            _TaskActionRow(
              label: '$pendingProofread 道待校对（低置信度）',
              icon: CupertinoIcons.eye,
              color: AppColors.warning,
              onTap: onOpenPendingProofread,
            ),
          if (recognitionFailed > 0)
            _TaskActionRow(
              label: '$recognitionFailed 道识别失败',
              icon: CupertinoIcons.xmark_octagon,
              color: AppColors.danger,
              onTap: onOpenRecognitionFailed,
            ),
          if (analysisFailed > 0)
            _TaskActionRow(
              label: '$analysisFailed 道 AI 分析失败',
              icon: CupertinoIcons.exclamationmark_triangle,
              color: AppColors.danger,
              onTap: onOpenAnalysisFailed,
            ),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onOpenNotebook,
              child: const Text('去错题本处理'),
            ),
          ),
        ],
      ),
    );
  }
}
