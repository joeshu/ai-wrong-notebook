import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionListProvider);
    final reviewLogsAsync = ref.watch(reviewLogListProvider);
    final batchGroups = ref.watch(questionBatchGroupsProvider).valueOrNull;

    return questionsAsync.when(
      data: (questions) {
        const scheduler = ReviewScheduleService();
        final pending = questions.where(scheduler.isDue).toList();
        final scheduled = questions.where((q) => !scheduler.isDue(q)).toList();
        final reviewedToday = _reviewedToday(
          reviewLogsAsync.valueOrNull ?? const <ReviewLog>[],
        );
        final todayTarget = pending.length + reviewedToday;

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.reviewTitle),
              actions: <Widget>[
                IconButton(
                  icon: const Icon(CupertinoIcons.clock),
                  tooltip: AppStrings.reviewHistory,
                  onPressed: () => context.go('/review/history'),
                ),
              ],
              bottom: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                labelColor: Theme.of(context).colorScheme.onPrimary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: <Widget>[
                  Tab(text: '${AppStrings.reviewPending} ${pending.length}'),
                  Tab(text: '${AppStrings.reviewScheduled} ${scheduled.length}'),
                ],
              ),
            ),
            body: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
                  child: _SummaryCard(
                    total: questions.length,
                    pending: pending.length,
                    scheduled: scheduled.length,
                    reviewedToday: reviewedToday,
                    todayTarget: todayTarget,
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _ReviewQuestionList(
                        questions: pending,
                        emptyMessage: AppStrings.reviewEmptyPending,
                        batchGroups: batchGroups,
                        ref: ref,
                      ),
                      _ReviewQuestionList(
                        questions: scheduled,
                        emptyMessage: AppStrings.reviewEmptyScheduled,
                        batchGroups: batchGroups,
                        ref: ref,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: AppLoadingState(label: '正在整理复习计划…'),
      ),
      error: (_, __) => Scaffold(
        body: AppErrorState(
          message: '复习计划暂时无法读取。',
          onRetry: () => ref.invalidate(questionListProvider),
        ),
      ),
    );
  }
}

int _reviewedToday(List<ReviewLog> logs, {DateTime? now}) {
  final day = now ?? DateTime.now();
  final ids = <String>{};
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    if (at.year == day.year && at.month == day.month && at.day == day.day) {
      ids.add(log.questionRecordId);
    }
  }
  return ids.length;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.pending,
    required this.scheduled,
    required this.reviewedToday,
    required this.todayTarget,
  });

  final int total;
  final int pending;
  final int scheduled;
  final int reviewedToday;
  final int todayTarget;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      borderRadius: AppRadius.large,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                AppStrings.reviewOverallProgress,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '共 $total 题',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _MiniStat(
                  value: '$pending',
                  label: AppStrings.reviewPending,
                  color: AppColors.warning),
              _MiniStat(
                  value: '$scheduled',
                  label: AppStrings.reviewScheduled,
                  color: AppColors.success),
              _MiniStat(
                  value: '$total', label: '总错题', color: colorScheme.onSurface),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            todayTarget == 0
                ? '今日暂无复习计划'
                : '$reviewedToday / $todayTarget ${AppStrings.reviewTodayProgress}',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.sm),
          LinearProgressIndicator(
            value: todayTarget == 0 ? 0 : reviewedToday / todayTarget,
            minHeight: 7,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});

  final String message;
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      backgroundColor:
          isDark ? AppColors.success.withValues(alpha: 0.12) : const Color(0xFFF0FDF4),
      borderColor: isDark
          ? AppColors.success.withValues(alpha: 0.35)
          : const Color(0xFFBBF7D0),
      child: Column(
        children: <Widget>[
          Icon(CupertinoIcons.star,
              size: 48, color: AppColors.success.withValues(alpha: 0.65)),
          const SizedBox(height: AppSpace.md),
          const Text('太棒了！',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: AppSpace.xs),
          Text(message, style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ReviewQuestionList extends StatelessWidget {
  const _ReviewQuestionList({
    required this.questions,
    required this.emptyMessage,
    required this.batchGroups,
    required this.ref,
  });

  final List<QuestionRecord> questions;
  final String emptyMessage;
  final Map<String, QuestionBatchGroup>? batchGroups;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: _EmptyCard(message: emptyMessage),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.lg),
      itemCount: questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
      itemBuilder: (context, index) => _ReviewCard(
        question: questions[index],
        batchLabel: _batchLabel(questions[index], batchGroups),
        onOpen: () {
          ref.read(currentQuestionProvider.notifier).state = questions[index];
          context.go('/notebook/question/${questions[index].id}');
        },
      ),
    );
  }
}

