import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/layout_provider_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_import_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/capture_service.dart';
import 'package:smart_wrong_notebook/src/data/services/notification_service.dart';
import 'package:smart_wrong_notebook/src/data/services/ocr_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_region_crop_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_split_service.dart';
import 'package:smart_wrong_notebook/src/data/services/vision_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_review_summary.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';

// --- Repository providers (default implementations) ---

final Provider<QuestionRepository> questionRepositoryProvider =
    Provider<QuestionRepository>((ref) {
  return SharedPrefsQuestionRepository();
});

final Provider<LayoutProviderRepository> layoutProviderRepositoryProvider =
    Provider<LayoutProviderRepository>((ref) => LayoutProviderRepository());

final Provider<WorksheetImportRepository> worksheetImportRepositoryProvider =
    Provider<WorksheetImportRepository>((ref) => WorksheetImportRepository());

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

final StateProvider<WorksheetImportSession?> currentWorksheetImportProvider =
    StateProvider<WorksheetImportSession?>((ref) => null);

Future<WorksheetImportSession?> restoreWorksheetImport(WidgetRef ref) async {
  final restored = await ref.read(worksheetImportRepositoryProvider).load();
  ref.read(currentWorksheetImportProvider.notifier).state = restored;
  return restored;
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

enum QuestionSort { newest, oldest, nextReview }

enum QuestionDateRange { all, last7Days, last30Days }

final StateProvider<QuestionDateRange> questionDateRangeProvider =
    StateProvider<QuestionDateRange>((ref) => QuestionDateRange.all);

final StateProvider<bool> dueOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> favoritesOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> failedOnlyFilterProvider =
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
  final pendingAiOnly = ref.watch(pendingAiOnlyFilterProvider);
  final lowConfidenceOnly = ref.watch(lowConfidenceOnlyFilterProvider);
  final dateRange = ref.watch(questionDateRangeProvider);
  final source = ref.watch(selectedSourceFilterProvider);
  final learningStage = ref.watch(selectedLearningStageFilterProvider);
  final difficulty = ref.watch(selectedDifficultyFilterProvider);
  final attemptStatus = ref.watch(selectedAttemptStatusFilterProvider);
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
            if (failedOnly &&
                q.contentStatus.toString().split('.').last != 'failed') {
              return false;
            }
            if (pendingAiOnly &&
                !(q.contentStatus == ContentStatus.ready && q.analysisResult == null)) {
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

// --- Capture mode (printed / handwritten / mixed) ---
//
// 录入时用户选择的识别模式，决定 AI 识别时如何处理图片中的印刷与手写内容。
// 默认 [CaptureMode.printed]，与原有"忽略手写批改"行为保持一致。
final StateProvider<CaptureMode> captureModeProvider =
    StateProvider<CaptureMode>((ref) => CaptureMode.printed);
