import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/mistake_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/layout_provider_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_import_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_draft_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/capture_service.dart';
import 'package:smart_wrong_notebook/src/data/services/notification_service.dart';
import 'package:smart_wrong_notebook/src/data/services/ocr_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_region_crop_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_split_service.dart';
import 'package:smart_wrong_notebook/src/data/services/vision_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/recommendation.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_review_summary.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mapping_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_management_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mastery_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/recommendation_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';

// --- Repository providers (default implementations) ---

final Provider<QuestionRepository> questionRepositoryProvider =
    Provider<QuestionRepository>((ref) {
  return SharedPrefsQuestionRepository();
});

final Provider<LayoutProviderRepository> layoutProviderRepositoryProvider =
    Provider<LayoutProviderRepository>((ref) => LayoutProviderRepository());

final Provider<WorksheetImportRepository> worksheetImportRepositoryProvider =
    Provider<WorksheetImportRepository>((ref) => WorksheetImportRepository());

/// 受控知识点树仓库（Phase 4）。
final Provider<KnowledgePointRepository> knowledgePointRepositoryProvider =
    Provider<KnowledgePointRepository>((ref) => KnowledgePointRepository());

/// 题目—知识点关联仓库（Phase 4）。
final Provider<QuestionKnowledgeLinkRepository>
    questionKnowledgeLinkRepositoryProvider =
    Provider<QuestionKnowledgeLinkRepository>(
        (ref) => QuestionKnowledgeLinkRepository());

/// 「待确认知识点」队列仓库（Phase 4-C）。
/// AI 返回但未匹配到受控节点的知识点文本会被持久化到本队列，
/// 用户可在错题详情页手动映射或忽略。
final Provider<PendingKnowledgePointMappingRepository>
    pendingKnowledgePointMappingRepositoryProvider =
    Provider<PendingKnowledgePointMappingRepository>((ref) {
  return PendingKnowledgePointMappingRepository();
});

/// 错因—知识点—题目三元关联仓库（Phase 4）。
final Provider<MistakeKnowledgeLinkRepository>
    mistakeKnowledgeLinkRepositoryProvider =
    Provider<MistakeKnowledgeLinkRepository>(
        (ref) => MistakeKnowledgeLinkRepository());

/// 知识点树快照，供 UI 消费。调用 [knowledgePointRepositoryProvider] 加载后
/// 缓存在 StateController 中，通过 [_knowledgePointVersionProvider] 触发刷新。
final StateProvider<int> _knowledgePointVersionProvider =
    StateProvider<int>((ref) => 0);

final FutureProvider<List<KnowledgePoint>> knowledgePointTreeProvider =
    FutureProvider<List<KnowledgePoint>>((ref) async {
  ref.watch(_knowledgePointVersionProvider);
  return ref.read(knowledgePointRepositoryProvider).loadAll();
});

/// 知识点树变更后调用，刷新 [knowledgePointTreeProvider]。
void invalidateKnowledgePointTree(WidgetRef ref) {
  ref.read(_knowledgePointVersionProvider.notifier).state++;
}

/// 知识点映射服务（Phase 4）：AI 自由文本 → 受控知识点 ID。
/// Phase 4-C：注入 [PendingKnowledgePointMappingRepository]，
/// 未匹配文本会进入待确认队列供 UI 手动映射。
final Provider<KnowledgePointMappingService> knowledgePointMappingServiceProvider =
    Provider<KnowledgePointMappingService>((ref) {
  return KnowledgePointMappingService(
    ref.read(knowledgePointRepositoryProvider),
    ref.read(questionKnowledgeLinkRepositoryProvider),
    pendingRepo: ref.read(pendingKnowledgePointMappingRepositoryProvider),
  );
});

/// 知识点树管理服务（Phase 4）：CRUD、启用/停用、合并、首次播种。
final Provider<KnowledgePointManagementService>
    knowledgePointManagementServiceProvider =
    Provider<KnowledgePointManagementService>((ref) {
  return KnowledgePointManagementService(
    ref.read(knowledgePointRepositoryProvider),
  );
});

/// 知识点掌握度计算服务（Phase 4）。
final Provider<KnowledgePointMasteryService>
    knowledgePointMasteryServiceProvider =
    Provider<KnowledgePointMasteryService>((ref) {
  return KnowledgePointMasteryService(
    ref.read(questionKnowledgeLinkRepositoryProvider),
  );
});

/// 薄弱点推荐服务（Phase 4）。
final Provider<RecommendationService> recommendationServiceProvider =
    Provider<RecommendationService>((ref) {
  return RecommendationService();
});

