import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/confidence_badge.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class AnalysisResultScreen extends ConsumerStatefulWidget {
  const AnalysisResultScreen({super.key});

  @override
  ConsumerState<AnalysisResultScreen> createState() =>
      _AnalysisResultScreenState();
}

class _AnalysisResultScreenState extends ConsumerState<AnalysisResultScreen> {
  int _activeCandidateIndex = 0;

  @override
  Widget build(BuildContext context) {
    final record = ref.watch(currentQuestionProvider);

    if (record == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('AI 解析结果'),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.chevron_left),
            onPressed: () => context.go('/analysis/loading'),
          ),
        ),
        body: const Center(child: Text('未找到错题记录')),
      );
    }

    final result = record.analysisResult;
    final splitResult = record.splitResult;
    final hasMultipleCandidates = splitResult?.hasMultipleCandidates ?? false;
    final safeCandidateIndex = hasMultipleCandidates
        ? _activeCandidateIndex.clamp(0, splitResult!.candidates.length - 1)
        : 0;
    final activeCandidate = hasMultipleCandidates
        ? splitResult!.candidates[safeCandidateIndex]
        : null;
    final activeCandidateAnalysis = activeCandidate == null
        ? null
        : record.candidateAnalyses.firstWhereOrNull(
            (candidate) => candidate.candidateId == activeCandidate.id);
    final displayResult = hasMultipleCandidates
        ? activeCandidateAnalysis?.analysisResult
        : result;
    final displayAiTags = hasMultipleCandidates
        ? activeCandidateAnalysis?.aiTags ?? const <String>[]
        : record.aiTags;
    final displayKnowledgePoints = hasMultipleCandidates
        ? activeCandidateAnalysis?.aiKnowledgePoints ?? const <String>[]
        : result?.knowledgePoints ?? const <String>[];
    final displayQuestionText = activeCandidateAnalysis?.questionText ??
        activeCandidate?.text ??
        record.correctedText;
    final displayExercises = hasMultipleCandidates
        ? activeCandidateAnalysis?.savedExercises ?? const []
        : record.savedExercises;
    final candidateInsight = hasMultipleCandidates
        ? _candidateInsight(
            candidateOrder: activeCandidate?.order ?? 1,
            total: splitResult?.candidates.length ?? 1,
            hasIndependentAnalysis: activeCandidateAnalysis != null,
          )
        : null;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final layoutProvider = record.tags
        .where((tag) => tag.startsWith('layout_provider:'))
        .map((tag) => tag.substring('layout_provider:'.length))
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 解析结果'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/capture/save-confirmation'),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () => _confirmDiscard(record),
            icon: const Icon(CupertinoIcons.trash, size: 18),
            label: const Text('放弃'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: <Widget>[
          // 统一标签分类框：科目 | AI识别 | 状态 | 知识点
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: AppSpace.md - 2),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 第一行：科目 + AI识别 + 状态
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: <Widget>[
                    AppTag(
                      label:
                          displayResult?.subject?.label ?? record.subject.label,
                      textColor: AppColors.primaryDark,
                      backgroundColor: AppColors.primaryContainerLight,
                    ),
                    if (displayResult?.subject != null)
                      const AppTag(
                        label: 'AI识别',
                        textColor: AppColors.success,
                        backgroundColor: AppColors.successContainerLight,
                      ),
                    AppTag(
                      label: _masteryLabel(record.masteryLevel),
                      textColor: _masteryColor(record.masteryLevel),
                      backgroundColor:
                          _masteryColor(record.masteryLevel).withValues(alpha: 0.1),
                    ),
                    if (layoutProvider.isNotEmpty)
                      AppTag(
                        label: '切题：$layoutProvider',
                        textColor: AppColors.infoDark,
                        backgroundColor: AppColors.infoContainerLight,
                      ),
                  ],
                ),
                if (record.splitResult != null) ...<Widget>[
                  const SizedBox(height: AppSpace.sm + 2),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.xs + 2,
                    children: <Widget>[
                      AppTag(
                        label: '候选 ${record.splitResult!.candidates.length} 题',
                        textColor: AppColors.accentPurple,
                        backgroundColor: AppColors.accentPurpleContainerLight,
                      ),
                      AppTag(
                        label:
                            _splitStrategyLabel(record.splitResult!.strategy),
                        textColor: AppColors.slate,
                        backgroundColor: AppColors.slateContainerLight,
                      ),
                      if (activeCandidate != null)
                        AppTag(
                          label: '当前第 ${activeCandidate.order} 题',
                          textColor: AppColors.accentAmber,
                          backgroundColor: AppColors.accentAmberContainerLight,
                        ),
                    ],
                  ),
                  if (record.splitResult!.hasMultipleCandidates) ...<Widget>[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      '这张图片已识别为多题内容，保存时会进入逐题确认。',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
                // AI 短标签（橙色）
                if (displayAiTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.sm + 2),
                  Text('AI标签',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.xs + 2,
                    runSpacing: AppSpace.xs,
                    children: displayAiTags
                        .map((tag) => AppTag(
                              label: tag,
                              textColor: AppColors.accentAmber,
                              backgroundColor: AppColors.accentAmberContainerLight,
                            ))
                        .toList(),
                  ),
                ],
                // 自定义标签（蓝色）
                if (record.customTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.sm),
                  Text('自定义标签',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.xs + 2,
                    runSpacing: AppSpace.xs,
                    children: record.customTags
                        .map((t) => AppTag(
                              label: t,
                              textColor: AppColors.primaryDark,
                              backgroundColor: AppColors.primaryContainerLight,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          if (record.splitResult?.hasMultipleCandidates ?? false) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            _CandidateSwitcherCard(
              splitResult: splitResult!,
              safeCandidateIndex: safeCandidateIndex,
              onSelected: (index) =>
                  setState(() => _activeCandidateIndex = index),
            ),
          ],
          if (displayResult == null) ...<Widget>[
            const SizedBox(height: AppSpace.lg + 4),
            AppInfoSection(
              icon: CupertinoIcons.exclamationmark_triangle,
              iconColor: AppColors.danger,
              backgroundColor: AppColors.dangerContainerLight,
              borderColor: const Color(0xFFFECACA),
              title: '第 ${activeCandidate?.order ?? 1}题解析失败',
              titleColor: const Color(0xFFB91C1C),
              child: MathContentView(
                activeCandidateAnalysis?.errorMessage?.isNotEmpty == true
                    ? '已自动重试，仍未成功。该题暂不可保存，可返回重新解析。\n${activeCandidateAnalysis!.errorMessage}'
                    : '已自动重试，仍未成功。该题暂不可保存，可返回重新解析。',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      isDark ? colorScheme.onSurface : const Color(0xFFB91C1C),
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (displayResult != null) ...<Widget>[
            const SizedBox(height: AppSpace.lg + 4),
            // 原题（包含图片和文本）
            AppInfoSection(
              icon: CupertinoIcons.doc_text,
              iconColor: AppColors.primary,
              backgroundColor: AppColors.primaryContainerLight,
              borderColor: const Color(0xFFC7D2FE),
              title: '原题',
              titleColor: AppColors.primaryDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (record.ocrConfidence != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: ConfidenceBadge(
                        confidence: record.ocrConfidence,
                        compact: true,
                      ),
                    ),
                  if (File(record.imagePath).existsSync())
                    GestureDetector(
                      onTap: () => _showFullImage(context, record.imagePath),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.small),
                        ),
                        child: Stack(
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.small),
                              child: SizedBox(
                                width: double.infinity,
                                height: 120,
                                child: CachedQuestionImage(
                                  record.imagePath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(CupertinoIcons.zoom_in,
                                        size: 12, color: Colors.white),
                                    SizedBox(width: 3),
                                    Text('查看原图',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (File(record.imagePath).existsSync())
                    const SizedBox(height: AppSpace.sm + 2),
                  MathContentView(
                    displayQuestionText,
                    contentFormat: hasMultipleCandidates
                        ? QuestionContentFormat.latexMixed
                        : record.contentFormat,
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm + 2),
            // Answer
            AppInfoSection(
              icon: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.checkmark_circle,
              iconColor: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? AppColors.warning
                  : AppColors.success,
              backgroundColor: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? AppColors.warningContainerLight
                  : AppColors.successContainerLight,
              borderColor: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? const Color(0xFFFED7AA)
                  : const Color(0xFFBBF7D0),
              title: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? '可能解法'
                  : '正确解答',
              titleColor: displayResult.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? AppColors.warningDark
                  : AppColors.successDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MathContentView(
                    displayResult.finalAnswer,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? colorScheme.onSurface
                            : const Color(0xFF15803D),
                        fontWeight: FontWeight.w600),
                  ),
                  if (_consistencyNotice(displayResult) != null) ...<Widget>[
                    const SizedBox(height: AppSpace.sm + 2),
                    _ConsistencyNotice(
                      notice: _consistencyNotice(displayResult)!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.sm + 2),
            // Mistake reason
            AppInfoSection(
              icon: CupertinoIcons.exclamationmark_triangle,
              iconColor: AppColors.warning,
              backgroundColor: AppColors.warningContainerLight,
              borderColor: const Color(0xFFFED7AA),
              title: '错因分析',
              titleColor: AppColors.warningDark,
              child: MathContentView(
                displayResult.mistakeReason,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? colorScheme.onSurface
                        : const Color(0xFFC2410C),
                    height: 1.5),
              ),
            ),
            const SizedBox(height: AppSpace.sm + 2),
            // Study advice
            AppInfoSection(
              icon: CupertinoIcons.lightbulb,
              iconColor: AppColors.accentAmber,
              backgroundColor: AppColors.accentAmberContainerLight,
              borderColor: const Color(0xFFFDE68A),
              title: '学习建议',
              titleColor: const Color(0xFF92400E),
              child: MathContentView(
                displayResult.studyAdvice,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? colorScheme.onSurface
                        : const Color(0xFFB45309),
                    height: 1.5),
              ),
            ),
            if (candidateInsight != null) ...<Widget>[
              const SizedBox(height: AppSpace.sm + 2),
              AppInfoSection(
                icon: CupertinoIcons.layers,
                iconColor: AppColors.accentTeal,
                backgroundColor: AppColors.accentTealContainerLight,
                borderColor: const Color(0xFF99F6E4),
                title: '当前子题状态',
                titleColor: const Color(0xFF115E59),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    MathContentView(
                      candidateInsight,
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? colorScheme.onSurface
                              : const Color(0xFF134E4A),
                          height: 1.5),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      activeCandidateAnalysis != null
                          ? '当前已切换到第 ${activeCandidate?.order ?? 1} 题独立解析。'
                          : '第 ${activeCandidate?.order ?? 1} 题暂无独立解析。',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
            // Knowledge points
            if (displayKnowledgePoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.lg),
              Text('知识点',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: displayKnowledgePoints
                    .map((p) => Container(
                          margin: const EdgeInsets.only(bottom: AppSpace.xs + 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.sm + 2, vertical: AppSpace.xs + 1),
                          decoration: BoxDecoration(
                            color: isDark
                                ? colorScheme.surface
                                : AppColors.primaryContainerLight,
                            borderRadius: BorderRadius.circular(AppRadius.small),
                            border: Border.all(
                              color: isDark
                                  ? colorScheme.outlineVariant
                                  : const Color(0xFFC7D2FE),
                            ),
                          ),
                          child: MathContentView(
                            p,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: isDark
                                    ? colorScheme.onSurface
                                    : AppColors.primaryDark),
                          ),
                        ))
                    .toList(),
              ),
            ],
            // Steps
            if (displayResult.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.lg),
              Text('解题步骤',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.sm + 2),
              ...displayResult.steps.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: AppSpace.sm + 2),
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surface
                          : const Color(0xFFFAFAFF),
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      border: Border.all(
                        color: isDark
                            ? colorScheme.outlineVariant
                            : const Color(0xFFE0E7FF),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isDark
                                ? colorScheme.primary.withValues(alpha: 0.14)
                                : AppColors.primaryContainerLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                              child: Text('${e.key + 1}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? colorScheme.primary
                                          : AppColors.primaryDark))),
                        ),
                        const SizedBox(width: AppSpace.sm + 2),
                        Expanded(
                            child: MathContentView(e.value,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: colorScheme.onSurface,
                                    height: 1.5))),
                      ],
                    ),
                  )),
            ],
            // Exercises
            if (displayExercises.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpace.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('举一反三',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${displayExercises.length} 题',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
              if (activeCandidate != null) ...<Widget>[
                const SizedBox(height: AppSpace.xs + 2),
                Text(
                  activeCandidateAnalysis != null
                      ? '当前展示第 ${activeCandidate.order} 题独立生成的练习。'
                      : '第 ${activeCandidate.order} 题暂无独立练习。',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: AppSpace.sm + 2),
              ...displayExercises.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpace.md),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        border: Border.all(
                            color:
                                Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _difficultyColor(context, e.difficulty)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  e.difficulty,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        _difficultyColor(context, e.difficulty),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (e.isCorrect == true)
                                const Icon(CupertinoIcons.checkmark_circle,
                                    color: AppColors.success, size: 18)
                              else if (e.isCorrect == false)
                                const Icon(CupertinoIcons.xmark_circle,
                                    color: AppColors.warning, size: 18),
                            ],
                          ),
                          const SizedBox(height: AppSpace.sm),
                          MathContentView(
                            e.question,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          Row(
                            children: <Widget>[
                              Icon(CupertinoIcons.lightbulb,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.65)),
                              const SizedBox(width: AppSpace.xs),
                              Expanded(
                                child: MathContentView(
                                  '答案：${e.answer}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          if (e.explanation.isNotEmpty) ...<Widget>[
                            const SizedBox(height: AppSpace.xs),
                            MathContentView(
                              e.explanation,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: AppSpace.xl),
          ],
        ],
      ),
      bottomNavigationBar: displayResult == null
          ? null
          : SafeArea(
              top: true,
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl, AppSpace.sm, AppSpace.xl, AppSpace.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _startPractice(record, activeCandidateAnalysis),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('开始练习'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final splitter = ref.read(questionSplitServiceProvider);
                          ref
                              .read(currentQuestionSplitSessionProvider.notifier)
                              .state = await buildQuestionSplitSession(
                            record,
                            splitter: splitter,
                          );
                          if (!context.mounted) return;
                          context.go('/capture/split-confirmation');
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('保存到错题本'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _confirmDiscard(QuestionRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃这次识别？'),
        content: const Text('题图、识别结果和本次分析都不会加入错题本。此操作不可恢复。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('继续查看')),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃并删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet != null && !worksheet.sourcePageIds.contains(record.id)) {
      await persistWorksheetImport(
        ref,
        worksheet.copyWith(pages: worksheet.pages.where((item) => item.id != record.id).toList()),
      );
    }
    await ref.read(questionRepositoryProvider).delete(record.id);
    await ref.read(imageStorageServiceProvider).deleteImage(record.imagePath);
    ref.read(currentQuestionProvider.notifier).state = null;
    invalidateQuestionList(ref);
    if (!mounted) return;
    context.go(worksheet == null ? '/' : '/worksheet/import');
  }

  void _startPractice(
    QuestionRecord record,
    CandidateAnalysisSnapshot? activeCandidateAnalysis,
  ) {
    ref.read(currentPracticeContextProvider.notifier).state = PracticeContext(
      source: PracticeContextSource.analysis,
      candidateId: activeCandidateAnalysis?.candidateId,
      candidateOrder: activeCandidateAnalysis?.order,
      returnRoute: '/analysis/result',
    );
    ref.read(currentQuestionProvider.notifier).state = record;
    context.go('/exercise/practice');
  }

  String _candidateInsight({
    required int candidateOrder,
    required int total,
    required bool hasIndependentAnalysis,
  }) {
    return hasIndependentAnalysis
        ? '当前正在查看第 $candidateOrder / $total 题，已切换到独立解析结果。'
        : '当前正在查看第 $candidateOrder / $total 题，题干切换已生效。';
  }

  String _splitStrategyLabel(Object strategy) {
    switch (strategy.toString().split('.').last) {
      case 'numbered':
        return '编号拆题';
      case 'paragraph':
        return '分段拆题';
      default:
        return '单题回退';
    }
  }

  Color _difficultyColor(BuildContext context, String difficulty) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (difficulty) {
      case '简单':
        return AppColors.success;
      case '中等':
        return AppColors.accentAmber;
      case '困难':
        return AppColors.danger;
      case '提高':
        return AppColors.accentPurple;
      case '同级':
        return AppColors.info;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  _ConsistencyNoticeData? _consistencyNotice(AnalysisResult result) {
    switch (result.consistencyStatus) {
      case AnalysisConsistencyStatus.repaired:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : 'AI 已复核答案；图中关键标注含义仍需核对',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return _ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: AppColors.success,
          background: AppColors.successContainerLight,
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return _ConsistencyNoticeData(
          text: '答案与步骤可能不一致，请核对',
          icon: CupertinoIcons.exclamationmark_triangle,
          color: AppColors.warning,
          background: AppColors.warningContainerLight,
        );
      case AnalysisConsistencyStatus.unchecked:
      case AnalysisConsistencyStatus.consistent:
      case AnalysisConsistencyStatus.unverifiable:
        return null;
    }
  }

  void _showFullImage(BuildContext context, String imagePath) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: const Text('原图'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedQuestionImage(imagePath, highRes: true),
            ),
          ),
        ),
      ),
    );
  }
}

