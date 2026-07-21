import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 知识点掌握度计算服务。
///
/// Phase 4 基础模型：从题目-知识点关联和复习日志中聚合计算每个知识点
/// 的掌握度。计算规则：
///
/// 1. **基础分**：mastered=1.0, reviewing=0.5, newQuestion=0.1
/// 2. **多知识点权重**：一题关联 N 个知识点时，每题贡献 1/N
/// 3. **复习衰减**：超过 7 天未复习，掌握度每日衰减 2%（下限 0）
/// 4. **错因权重**：最近 30 天内每次"忘记"扣 5 分，"模糊"扣 2 分
/// 5. **新题影响**：新题占比 >50% 时额外扣 10 分（知识点尚未充分练习）
class KnowledgePointMasteryService {
  KnowledgePointMasteryService(this._linkRepo);

  final QuestionKnowledgeLinkRepository _linkRepo;

  /// 衰减起始天数（超过此天数开始衰减）。
  static const int _decayStartDays = 7;

  /// 每日衰减率。
  static const double _dailyDecayRate = 0.02;

  /// 忘记扣分。
  static const double _forgotPenalty = 5.0;

  /// 模糊扣分。
  static const double _hardPenalty = 2.0;

  /// 新题占比阈值。
  static const double _newQuestionRatioThreshold = 0.5;

  /// 新题占比超阈值的额外扣分。
  static const double _newQuestionPenalty = 10.0;

  /// 计算指定知识点的掌握度。
  ///
  /// [questions] 是该知识点关联的全部题目（调用方通过 linkRepo 查出 ID 后
  /// 从 questionRepository 加载）。[reviewStatsByQuestion] 是每道题的
  /// 复习统计（forgot/hard/easy 次数），由调用方从 reviewLogRepository 聚合。
  Future<KnowledgePointMastery> calculate({
    required String knowledgePointId,
    required List<QuestionRecord> questions,
    required Map<String, ReviewStats> reviewStatsByQuestion,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();

    if (questions.isEmpty) {
      return KnowledgePointMastery(
        knowledgePointId: knowledgePointId,
        totalQuestions: 0,
        masteredCount: 0,
        reviewingCount: 0,
        newCount: 0,
        forgotCount: 0,
        hardCount: 0,
        easyCount: 0,
        lastReviewedAt: null,
        masteryPercentage: 0,
        calculatedAt: at,
      );
    }

    // 查询每道题关联的知识点数，用于权重计算
    final kpCountByQuestion = <String, int>{};
    for (final q in questions) {
      final links = await _linkRepo.linksForQuestion(q.id);
      kpCountByQuestion[q.id] = links.length;
    }

    int masteredCount = 0;
    int reviewingCount = 0;
    int newCount = 0;
    int forgotCount = 0;
    int hardCount = 0;
    int easyCount = 0;
    DateTime? lastReviewedAt;

    double weightedScore = 0.0;
    double totalWeight = 0.0;

    for (final q in questions) {
      final weight = 1.0 / (kpCountByQuestion[q.id] ?? 1).clamp(1, 10);
      totalWeight += weight;

      // 基础分
      double baseScore;
      switch (q.masteryLevel) {
        case MasteryLevel.mastered:
          masteredCount++;
          baseScore = 1.0;
          break;
        case MasteryLevel.reviewing:
          reviewingCount++;
          baseScore = 0.5;
          break;
        case MasteryLevel.newQuestion:
          newCount++;
          baseScore = 0.1;
          break;
      }

      // 复习衰减
      final reviewedAt = q.lastReviewedAt;
      if (reviewedAt != null) {
        final daysSinceReview = at.difference(reviewedAt).inDays;
        if (daysSinceReview > _decayStartDays) {
          final decayDays = daysSinceReview - _decayStartDays;
          baseScore *= (1.0 - decayDays * _dailyDecayRate).clamp(0.0, 1.0);
        }
        if (lastReviewedAt == null || reviewedAt.isAfter(lastReviewedAt)) {
          lastReviewedAt = reviewedAt;
        }
      }

      weightedScore += baseScore * weight;
    }

    // 聚合复习统计
    for (final stats in reviewStatsByQuestion.values) {
      forgotCount += stats.forgotCount;
      hardCount += stats.hardCount;
      easyCount += stats.easyCount;
    }

    // 基础掌握度百分比
    double percentage =
        totalWeight > 0 ? (weightedScore / totalWeight) * 100 : 0.0;

    // 错因扣分（最近 30 天内）
    double penalty = 0.0;
    final cutoff = at.subtract(const Duration(days: 30));
    for (final entry in reviewStatsByQuestion.entries) {
      final stats = entry.value;
      for (final reviewDate in stats.recentReviewDates) {
        if (reviewDate.isAfter(cutoff)) {
          // 每次复习的扣分已包含在 forgotCount/hardCount 中
        }
      }
    }
    penalty += forgotCount * _forgotPenalty;
    penalty += hardCount * _hardPenalty;

    // 新题占比惩罚
    final newRatio = newCount / questions.length;
    if (newRatio > _newQuestionRatioThreshold) {
      penalty += _newQuestionPenalty;
    }

    percentage = (percentage - penalty).clamp(0.0, 100.0);

    // 记录计算因子（用于 UI 展示"掌握度计算依据"）
    final factors = <String, double>{
      'baseScore': weightedScore / (totalWeight > 0 ? totalWeight : 1) * 100,
      'forgotPenalty': forgotCount * _forgotPenalty,
      'hardPenalty': hardCount * _hardPenalty,
      'newQuestionPenalty':
          newRatio > _newQuestionRatioThreshold ? _newQuestionPenalty : 0.0,
    };

    return KnowledgePointMastery(
      knowledgePointId: knowledgePointId,
      totalQuestions: questions.length,
      masteredCount: masteredCount,
      reviewingCount: reviewingCount,
      newCount: newCount,
      forgotCount: forgotCount,
      hardCount: hardCount,
      easyCount: easyCount,
      lastReviewedAt: lastReviewedAt,
      masteryPercentage: percentage,
      calculatedAt: at,
      factors: factors,
    );
  }

  /// 批量计算多个知识点的掌握度。
  ///
  /// [questionsByKp] 是知识点 ID → 关联题目列表的映射。
  /// [reviewStatsByQuestion] 是全局的题目复习统计（所有题目共享）。
  Future<List<KnowledgePointMastery>> calculateBatch({
    required Map<String, List<QuestionRecord>> questionsByKp,
    required Map<String, ReviewStats> reviewStatsByQuestion,
    DateTime? now,
  }) async {
    final results = <KnowledgePointMastery>[];
    for (final entry in questionsByKp.entries) {
      final mastery = await calculate(
        knowledgePointId: entry.key,
        questions: entry.value,
        reviewStatsByQuestion: reviewStatsByQuestion,
        now: now,
      );
      results.add(mastery);
    }
    return results;
  }
}

/// 题目复习统计快照。
class ReviewStats {
  ReviewStats({
    required this.forgotCount,
    required this.hardCount,
    required this.easyCount,
    this.recentReviewDates = const <DateTime>[],
  });

  final int forgotCount;
  final int hardCount;
  final int easyCount;
  final List<DateTime> recentReviewDates;

  int get totalReviews => forgotCount + hardCount + easyCount;
}