/// 首页薄弱知识点推荐列表。
///
/// 聚合题目-知识点关联、复习日志和掌握度计算，调用
/// [RecommendationService.generate] 生成可解释推荐。依赖
/// [questionListProvider] 和 [reviewLogListProvider] 响应式刷新。
///
/// 返回值按推荐评分降序排列。无结构化关联数据时返回空列表
/// （首页 UI 会回退到旧的字符串 aiKnowledgePoints 统计）。
final FutureProvider<List<WeakPointRecommendation>>
    weakPointRecommendationsProvider =
    FutureProvider<List<WeakPointRecommendation>>((ref) async {
  // watch 响应式 provider，数据变更自动重算
  final questionsAsync = ref.watch(questionListProvider);
  final logsAsync = ref.watch(reviewLogListProvider);
  final questions = questionsAsync.maybeWhen(
    data: (q) => q,
    orElse: () => const <QuestionRecord>[],
  );
  final logs = logsAsync.maybeWhen(
    data: (l) => l,
    orElse: () => const <ReviewLog>[],
  );
  if (questions.isEmpty) return const <WeakPointRecommendation>[];

  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final kpRepo = ref.read(knowledgePointRepositoryProvider);
  final masteryService = ref.read(knowledgePointMasteryServiceProvider);
  final recommendationService = ref.read(recommendationServiceProvider);

  // 1. 按知识点 ID 分组题目
  final allLinks = await linkRepo.allLinks();
  if (allLinks.isEmpty) return const <WeakPointRecommendation>[];

  final questionIdsByKp = <String, Set<String>>{};
  for (final link in allLinks) {
    questionIdsByKp
        .putIfAbsent(link.knowledgePointId, () => <String>{})
        .add(link.questionId);
  }

  // 2. 计算每个知识点的掌握度
  final questionMap = {for (final q in questions) q.id: q};
  final questionsByKp = <String, List<QuestionRecord>>{};
  for (final entry in questionIdsByKp.entries) {
    final related = entry.value
        .map((id) => questionMap[id])
        .whereType<QuestionRecord>()
        .toList();
    if (related.isNotEmpty) questionsByKp[entry.key] = related;
  }
  if (questionsByKp.isEmpty) return const <WeakPointRecommendation>[];

  final reviewStatsByQuestion = <String, ReviewStats>{};
  for (final log in logs) {
    final stats = reviewStatsByQuestion[log.questionRecordId] ??
        ReviewStats(forgotCount: 0, hardCount: 0, easyCount: 0);
    // ReviewLog.result 是字符串：'forgot' / 'reviewing' / 'mastered' / 'reset'
    switch (log.result) {
      case 'forgot':
        reviewStatsByQuestion[log.questionRecordId] = ReviewStats(
          forgotCount: stats.forgotCount + 1,
          hardCount: stats.hardCount,
          easyCount: stats.easyCount,
          recentReviewDates: <DateTime>[...stats.recentReviewDates, log.reviewedAt],
        );
        break;
      case 'reviewing':
        reviewStatsByQuestion[log.questionRecordId] = ReviewStats(
          forgotCount: stats.forgotCount,
          hardCount: stats.hardCount + 1,
          easyCount: stats.easyCount,
          recentReviewDates: <DateTime>[...stats.recentReviewDates, log.reviewedAt],
        );
        break;
      case 'mastered':
        reviewStatsByQuestion[log.questionRecordId] = ReviewStats(
          forgotCount: stats.forgotCount,
          hardCount: stats.hardCount,
          easyCount: stats.easyCount + 1,
          recentReviewDates: <DateTime>[...stats.recentReviewDates, log.reviewedAt],
        );
        break;
      // 'reset' 或其他值不计入统计
    }
  }

  final masteries = await masteryService.calculateBatch(
    questionsByKp: questionsByKp,
    reviewStatsByQuestion: reviewStatsByQuestion,
  );
  final masteryByKp = {for (final m in masteries) m.knowledgePointId: m};

  // 3. 生成推荐
  final inputs = <RecommendationInput>[];
  for (final mastery in masteries) {
    if (mastery.totalQuestions == 0) continue;
    final relatedQuestions = questionsByKp[mastery.knowledgePointId] ?? const [];
    inputs.add(RecommendationInput(
      knowledgePointId: mastery.knowledgePointId,
      mastery: mastery,
      questionIds: relatedQuestions.map((q) => q.id).toList(),
      errorQuestionIds: relatedQuestions
          .where((q) => q.masteryLevel != MasteryLevel.mastered)
          .map((q) => q.id)
          .toList(),
      difficultyByQuestion: {
        for (final q in relatedQuestions)
          if (q.difficulty != null) q.id: q.difficulty!,
      },
    ));
  }
  if (inputs.isEmpty) return const <WeakPointRecommendation>[];

  final recommendations = await recommendationService.generate(inputs: inputs);

  // 4. 关联知识点名称和掌握度
  final kpNameById = {for (final kp in await kpRepo.loadAll()) kp.id: kp.name};
  return recommendations.map((rec) {
    final mastery = masteryByKp[rec.knowledgePointId];
    final pendingReview = questionsByKp[rec.knowledgePointId]
            ?.where((q) =>
                q.masteryLevel == MasteryLevel.reviewing ||
                q.masteryLevel == MasteryLevel.newQuestion)
            .length ??
        0;
    return WeakPointRecommendation(
      recommendation: rec,
      knowledgePointName: kpNameById[rec.knowledgePointId] ?? rec.knowledgePointId,
      mastery: mastery,
      pendingReviewCount: pendingReview,
    );
  }).toList();
});

/// 首页薄弱知识点推荐条目（含推荐、知识点名、掌握度）。
class WeakPointRecommendation {
  const WeakPointRecommendation({
    required this.recommendation,
    required this.knowledgePointName,
    required this.mastery,
    required this.pendingReviewCount,
  });

  final Recommendation recommendation;
  final String knowledgePointName;
  final KnowledgePointMastery? mastery;
  final int pendingReviewCount;
}

/// 待确认知识点队列版本号。每次队列变化（新增/映射/忽略）后递增，
/// 触发 [pendingKnowledgePointMappingsProvider] 重新加载。
final StateProvider<int> _pendingKnowledgePointVersionProvider =
    StateProvider<int>((ref) => 0);

/// 知识点树节点 + 掌握度聚合条目（Phase 5）。
///
/// 把 [knowledgePointTreeProvider] 的全部节点与
/// [weakPointRecommendationsProvider] 计算出的掌握度合并，
/// 供知识树页面按节点展示掌握度热力图与统计。
class KnowledgeTreeNodeView {
  const KnowledgeTreeNodeView({
    required this.point,
    this.mastery,
    this.pendingReviewCount = 0,
  });

  final KnowledgePoint point;
  final KnowledgePointMastery? mastery;
  final int pendingReviewCount;

  /// 掌握度百分比，无数据时返回 null。
  double? get masteryPercentage => mastery?.masteryPercentage;
}

/// 知识树页面聚合数据：全部知识点（带掌握度）+ 薄弱 TOP5 + 掌握度分布。
class KnowledgeTreeOverview {
  const KnowledgeTreeOverview({
    required this.nodes,
    required this.weakTop5,
    required this.masteredCount,
    required this.reviewingCount,
    required this.newCount,
  });

  /// 全部知识点节点（带掌握度，可能为 null）。
  final List<KnowledgeTreeNodeView> nodes;

  /// 薄弱知识点 TOP5（按掌握度升序，仅含有题目的知识点）。
  final List<KnowledgeTreeNodeView> weakTop5;

  /// 全局掌握度分布（按题目数汇总）。
  final int masteredCount;
  final int reviewingCount;
  final int newCount;
}

/// 知识树页面聚合 provider（Phase 5）。
///
/// 合并知识点树与掌握度计算，watch [weakPointRecommendationsProvider]
/// 以响应题目/复习日志变更。返回 [KnowledgeTreeOverview] 供页面消费。
final FutureProvider<KnowledgeTreeOverview> knowledgeTreeOverviewProvider =
    FutureProvider<KnowledgeTreeOverview>((ref) async {
  final treeAsync = ref.watch(knowledgePointTreeProvider);
  final recsAsync = ref.watch(weakPointRecommendationsProvider);
  final tree = treeAsync.maybeWhen(
    data: (d) => d,
    orElse: () => const <KnowledgePoint>[],
  );
  final recs = recsAsync.maybeWhen(
    data: (d) => d,
    orElse: () => const <WeakPointRecommendation>[],
  );

  // 掌握度映射：kpId -> WeakPointRecommendation
  final recByKp = {for (final r in recs) r.recommendation.knowledgePointId: r};

  final nodes = <KnowledgeTreeNodeView>[];
  var mastered = 0;
  var reviewing = 0;
  var newQ = 0;
  for (final kp in tree) {
    final rec = recByKp[kp.id];
    final mastery = rec?.mastery;
    nodes.add(KnowledgeTreeNodeView(
      point: kp,
      mastery: mastery,
      pendingReviewCount: rec?.pendingReviewCount ?? 0,
    ));
    if (mastery != null) {
      mastered += mastery.masteredCount;
      reviewing += mastery.reviewingCount;
      newQ += mastery.newCount;
    }
  }

  // 薄弱 TOP5：仅有掌握度且 totalQuestions>0 的节点，按掌握度升序
  final weak = nodes
      .where((n) => n.mastery != null && n.mastery!.totalQuestions > 0)
      .toList()
    ..sort((a, b) =>
        a.mastery!.masteryPercentage.compareTo(b.mastery!.masteryPercentage));

  return KnowledgeTreeOverview(
    nodes: nodes,
    weakTop5: weak.take(5).toList(),
    masteredCount: mastered,
    reviewingCount: reviewing,
    newCount: newQ,
  );
});

