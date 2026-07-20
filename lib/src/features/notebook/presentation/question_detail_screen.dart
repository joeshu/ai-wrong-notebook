import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/services/auto_grading_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_controller.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/confidence_badge.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/single_text_field_dialog.dart';

class QuestionDetailScreen extends ConsumerStatefulWidget {
  const QuestionDetailScreen({super.key});

  @override
  ConsumerState<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentQuestionProvider);

    if (current == null) {
      return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.detailTitle)),
        body: const Center(child: Text('未找到该错题')),
      );
    }

    final result = current.analysisResult;
    final batchGroupsAsync = ref.watch(questionBatchGroupsProvider);
    final batchGroups = batchGroupsAsync.valueOrNull;
    final batchGroup = batchGroups?[questionBatchRootId(current)];
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.detailTitle),
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
            icon: Icon(current.isArchived
                ? CupertinoIcons.archivebox_fill
                : CupertinoIcons.archivebox),
            tooltip: current.isArchived ? '取消归档' : '归档',
            onPressed: () => current.isArchived
                ? _unarchive(context, ref, current)
                : _confirmArchive(context, ref, current),
          ),
          IconButton(
            icon: Icon(_editing ? CupertinoIcons.check_mark : CupertinoIcons.pencil),
            tooltip: _editing ? '完成编辑' : '编辑题目',
            onPressed: () => setState(() => _editing = !_editing),
          ),
          if (_editing)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _confirmDelete(context, ref, current);
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: <Widget>[
                    Icon(CupertinoIcons.trash, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Text('删除', style: TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(999),
          ),
          labelColor: colorScheme.onPrimary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const <Widget>[
            Tab(text: AppStrings.detailTabQuestion),
            Tab(text: AppStrings.detailTabAnalysis),
            Tab(text: AppStrings.detailTabPractice),
            Tab(text: AppStrings.detailTabRecord),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          if (_editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _editQuestion(context, ref, current),
                  icon: const Icon(CupertinoIcons.doc_text),
                  label: const Text('编辑题干、答案与解析'),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _QuestionTab(
                  current: current,
                  editing: _editing,
                  batchGroup: batchGroup,
                  showFullImage: (path) => _showFullImage(context, path),
                  onToggleFavorite: () => _toggleFavorite(context, ref, current),
                  onEditSource: () => _editSource(context, ref, current),
                  onEditLearningContext: () => _editLearningContext(context, ref, current),
                  onSelectSibling: (question) {
                    ref.read(currentQuestionProvider.notifier).state = question;
                    context.go('/notebook/question/${question.id}');
                  },
                  onAddTag: () => _showAddTagDialog(context, ref, current),
                  onEditReflection: () => _editReflection(context, ref, current),
                  onEditStudentAnswer: () => _editStudentAnswer(context, ref, current),
                  onEditExpectedAnswer: () => _editExpectedAnswer(context, ref, current),
                  onGradeAnswer: () => _gradeAnswer(context, ref, current),
                ),
                _AnalysisTab(
                  current: current,
                  result: result,
                  onSetCategory: (category) => _setMistakeCategory(context, ref, current, category),
                  onAddAnalysis: () {
                    ref.read(currentQuestionProvider.notifier).state = current;
                    context.go('/analysis/loading');
                  },
                ),
                _PracticeTab(current: current),
                _RecordTab(
                  current: current,
                  onForgot: () => _markResult(context, ref, current, ReviewRating.forgot),
                  onHard: () => _markResult(context, ref, current, ReviewRating.hard),
                  onEasy: () => _markResult(context, ref, current, ReviewRating.easy),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _ConsistencyNoticeData? _consistencyNotice(AnalysisResult result) {
    switch (result.consistencyStatus) {
      case AnalysisConsistencyStatus.repaired:
        if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : 'AI 已复核答案；图中关键标注含义仍需核对',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return const _ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: AppColors.success,
          background: Color(0xFFEFFDF5),
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return const _ConsistencyNoticeData(
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
          title: const Text(AppStrings.detailLearningProfile),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
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
                    labelText: '题目层级',
                    border: OutlineInputBorder(),
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
                    labelText: '作答状态',
                    border: OutlineInputBorder(),
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
          actions: <Widget>[
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
    ).then((_) {
      stageController.dispose();
      workController.dispose();
    });
  }

  Future<void> _editSource(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '题目来源',
      initialText: question.source ?? '',
      autofocus: true,
      maxLength: 30,
      hintText: '例如：期中考试、课堂作业',
    );
    if (text == null) return;
    final updated = question.withSource(text);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editQuestion(
      BuildContext context, WidgetRef ref, QuestionRecord question) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '编辑题目',
      initialText: question.correctedText,
      maxLines: 4,
    );
    if (text == null) return;
    final updated = question.copyWith(normalizedQuestionText: text);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editReflection(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '学习反思',
      initialText: question.reflectionNote ?? '',
      maxLines: 6,
      minLines: 3,
      hintText: '记录你对这道题的反思、总结或易错点…',
    );
    if (text == null) return;
    final updated = question.copyWith(reflectionNote: text);
    await ref.read(questionRepositoryProvider).update(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editStudentAnswer(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '我的答案',
      initialText: question.studentAnswer ?? '',
      maxLines: 8,
      minLines: 3,
      hintText: '记录你的作答过程（支持 LaTeX 公式）…',
    );
    if (text == null) return;
    final updated = question.copyWith(studentAnswer: text);
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _editExpectedAnswer(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final text = await showSingleTextFieldDialog(
      context: context,
      title: '标准答案',
      initialText: question.expectedAnswer ?? '',
      maxLines: 8,
      minLines: 3,
      hintText: '填写标准答案（支持 LaTeX 公式）…',
    );
    if (text == null) return;
    final updated = question.withExpectedAnswer(text);
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
  }

  Future<void> _gradeAnswer(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final service = AutoGradingService(
      ref.read(aiAnalysisServiceProvider),
      ref.read(questionRepositoryProvider),
    );
    try {
      final isCorrect = await service.gradeQuestion(question);
      // gradeQuestion 内部已通过 saveDraft 写回 isCorrect；这里同步刷新当前
      // 题目快照，避免 UI 等待 watchAll() 推送。
      final updated = question.withIsCorrect(isCorrect);
      ref.read(currentQuestionProvider.notifier).state = updated;
      invalidateQuestionList(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isCorrect ? '判分结果：正确' : '判分结果：错误')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('判分失败：$e')),
      );
    }
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
              children: <Widget>[
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
    ).then((_) => controller.dispose());
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
              child: CachedQuestionImage(imagePath, highRes: true),
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

  void _confirmArchive(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档这道错题？'),
        content: const Text('归档后题目默认从错题本列表隐藏，可在"显示归档"中查看，随时可取消归档。'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _archive(context, ref, question);
            },
            child: const Text('归档'),
          ),
        ],
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final updated = question.archive();
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已归档')),
    );
  }

  Future<void> _unarchive(
    BuildContext context,
    WidgetRef ref,
    QuestionRecord question,
  ) async {
    final updated = question.unarchive();
    await ref.read(questionRepositoryProvider).saveDraft(updated);
    ref.read(currentQuestionProvider.notifier).state = updated;
    invalidateQuestionList(ref);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消归档')),
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

class _RecognitionStatusTags extends StatelessWidget {
  const _RecognitionStatusTags({required this.question});
  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final source = question.tags.firstWhere(
      (tag) => tag.startsWith('layout_provider:'),
      orElse: () => '',
    );
    final provider = source.isEmpty ? null : source.substring('layout_provider:'.length);
    final aiReady = question.analysisResult != null;
    final recognitionLabel = provider ?? (question.imagePath.isNotEmpty ? '图片已保留' : '待识别');
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      children: <Widget>[
        AppTag(
          label: '识别：$recognitionLabel',
          textColor: AppColors.successDark,
          backgroundColor: AppColors.successContainerLight,
        ),
        AppTag(
          label: aiReady ? 'AI：已分析' : 'AI：未分析',
          textColor: aiReady ? AppColors.primaryDark : AppColors.slate,
          backgroundColor: aiReady ? AppColors.primaryContainerLight : AppColors.slateContainerLight,
        ),
      ],
    );
  }
}
class _RecognitionEvidenceCard extends StatelessWidget {
  const _RecognitionEvidenceCard({required this.question});
  final QuestionRecord question;

  @override
  Widget build(BuildContext context) {
    final source = question.tags.firstWhere(
      (tag) => tag.startsWith('layout_provider:'),
      orElse: () => '',
    );
    final provider = source.isEmpty
        ? (question.imagePath.isNotEmpty ? '图片原题' : '未记录')
        : source.substring('layout_provider:'.length);
    final analyzed = question.analysisResult != null;
    final confidence = question.ocrConfidence;
    return AppInfoSection(
      icon: CupertinoIcons.doc_text_search,
      title: '识别与分析状态',
      iconColor: AppColors.successDark,
      backgroundColor: AppColors.successContainerLight,
      borderColor: const Color(0xFFBBF7D0),
      titleColor: AppColors.successDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: <Widget>[
              AppTag(label: '识别：$provider', textColor: AppColors.successDark, backgroundColor: AppColors.successContainerLight),
              AppTag(label: analyzed ? 'AI：已分析' : 'AI：未分析', textColor: analyzed ? AppColors.primaryDark : AppColors.slate, backgroundColor: analyzed ? AppColors.primaryContainerLight : AppColors.slateContainerLight),
              if (confidence != null) AppTag(label: '置信度：${(confidence * 100).round()}%', textColor: confidence < .7 ? AppColors.warningDark : AppColors.successDark, backgroundColor: confidence < .7 ? AppColors.warningContainerLight : AppColors.successContainerLight),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            analyzed
                ? '识别结果已交给普通 AI，当前可查看答案、错因、知识点和练习。'
                : '当前仅保存识别结果；可在“分析”页继续交给普通 AI。',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}


  const _QuestionTab({
    required this.current,
    required this.editing,
    required this.batchGroup,
    required this.showFullImage,
    required this.onToggleFavorite,
    required this.onEditSource,
    required this.onEditLearningContext,
    required this.onSelectSibling,
    required this.onAddTag,
    required this.onEditReflection,
    required this.onEditStudentAnswer,
    required this.onEditExpectedAnswer,
    required this.onGradeAnswer,
  });

  final QuestionRecord current;
  final bool editing;
  final QuestionBatchGroup? batchGroup;
  final void Function(String) showFullImage;
  final VoidCallback onToggleFavorite;
  final VoidCallback onEditSource;
  final VoidCallback onEditLearningContext;
  final void Function(QuestionRecord) onSelectSibling;
  final VoidCallback onAddTag;
  final VoidCallback onEditReflection;
  final VoidCallback onEditStudentAnswer;
  final VoidCallback onEditExpectedAnswer;
  final Future<void> Function() onGradeAnswer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = current.analysisResult;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        AppCard(
          borderRadius: AppRadius.large,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: <Widget>[
                  AppTag(
                    label: current.subject.label,
                    textColor: AppColors.primary,
                    backgroundColor: AppColors.primaryContainerLight,
                  ),
                  if (result?.subject != null)
                    const AppTag(
                      label: 'AI识别',
                      textColor: AppColors.success,
                      backgroundColor: AppColors.successContainerLight,
                    ),
                  _MasteryTag(current: current),
                  _RecognitionStatusTags(question: current),
                  if (_batchLabel(current) != null)
                    AppTag(
                      label: _batchLabel(current)!,
                      textColor: AppColors.slate,
                      backgroundColor: AppColors.slateContainerLight,
                    ),
                  if (current.source != null)
                    AppTag(
                      label: current.source!,
                      textColor: AppColors.successDark,
                      backgroundColor: AppColors.successContainerLight,
                    ),
                ],
              ),
              if (current.aiTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text('AI标签',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: current.aiTags
                      .map((tag) => AppTag(
                            label: tag,
                            textColor: AppColors.accentAmber,
                            backgroundColor: AppColors.accentAmberContainerLight,
                          ))
                      .toList(),
                ),
              ],
              if (current.customTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                Text('自定义标签',
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: current.customTags
                      .map((t) => AppTag(
                            label: t,
                            textColor: AppColors.primaryDark,
                            backgroundColor: AppColors.primaryContainerLight,
                          ))
                      .toList(),
                ),
              ],
              if (editing) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                _AddTagButton(onTap: onAddTag),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _LearningProfileGrid(
          question: current,
          editing: editing,
          onToggleFavorite: onToggleFavorite,
          onEditSource: onEditSource,
          onEditLearningContext: onEditLearningContext,
        ),
        if (batchGroup != null) ...<Widget>[
          const SizedBox(height: AppSpace.md),
          _BatchSiblingCard(
            current: current,
            group: batchGroup!,
            onSelect: onSelectSibling,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        _buildOriginalQuestion(context, isDark, colorScheme),
        const SizedBox(height: AppSpace.lg),
        _RecognitionEvidenceCard(question: current),
        if (current.studentAnswer != null &&
            current.studentAnswer!.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          _StudentAnswerCard(
            answer: current.studentAnswer!,
            contentFormat: current.contentFormat,
            onEdit: onEditStudentAnswer,
          ),
          const SizedBox(height: AppSpace.lg),
          _ExpectedAnswerCard(
            expectedAnswer: current.expectedAnswer,
            studentAnswer: current.studentAnswer,
            isCorrect: current.isCorrect,
            contentFormat: current.contentFormat,
            onEdit: onEditExpectedAnswer,
            onGrade: onGradeAnswer,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        _ReflectionNoteCard(
          note: current.reflectionNote,
          onEdit: onEditReflection,
        ),
      ],
    );
  }

  String? _batchLabel(QuestionRecord question) {
    if (question.parentQuestionId == null && question.rootQuestionId == null) {
      return null;
    }
    final order = question.splitOrder;
    return order == null ? '拍照批次' : '拍照批次 · 第 $order 题';
  }

  Widget _buildOriginalQuestion(BuildContext context, bool isDark, ColorScheme colorScheme) {
    return AppInfoSection(
      icon: CupertinoIcons.doc_text,
      title: AppStrings.detailOriginalQuestion,
      iconColor: AppColors.primary,
      backgroundColor: AppColors.primaryContainerLight,
      borderColor: const Color(0xFFC7D2FE),
      titleColor: AppColors.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (current.ocrConfidence != null) ...<Widget>[
            ConfidenceBadge(confidence: current.ocrConfidence, compact: true),
            const SizedBox(height: AppSpace.sm),
          ],
          if (current.imagePath.isNotEmpty) ...<Widget>[
            GestureDetector(
              onTap: () => showFullImage(current.imagePath),
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Stack(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      child: SizedBox(
                        width: double.infinity,
                        height: 160,
                        child: CachedQuestionImage(
                          current.imagePath,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(CupertinoIcons.zoom_in, size: 12, color: Colors.white),
                            SizedBox(width: 3),
                            Text('查看原图',
                                style: TextStyle(fontSize: 10, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],
          MathContentView(
            current.correctedText,
            contentFormat: current.contentFormat,
            style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface,
                height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ReflectionNoteCard extends StatelessWidget {
  const _ReflectionNoteCard({required this.note, required this.onEdit});

  final String? note;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasNote = note != null && note!.isNotEmpty;

    return AppInfoSection(
      icon: CupertinoIcons.pencil_ellipsis_rectangle,
      title: '学习反思',
      iconColor: AppColors.primary,
      backgroundColor: AppColors.primaryContainerLight,
      borderColor: const Color(0xFFC7D2FE),
      titleColor: AppColors.primaryDark,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              child: hasNote
                  ? Text(
                      note!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colorScheme.onSurface,
                      ),
                    )
                  : Text(
                      '点此添加学习反思…',
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            icon: const Icon(CupertinoIcons.pencil, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '编辑学习反思',
            color: colorScheme.onSurfaceVariant,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _StudentAnswerCard extends StatelessWidget {
  const _StudentAnswerCard({
    required this.answer,
    required this.contentFormat,
    required this.onEdit,
  });

  final String answer;
  final QuestionContentFormat contentFormat;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppInfoSection(
      icon: CupertinoIcons.doc_richtext,
      title: '我的答案',
      iconColor: AppColors.accentTeal,
      backgroundColor: AppColors.accentTealContainerLight,
      borderColor: const Color(0xFF99F6E4),
      titleColor: AppColors.accentTeal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: MathContentView(
              answer,
              contentFormat: contentFormat,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          IconButton(
            icon: const Icon(CupertinoIcons.pencil, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '编辑我的答案',
            color: colorScheme.onSurfaceVariant,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// 标准答案卡片，附带 AI 判分入口与判分结果徽章。
///
/// 仅当题目已有学生作答时显示（判分才有意义），由父组件控制显示条件。
class _ExpectedAnswerCard extends StatefulWidget {
  const _ExpectedAnswerCard({
    required this.expectedAnswer,
    required this.studentAnswer,
    required this.isCorrect,
    required this.contentFormat,
    required this.onEdit,
    required this.onGrade,
  });

  final String? expectedAnswer;
  final String? studentAnswer;
  final bool? isCorrect;
  final QuestionContentFormat contentFormat;
  final VoidCallback onEdit;
  final Future<void> Function() onGrade;

  @override
  State<_ExpectedAnswerCard> createState() => _ExpectedAnswerCardState();
}

class _ExpectedAnswerCardState extends State<_ExpectedAnswerCard> {
  bool _grading = false;

  Future<void> _handleGrade() async {
    if (_grading) return;
    setState(() => _grading = true);
    try {
      await widget.onGrade();
    } finally {
      if (mounted) {
        setState(() => _grading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasAnswer =
        widget.expectedAnswer != null && widget.expectedAnswer!.isNotEmpty;

    return AppInfoSection(
      icon: CupertinoIcons.checkmark_seal,
      title: '标准答案',
      iconColor: AppColors.primary,
      backgroundColor: AppColors.primaryContainerLight,
      borderColor: const Color(0xFFC7D2FE),
      titleColor: AppColors.primaryDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: hasAnswer
                    ? MathContentView(
                        widget.expectedAnswer!,
                        contentFormat: widget.contentFormat,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: colorScheme.onSurface,
                        ),
                      )
                    : GestureDetector(
                        onTap: widget.onEdit,
                        child: Text(
                          '点此填写标准答案，用于 AI 判分…',
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: AppSpace.sm),
              IconButton(
                icon: const Icon(CupertinoIcons.pencil, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: '编辑标准答案',
                color: colorScheme.onSurfaceVariant,
                onPressed: widget.onEdit,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: <Widget>[
              if (widget.isCorrect != null) ...<Widget>[
                _buildCorrectnessBadge(widget.isCorrect!),
                const SizedBox(width: AppSpace.sm),
                OutlinedButton.icon(
                  onPressed: _grading ? null : _handleGrade,
                  icon: _grading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.arrow_2_circlepath,
                          size: 14),
                  label: Text(_grading ? '判分中' : '重新判分'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _grading ? null : _handleGrade,
                  icon: _grading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(CupertinoIcons.sparkles, size: 14),
                  label: Text(_grading ? '判分中…' : 'AI 判分'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCorrectnessBadge(bool isCorrect) {
    final color =
        isCorrect ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isCorrect
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.xmark_circle_fill,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isCorrect ? '判分正确' : '判分错误',
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _MasteryTag extends StatelessWidget {
  const _MasteryTag({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context) {
    final color = _masteryColor(context, current.masteryLevel);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppTag(
      label: _masteryLabel(current.masteryLevel),
      textColor: isDark ? Theme.of(context).colorScheme.onSurface : color,
      backgroundColor: color.withValues(alpha: isDark ? 0.16 : 0.1),
    );
  }
}

String _masteryLabel(MasteryLevel level) {
  switch (level) {
    case MasteryLevel.newQuestion:
      return '待复习';
    case MasteryLevel.reviewing:
      return '复习中';
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

class _AddTagButton extends StatelessWidget {
  const _AddTagButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(CupertinoIcons.plus, size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('添加标签',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _LearningProfileGrid extends StatelessWidget {
  const _LearningProfileGrid({
    required this.question,
    required this.editing,
    this.onToggleFavorite,
    this.onEditSource,
    this.onEditLearningContext,
  });

  final QuestionRecord question;
  final bool editing;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEditSource;
  final VoidCallback? onEditLearningContext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final category = question.mistakeCategory?.label ?? '未分类';
    final nextReview = question.nextReviewAt == null
        ? '待安排'
        : _formatProfileDate(question.nextReviewAt!);

    final items = <_ProfileData>[
      _ProfileData(
          icon: CupertinoIcons.exclamationmark_triangle,
          label: '错因',
          value: category),
      _ProfileData(
          icon: CupertinoIcons.clock,
          label: '下次复习',
          value: nextReview),
      _ProfileData(
          icon: question.isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
          label: '收藏',
          value: question.isFavorite ? '已收藏' : '未收藏',
          isAction: editing,
          onTap: onToggleFavorite),
      _ProfileData(
          icon: CupertinoIcons.folder,
          label: '来源',
          value: question.source ?? '未设置',
          isAction: editing,
          onTap: onEditSource),
      _ProfileData(
          icon: CupertinoIcons.person_crop_circle,
          label: '学习阶段',
          value: question.learningStage ?? '未设置',
          isAction: editing,
          onTap: onEditLearningContext),
      if (question.difficulty != null)
        _ProfileData(
            icon: CupertinoIcons.chart_bar,
            label: '层级',
            value: _difficultyLabel(question.difficulty!)),
      if (question.attemptStatus != null)
        _ProfileData(
            icon: CupertinoIcons.pencil_ellipsis_rectangle,
            label: '作答',
            value: _attemptStatusLabel(question.attemptStatus!)),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      borderRadius: AppRadius.large,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(AppStrings.detailLearningProfile,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.md),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: AppSpace.sm,
            crossAxisSpacing: AppSpace.sm,
            childAspectRatio: 2.8,
            children: items.map((item) => _ProfileTile(data: item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.icon,
    required this.label,
    required this.value,
    this.isAction = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isAction;
  final VoidCallback? onTap;
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.data});

  final _ProfileData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(data.icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(data.label,
                    style: TextStyle(
                        fontSize: 10, color: colorScheme.onSurfaceVariant)),
                Text(data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface)),
              ],
            ),
          ),
          if (data.isAction)
            Icon(CupertinoIcons.pencil,
                size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        ],
      ),
    );

    if (!data.isAction || data.onTap == null) return child;
    return InkWell(
      onTap: data.onTap,
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: child,
    );
  }
}

class _AnalysisTab extends StatelessWidget {
  const _AnalysisTab({
    required this.current,
    required this.result,
    required this.onSetCategory,
    required this.onAddAnalysis,
  });

  final QuestionRecord current;
  final AnalysisResult? result;
  final ValueChanged<MistakeCategory?> onSetCategory;
  final VoidCallback onAddAnalysis;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (result == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: AppCard(
          child: Column(
            children: <Widget>[
              Icon(CupertinoIcons.sparkles,
                  size: 40, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: AppSpace.md),
              const Text('当前已保存识别结果，可继续交给普通 AI 完成答案、错因、知识点和练习分析。', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: onAddAnalysis,
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
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        AppInfoSection(
          icon: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? CupertinoIcons.exclamationmark_triangle
              : CupertinoIcons.checkmark_circle,
          title: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppStrings.detailPossibleAnswer
              : AppStrings.detailCorrectAnswer,
          iconColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppColors.warning
              : AppColors.success,
          backgroundColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppColors.warningContainerLight
              : AppColors.successContainerLight,
          borderColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? const Color(0xFFFED7AA)
              : const Color(0xFFBBF7D0),
          titleColor: result!.visualAssumptionStatus == VisualAssumptionStatus.needsReview
              ? AppColors.warningDark
              : AppColors.successDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              MathContentView(
                result!.finalAnswer,
                style: TextStyle(
                    fontSize: 14,
                    color: isDark ? colorScheme.onSurface : AppColors.successDark,
                    fontWeight: FontWeight.w600),
              ),
              if (_consistencyNotice(result!) != null) ...<Widget>[
                const SizedBox(height: AppSpace.md),
                _ConsistencyNotice(notice: _consistencyNotice(result!)!),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        AppInfoSection(
          icon: CupertinoIcons.exclamationmark_triangle,
          title: AppStrings.detailMistakeReason,
          iconColor: AppColors.warning,
          backgroundColor: AppColors.warningContainerLight,
          borderColor: const Color(0xFFFED7AA),
          titleColor: AppColors.warningDark,
          child: MathContentView(
            result!.mistakeReason,
            style: TextStyle(
                fontSize: 14,
                color: isDark ? colorScheme.onSurface : AppColors.warning,
                height: 1.5),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _MistakeCategoryCard(
          selected: current.mistakeCategory,
          onChanged: onSetCategory,
        ),
        const SizedBox(height: AppSpace.md),
        AppInfoSection(
          icon: CupertinoIcons.lightbulb,
          title: AppStrings.detailStudyAdvice,
          iconColor: AppColors.accentAmber,
          backgroundColor: AppColors.accentAmberContainerLight,
          borderColor: const Color(0xFFFDE68A),
          titleColor: const Color(0xFF92400E),
          child: MathContentView(
            result!.studyAdvice,
            style: TextStyle(
                fontSize: 14,
                color: isDark ? colorScheme.onSurface : const Color(0xFFB45309),
                height: 1.5),
          ),
        ),
        if (result!.knowledgePoints.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          AppSectionTitle(AppStrings.detailKnowledgePoints,
              padding: const EdgeInsets.only(bottom: AppSpace.md)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: result!.knowledgePoints.map((p) => _KnowledgePointItem(text: p)).toList(),
          ),
        ],
        if (result!.steps.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          AppSectionTitle(AppStrings.detailSolutionSteps,
              padding: const EdgeInsets.only(bottom: AppSpace.md)),
          ...result!.steps.asMap().entries.map((e) => _SolutionStepItem(index: e.key, text: e.value)),
        ],
      ],
    );
  }

  _ConsistencyNoticeData? _consistencyNotice(AnalysisResult result) {
    switch (result.consistencyStatus) {
      case AnalysisConsistencyStatus.repaired:
        if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : 'AI 已复核答案；图中关键标注含义仍需核对',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return const _ConsistencyNoticeData(
          text: 'AI 已复核并修正答案',
          icon: CupertinoIcons.checkmark_shield,
          color: AppColors.success,
          background: Color(0xFFEFFDF5),
        );
      case AnalysisConsistencyStatus.needsReview:
        if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
          return _ConsistencyNoticeData(
            text: result.consistencyNote.isNotEmpty
                ? result.consistencyNote
                : '图中关键标注含义需核对，当前为可能解法',
            icon: CupertinoIcons.exclamationmark_triangle,
            color: AppColors.warning,
            background: AppColors.warningContainerLight,
          );
        }
        return const _ConsistencyNoticeData(
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
}

class _KnowledgePointItem extends StatelessWidget {
  const _KnowledgePointItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : AppColors.primaryContainerLight,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(
          color: isDark ? colorScheme.outlineVariant : const Color(0xFFC7D2FE),
        ),
      ),
      child: MathContentView(
        text,
        style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: isDark ? colorScheme.onSurface : AppColors.primaryDark),
      ),
    );
  }
}

class _SolutionStepItem extends StatelessWidget {
  const _SolutionStepItem({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(
          color: isDark ? colorScheme.outlineVariant : const Color(0xFFE0E7FF),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isDark ? colorScheme.primary.withValues(alpha: 0.14) : AppColors.primaryContainerLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? colorScheme.primary : AppColors.primaryDark)),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: MathContentView(
              text,
              style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PracticeTab extends StatelessWidget {
  const _PracticeTab({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        _PracticeSummaryCard(current: current),
      ],
    );
  }
}

class _RecordTab extends StatelessWidget {
  const _RecordTab({
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
    final due = const ReviewScheduleService().isDue(current);

    return ListView(
      padding: const EdgeInsets.all(AppSpace.lg),
      children: <Widget>[
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ProfileTile(
                data: _ProfileData(
                  icon: CupertinoIcons.number,
                  label: '复习次数',
                  value: '${current.reviewCount} 次',
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              _ProfileTile(
                data: _ProfileData(
                  icon: CupertinoIcons.calendar,
                  label: '上次复习',
                  value: current.lastReviewedAt == null
                      ? '从未'
                      : _formatProfileDate(current.lastReviewedAt!),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              _ProfileTile(
                data: _ProfileData(
                  icon: CupertinoIcons.clock,
                  label: '下次复习',
                  value: current.nextReviewAt == null
                      ? '待安排'
                      : _formatProfileDate(current.nextReviewAt!),
                ),
              ),
            ],
          ),
        ),
        if (due) ...<Widget>[
          const SizedBox(height: AppSpace.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('这次复习感觉如何？',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onForgot,
                        child: const Text('忘记了'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onHard,
                        child: const Text('有点模糊'),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: onEasy,
                        child: const Text('掌握了'),
                      ),
                    ),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(CupertinoIcons.tag, size: 18),
              const SizedBox(width: AppSpace.sm),
              const Text('错因分类', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (selected != null)
                TextButton(
                  onPressed: () => onChanged(null),
                  child: const Text('清除'),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
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

class _PracticeSummaryCard extends ConsumerWidget {
  const _PracticeSummaryCard({required this.current});

  final QuestionRecord current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = AppColors.primary;

    return AppCard(
      borderRadius: AppRadius.large,
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
              const SizedBox(width: AppSpace.sm),
              Text(AppStrings.detailSimilarExercises,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              const Spacer(),
              Text(
                current.savedExercises.isEmpty
                    ? '暂无练习'
                    : '${current.savedExercises.where((e) => e.isCorrect != null).length}/${current.savedExercises.length} 已答',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            current.savedExercises.isEmpty
                ? '这道错题还没有可继续的练习题。'
                : '继续基于这道原题完成练习，已作答状态会保留。',
            style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpace.lg),
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
                      ref.read(currentQuestionProvider.notifier).state = current;
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

class _BatchSiblingCard extends StatelessWidget {
  const _BatchSiblingCard(
      {required this.current, required this.group, this.onSelect});

  final QuestionRecord current;
  final QuestionBatchGroup group;
  final void Function(QuestionRecord question)? onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(CupertinoIcons.square_grid_2x2,
                  size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpace.xs),
              Text('同批题目',
                  key: const ValueKey('batchSiblingTitle'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant)),
              const SizedBox(width: AppSpace.xs),
              Text('${group.questions.length} 题',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: group.questions.map((question) {
              final selected = question.id == current.id;
              return GestureDetector(
                onTap: selected || onSelect == null ? null : () => onSelect!(question),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
        color: isDark ? notice.color.withValues(alpha: 0.14) : notice.background,
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
                color: isDark ? Theme.of(context).colorScheme.onSurface : notice.color,
                fontWeight: FontWeight.w600,
              ),
            ),
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
