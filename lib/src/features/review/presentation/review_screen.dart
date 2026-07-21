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

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// 本次会话的复习统计：忘记 / 模糊 / 掌握 三类计数。
  final Map<ReviewRating, int> _sessionStats = <ReviewRating, int>{
    ReviewRating.forgot: 0,
    ReviewRating.hard: 0,
    ReviewRating.easy: 0,
  };

  /// 进入复习页时待复习题数，用于判断是否全部完成。
  int _initialPending = 0;
  bool _summaryShown = false;

  /// 连续复习模式：评价完成后自动滚动到下一题。
  bool _continuousMode = false;

  /// 待复习列表的滚动控制器，用于支持「下一题」自动滚动。
  final ScrollController _pendingScrollController = ScrollController();

  @override
  void dispose() {
    _pendingScrollController.dispose();
    super.dispose();
  }

  void _onRated(ReviewRating rating) {
    setState(() => _sessionStats[rating] = (_sessionStats[rating] ?? 0) + 1);
    // 总结弹窗的检查在 build 中数据可用时进行，避免在 provider 加载期间误判。
  }

  /// 滚动到下一题。预估单题卡片高度约 380px，确保下一张卡片可见。
  void _scrollToNextPending() {
    final controller = _pendingScrollController;
    if (!controller.hasClients) return;
    final target = controller.offset + 380;
    final max = controller.position.maxScrollExtent;
    controller.animateTo(
      target > max ? max : target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showSummaryDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(children: <Widget>[
          Icon(CupertinoIcons.checkmark_seal_fill, color: AppColors.success),
          SizedBox(width: AppSpace.sm),
          Text('本次复习完成'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '本次共复习 ${_sessionStats.values.fold<int>(0, (a, b) => a + b)} 题：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.sm),
            _SummaryRow(
              label: '忘记',
              count: _sessionStats[ReviewRating.forgot] ?? 0,
              color: AppColors.danger,
            ),
            _SummaryRow(
              label: '模糊',
              count: _sessionStats[ReviewRating.hard] ?? 0,
              color: AppColors.warning,
            ),
            _SummaryRow(
              label: '掌握',
              count: _sessionStats[ReviewRating.easy] ?? 0,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              (_sessionStats[ReviewRating.forgot] ?? 0) > 0
                  ? '忘记的题目将在近期再次出现，建议加强巩固。'
                  : '本次复习表现不错，继续保持节奏！',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(ctx);
              // 关闭弹窗后用户可继续查看已排程题目，本轮统计保留。
            },
            child: const Text('继续下一组'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/notebook');
            },
            child: const Text('返回错题本'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

        // 首次拿到待复习列表时记录初始数量，用于判断本次会话是否全部完成。
        if (_initialPending == 0 && pending.isNotEmpty) {
          _initialPending = pending.length;
        }

        // 数据可用时检查是否应展示本次复习总结：本次至少评价过一题，且当前已无待复习。
        final reviewed = _sessionStats.values.fold<int>(0, (a, b) => a + b);
        if (!_summaryShown && _initialPending > 0 && reviewed > 0 && pending.isEmpty) {
          _summaryShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _showSummaryDialog());
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.reviewTitle),
              actions: <Widget>[
                IconButton(
                  icon: Icon(_continuousMode
                      ? CupertinoIcons.repeat_1
                      : CupertinoIcons.repeat),
                  tooltip: _continuousMode ? '关闭连续复习' : '开启连续复习',
                  color: _continuousMode
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  onPressed: () => setState(() => _continuousMode = !_continuousMode),
                ),
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
                        onRated: _onRated,
                        scrollController: _pendingScrollController,
                        onNext: _scrollToNextPending,
                        autoAdvance: _continuousMode,
                      ),
                      _ReviewQuestionList(
                        questions: scheduled,
                        emptyMessage: AppStrings.reviewEmptyScheduled,
                        batchGroups: batchGroups,
                        ref: ref,
                        onRated: null,
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Text('$count 题', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
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
    this.onRated,
    this.scrollController,
    this.onNext,
    this.autoAdvance = false,
  });

  final List<QuestionRecord> questions;
  final String emptyMessage;
  final Map<String, QuestionBatchGroup>? batchGroups;
  final WidgetRef ref;
  final ValueChanged<ReviewRating>? onRated;
  final ScrollController? scrollController;
  final VoidCallback? onNext;
  final bool autoAdvance;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: _EmptyCard(message: emptyMessage),
      );
    }

    return ListView.separated(
      controller: scrollController,
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
        onRated: onRated,
        onNext: onNext,
        autoAdvance: autoAdvance,
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
    this.onRated,
    this.onNext,
    this.autoAdvance = false,
  });

  final QuestionRecord question;
  final VoidCallback onOpen;
  final String? batchLabel;
  final ValueChanged<ReviewRating>? onRated;
  final VoidCallback? onNext;
  final bool autoAdvance;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _revealed = false;
  bool _rating = false;
  bool _rated = false;

  Future<void> _rate(ReviewRating rating) async {
    if (_rating || _rated) return;
    setState(() => _rating = true);
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    try {
      final updated = switch (rating) {
        ReviewRating.forgot => await controller.markForgot(widget.question.id),
        ReviewRating.hard => await controller.markReviewing(widget.question.id),
        ReviewRating.easy => await controller.markMastered(widget.question.id),
      };
      invalidateQuestionList(ref);
      widget.onRated?.call(rating);
      if (mounted) {
        setState(() {
          _rating = false;
          _rated = true;
        });
        _showRatingFeedback(rating, updated);
        // 连续复习模式：评价完成后短暂延迟再自动滚动到下一题，
        // 让用户先看到反馈卡片和 SnackBar。
        if (widget.autoAdvance && widget.onNext != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Future<void>.delayed(const Duration(milliseconds: 600))
                .then((_) {
              if (mounted) widget.onNext?.call();
            });
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _rating = false);
        _showRatingError(e);
      }
    }
  }

  void _showRatingFeedback(ReviewRating rating, QuestionRecord updated) {
    final ratingLabel = switch (rating) {
      ReviewRating.forgot => '忘记',
      ReviewRating.hard => '模糊',
      ReviewRating.easy => '掌握',
    };
    final masteryLabel = _masteryLabel(updated.masteryLevel);
    final nextLabel = updated.nextReviewAt != null
        ? _nextReviewLabel(updated.nextReviewAt!)
        : '已掌握，暂无下次复习';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已记录「$ratingLabel」· $masteryLabel\n$nextLabel'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '下一题',
          onPressed: () {
            // SnackBar 自身消失即可，列表已刷新，下一题自然显示在原位置。
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showRatingError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('复习记录保存失败，请重试'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '重试',
          onPressed: () {
            // 不在此处自动重试特定 rating，引导用户再次点击按钮。
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.question.analysisResult;
    final answer = (widget.question.expectedAnswer?.trim().isNotEmpty ?? false)
        ? widget.question.expectedAnswer!.trim()
        : result?.finalAnswer.trim() ?? '';
    final hasAnswer = answer.isNotEmpty;

    if (_rated) {
      return _RatedCard(
        question: widget.question,
        onOpen: widget.onOpen,
        onNext: widget.onNext,
      );
    }

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
          onPressed: hasAnswer ? () => setState(() => _revealed = !_revealed) : widget.onOpen,
          icon: Icon(hasAnswer
              ? (_revealed ? CupertinoIcons.eye_slash : CupertinoIcons.eye)
              : CupertinoIcons.doc_text_search),
          label: Text(hasAnswer
              ? (_revealed ? '收起答案' : '回忆后查看答案')
              : '打开详情查看完整题目'),
        ),
        if (!hasAnswer) ...<Widget>[
          const SizedBox(height: AppSpace.xs),
          Text(
            '本题未保存参考答案，可直接评价或打开详情查看',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_revealed && hasAnswer) ...<Widget>[
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
        ],
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
    );
  }
}

/// 评价完成后展示的简短卡片，提示已记录并提供「打开详情」入口。
class _RatedCard extends StatelessWidget {
  const _RatedCard({required this.question, required this.onOpen, this.onNext});

  final QuestionRecord question;
  final VoidCallback onOpen;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: AppColors.success.withValues(alpha: 0.08),
      borderColor: AppColors.success.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.checkmark_circle_fill, size: 18, color: AppColors.success),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              question.nextReviewAt != null
                  ? '已记录 · ${_nextReviewLabel(question.nextReviewAt!)}'
                  : '已记录 · 已掌握',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('详情')),
          if (onNext != null) ...<Widget>[
            const SizedBox(width: AppSpace.xs),
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(CupertinoIcons.arrow_down, size: 16),
              label: const Text('下一题'),
            ),
          ],
        ],
      ),
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