/// 按科目聚合的掌握度快照（Phase 8-2），供首页知识树区块展示。
class SubjectMasterySnapshot {
  const SubjectMasterySnapshot({
    required this.subject,
    required this.averageMastery,
    required this.knowledgePointCount,
    required this.pendingReviewCount,
  });

  final Subject subject;

  /// 该科目下所有有题目的知识点的掌握度平均值（0.0–100.0）。
  final double averageMastery;

  /// 该科目下有题目的知识点数量。
  final int knowledgePointCount;

  /// 该科目下待复习题目总数。
  final int pendingReviewCount;
}

/// Phase 8-2：按科目聚合掌握度快照，用于首页知识树区块。
///
/// watch [knowledgeTreeOverviewProvider] 响应知识点树与掌握度变更，
/// 按 `node.point.subject` 分组聚合 `mastery.masteryPercentage` 平均值。
/// 仅统计有 mastery 且 totalQuestions>0 的知识点；subject 为 null 的节点跳过。
final FutureProvider<List<SubjectMasterySnapshot>> subjectMasterySnapshotProvider =
    FutureProvider<List<SubjectMasterySnapshot>>((ref) async {
  final overview = ref.watch(knowledgeTreeOverviewProvider).maybeWhen(
        data: (d) => d,
        orElse: () => null,
      );
  if (overview == null) return const <SubjectMasterySnapshot>[];

  // 按 Subject 分组：累计掌握度总和 + 知识点计数 + 待复习题目数
  final bySubject = <Subject, _SubjectAccumulator>{};
  for (final node in overview.nodes) {
    final subject = node.point.subject;
    if (subject == null) continue;
    final mastery = node.mastery;
    if (mastery == null || mastery.totalQuestions == 0) continue;
    final acc = bySubject.putIfAbsent(subject, () => _SubjectAccumulator());
    acc.masterySum += mastery.masteryPercentage;
    acc.knowledgePointCount += 1;
    acc.pendingReviewCount += node.pendingReviewCount;
  }

  final snapshots = bySubject.entries.map((entry) {
    final acc = entry.value;
    return SubjectMasterySnapshot(
      subject: entry.key,
      averageMastery: acc.knowledgePointCount == 0
          ? 0.0
          : acc.masterySum / acc.knowledgePointCount,
      knowledgePointCount: acc.knowledgePointCount,
      pendingReviewCount: acc.pendingReviewCount,
    );
  }).toList()
    ..sort((a, b) => b.averageMastery.compareTo(a.averageMastery));
  return snapshots;
});

class _SubjectAccumulator {
  double masterySum = 0.0;
  int knowledgePointCount = 0;
  int pendingReviewCount = 0;
}

/// 近 7 天每日复习趋势条目（Phase 8-3），供首页折线图展示。
class DailyReviewTrend {
  const DailyReviewTrend({
    required this.date,
    required this.reviewCount,
    required this.masteredCount,
  });

  /// 当天 0 点的本地时间。
  final DateTime date;

  /// 当天复习次数（含所有 result）。
  final int reviewCount;

  /// 当天标记为"掌握"的次数（result == 'mastered'）。
  final int masteredCount;
}

/// Phase 8-3：近 7 天每日复习趋势，用于首页学习趋势折线图。
///
/// watch [reviewLogListProvider] 响应复习日志变更。返回从 6 天前到今天
/// 共 7 天的 [DailyReviewTrend] 列表（按日期升序），无复习的日子计数为 0。
final FutureProvider<List<DailyReviewTrend>> reviewTrend7DaysProvider =
    FutureProvider<List<DailyReviewTrend>>((ref) async {
  final logs = ref.watch(reviewLogListProvider).maybeWhen(
        data: (l) => l,
        orElse: () => const <ReviewLog>[],
      );
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final buckets = <DateTime, _DayAccumulator>{};
  for (var i = 6; i >= 0; i -= 1) {
    final day = today.subtract(Duration(days: i));
    buckets[day] = _DayAccumulator();
  }
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    final logDay = DateTime(at.year, at.month, at.day);
    final acc = buckets[logDay];
    if (acc == null) continue; // 不在近 7 天范围内
    acc.reviewCount += 1;
    if (log.result == 'mastered') acc.masteredCount += 1;
  }
  final sortedDays = buckets.keys.toList()..sort();
  return sortedDays
      .map((day) => DailyReviewTrend(
            date: day,
            reviewCount: buckets[day]!.reviewCount,
            masteredCount: buckets[day]!.masteredCount,
          ))
      .toList();
});

class _DayAccumulator {
  int reviewCount = 0;
  int masteredCount = 0;
}

/// 知识点详情页数据（Phase 5）：知识点 + 关联题目列表 + 掌握度。
class KnowledgePointDetail {
  const KnowledgePointDetail({
    required this.point,
    required this.questions,
    this.mastery,
  });

  final KnowledgePoint point;
  final List<QuestionRecord> questions;
  final KnowledgePointMastery? mastery;
}

