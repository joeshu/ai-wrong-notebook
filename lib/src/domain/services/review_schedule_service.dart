import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

enum ReviewRating { forgot, hard, easy }

/// A deliberately small, deterministic spaced-repetition policy for MVP.
///
/// It is kept independent from UI and persistence so an FSRS policy can replace
/// it later without migrating existing review history.
class ReviewScheduleService {
  const ReviewScheduleService();

  QuestionRecord apply(
    QuestionRecord question,
    ReviewRating rating, {
    DateTime? reviewedAt,
  }) {
    final now = reviewedAt ?? DateTime.now();
    final nextCount = question.reviewCount + 1;
    final interval = _intervalFor(rating, nextCount);
    final mastery = rating == ReviewRating.easy
        ? MasteryLevel.mastered
        : MasteryLevel.reviewing;

    return question.copyWith(
      masteryLevel: mastery,
      reviewCount: nextCount,
      lastReviewedAt: now,
      nextReviewAt: now.add(interval),
    );
  }

  QuestionRecord reset(QuestionRecord question, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return question.copyWith(
      masteryLevel: MasteryLevel.newQuestion,
      nextReviewAt: at,
    );
  }

  Duration _intervalFor(ReviewRating rating, int reviewCount) {
    switch (rating) {
      case ReviewRating.forgot:
        return const Duration(hours: 1);
      case ReviewRating.hard:
        return reviewCount <= 1
            ? const Duration(days: 1)
            : const Duration(days: 3);
      case ReviewRating.easy:
        if (reviewCount <= 1) return const Duration(days: 3);
        if (reviewCount == 2) return const Duration(days: 7);
        if (reviewCount == 3) return const Duration(days: 14);
        return const Duration(days: 30);
    }
  }

  bool isDue(QuestionRecord question, {DateTime? now}) {
    if (question.contentStatus != ContentStatus.ready) return false;
    // Legacy "mastered" records never carried a schedule and historically
    // meant permanently complete. New easy reviews always receive a date and
    // will re-enter the queue when that date is reached.
    if (question.masteryLevel == MasteryLevel.mastered &&
        question.nextReviewAt == null) {
      return false;
    }
    final dueAt = question.nextReviewAt ?? question.createdAt;
    return !dueAt.isAfter(now ?? DateTime.now());
  }
}