extension _IterableFirstOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}

class _CandidateSwitcherCard extends StatelessWidget {
  const _CandidateSwitcherCard({
    required this.splitResult,
    required this.safeCandidateIndex,
    required this.onSelected,
  });

  final QuestionSplitResult splitResult;
  final int safeCandidateIndex;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.accentPurple;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border:
            Border.all(color: accent.withValues(alpha: isDark ? 0.28 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(CupertinoIcons.square_list,
                    size: 16, color: accent),
              ),
              const SizedBox(width: AppSpace.sm + 2),
              Text('题号切换',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: AppSpace.md + 2),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: splitResult.candidates.asMap().entries.map((entry) {
                final candidate = entry.value;
                final isActive = entry.key == safeCandidateIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpace.sm),
                  child: ChoiceChip(
                    label: Text('第 ${candidate.order} 题'),
                    selected: isActive,
                    onSelected: (_) => onSelected(entry.key),
                    labelStyle: TextStyle(
                      fontSize: 14,
                      color: isActive
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surface,
                    side: BorderSide(
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsistencyNoticeData {
  const _ConsistencyNoticeData({
    required this.text,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String text;
  final IconData icon;
  final Color color;
  final Color background;
}

class _ConsistencyNotice extends StatelessWidget {
  const _ConsistencyNotice({required this.notice});

  final _ConsistencyNoticeData notice;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm + 2, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color:
            isDark ? notice.color.withValues(alpha: 0.14) : notice.background,
        borderRadius: BorderRadius.circular(AppRadius.small + 2),
        border: Border.all(color: notice.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(notice.icon, size: 15, color: notice.color),
          const SizedBox(width: AppSpace.xs + 2),
          Expanded(
            child: Text(
              notice.text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: isDark
                    ? Theme.of(context).colorScheme.onSurface
                    : notice.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '未复习';
    case MasteryLevel.reviewing:
      return '复习中';
    case MasteryLevel.mastered:
      return '已掌握';
  }
}

Color _masteryColor(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return Colors.grey;
    case MasteryLevel.reviewing:
      return Colors.orange;
    case MasteryLevel.mastered:
      return Colors.green;
  }
}