/// 按知识点 ID 加载详情（Phase 5）。
///
/// watch [questionListProvider] 和 [knowledgePointTreeProvider] 以响应
/// 题目/知识点树变更。返回该知识点关联的题目列表与掌握度快照。
final FutureProviderFamily<KnowledgePointDetail, String>
    knowledgePointDetailProvider =
    FutureProvider.family<KnowledgePointDetail, String>(
        (ref, knowledgePointId) async {
  final tree = await ref.watch(knowledgePointTreeProvider.future);
  final point = tree.firstWhere(
    (kp) => kp.id == knowledgePointId,
    orElse: () => KnowledgePoint(
      id: knowledgePointId,
      name: '未知知识点',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final questionIds = await linkRepo.questionIdsForKnowledgePoint(knowledgePointId);
  final allQuestions = ref.watch(questionListProvider).maybeWhen(
        data: (q) => q,
        orElse: () => const <QuestionRecord>[],
      );
  final idSet = questionIds.toSet();
  final questions =
      allQuestions.where((q) => idSet.contains(q.id)).toList();

  // 掌握度：从 overview 的 nodes 中取（若该知识点有题）
  final overview = ref.watch(knowledgeTreeOverviewProvider).maybeWhen(
        data: (d) => d,
        orElse: () => null,
      );
  final mastery = overview?.nodes
      .firstWhere(
        (n) => n.point.id == knowledgePointId,
        orElse: () => KnowledgeTreeNodeView(
          point: point,
          mastery: null,
        ),
      )
      .mastery;

  return KnowledgePointDetail(
    point: point,
    questions: questions,
    mastery: mastery,
  );
});

/// 通知待确认知识点队列已变更，刷新 [pendingKnowledgePointMappingsProvider]。
void invalidatePendingKnowledgePoints(WidgetRef ref) {
  ref.read(_pendingKnowledgePointVersionProvider.notifier).state++;
}

/// 全部待确认知识点列表（仅未处理项）。
///
/// Phase 4-C：消费 [PendingKnowledgePointMappingRepository.allPending]，
/// watch [_pendingKnowledgePointVersionProvider] 以在队列变更后响应式刷新。
final FutureProvider<List<PendingKnowledgePointMapping>>
    pendingKnowledgePointMappingsProvider =
    FutureProvider<List<PendingKnowledgePointMapping>>((ref) async {
  ref.watch(_pendingKnowledgePointVersionProvider);
  final repo = ref.read(pendingKnowledgePointMappingRepositoryProvider);
  return repo.allPending();
});

/// 指定题目下的待确认知识点列表。watch 全局版本号以响应队列变更。
final FutureProviderFamily<List<PendingKnowledgePointMapping>, String>
    pendingKnowledgePointsForQuestionProvider =
    FutureProvider.family<List<PendingKnowledgePointMapping>, String>(
        (ref, questionId) async {
  ref.watch(_pendingKnowledgePointVersionProvider);
  final repo = ref.read(pendingKnowledgePointMappingRepositoryProvider);
  return repo.pendingForQuestion(questionId);
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) {
  return SharedPrefsSettingsRepository.instance;
});

// Production overrides this with a real OnboardingNotifier in main().
final Provider<OnboardingNotifier> onboardingNotifierProvider =
    Provider<OnboardingNotifier>((ref) {
  return OnboardingNotifier(initialDone: true);
});

// Production overrides this with DriftReviewLogRepository in main().
final Provider<ReviewLogRepository> reviewLogRepositoryProvider =
    Provider<ReviewLogRepository>((ref) => InMemoryReviewLogRepository());

// --- Service providers ---

final Provider<AiAnalysisService> aiAnalysisServiceProvider =
    Provider<AiAnalysisService>((ref) {
  return AiAnalysisService(
      settingsRepository: ref.read(settingsRepositoryProvider));
});

final Provider<ImageStorageService> imageStorageServiceProvider =
    Provider<ImageStorageService>((ref) {
  return ImageStorageService();
});

final Provider<OcrService> ocrServiceProvider = Provider<OcrService>((ref) {
  return OcrService();
});

final Provider<VisionDocumentLayoutService> visionDocumentLayoutServiceProvider =
    Provider<VisionDocumentLayoutService>((ref) {
  return VisionDocumentLayoutService(ref.read(aiAnalysisServiceProvider));
});

final Provider<QuestionRegionCropService> questionRegionCropServiceProvider =
    Provider<QuestionRegionCropService>((ref) {
  return QuestionRegionCropService(
      storage: ref.read(imageStorageServiceProvider));
});

final Provider<QuestionSplitService> questionSplitServiceProvider =
    Provider<QuestionSplitService>((ref) {
  return QuestionSplitService(
      aiAnalysisService: ref.read(aiAnalysisServiceProvider));
});

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((ref) {
  return NotificationService(
      questionRepository: ref.read(questionRepositoryProvider));
});

final Provider<CaptureService> captureServiceProvider =
    Provider<CaptureService>((ref) {
  return CaptureService(storage: ref.read(imageStorageServiceProvider));
});

// --- Current question flow ---

final StateProvider<QuestionRecord?> currentQuestionProvider =
    StateProvider<QuestionRecord?>((ref) => null);

enum PracticeContextSource { analysis, notebook }

class PracticeContext {
  const PracticeContext({
    required this.source,
    this.candidateId,
    this.candidateOrder,
    required this.returnRoute,
  });

  final PracticeContextSource source;
  final String? candidateId;
  final int? candidateOrder;
  final String returnRoute;
}

final StateProvider<PracticeContext?> currentPracticeContextProvider =
    StateProvider<PracticeContext?>((ref) => null);

final StateProvider<QuestionSplitSession?> currentQuestionSplitSessionProvider =
    StateProvider<QuestionSplitSession?>((ref) => null);

/// Holds selected worksheet pages while the user processes them one by one.
/// Persistence/queueing is intentionally added in the next import slice.
final StateProvider<LayoutProviderConfig> layoutProviderConfigProvider =
    StateProvider<LayoutProviderConfig>((ref) =>
        const LayoutProviderConfig(type: LayoutProviderType.currentVision));

final StateProvider<LayoutProviderType?> oneShotLayoutProviderTypeProvider =
    StateProvider<LayoutProviderType?>((ref) => null);

Future<LayoutProviderConfig> restoreLayoutProviderConfig(WidgetRef ref) async {
  final config = await ref.read(layoutProviderRepositoryProvider).load();
  ref.read(layoutProviderConfigProvider.notifier).state = config;
  return config;
}

Future<void> persistLayoutProviderConfig(
    WidgetRef ref, LayoutProviderConfig config) async {
  await ref.read(layoutProviderRepositoryProvider).save(config);
  ref.read(layoutProviderConfigProvider.notifier).state = config;
}

final StateProvider<List<String>> worksheetDraftQuestionIdsProvider =
    StateProvider<List<String>>((ref) => const <String>[]);

/// Phase 8-4：试卷预览页要展示的题目 ID 列表（保留顺序）。
///
/// 工作台预览按钮写入后跳 `/worksheet/preview`，预览页首帧读取。
final StateProvider<List<String>> worksheetPreviewQuestionIdsProvider =
    StateProvider<List<String>>((ref) => const <String>[]);

/// 组卷草稿与历史组卷仓库（Phase 5）。
final Provider<WorksheetDraftRepository> worksheetDraftRepositoryProvider =
    Provider<WorksheetDraftRepository>((ref) {
  return WorksheetDraftRepository();
});

/// 所有已保存的组卷草稿（按 updatedAt 降序）。
/// 在工作台「历史」对话框中消费；保存/删除后调用 invalidate 刷新。
final FutureProvider<List<WorksheetDraft>> savedWorksheetDraftsProvider =
    FutureProvider<List<WorksheetDraft>>((ref) {
  return ref.watch(worksheetDraftRepositoryProvider).loadAll();
});

final StateProvider<WorksheetImportSession?> currentWorksheetImportProvider =
    StateProvider<WorksheetImportSession?>((ref) => null);

/// 从持久化仓库恢复上次未完成的导入批次。
///
/// 在 app 启动时调用，避免 App 被系统杀掉后批次状态丢失。
/// 返回恢复的 session（同时写入 [currentWorksheetImportProvider]）；
/// 无草稿时返回 null。
Future<WorksheetImportSession?> restoreWorksheetImport(WidgetRef ref) async {
  final restored = await ref.read(worksheetImportRepositoryProvider).load();
  ref.read(currentWorksheetImportProvider.notifier).state = restored;
  return restored;
}

/// 仅读取持久化仓库中的批次，不依赖 WidgetRef。
/// 用于 app 启动时（ProviderScope 尚未建立）预加载批次。
Future<WorksheetImportSession?> loadWorksheetImportSession(
    WorksheetImportRepository repository) async {
  return repository.load();
}

Future<void> persistWorksheetImport(
    WidgetRef ref, WorksheetImportSession? session) async {
  final repository = ref.read(worksheetImportRepositoryProvider);
  if (session == null) {
    await repository.clear();
  } else {
    await repository.save(session);
  }
  ref.read(currentWorksheetImportProvider.notifier).state = session;
}

final StateProvider<WorksheetReviewSummary?> currentWorksheetReviewSummaryProvider =
    StateProvider<WorksheetReviewSummary?>((ref) => null);

/// Whether the worksheet importer should continue through remaining question
/// candidates without opening a result page after every successful analysis.
final StateProvider<bool> worksheetAutoAnalyzeProvider =
    StateProvider<bool>((ref) => false);

/// 统一更新 [worksheetAutoAnalyzeProvider] 并把状态同步进当前 session（持久化）。
///
/// 在跨进程恢复时，[WorksheetImportRepository.load] 会从持久化读回 autoAnalyze，
/// 启动后由 main.dart 通过 override 写入 [worksheetAutoAnalyzeProvider]；运行期
/// 调用本 helper 才能保证两者一致。session 不存在时仅更新内存状态（兼容单题
/// 流程或测试场景）。
Future<void> setWorksheetAutoAnalyze(WidgetRef ref, bool value) async {
  ref.read(worksheetAutoAnalyzeProvider.notifier).state = value;
  final session = ref.read(currentWorksheetImportProvider);
  if (session == null || session.autoAnalyze == value) return;
  await persistWorksheetImport(ref, session.copyWith(autoAnalyze: value));
}

Future<QuestionSplitSession> buildQuestionSplitSession(
  QuestionRecord source, {
  QuestionSplitService splitter = const QuestionSplitService(),
}) async {
  final result = source.splitResult ??
      await _resolveSplitResult(source, splitter: splitter);

  final hasMultipleCandidates = result.hasMultipleCandidates;

  return QuestionSplitSession(
    source: source,
    strategy: result.strategy,
    drafts: result.candidates.map((candidate) {
      final snapshot = source.candidateAnalyses
          .where((analysis) => analysis.order == candidate.order)
          .cast<CandidateAnalysisSnapshot?>()
          .firstWhere((analysis) => analysis != null, orElse: () => null);
      final canSave =
          !hasMultipleCandidates || (snapshot?.isSuccessful ?? false);
      return QuestionSplitDraft(
        id: '${source.id}-${candidate.order - 1}',
        text: candidate.text,
        selected: canSave,
        originalOrder: candidate.order,
        contentFormat: source.contentFormat,
        canSave: canSave,
        disabledReason: canSave ? null : '解析失败，暂不可保存',
      );
    }).toList(),
  );
}

Future<QuestionSplitResult> _resolveSplitResult(
  QuestionRecord source, {
  required QuestionSplitService splitter,
}) async {
  final normalized = source.normalizedQuestionText.trim();
  final extracted = source.extractedQuestionText.trim();
  final seedText = normalized.isNotEmpty ? normalized : extracted;
  return splitter.split(seedText, subject: source.subject);
}

QuestionRecord buildSplitQuestionRecord({
  required QuestionRecord source,
  required QuestionSplitDraft draft,
  required int sortOrder,
}) {
  final trimmedText = draft.text.trim();
  final now = DateTime.now();
  final candidateSnapshot = source.candidateAnalyses
      .where((candidate) {
        return candidate.order == draft.originalOrder;
      })
      .cast<CandidateAnalysisSnapshot?>()
      .firstWhere(
        (candidate) => candidate != null,
        orElse: () => null,
      );
  final hasMultipleCandidates =
      source.splitResult?.hasMultipleCandidates ?? false;
  final analysisResult = candidateSnapshot?.analysisResult ??
      (hasMultipleCandidates ? null : source.analysisResult);
  final savedExercises = (candidateSnapshot?.savedExercises ??
          (hasMultipleCandidates
              ? const <GeneratedExercise>[]
              : source.savedExercises))
      .asMap()
      .entries
      .map((entry) {
    final order = entry.value.order ?? entry.key;
    final roundIndex = entry.value.roundIndex ?? 1;
    return entry.value.copyWith(
      id: '${source.id}-$sortOrder-round-$roundIndex-exercise-${order + 1}',
      questionId: '${source.id}-$sortOrder',
      order: order,
    );
  }).toList();
  final aiTags = candidateSnapshot?.aiTags ??
      (hasMultipleCandidates ? const <String>[] : source.aiTags);
  final aiKnowledgePoints = candidateSnapshot?.aiKnowledgePoints ??
      (hasMultipleCandidates ? const <String>[] : source.aiKnowledgePoints);
  final subject =
      candidateSnapshot?.subject ?? analysisResult?.subject ?? source.subject;

  return QuestionRecord(
    id: '${source.id}-$sortOrder',
    imagePath: source.imagePath,
    subject: subject,
    extractedQuestionText: trimmedText,
    normalizedQuestionText: trimmedText,
    contentFormat: draft.contentFormat ?? source.contentFormat,
    tags: source.tags,
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: source.contentStatus,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: analysisResult,
    savedExercises: savedExercises,
    aiTags: aiTags,
    aiKnowledgePoints: aiKnowledgePoints,
    customTags: source.customTags,
    parentQuestionId: source.id,
    rootQuestionId: source.rootQuestionId ?? source.id,
    splitOrder: sortOrder,
  );
}

// --- Internal version counter for cache invalidation ---
//
// 保留 `invalidateQuestionList` 作为显式刷新入口（兼容旧调用方与
// 非 Drift 仓库），核心数据 provider 已改为 StreamProvider 响应式订阅，
// 无需手动 invalidate 即可自动更新。

final StateProvider<int> _listVersionProvider = StateProvider<int>((ref) => 0);

/// Call after any mutation (save, delete, review) to refresh list/review providers.
void invalidateQuestionList(WidgetRef ref) {
  ref.read(_listVersionProvider.notifier).state++;
}

// --- All questions list (reactive) ---

/// 全量题目列表，基于 Drift `watch()` 响应式更新，表变更自动推送新快照。
/// 非 Drift 仓库回退到 `watchAll()` 默认实现（一次性 Future）。
final StreamProvider<List<QuestionRecord>> questionListProvider =
    StreamProvider<List<QuestionRecord>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.read(questionRepositoryProvider).watchAll();
});