String? _batchLabel(
    QuestionRecord question, Map<String, QuestionBatchGroup>? batchGroups) {
  final rootId = questionBatchRootId(question);
  if (rootId == null) return null;

  final group = batchGroups?[rootId];
  if (group == null || group.questions.length < 2) return null;

  final order = question.splitOrder;
  return order == null ? '来自同一拍照批次' : '来自同一拍照批次 · 第 $order 题';
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '待复习';
    case MasteryLevel.reviewing:
      return '待复习';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

Color _masteryColor(BuildContext context, MasteryLevel level) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (level) {
    case MasteryLevel.newQuestion:
      return colorScheme.onSurfaceVariant;
    case MasteryLevel.reviewing:
      return AppColors.warning;
    case MasteryLevel.mastered:
      return AppColors.success;
  }
}

class _MasteryChip extends StatelessWidget {
  const _MasteryChip({required this.level});

  final MasteryLevel level;

  @override
  Widget build(BuildContext context) {
    final color = _masteryColor(context, level);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _masteryLabel(level),
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

String _nextReviewLabel(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '下次复习 $month-$day $hour:$minute';
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({
    required this.question,
    required this.onOpen,
    this.batchLabel,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final String? batchLabel;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _revealed = false;
  bool _rating = false;

  Future<void> _rate(ReviewRating rating) async {
    if (_rating) return;
    setState(() => _rating = true);
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    try {
      switch (rating) {
        case ReviewRating.forgot:
          await controller.markForgot(widget.question.id);
        case ReviewRating.hard:
          await controller.markReviewing(widget.question.id);
        case ReviewRating.easy:
          await controller.markMastered(widget.question.id);
      }
      invalidateQuestionList(ref);
      if (mounted) setState(() => _rating = false);
    } catch (_) {
      if (mounted) setState(() => _rating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.question.analysisResult;
    final answer = (widget.question.expectedAnswer?.trim().isNotEmpty ?? false)
        ? widget.question.expectedAnswer!.trim()
        : result?.finalAnswer.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _ReviewCardContent(
          question: widget.question,
          onOpen: widget.onOpen,
          batchLabel: widget.batchLabel,
        ),
        const SizedBox(height: AppSpace.xs),
        OutlinedButton.icon(
          onPressed: answer.isEmpty ? widget.onOpen : () => setState(() => _revealed = !_revealed),
          icon: Icon(_revealed ? CupertinoIcons.eye_slash : CupertinoIcons.eye),
          label: Text(answer.isEmpty ? '打开详情查看并评价' : (_revealed ? '收起答案' : '回忆后查看答案')),
        ),
        if (_revealed && answer.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.xs),
          AppInfoSection(
            icon: CupertinoIcons.checkmark_circle,
            title: '参考答案',
            iconColor: AppColors.successDark,
            backgroundColor: AppColors.successContainerLight,
            borderColor: const Color(0xFFBBF7D0),
            titleColor: AppColors.successDark,
            child: MathContentView(answer, contentFormat: widget.question.contentFormat),
          ),
          const SizedBox(height: AppSpace.sm),
          Text('回忆结果', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: <Widget>[
              Expanded(child: OutlinedButton(onPressed: _rating ? null : () => _rate(ReviewRating.forgot), child: const Text('忘记'))),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: OutlinedButton(onPressed: _rating ? null : () => _rate(ReviewRating.hard), child: const Text('模糊'))),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: FilledButton(onPressed: _rating ? null : () => _rate(ReviewRating.easy), child: const Text('掌握'))),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReviewCardContent extends StatelessWidget {
  const _ReviewCardContent({
    required this.question,
    required this.onOpen,
    this.batchLabel,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final String? batchLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: question.subject.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(question.subject.icon,
                  size: 18, color: question.subject.color),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MathContentView(
                    question.correctedText,
                    contentFormat: question.contentFormat,
                    mode: MathContentViewMode.compact,
                    maxLines: 1,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: colorScheme.onSurface),
                  ),
                  if (batchLabel != null) ...<Widget>[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      batchLabel!,
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                  if (question.nextReviewAt != null) ...<Widget>[
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      _nextReviewLabel(question.nextReviewAt!),
                      style: TextStyle(
                          fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Text(
                        question.subject.label,
                        style: TextStyle(
                            fontSize: 12, color: question.subject.color),
                      ),
                      _MasteryChip(level: question.masteryLevel),
                      ...question.aiTags.take(3).map((tag) {
                        const tagColor = AppColors.accentAmber;
                        return AppTag(
                          label: tag,
                          textColor: isDark ? colorScheme.onSurface : tagColor,
                          backgroundColor: isDark
                              ? tagColor.withValues(alpha: 0.14)
                              : AppColors.accentAmberContainerLight,
                          fontSize: 10,
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                size: 22),
          ],
        ),
      ),
    );
  }
}
