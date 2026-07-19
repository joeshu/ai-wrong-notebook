import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class QuestionDetailScreen extends ConsumerStatefulWidget {
  const QuestionDetailScreen({super.key});

  @override
  ConsumerState<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen> {
  final _questionKey = GlobalKey();
  final _analysisKey = GlobalKey();
  final _practiceKey = GlobalKey();
  final _recordKey = GlobalKey();

  void _jumpTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentQuestionProvider);

    if (current == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错题详情')),
        body: const Center(child: Text('未找到该错题')),
      );
    }

    final result = current.analysisResult;
    final masteryColor = _masteryColor(context, current.masteryLevel);
    final batchGroups = ref.watch(questionBatchGroupsProvider).valueOrNull;
    final batchGroup = batchGroups?[questionBatchRootId(current)];
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('错题详情'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/notebook'),
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(current.isFavorite
                ? CupertinoIcons.star_fill
                : CupertinoIcons.star),
            tooltip: current.isFavorite ? '取消收藏' : '收藏',
            onPressed: () => _toggleFavorite(context, ref, current),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.pencil),
            onPressed: () => _editQuestion(context, ref, current),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _confirmDelete(context, ref, current);
              if (value == 'source') _editSource(context, ref, current);
              if (value == 'learningContext') {
                _editLearningContext(context, ref, current);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'learningContext',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.person_crop_circle, size: 20),
                    SizedBox(width: 8),
                    Text('编辑学习档案'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'source',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.folder, size: 20),
                    SizedBox(width: 8),
                    Text('设置题目来源'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(CupertinoIcons.trash, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('删除', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: <Widget>[
        _DetailSectionBar(onQuestion: () => _jumpTo(_questionKey), onAnalysis: () => _jumpTo(_analysisKey), onPractice: () => _jumpTo(_practiceKey), onRecord: () => _jumpTo(_recordKey)),
        Expanded(child: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          // 统一标签分类框：科目 | AI识别 | 状态
          Container(
            key: _questionKey,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 第一行：科目 + AI识别 + 状态
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _TagChip(
                      label: current.subject.label,
                      bgColor: const Color(0xFFEEF2FF),
                      textColor: const Color(0xFF4F46E5),
                    ),
                    if (result?.subject != null) ...<Widget>[
                      const SizedBox(width: 8),
                      const _TagChip(
                        label: 'AI识别',
                        bgColor: Color(0xFFF0FDF4),
                        textColor: Color(0xFF16A34A),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _TagChip(
                      label: _masteryLabel(current.masteryLevel),
                      bgColor: masteryColor.withValues(alpha: 0.1),
                      textColor: masteryColor,
                    ),
                    if (_batchLabel(current) != null) ...<Widget>[
                      const SizedBox(width: 8),
                      _TagChip(
                        label: _batchLabel(current)!,
                        bgColor: const Color(0xFFF8FAFC),
                        textColor: const Color(0xFF64748B),
                      ),
                    ],
                    if (current.source != null) ...<Widget>[
                      const SizedBox(width: 8),
                      _TagChip(
                        label: current.source!,
                        bgColor: const Color(0xFFF0FDF4),
                        textColor: const Color(0xFF166534),
                      ),
                    ],
                  ],
                ),
                // AI 短标签（橙色）
                if (current.aiTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('AI标签',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: current.aiTags
                        .map((tag) => _TagChip(
                              label: tag,
                              bgColor: const Color(0xFFFFF7ED),
                              textColor: const Color(0xFFD97706),
                            ))
                        .toList(),
                  ),
                ],
                // 自定义标签（蓝色）
                if (current.customTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text('自定义标签',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: current.customTags
                        .map((t) => _TagChip(
                              label: t,
                              bgColor: const Color(0xFFEEF2FF),
                              textColor: const Color(0xFF4F46E5),
                            ))
                        .toList(),
                  ),
                ],
                // 添加标签按钮
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showAddTagDialog(context, ref, current),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: 0.5),
                          style: BorderStyle.solid),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(CupertinoIcons.plus,
                            size: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('添加标签',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _LearningProfileCard(
            question: current,
            onToggleFavorite: () => _toggleFavorite(context, ref, current),
            onEditSource: () => _editSource(context, ref, current),
            onEditLearningContext: () => _editLearningContext(context, ref, current),
          ),
          if (batchGroup != null) ...<Widget>[
            const SizedBox(height: 12),
            _BatchSiblingCard(
              current: current,
              group: batchGroup,
              onSelect: (question) {
                ref.read(currentQuestionProvider.notifier).state = question;
                context.go('/notebook/question/${question.id}');
              },
            ),
          ],
          if (result == null) ...<Widget>[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                children: <Widget>[
                  Icon(CupertinoIcons.sparkles,
                      size: 40,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  const Text('暂无 AI 解析结果', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () {
                      ref.read(currentQuestionProvider.notifier).state = current;
                      context.go(current.contentStatus.toString().split('.').last == 'failed'
                          ? '/analysis/loading'
                          : '/capture/correction');
                    },
                    icon: Icon(current.contentStatus.toString().split('.').last == 'failed'
                        ? CupertinoIcons.arrow_2_circlepath
                        : CupertinoIcons.camera),
                    label: Text(current.contentStatus.toString().split('.').last == 'failed'
                        ? '重试 AI 解析'
                        : '去添加'),
                  ),
                ],
              ),
            ),
          ],
          if (result != null) ...<Widget>[
            Container(key: _analysisKey),
            const SizedBox(height: 16),
            Container(key: _practiceKey),
            _PracticeSummaryCard(current: current),
            const SizedBox(height: 20),
            // 原题（包含图片和文本）
            _InfoCard(
              icon: CupertinoIcons.doc_text,
              iconColor: const Color(0xFF6366F1),
              bg: const Color(0xFFEEF2FF),
              border: const Color(0xFFC7D2FE),
              title: '原题',
              titleColor: const Color(0xFF4338CA),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // 图片预览
                  if (current.imagePath.isNotEmpty)
                    GestureDetector(
                      onTap: () => _showFullImage(context, current.imagePath),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(current.imagePath),
                                width: double.infinity,
                                height: 120,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(CupertinoIcons.photo,
                                          size: 30,
                                          color: colorScheme.onSurfaceVariant),
                                      const SizedBox(height: 4),
                                      Text('图片加载失败',
                                          style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              fontSize: 11)),
                                    ],
                                  ),
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
                                            fontSize: 10, color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (current.imagePath.isNotEmpty) const SizedBox(height: 10),
                  MathContentView(
                    current.correctedText,
                    contentFormat: current.contentFormat,
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Answer
            _InfoCard(
              icon: result.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.checkmark_circle,
              iconColor: result.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? const Color(0xFFEA580C)
                  : const Color(0xFF16A34A),
              bg: result.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? const Color(0xFFFFF7ED)
                  : const Color(0xFFF0FDF4),
              border: result.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? const Color(0xFFFED7AA)
                  : const Color(0xFFBBF7D0),
              title: result.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? '可能解法'
                  : '正确答案',
              titleColor: result.visualAssumptionStatus ==
                      VisualAssumptionStatus.needsReview
                  ? const Color(0xFF9A3412)
                  : const Color(0xFF166534),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MathContentView(
                    result.finalAnswer,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? colorScheme.onSurface
                            : const Color(0xFF15803D),
                        fontWeight: FontWeight.w600),
                  ),
                  if (_consistencyNotice(result) != null) ...<Widget>[
                    const SizedBox(height: 10),
                    _ConsistencyNotice(
                      notice: _consistencyNotice(result)!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Mistake reason
            _InfoCard(
              icon: CupertinoIcons.exclamationmark_triangle,
              iconColor: const Color(0xFFEA580C),
              bg: const Color(0xFFFFF7ED),
              border: const Color(0xFFFED7AA),
              title: '错因分析',
              titleColor: const Color(0xFF9A3412),
              child: MathContentView(
                result.mistakeReason,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? colorScheme.onSurface
                        : const Color(0xFFC2410C),
                    height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            _MistakeCategoryCard(
              selected: current.mistakeCategory,
              onChanged: (category) => _setMistakeCategory(
                context,
                ref,
                current,
                category,
              ),
            ),
            const SizedBox(height: 10),
            // Study advice
            _InfoCard(
              icon: CupertinoIcons.lightbulb,
              iconColor: const Color(0xFFD97706),
              bg: const Color(0xFFFFFBEB),
              border: const Color(0xFFFDE68A),
              title: '学习建议',
              titleColor: const Color(0xFF92400E),
              child: MathContentView(
                result.studyAdvice,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? colorScheme.onSurface
                        : const Color(0xFFB45309),
                    height: 1.5),
              ),
            ),
            // Knowledge points
            if (result.knowledgePoints.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('知识点',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: result.knowledgePoints
                    .map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark
                                ? colorScheme.surface
                                : const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(8),
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
                                    : const Color(0xFF4F46E5)),
                          ),
                        ))
                    .toList(),
              ),
            ],
            // Steps
            if (result.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text('解题步骤',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              ...result.steps.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colorScheme.surface
                          : const Color(0xFFFAFAFF),
                      borderRadius: BorderRadius.circular(12),
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
                                : const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                              child: Text('${e.key + 1}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? colorScheme.primary
                                          : const Color(0xFF4F46E5)))),
                        ),
                        const SizedBox(width: 10),
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
            const SizedBox(height: 24),
            Container(key: _recordKey),
            _MasteryActions(
              current: current,
              onForgot: () => _markResult(context, ref, current, ReviewRating.forgot),
              onHard: () => _markResult(context, ref, current, ReviewRating.hard),
              onEasy: () => _markResult(context, ref, current, ReviewRating.easy),
            ),
          ],
        ],
      )),
    ]),
    );
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
            color: const Color(0xFFEA580C),
            background: const Color(0xFFFFF7ED),
          );
        }
        return const _ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: Color(0xFF16A34A),
          background: Color(0xFFEFFDF5),
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus ==
            VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: const Color(0xFFEA580C),
            background: const Color(0xFFFFF7ED),
          );
        }
        return const _ConsistencyNoticeData(
          text: '答案与步骤可能不一致，请核对',
          icon: CupertinoIcons.exclamationmark_triangle,
          color: Color(0xFFEA580C),
          background: Color(0xFFFFF7ED),
        );
      case AnalysisConsistencyStatus.unchecked:
      case AnalysisConsistencyStatus.consistent:
      case AnalysisConsistencyStatus.unverifiable:
        return null;
    }
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
        return const Color(0xFFD97706);
      case MasteryLevel.mastered:
        return const Color(0xFF16A34A);
    }
  }

  String? _batchLabel(QuestionRecord question) {
    if (question.parentQuestionId == null && question.rootQuestionId == null) {
      return null;
    }
    final order = question.splitOrder;
    return order == null ? '拍照批次' : '拍照批次 · 第 $order 题';
  }

  void _editLearningContext(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    final stageController = TextEditingController(text: question.learningStage ?? '');
    final workController = TextEditingController(text: question.studentWork ?? '');
    var difficulty = question.difficulty;
    var attemptStatus = question.attemptStatus;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('学习档案'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: stageController,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: '年级 / 教材阶段',
                    hintText: '例如：七年级上、人教版必修一',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<QuestionDifficulty?>(
                  value: difficulty,
                  decoration: const InputDecoration(
                    labelText: '题目层级', border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('未设置')),
                    DropdownMenuItem(value: QuestionDifficulty.foundation, child: Text('基础')),
                    DropdownMenuItem(value: QuestionDifficulty.advanced, child: Text('提高')),
                    DropdownMenuItem(value: QuestionDifficulty.challenge, child: Text('压轴 / 挑战')),
                    DropdownMenuItem(value: QuestionDifficulty.custom, child: Text('自定义')),
                  ],
                  onChanged: (value) => setState(() => difficulty = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AttemptStatus?>(
                  value: attemptStatus,
                  decoration: const InputDecoration(
                    labelText: '作答状态', border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('未判断')),
                    DropdownMenuItem(value: AttemptStatus.notAttempted, child: Text('不会做')),
                    DropdownMenuItem(value: AttemptStatus.wrongAttempt, child: Text('做错了')),
                    DropdownMenuItem(value: AttemptStatus.incomplete, child: Text('未完成')),
                    DropdownMenuItem(value: AttemptStatus.unknown, child: Text('未判断（已标记）')),
                  ],
                  onChanged: (value) => setState(() => attemptStatus = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: workController,
                  maxLines: 3,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: '我的作答 / 订正过程',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final updated = question.withLearningContext(
                  learningStage: stageController.text,
                  difficulty: difficulty,
                  attemptStatus: attemptStatus,
                  studentWork: workController.text,
                );
                await ref.read(questionRepositoryProvider).update(updated);
                ref.read(currentQuestionProvider.notifier).state = updated;
                invalidateQuestionList(ref);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _editSource(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    final controller = TextEditingController(text: question.source ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('题目来源'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '例如：期中考试、课堂作业',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final updated = question.withSource(controller.text);
              await ref.read(questionRepositoryProvider).update(updated);
              ref.read(currentQuestionProvider.notifier).state = updated;
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _editQuestion(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
    final controller = TextEditingController(text: question.correctedText);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑题目'),
        content: TextFormField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final updated = question.copyWith(
                  normalizedQuestionText: controller.text.trim());
              await ref.read(questionRepositoryProvider).update(updated);
              ref.read(currentQuestionProvider.notifier).state = updated;
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这道错题吗？'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ref.read(questionRepositoryProvider).delete(question.id);
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) context.go('/notebook');
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAddTagDialog(
      BuildContext context, WidgetRef ref, QuestionRecord question) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加标签'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '输入标签名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('已有标签',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ...question.aiTags
                    .map((tag) => _dialogTagChip(tag, Colors.orange)),
                ...question.aiKnowledgePoints
                    .map((kp) => _dialogTagChip(kp, Colors.orange)),
                ...question.customTags
                    .map((t) => _dialogTagChip(t, Colors.indigo)),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final tag = controller.text.trim();
              if (tag.isEmpty) return;

              // 检查是否已存在（去重）
              final allTags = [
                ...question.aiTags,
                ...question.aiKnowledgePoints,
                ...question.customTags
              ];
              if (allTags.contains(tag)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('标签已存在')),
                );
                return;
              }

              final newTags = [...question.customTags, tag];
              final updated = question.copyWith(customTags: newTags);
              await ref.read(questionRepositoryProvider).update(updated);
              ref.read(currentQuestionProvider.notifier).state = updated;
              invalidateQuestionList(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Widget _dialogTagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
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
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final updated = question.withFavorite(!question.isFavorite);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(updated.isFavorite ? '已收藏' : '已取消收藏')),
    );
  }

  Future<void> _setMistakeCategory(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
    MistakeCategory? category,
  ) async {
    final updated = question.withMistakeCategory(category);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    final message = category == null ? '已清除错因分类' : '错因已标记为：${category.label}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _markResult(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
    ReviewRating rating,
  ) async {
    final controller = ReviewController(
      repository: ref.read(questionRepositoryProvider),
      logRepository: ref.read(reviewLogRepositoryProvider),
    );
    final updated = switch (rating) {
      ReviewRating.forgot => await controller.markForgot(question.id),
      ReviewRating.hard => await controller.markReviewing(question.id),
      ReviewRating.easy => await controller.markMastered(question.id),
    };
    invalidateQuestionList(ref);
    ref.read(currentQuestionProvider.notifier).state = updated;
    if (!context.mounted) return;
    final message = switch (rating) {
      ReviewRating.forgot => '将在 1 小时后再次复习',
      ReviewRating.hard => '已安排后续复习',
      ReviewRating.easy => '已掌握，复习间隔已延长',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DetailSectionBar extends StatelessWidget {
  const _DetailSectionBar({required this.onQuestion, required this.onAnalysis, required this.onPractice, required this.onRecord});
  final VoidCallback onQuestion;
  final VoidCallback onAnalysis;
  final VoidCallback onPractice;
  final VoidCallback onRecord;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 6, 12, 8), child: Row(children: <Widget>[
      _SectionNavButton(label: '题目', onTap: onQuestion),
      _SectionNavButton(label: '解析', onTap: onAnalysis),
      _SectionNavButton(label: '练习', onTap: onPractice),
      _SectionNavButton(label: '记录', onTap: onRecord),
    ])),
  );
}

class _SectionNavButton extends StatelessWidget {
  const _SectionNavButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 8), child: OutlinedButton(onPressed: onTap, child: Text(label)));
}

class _LearningProfileCard extends StatelessWidget {
  const _LearningProfileCard({
    required this.question,
    required this.onToggleFavorite,
    required this.onEditSource,
    required this.onEditLearningContext,
  });

  final QuestionRecord question;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditSource;
  final VoidCallback onEditLearningContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = question.mistakeCategory?.label ?? '未分类';
    final nextReview = question.nextReviewAt == null
        ? '待安排'
        : _formatProfileDate(question.nextReviewAt!);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('学习档案',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _ProfileItem(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  label: '错因',
                  value: category),
              _ProfileItem(
                  icon: CupertinoIcons.clock,
                  label: '下次复习',
                  value: nextReview),
              _ProfileAction(
                icon: question.isFavorite
                    ? CupertinoIcons.star_fill
                    : CupertinoIcons.star,
                label: question.isFavorite ? '已收藏' : '收藏',
                onTap: onToggleFavorite,
              ),
              _ProfileAction(
                icon: CupertinoIcons.folder,
                label: question.source ?? '设置来源',
                onTap: onEditSource,
              ),
              _ProfileAction(
                icon: CupertinoIcons.person_crop_circle,
                label: question.learningStage ?? '学习档案',
                onTap: onEditLearningContext,
              ),
              if (question.difficulty != null)
                _ProfileItem(
                  icon: CupertinoIcons.chart_bar,
                  label: '层级',
                  value: _difficultyLabel(question.difficulty!),
                ),
              if (question.attemptStatus != null)
                _ProfileItem(
                  icon: CupertinoIcons.pencil_ellipsis_rectangle,
                  label: '作答',
                  value: _attemptStatusLabel(question.attemptStatus!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _difficultyLabel(QuestionDifficulty value) => switch (value) {
      QuestionDifficulty.foundation => '基础',
      QuestionDifficulty.advanced => '提高',
      QuestionDifficulty.challenge => '压轴 / 挑战',
      QuestionDifficulty.custom => '自定义',
    };

String _attemptStatusLabel(AttemptStatus value) => switch (value) {
      AttemptStatus.notAttempted => '不会做',
      AttemptStatus.wrongAttempt => '做错了',
      AttemptStatus.incomplete => '未完成',
      AttemptStatus.unknown => '未判断',
    };

String _formatProfileDate(DateTime value) {
  final date = value.toLocal();
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month-$day ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text('$label：$value', style: const TextStyle(fontSize: 12)),
        ]),
      );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 15),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      );
}