final StreamProvider<List<ReviewLog>> reviewLogListProvider =
    StreamProvider<List<ReviewLog>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.read(reviewLogRepositoryProvider).watchAll();
});

/// 按题目 ID 查询复习历史（Phase 6-5）。详情页记录 Tab 展示时间线用。
/// 监听 [_listVersionProvider] 以便复习后（invalidate 列表版本）自动刷新。
final FutureProviderFamily<List<ReviewLog>, String>
    reviewLogsForQuestionProvider =
        FutureProviderFamily<List<ReviewLog>, String>((ref, questionId) {
  ref.watch(_listVersionProvider);
  return ref.read(reviewLogRepositoryProvider).getByQuestionId(questionId);
});

/// 题目—知识点结构化关联视图（Phase 6-3）。
///
/// 把 [QuestionKnowledgeLink] 与 [KnowledgePoint] 名称、知识点掌握度
/// （从 [weakPointRecommendationsProvider] 取，无题目关联时为 null）
/// 合并成单条 UI 视图，供详情页「知识点关联」区块直接渲染。
class StructuredKnowledgeLinkView {
  const StructuredKnowledgeLinkView({
    required this.link,
    required this.knowledgePoint,
    this.masteryPercentage,
  });

  final QuestionKnowledgeLink link;
  final KnowledgePoint knowledgePoint;

