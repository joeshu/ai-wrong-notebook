import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/common/widgets/stats_chart.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/notebook/application/knowledge_point_practice_controller.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_history_service.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/subject_avatar.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_components.dart';
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
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xl),
        children: <Widget>[
          AppHeroCard(
            title: AppStrings.homeGreeting,
            subtitle: AppStrings.homeSubtitle,
            action: AppGradientButton(
              label: AppStrings.homeCapture,
              icon: CupertinoIcons.camera_fill,
              onTap: () => context.go('/add'),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          // Phase 8-1：统一今日行动面板。
          // 优先级：复习 → 未完成识别 → 添加新错题；卡片可同时显示，
          // 按优先级从上到下排列；全部为空时显示空状态引导。
          questionsAsync.when(
            data: (questions) {
              final pendingRecognition = _countPendingRecognition(
                questions,
                worksheetSession,
              );
              return todayPlanAsync.when(
                data: (plan) => _UnifiedActionPanel(
                  plan: plan,
                  pendingRecognition: pendingRecognition,
                  hasPendingBatch: hasPendingBatch,
                  onOpenReview: () => context.go('/review'),
                  onOpenRecognize: hasPendingBatch
                      ? () => context.go('/worksheet/import')
                      : () => context.go('/notebook'),
                  onCapture: () => context.go('/add'),
                ),
                loading: () => const _TodayPlanSkeleton(),
                error: (_, __) => AppErrorState(
                  message: AppStrings.homePlanError,
                  onRetry: () => ref.invalidate(todayReviewPlanProvider),
                ),
              );
            },
            loading: () => todayPlanAsync.when(
              data: (plan) => _UnifiedActionPanel(
                plan: plan,
                pendingRecognition: 0,
                hasPendingBatch: hasPendingBatch,
                onOpenReview: () => context.go('/review'),
                onOpenRecognize: hasPendingBatch
                    ? () => context.go('/worksheet/import')
                    : () => context.go('/notebook'),
                onCapture: () => context.go('/add'),
              ),
              loading: () => const _TodayPlanSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            error: (_, __) => todayPlanAsync.when(
              data: (plan) => _UnifiedActionPanel(
                plan: plan,
                pendingRecognition: 0,
                hasPendingBatch: hasPendingBatch,
                onOpenReview: () => context.go('/review'),
                onOpenRecognize: hasPendingBatch
                    ? () => context.go('/worksheet/import')
                    : () => context.go('/notebook'),
                onCapture: () => context.go('/add'),
              ),
              loading: () => const _TodayPlanSkeleton(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(AppStrings.homeStatsTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.sm),
          RepaintBoundary(
            child: questionsAsync.when(
              data: (questions) => _buildStatsSection(context, questions),
              loading: () => const _StatsGridSkeleton(),
              error: (_, __) => AppErrorState(message: AppStrings.homeStatsError, onRetry: () => ref.invalidate(questionListProvider)),
            ),
          ),
          // 最近新增上移：紧随统计之后，确保首屏可见。
          const SizedBox(height: AppSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(AppStrings.homeRecentTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              TextButton(
                onPressed: () => context.go('/notebook'),
                child: const Text(AppStrings.homeViewAll),
              ),
            ],
          ),
          questionsAsync.when(
            data: (questions) =>
                _RecentList(questions: questions.take(3).toList(), ref: ref),
            loading: () => const AppLoadingState(label: '正在加载最近错题…'),
            error: (e, _) => AppErrorState(
              error: e,
              onRetry: () => ref.invalidate(questionListProvider),
            ),
          ),
          questionsAsync.when(
            data: (questions) {
              final lowConfidenceCount = questions
                  .where((q) => q.ocrConfidence != null && q.ocrConfidence! < 0.7)
                  .length;
              if (lowConfidenceCount == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
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
                    padding: const EdgeInsets.only(top: AppSpace.md),
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
          // 导出与分享区块——快速导出入口 + 最近导出记录。
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: const _ExportCenterSection(),
          ),
          // Phase 8-3：近 7 天学习趋势折线图。
          ref.watch(reviewTrend7DaysProvider).when(
                data: (trend) => Padding(
                  padding: const EdgeInsets.only(top: AppSpace.md),
                  child: _ReviewTrendSection(trend: trend),
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
                  padding: const EdgeInsets.only(top: AppSpace.md),
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
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: _WeakPointSection(
                  ranked: ranked,
                  questions: questions,
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
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
          AppCard(
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

const Color _kMasteredColor = AppColors.success;
const Color _kReviewingColor = AppColors.warning;
const Color _kNewColor = AppColors.newQuestion;

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
            leading: SubjectAvatar(question: question, size: 36, iconSize: 16),
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
                  fontSize: 12,
                ),
                ...allTags.take(2).map((tag) {
                  final isAiTag = aiTags.contains(tag);
                  return AppTag(
                    label: tag,
                    textColor: isAiTag ? AppColors.accentAmber : AppColors.primary,
                    backgroundColor: isAiTag
                        ? AppColors.accentAmberContainerLight
                        : AppColors.primaryContainerLight,
                    fontSize: 12,
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
          Text('点击筛选 / 专项练习', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
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
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
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
                        fontSize: 12,
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

/// Phase 8-1：统计「未完成识别」题目数（含批量导入批次 + 错题本内的
/// 待AI/待校对/识别失败/分析失败），用于统一行动面板的识别行动卡。
int _countPendingRecognition(
  List<QuestionRecord> questions,
  WorksheetImportSession? worksheetSession,
) {
  // 错题本内的未完成项
  var count = 0;
  for (final q in questions) {
    final status = inferQuestionDisplayStatus(q);
    if (status.isInProgress || status.isFailed) count++;
  }
  // 批量导入批次的未完成项（页面级别）
  if (worksheetSession != null) {
    for (final page in worksheetSession.pages) {
      final status = inferQuestionDisplayStatus(page);
      if (status.isInProgress || status.isFailed ||
          status == QuestionDisplayStatus.recognized) {
        count++;
      }
    }
  }
  return count;
}

/// Phase 8-1：统一今日行动面板。
///
/// 三张行动卡按优先级从上到下排列：
///   1. 待复习（dueCount > 0 时显示）
///   2. 继续未完成识别（pendingRecognition > 0 时显示）
///   3. 添加新错题（始终显示）
/// 全部空时显示空状态引导。
class _UnifiedActionPanel extends StatelessWidget {
  const _UnifiedActionPanel({
    required this.plan,
    required this.pendingRecognition,
    required this.hasPendingBatch,
    required this.onOpenReview,
    required this.onOpenRecognize,
    required this.onCapture,
  });

  final TodayReviewPlan plan;
  final int pendingRecognition;
  final bool hasPendingBatch;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenRecognize;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];

    // 优先级 1：待复习
    if (plan.dueCount > 0) {
      cards.add(_ActionTile(
        icon: CupertinoIcons.play_circle_fill,
        color: AppColors.warning,
        title: AppStrings.homeStartReview,
        subtitle: '${plan.dueCount}${AppStrings.homeReviewDue} · '
            '${AppStrings.homeReviewEstimated.replaceFirst('{}', '${plan.estimatedMinutes}')}',
        trailing: AppStrings.homeStartReview,
        onTap: onOpenReview,
      ));
    }

    // 优先级 2：继续未完成识别
    if (pendingRecognition > 0) {
      cards.add(_ActionTile(
        icon: hasPendingBatch
            ? CupertinoIcons.rectangle_stack
            : CupertinoIcons.sparkles,
        color: AppColors.info,
        title: hasPendingBatch
            ? AppStrings.homeBatchPriority
            : '继续未完成识别',
        subtitle: '$pendingRecognition 项待处理',
        trailing: hasPendingBatch
            ? AppStrings.homeBatchContinueProcess
            : '去处理',
        onTap: onOpenRecognize,
      ));
    }

    // 优先级 3：添加新错题（始终显示）
    cards.add(_ActionTile(
      icon: CupertinoIcons.add_circled_solid,
      color: AppColors.success,
      title: AppStrings.homeCapture,
      subtitle: AppStrings.homeSubtitle,
      trailing: AppStrings.homeCapture,
      onTap: onCapture,
    ));

    // 空状态：无待复习、无未完成识别，且仅剩添加卡时，把添加卡替换为引导文案
    // （添加卡始终显示，但「全部为空」场景下强化引导）。
    if (plan.dueCount == 0 &&
        pendingRecognition == 0 &&
        plan.streakDays == 0) {
      return _EmptyActionGuide(onCapture: onCapture);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: Text(
            '今日行动',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ...cards,
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppActionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: color,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Icon(CupertinoIcons.chevron_right, size: 14, color: color),
        ],
      ),
    );
  }
}

class _EmptyActionGuide extends StatelessWidget {
  const _EmptyActionGuide({required this.onCapture});

  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        children: <Widget>[
          Icon(CupertinoIcons.checkmark_seal_fill,
              size: 36, color: AppColors.success.withValues(alpha: 0.7)),
          const SizedBox(height: AppSpace.sm),
          const Text('今日清单已清空',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            '没有待复习或待处理的错题，继续保持节奏！\n也可以随时录入新的错题。',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: onCapture,
            icon: const Icon(CupertinoIcons.add, size: 16),
            label: const Text(AppStrings.homeCapture),
          ),
        ],
      ),
    );
  }
}

/// 导出与分享区块——提供快速导出入口与最近导出记录。
///
/// 点击格式卡片或「进入工作台」跳转 `/settings/export-workbench`；
/// 最近导出记录来自 [exportHistoryProvider]。
class _ExportCenterSection extends ConsumerWidget {
  const _ExportCenterSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final questionCount = ref.watch(questionListProvider).maybeWhen(
          data: (q) => q.length,
          orElse: () => null,
        );
    final historyAsync = ref.watch(exportHistoryProvider);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.arrow_up_doc,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpace.sm),
              const Text(AppStrings.settingsExportShare,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push('/settings/export-workbench'),
                child: Row(
                  children: <Widget>[
                    Text(
                      '进入工作台',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right,
                        size: 12, color: colorScheme.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            AppStrings.settingsExportWorkbenchSubtitle,
            style: TextStyle(
                fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.md),
          Text('支持格式',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kExportQuickEntries
                .map((e) => _ExportFormatChip(entry: e))
                .toList(),
          ),
          const SizedBox(height: AppSpace.md),
          Text('最近导出',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: AppSpace.sm),
          historyAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return Text(
                  questionCount == 0
                      ? '题库为空，暂无可导出内容'
                      : '暂无导出记录，去工作台生成第一份报告',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                );
              }
              return Column(
                children: entries
                    .take(3)
                    .map((e) => _ExportHistoryTile(entry: e))
                    .toList(),
              );
            },
            loading: () => const SizedBox(
              height: 20,
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Text(
              '导出记录读取失败',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportQuickEntry {
  const _ExportQuickEntry({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;
}

const List<_ExportQuickEntry> _kExportQuickEntries = <_ExportQuickEntry>[
  _ExportQuickEntry(
      label: 'HTML', icon: CupertinoIcons.doc_text, color: AppColors.primary),
  _ExportQuickEntry(
      label: 'PDF',
      icon: CupertinoIcons.doc_richtext,
      color: AppColors.danger),
  _ExportQuickEntry(
      label: 'Markdown',
      icon: CupertinoIcons.text_badge_plus,
      color: AppColors.accentPurple),
  _ExportQuickEntry(
      label: 'Anki',
      icon: CupertinoIcons.rectangle_stack,
      color: AppColors.warning),
  _ExportQuickEntry(
      label: 'CSV', icon: CupertinoIcons.table, color: AppColors.success),
  _ExportQuickEntry(
      label: 'JSON',
      icon: CupertinoIcons.square_stack_3d_up,
      color: AppColors.info),
];

class _ExportFormatChip extends StatelessWidget {
  const _ExportFormatChip({required this.entry});
  final _ExportQuickEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: entry.color.withValues(alpha: isDark ? 0.18 : 0.1),
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: InkWell(
        onTap: () => context.push('/settings/export-workbench'),
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(entry.icon, size: 14, color: entry.color),
              const SizedBox(width: 4),
              Text(
                entry.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: entry.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportHistoryTile extends StatelessWidget {
  const _ExportHistoryTile({required this.entry});
  final ExportHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(
        children: <Widget>[
          Icon(CupertinoIcons.checkmark_circle_fill,
              size: 14, color: AppColors.success.withValues(alpha: 0.7)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              '${entry.format} · ${entry.template} · ${entry.questionCount} 题',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            _formatRelativeTime(
                DateTime.fromMillisecondsSinceEpoch(entry.timestamp)),
            style: TextStyle(
                fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Phase 8-3：近 7 天学习趋势折线图区块。
///
/// 展示每日复习次数与掌握次数两条折线，无数据时显示空状态。
class _ReviewTrendSection extends StatelessWidget {
  const _ReviewTrendSection({required this.trend});

  final List<DailyReviewTrend> trend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalReviews = trend.fold<int>(0, (s, d) => s + d.reviewCount);
    final totalMastered = trend.fold<int>(0, (s, d) => s + d.masteredCount);
    final hasData = totalReviews > 0;

    final reviewSpots = <FlSpot>[];
    final masteredSpots = <FlSpot>[];
    for (var i = 0; i < trend.length; i += 1) {
      reviewSpots.add(FlSpot(i.toDouble(), trend[i].reviewCount.toDouble()));
      masteredSpots.add(FlSpot(i.toDouble(), trend[i].masteredCount.toDouble()));
    }
    final maxYValue = trend.fold<double>(
      0.0,
      (m, d) => d.reviewCount > m ? d.reviewCount.toDouble() : m,
    );
    final maxY = maxYValue < 1 ? 4.0 : maxYValue * 1.3;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.chart_bar_alt_fill,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpace.sm),
              const Text('学习趋势',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              Text('近 7 天',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: <Widget>[
              _TrendLegend(
                color: AppColors.primary,
                label: '复习',
                count: totalReviews,
              ),
              const SizedBox(width: AppSpace.md),
              _TrendLegend(
                color: AppColors.success,
                label: '掌握',
                count: totalMastered,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (hasData)
            SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4 > 1 ? maxY / 4 : 1,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          final d = trend[i].date;
                          final label = '${d.month}/${d.day}';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant)),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: maxY,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      tooltipRoundedRadius: 6,
                      getTooltipItems: (spots) {
                        return spots.map((s) {
                          final isReview = s.barIndex == 0;
                          return LineTooltipItem(
                            '${isReview ? '复习' : '掌握'} ${s.y.toInt()}',
                            TextStyle(
                              color: isReview
                                  ? AppColors.primary
                                  : AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: <LineChartBarData>[
                    LineChartBarData(
                      spots: reviewSpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      preventCurveOverShooting: true,
                      color: AppColors.primary,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    ),
                    LineChartBarData(
                      spots: masteredSpots,
                      isCurved: true,
                      curveSmoothness: 0.3,
                      preventCurveOverShooting: true,
                      color: AppColors.success,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.success.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 100,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(CupertinoIcons.chart_bar,
                        size: 28, color: colorScheme.onSurfaceVariant),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      '近 7 天暂无复习记录',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label $count',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