class _MistakeCategoryCard extends StatelessWidget {
  const _MistakeCategoryCard({
    required this.selected,
    required this.onChanged,
  });

  final MistakeCategory? selected;
  final ValueChanged<MistakeCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.tag, size: 18),
              const SizedBox(width: 8),
              const Text('错因分类',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (selected != null)
                TextButton(
                  onPressed: () => onChanged(null),
                  child: const Text('清除'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: MistakeCategory.values.map((category) {
              return ChoiceChip(
                label: Text(category.label),
                selected: selected == category,
                onSelected: (_) => onChanged(category),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _MasteryActions extends StatelessWidget {
  const _MasteryActions({
    required this.current,
    required this.onForgot,
    required this.onHard,
    required this.onEasy,
  });

  final QuestionRecord current;
  final VoidCallback onForgot;
  final VoidCallback onHard;
  final VoidCallback onEasy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('这次复习感觉如何？', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: onForgot,
                child: const Text('忘记了'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onHard,
                child: const Text('有点模糊'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: onEasy,
                child: const Text('掌握了'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PracticeSummaryCard extends ConsumerWidget {
  const _PracticeSummaryCard({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF6366F1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
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
                child: const Icon(CupertinoIcons.arrow_2_circlepath,
                    size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Text('举一反三',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              const Spacer(),
              Text(
                current.savedExercises.isEmpty
                    ? '暂无练习'
                    : '${current.savedExercises.where((e) => e.isCorrect != null).length}/${current.savedExercises.length} 已答',
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            current.savedExercises.isEmpty
                ? '这道错题还没有可继续的练习题。'
                : '继续基于这道原题完成练习，已作答状态会保留。',
            style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: current.savedExercises.isEmpty
                  ? null
                  : () {
                      ref.read(currentPracticeContextProvider.notifier).state =
                          PracticeContext(
                        source: PracticeContextSource.notebook,
                        returnRoute: '/notebook/question/${current.id}',
                      );
                      ref.read(currentQuestionProvider.notifier).state =
                          current;
                      context.go('/exercise/practice');
                    },
              icon: const Icon(CupertinoIcons.play_fill),
              label: Text(current.savedExercises.isEmpty ? '暂无可练习内容' : '继续练习'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.bg,
    required this.border,
    required this.title,
    required this.titleColor,
    this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Color bg;
  final Color border;
  final String title;
  final Color titleColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? iconColor.withValues(alpha: 0.28) : border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      isDark ? iconColor.withValues(alpha: 0.16) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? colorScheme.onSurface : titleColor)),
            ],
          ),
          const SizedBox(height: 10),
          if (child != null) child! else const SizedBox.shrink(),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            isDark ? notice.color.withValues(alpha: 0.14) : notice.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: notice.color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(notice.icon, size: 15, color: notice.color),
          const SizedBox(width: 6),
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

class _BatchSiblingCard extends StatelessWidget {
  const _BatchSiblingCard(
      {required this.current, required this.group, required this.onSelect});

  final QuestionRecord current;
  final QuestionBatchGroup group;
  final void Function(QuestionRecord question) onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(CupertinoIcons.square_grid_2x2,
                  size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('同批题目',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Text('${group.questions.length} 题',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: group.questions.map((question) {
              final selected = question.id == current.id;
              return GestureDetector(
                onTap: selected ? null : () => onSelect(question),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? colorScheme.primary : colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant),
                  ),
                  child: Text(
                    _siblingLabel(question),
                    style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _siblingLabel(QuestionRecord question) {
    final order = question.splitOrder;
    return order == null ? '同批题' : '第 $order 题';
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip(
      {required this.label, required this.bgColor, required this.textColor});

  final String label;
  final Color bgColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? textColor.withValues(alpha: 0.14) : bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? textColor.withValues(alpha: 0.24)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? colorScheme.onSurface : textColor,
              fontWeight: FontWeight.w500)),
    );
  }
}