  /// 知识点掌握度百分比 0–100。无题目关联或未参与计算时为 null。
  final double? masteryPercentage;

  bool get isPrimary => link.isPrimary;
}

/// 按题目 ID 查询结构化关联列表（含知识点名 + 掌握度）。
///
/// 监听 [_listVersionProvider] 以便关联变更（add/remove/setPrimary）
/// 后自动刷新。
final FutureProviderFamily<List<StructuredKnowledgeLinkView>, String>
    structuredKnowledgeLinksProvider =
        FutureProviderFamily<List<StructuredKnowledgeLinkView>, String>(
            (ref, questionId) async {
  ref.watch(_listVersionProvider);
  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final kpRepo = ref.read(knowledgePointRepositoryProvider);
  final links = await linkRepo.linksForQuestion(questionId);
  if (links.isEmpty) return const <StructuredKnowledgeLinkView>[];

  final allPoints = await kpRepo.loadAll();
  final kpById = {for (final kp in allPoints) kp.id: kp};

  // 掌握度从 weakPointRecommendationsProvider 取（仅有题目关联的知识点）。
  final recommendations =
      ref.read(weakPointRecommendationsProvider).maybeWhen(
            data: (r) => r,
            orElse: () => const <WeakPointRecommendation>[],
          );
  final masteryByKp = <String, double>{
    for (final r in recommendations)
      if (r.mastery != null) r.recommendation.knowledgePointId: r.mastery!.masteryPercentage,
  };

  final views = <StructuredKnowledgeLinkView>[];
  for (final link in links) {
    final kp = kpById[link.knowledgePointId];
    if (kp == null) continue;
    views.add(StructuredKnowledgeLinkView(
      link: link,
      knowledgePoint: kp,
      masteryPercentage: masteryByKp[link.knowledgePointId],
    ));
  }
  return views;
});

class QuestionBatchGroup {
  const QuestionBatchGroup({required this.rootId, required this.questions});

  final String rootId;
  final List<QuestionRecord> questions;
}

final StreamProvider<Map<String, QuestionBatchGroup>>
    questionBatchGroupsProvider =
    StreamProvider<Map<String, QuestionBatchGroup>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) => Stream.value(buildQuestionBatchGroups(all)),
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

Map<String, QuestionBatchGroup> buildQuestionBatchGroups(
    List<QuestionRecord> questions) {
  final grouped = <String, List<QuestionRecord>>{};

  for (final question in questions) {
    final rootId = _questionBatchRootId(question);
    if (rootId == null) continue;
    grouped.putIfAbsent(rootId, () => <QuestionRecord>[]).add(question);
  }

  final result = <String, QuestionBatchGroup>{};
  for (final entry in grouped.entries) {
    if (entry.value.length < 2) continue;
    final sorted = [...entry.value]..sort(_compareBatchQuestions);
    result[entry.key] =
        QuestionBatchGroup(rootId: entry.key, questions: sorted);
  }
  return result;
}

String? questionBatchRootId(QuestionRecord question) =>
    _questionBatchRootId(question);

String? _questionBatchRootId(QuestionRecord question) {
  final rootId = question.rootQuestionId ?? question.parentQuestionId;
  return rootId == null || rootId.isEmpty ? null : rootId;
}

int _compareBatchQuestions(QuestionRecord a, QuestionRecord b) {
  final orderA = a.splitOrder;
  final orderB = b.splitOrder;
  if (orderA != null && orderB != null && orderA != orderB) {
    return orderA.compareTo(orderB);
  }
  if (orderA != null && orderB == null) return -1;
  if (orderA == null && orderB != null) return 1;
  final created = a.createdAt.compareTo(b.createdAt);
  if (created != 0) return created;
  return a.id.compareTo(b.id);
}

// --- Questions due for review ---

final StreamProvider<List<QuestionRecord>> dueReviewProvider =
    StreamProvider<List<QuestionRecord>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          const scheduler = ReviewScheduleService();
          return Stream.value(all.where(scheduler.isDue).toList());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- Today's review plan ---

class TodayReviewPlan {
  const TodayReviewPlan({
    required this.dueCount,
    required this.completedCount,
    required this.streakDays,
  });

  final int dueCount;
  final int completedCount;
  final int streakDays;

  int get targetCount => dueCount + completedCount;
  int get estimatedMinutes => dueCount * 3;
}

final StreamProvider<TodayReviewPlan> todayReviewPlanProvider =
    StreamProvider<TodayReviewPlan>((ref) async* {
  ref.watch(_listVersionProvider);
  const scheduler = ReviewScheduleService();
  // 等待题目和复习记录两个流的首个快照，再计算计划。
  // _listVersionProvider 变化时整个 StreamProvider 会重建，触发重新计算；
  // Drift watchAll() 在表变更时也会推动 questionListProvider/reviewLogListProvider
  // 发出新值，通过 _listVersionProvider 间接触发刷新（保持兼容）。
  final questions = await ref.read(questionListProvider.future);
  final logs = await ref.read(reviewLogListProvider.future);
  final now = DateTime.now();
  final completedIds = <String>{};
  final reviewedDays = <DateTime>{};
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    reviewedDays.add(day);
    if (day == DateTime(now.year, now.month, now.day)) {
      completedIds.add(log.questionRecordId);
    }
  }
  var streak = 0;
  var day = DateTime(now.year, now.month, now.day);
  while (reviewedDays.contains(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  yield TodayReviewPlan(
    dueCount: questions.where(scheduler.isDue).length,
    completedCount: completedIds.length,
    streakDays: streak,
  );
});

// --- Mistake category statistics ---

final StreamProvider<Map<MistakeCategory, int>> mistakeCategoryStatsProvider =
    StreamProvider<Map<MistakeCategory, int>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final stats = <MistakeCategory, int>{};
          for (final question in all) {
            final category = question.mistakeCategory;
            if (category != null) stats[category] = (stats[category] ?? 0) + 1;
          }
          return Stream.value(stats);
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- Notebook filter state ---

final StateProvider<Subject?> selectedSubjectFilterProvider =
    StateProvider<Subject?>((ref) => null);

final StateProvider<MasteryLevel?> selectedMasteryFilterProvider =
    StateProvider<MasteryLevel?>((ref) => null);

final StateProvider<bool> unmasteredOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<MistakeCategory?> selectedMistakeCategoryFilterProvider =
    StateProvider<MistakeCategory?>((ref) => null);

enum QuestionSort { newest, oldest, nextReview, mastery, subject }

enum QuestionDateRange { all, last7Days, last30Days }

final StateProvider<QuestionDateRange> questionDateRangeProvider =
    StateProvider<QuestionDateRange>((ref) => QuestionDateRange.all);

final StateProvider<bool> dueOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> favoritesOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> failedOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

/// 仅显示识别失败题目（ContentStatus.failed → recognitionFailed）。
/// 与 [failedOnlyFilterProvider] 互补：后者同时匹配识别失败与分析失败，
/// 此 Provider 仅匹配识别失败，便于首页"分开统计识别失败与 AI 分析失败"。
final StateProvider<bool> recognitionFailedOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

/// 仅显示 AI 分析失败题目（ContentStatus.analysisFailed → analysisFailed）。
final StateProvider<bool> analysisFailedOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

/// 仅显示待校对题目（OCR 已成功但低置信度，需人工确认）。
/// 与 [pendingAiOnlyFilterProvider] 互补：后者仅匹配 recognized 状态，
/// 此 Provider 额外要求 ocrConfidence < 0.7，便于首页"分开统计待校对与低置信度"。
final StateProvider<bool> pendingProofreadOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> pendingAiOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> lowConfidenceOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<QuestionSort> questionSortProvider =
    StateProvider<QuestionSort>((ref) => QuestionSort.newest);

final StateProvider<String?> selectedSourceFilterProvider =
    StateProvider<String?>((ref) => null);

final StateProvider<String?> selectedLearningStageFilterProvider =
    StateProvider<String?>((ref) => null);

final StateProvider<QuestionDifficulty?> selectedDifficultyFilterProvider =
    StateProvider<QuestionDifficulty?>((ref) => null);

final StateProvider<AttemptStatus?> selectedAttemptStatusFilterProvider =
    StateProvider<AttemptStatus?>((ref) => null);

/// 题型筛选（Phase 6-2）。`null` 表示不限制题型。
final StateProvider<QuestionType?> selectedQuestionTypeFilterProvider =
    StateProvider<QuestionType?>((ref) => null);

final StateProvider<String> searchQueryProvider =
    StateProvider<String>((ref) => '');

final StateProvider<String?> selectedKnowledgePointFilterProvider =
    StateProvider<String?>((ref) => null);

// 多选标签过滤
final StateProvider<List<String>> selectedTagsFilterProvider =
    StateProvider<List<String>>((ref) => []);

final StreamProvider<List<String>> allLearningStagesProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) => Stream.value(all
            .map((question) => question.learningStage)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort()),
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

final StreamProvider<List<String>> allSourcesProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final sources = all
              .map((question) => question.source)
              .whereType<String>()
              .toSet();
          return Stream.value(sources.toList()..sort());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- All tags provider ---
final StreamProvider<List<String>> allTagsProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final tags = <String>{};
          for (final q in all) {
            tags.addAll(q.aiTags);
            tags.addAll(q.aiKnowledgePoints);
            tags.addAll(q.customTags);
          }
          return Stream.value(tags.toList()..sort());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

final StreamProvider<List<String>> allKnowledgePointsProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(_listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final points = <String>{};
          for (final question in all) {
            points.addAll(question.aiKnowledgePoints);
          }
          return Stream.value(points.toList()..sort());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- Filtered notebook list ---

final StreamProvider<List<QuestionRecord>> filteredQuestionListProvider =
    StreamProvider<List<QuestionRecord>>((ref) {
  ref.watch(_listVersionProvider);

  final subject = ref.watch(selectedSubjectFilterProvider);
  final mastery = ref.watch(selectedMasteryFilterProvider);
  final unmasteredOnly = ref.watch(unmasteredOnlyFilterProvider);
  final mistakeCategory = ref.watch(selectedMistakeCategoryFilterProvider);
  final dueOnly = ref.watch(dueOnlyFilterProvider);
  final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
  final failedOnly = ref.watch(failedOnlyFilterProvider);
  final recognitionFailedOnly = ref.watch(recognitionFailedOnlyFilterProvider);
  final analysisFailedOnly = ref.watch(analysisFailedOnlyFilterProvider);
  final pendingProofreadOnly = ref.watch(pendingProofreadOnlyFilterProvider);
  final pendingAiOnly = ref.watch(pendingAiOnlyFilterProvider);
  final lowConfidenceOnly = ref.watch(lowConfidenceOnlyFilterProvider);
  final dateRange = ref.watch(questionDateRangeProvider);
  final source = ref.watch(selectedSourceFilterProvider);
  final learningStage = ref.watch(selectedLearningStageFilterProvider);
  final difficulty = ref.watch(selectedDifficultyFilterProvider);
  final attemptStatus = ref.watch(selectedAttemptStatusFilterProvider);
  final questionType = ref.watch(selectedQuestionTypeFilterProvider);
  final sort = ref.watch(questionSortProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final knowledgePoint = ref.watch(selectedKnowledgePointFilterProvider);
  final selectedTags = ref.watch(selectedTagsFilterProvider);

  const scheduler = ReviewScheduleService();
  final now = DateTime.now();

  return ref.watch(questionListProvider).when(
        data: (all) {
          final filtered = all.where((QuestionRecord q) {
            if (subject != null && q.subject != subject) return false;
            if (mastery != null && q.masteryLevel != mastery) return false;
            if (unmasteredOnly && q.masteryLevel == MasteryLevel.mastered) {
              return false;
            }
            if (mistakeCategory != null && q.mistakeCategory != mistakeCategory) {
              return false;
            }
            if (dueOnly && !scheduler.isDue(q)) return false;
            if (favoritesOnly && !q.isFavorite) return false;
            if (failedOnly && !inferQuestionDisplayStatus(q).isFailed) {
              return false;
            }
            if (recognitionFailedOnly &&
                inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.recognitionFailed) {
              return false;
            }
            if (analysisFailedOnly &&
                inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.analysisFailed) {
              return false;
            }
            if (pendingProofreadOnly &&
                !(inferQuestionDisplayStatus(q) ==
                        QuestionDisplayStatus.recognized &&
                    q.ocrConfidence != null &&
                    q.ocrConfidence! < 0.7)) {
              return false;
            }
            if (pendingAiOnly &&
                inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.recognized) {
              return false;
            }
            if (lowConfidenceOnly &&
                !(q.ocrConfidence != null && q.ocrConfidence! < 0.7)) {
              return false;
            }
            if (!_isWithinDateRange(q.createdAt, dateRange, now)) return false;
            if (source != null && q.source != source) return false;
            if (learningStage != null && q.learningStage != learningStage) {
              return false;
            }
            if (difficulty != null && q.difficulty != difficulty) return false;
            if (attemptStatus != null && q.attemptStatus != attemptStatus) {
              return false;
            }
            if (questionType != null && q.questionType != questionType) {
              return false;
            }
            if (query.isNotEmpty &&
                !q.normalizedQuestionText.toLowerCase().contains(query)) {
              return false;
            }
            if (knowledgePoint != null && knowledgePoint.isNotEmpty) {
              final kps = q.aiKnowledgePoints;
              if (!kps.any((kp) => kp.contains(knowledgePoint))) return false;
            }
            if (selectedTags.isNotEmpty) {
              final allQTags = [...q.aiKnowledgePoints, ...q.customTags];
              for (final tag in selectedTags) {
                if (!allQTags.any((t) => t.contains(tag))) return false;
              }
            }
            return true;
          }).toList();

          filtered.sort((a, b) {
            switch (sort) {
              case QuestionSort.newest:
                return b.createdAt.compareTo(a.createdAt);
              case QuestionSort.oldest:
                return a.createdAt.compareTo(b.createdAt);
              case QuestionSort.nextReview:
                final aAt = a.nextReviewAt ?? a.createdAt;
                final bAt = b.nextReviewAt ?? b.createdAt;
                return aAt.compareTo(bAt);
              case QuestionSort.mastery:
                // 掌握度低到高：newQuestion(0) → reviewing(1) → mastered(2)，
                // 同档内按最新录入优先，便于优先处理最需要关注的题。
                final byMastery =
                    a.masteryLevel.index.compareTo(b.masteryLevel.index);
                if (byMastery != 0) return byMastery;
                return b.createdAt.compareTo(a.createdAt);
              case QuestionSort.subject:
                // 按科目 label 排序，同科目内按最新录入优先。
                final bySubject = a.subject.label.compareTo(b.subject.label);
                if (bySubject != 0) return bySubject;
                return b.createdAt.compareTo(a.createdAt);
            }
          });
          return Stream.value(filtered);
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

bool _isWithinDateRange(
  DateTime createdAt,
  QuestionDateRange range,
  DateTime now,
) {
  switch (range) {
    case QuestionDateRange.all:
      return true;
    case QuestionDateRange.last7Days:
      return !createdAt.isBefore(now.subtract(const Duration(days: 7)));
    case QuestionDateRange.last30Days:
      return !createdAt.isBefore(now.subtract(const Duration(days: 30)));
  }
}

// --- Theme mode ---

final StateNotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.read(settingsRepositoryProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._settingsRepo) : super(ThemeMode.system) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('theme_mode');
    final mode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    state = mode;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _settingsRepo.setString('theme_mode', value);
  }
}

final StateNotifierProvider<ReviewReminderNotifier, bool> reviewReminderEnabledProvider =
    StateNotifierProvider<ReviewReminderNotifier, bool>((ref) {
  return ReviewReminderNotifier(ref.read(settingsRepositoryProvider));
});

class ReviewReminderNotifier extends StateNotifier<bool> {
  ReviewReminderNotifier(this._settingsRepo) : super(true) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('review_reminder_enabled');
    state = value != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _settingsRepo.setString('review_reminder_enabled', enabled ? 'true' : 'false');
  }
}

/// Phase 9-3：定时复习提醒时间（24 小时制）。
///
/// 默认 20:00，持久化到 settings 仓库的 `review_reminder_time` 字段
/// （格式 `HH:MM`）。开启 [reviewReminderEnabledProvider] 后由调用方
/// 读取本 provider 并调用 [NotificationService.scheduleDailyReminder]。
final StateNotifierProvider<ReviewReminderTimeNotifier, TimeOfDay>
    reviewReminderTimeProvider = StateNotifierProvider<ReviewReminderTimeNotifier,
        TimeOfDay>((ref) {
  return ReviewReminderTimeNotifier(ref.read(settingsRepositoryProvider));
});

class ReviewReminderTimeNotifier extends StateNotifier<TimeOfDay> {
  ReviewReminderTimeNotifier(this._settingsRepo)
      : super(const TimeOfDay(hour: 20, minute: 0)) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('review_reminder_time');
    if (value == null || !value.contains(':')) return;
    final parts = value.split(':');
    if (parts.length != 2) return;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return;
    if (h < 0 || h > 23 || m < 0 || m > 59) return;
    state = TimeOfDay(hour: h, minute: m);
  }

  Future<void> setTime(TimeOfDay time) async {
    state = time;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    await _settingsRepo.setString('review_reminder_time', '$hh:$mm');
  }
}

// --- Capture mode (printed / handwritten / mixed) ---
//
// 录入时用户选择的识别模式，决定 AI 识别时如何处理图片中的印刷与手写内容。
// 默认 [CaptureMode.printed]，与原有"忽略手写批改"行为保持一致。
final StateProvider<CaptureMode> captureModeProvider =
    StateProvider<CaptureMode>((ref) => CaptureMode.printed);
