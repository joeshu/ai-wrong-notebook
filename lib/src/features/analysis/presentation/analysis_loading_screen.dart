import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/shared/utils/composite_worksheet_detector.dart';

class AnalysisLoadingScreen extends ConsumerStatefulWidget {
  const AnalysisLoadingScreen({super.key});

  @override
  ConsumerState<AnalysisLoadingScreen> createState() =>
      _AnalysisLoadingScreenState();
}

class _AnalysisLoadingScreenState extends ConsumerState<AnalysisLoadingScreen> {
  String? _errorMessage;
  String? _debugInfo;
  int _step = 0;
  String? _progressText;
  Timer? _stepTimer;
  // 是否由极速模式进入（拍照后跳过裁剪/校对直接进入解析）。
  // 失败时若为 true，则提供"重新裁剪 / 重新拍照 / 取消"按钮。
  bool _isQuickCapture = false;
  // 是否处于"超时可恢复"状态。Dio 自身超时会抛 AiAnalysisException 走通用失败路径；
  // 这里再加一层总超时保险，避免极端慢响应让加载页无限旋转。
  bool _isTimeout = false;
  Timer? _timeoutTimer;
  // 上层总超时阈值。超过 Dio receiveTimeout (240s) 即不合理，给一个更早的兜底。
  static const _analysisTimeout = Duration(seconds: 120);

  final _steps = const ['正在识别题目...', '正在理解题意...', '正在生成解析...', '即将完成...'];

  @override
  void initState() {
    super.initState();
    _animateSteps();
    // 先读取极速模式标记，再启动解析流程；避免 catch 块读到默认 false
    // 时显示错误的回退按钮组。
    _initQuickCaptureThenAnalyze();
  }

  Future<void> _initQuickCaptureThenAnalyze() async {
    await _loadQuickCaptureFlag();
    if (!mounted) return;
    await _runAnalysis();
  }

  Future<void> _loadQuickCaptureFlag() async {
    try {
      final enabled = await ref
          .read(settingsRepositoryProvider)
          .isQuickCaptureEnabled();
      if (!mounted) return;
      setState(() => _isQuickCapture = enabled);
    } catch (_) {
      // 读取失败时按非极速模式处理（默认 false）。
    }
  }

  void _animateSteps() {
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_step < _steps.length - 1) {
        setState(() => _step++);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  /// 启动总超时计时器。若超过 [_analysisTimeout] 仍未完成，强制进入
  /// 超时可恢复状态，避免 Dio 慢响应导致加载页无限旋转。
  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_analysisTimeout, () {
      if (!mounted) return;
      // 已经在错误/成功态时不再覆盖。
      if (_errorMessage != null) return;
      setState(() {
        _isTimeout = true;
        _stepTimer?.cancel();
        _errorMessage = '识别超时（已等待 ${_analysisTimeout.inSeconds} 秒）。'
            '可重试当前引擎，或切换到其他识别引擎。';
      });
    });
  }

  void _clearTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  Future<void> _runAnalysis() async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }

    // 重置超时态并启动总超时计时器。
    if (_isTimeout || _errorMessage != null) {
      setState(() {
        _isTimeout = false;
        _errorMessage = null;
        _progressText = null;
        _step = 0;
      });
    }
    _startTimeoutTimer();

    final reusable = await _findReusableLocalAnalysis(current);
    if (reusable != null) {
      ref.read(currentQuestionProvider.notifier).state = reusable;
      if (mounted) {
        _stepTimer?.cancel();
        _clearTimeoutTimer();
        context.go('/analysis/result');
      }
      return;
    }

    // 检查配置并显示调试信息
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final config = await settingsRepo.getAiProviderConfig();

    String debugInfo = '配置状态:\n';
    debugInfo += '- 配置对象: ${config != null ? "存在" : "为空"}\n';
    if (config != null) {
      debugInfo +=
          '- baseUrl: ${config.baseUrl.isNotEmpty ? config.baseUrl : "(空)"}\n';
      debugInfo +=
          '- model: ${config.model.isNotEmpty ? config.model : "(空)"}\n';
      debugInfo +=
          '- apiKey: ${config.apiKey.isNotEmpty ? "[已设置(${config.apiKey.length}字符)]" : "(空)"}\n';
    } else {
      debugInfo += '\n请到设置中配置 AI 服务';
    }

    setState(() => _debugInfo = debugInfo);

    try {
      final service = ref.read(aiAnalysisServiceProvider);

      var working = current;
      final shouldAnalyzeImageDirectly = _shouldAnalyzeImageDirectly(working);
      if (working.normalizedQuestionText.isEmpty &&
          !shouldAnalyzeImageDirectly) {
        // 录入模式由 capture_entry_sheet 的模式选择器决定，默认 printed。
        final captureMode = ref.read(captureModeProvider);
        final extraction = await service.extractQuestionStructure(
          subjectName: working.subject.name,
          imagePath: working.imagePath,
          textHint: working.extractedQuestionText,
          mode: captureMode,
        );
        working = working.copyWith(
          extractedQuestionText: extraction.extractedQuestionText,
          normalizedQuestionText: extraction.normalizedQuestionText.isNotEmpty
              ? extraction.normalizedQuestionText
              : extraction.extractedQuestionText,
          subject: extraction.subject ?? working.subject,
          splitResult: extraction.splitResult,
          studentAnswer: extraction.studentAnswer,
        );
        ref.read(currentQuestionProvider.notifier).state = working;
      }

      if (!(working.splitResult?.hasMultipleCandidates ?? false)) {
        final splitSeed = _splitSeedText(working);
        if (splitSeed.isNotEmpty) {
          final splitResult = await service.splitQuestionCandidates(
            text: splitSeed,
            subjectName: working.subject.name,
          );
          if (splitResult.hasMultipleCandidates) {
            working = working.copyWith(splitResult: splitResult);
            ref.read(currentQuestionProvider.notifier).state = working;
          }
        }
      }

      var candidateSnapshots = <CandidateAnalysisPayload>[];
      CandidateAnalysisPayload? firstSuccessfulCandidate;
      if (working.splitResult?.hasMultipleCandidates ?? false) {
        final totalCandidates = working.splitResult!.candidates.length;
        if (mounted) {
          setState(() {
            _stepTimer?.cancel();
            _progressText = '正在并行分析 $totalCandidates 道题...';
          });
        }
        candidateSnapshots = await service.analyzeSplitCandidates(
          questionId: working.id,
          subjectName: working.subject.name,
          splitResult: working.splitResult!,
          imagePath: working.imagePath,
          onProgress: (completed, total, {int failed = 0}) {
            if (mounted) {
              setState(() {
                final suffix = failed > 0 ? '（$failed题失败）' : '';
                _progressText = '已完成 $completed/$total题分析$suffix';
              });
            }
          },
        );
        firstSuccessfulCandidate = candidateSnapshots
            .where((payload) => payload.isSuccessful)
            .cast<CandidateAnalysisPayload?>()
            .firstWhere((payload) => payload != null, orElse: () => null);
        if (firstSuccessfulCandidate == null) {
          throw AiAnalysisException('多题解析全部失败，请重试；系统不会保存缺少解析的子题。');
        }
      }
      final shouldUseImageForAnalysis =
          shouldAnalyzeImageDirectly || _shouldUseImageForAnalysis(working);
      final textForAnalysis = shouldUseImageForAnalysis
          ? working.extractedQuestionText
          : working.correctedText;
      if (mounted && firstSuccessfulCandidate == null) {
        setState(() {
          _progressText = shouldUseImageForAnalysis
              ? '正在使用视觉模型理解题图...'
              : '正在使用文字模型分析题目...';
        });
      }

      AnalysisResult analysis;
      if (firstSuccessfulCandidate != null) {
        analysis = firstSuccessfulCandidate.analysisResult!;
      } else {
        try {
          analysis = await service.analyzeExtractedQuestion(
            correctedText: textForAnalysis,
            subjectName: working.subject.name,
            imagePath: shouldUseImageForAnalysis ? working.imagePath : null,
          );
        } on AiAnalysisException {
          // 视觉模型失败时，已校对的文字题仍有可用价值。退回文本分析，
          // 既减少一次失败阻断，也避免为纯文本题反复发送原图。
          final fallbackText = working.correctedText.trim();
          if (!shouldUseImageForAnalysis || fallbackText.isEmpty) rethrow;
          if (mounted) {
            setState(() => _progressText = '图片分析失败，正在改用文字解析...');
          }
          analysis = await service.analyzeExtractedQuestion(
            correctedText: fallbackText,
            subjectName: working.subject.name,
            imagePath: null,
          );
        }
      }

      // AI 重构题干独立存到 aiReconstructedText，不再覆盖 normalizedQuestionText
      // （用户校对文本）。详情页据此展示三段对照：OCR 原文 / 用户校对 / AI 重构。
      // 保留 extractedQuestionText（OCR 原文）以便详情页展示 OCR vs 校对后对照。
      String? aiReconstructed;
      if (firstSuccessfulCandidate == null &&
          analysis.reconstructedQuestionText.trim().isNotEmpty) {
        aiReconstructed = analysis.reconstructedQuestionText;
      }

      final generatedExercises = firstSuccessfulCandidate?.savedExercises ??
          (analysis is ParsedAnalysisResult
              ? service.extractGeneratedExercisesFromContent(
                  analysis.rawContent,
                  questionId: working.id,
                  sourceQuestionText: working.correctedText,
                )
              : service.extractGeneratedExercises(
                  analysis,
                  questionId: working.id,
                  sourceQuestionText: working.correctedText,
                ));

      final updated = working
          .copyWith(
            contentStatus: ContentStatus.ready,
            analysisResult: analysis,
            savedExercises: generatedExercises,
            subject: analysis.subject ?? working.subject,
            aiTags: analysis.aiTags,
            aiKnowledgePoints: analysis.knowledgePoints,
            aiReconstructedText: aiReconstructed,
            candidateAnalyses: candidateSnapshots.map((payload) {
              return CandidateAnalysisSnapshot(
                candidateId: payload.candidateId,
                order: payload.order,
                questionText: payload.questionText,
                analysisResult: payload.analysisResult,
                savedExercises: payload.savedExercises,
                subject: payload.subject,
                aiTags: payload.aiTags,
                aiKnowledgePoints: payload.aiKnowledgePoints,
                status: payload.status,
                errorMessage: payload.errorMessage,
              );
            }).toList(),
          )
          .withLastAnalysisError(null);
      ref.read(currentQuestionProvider.notifier).state = updated;
      await _replaceWorksheetQueueItem(updated);
      _clearTimeoutTimer();

      if (mounted) {
        _stepTimer?.cancel();
        final wasAutoQueue = ref.read(worksheetAutoAnalyzeProvider);
        if (_continueWorksheetQueue(updated)) return;
        if (wasAutoQueue) {
          context.go('/worksheet/import');
          return;
        }
        context.go('/analysis/result');
      }
    } on AiAnalysisException catch (e) {
      _clearTimeoutTimer();
      // AI 不可用时也必须保留原图和用户已校对的题干。saveDraft 是幂等
      // upsert，既覆盖同 ID 的处理中草稿，也兼容首次保存。
      // 用 analysisFailed 而非 failed，区分"识别失败"与"分析失败"，
      // 并持久化 friendlyAiErrorMessage 输出，让详情页能展示具体失败原因。
      final friendlyError = friendlyAiErrorMessage(e);
      final failedDraft = current
          .copyWith(
            contentStatus: ContentStatus.analysisFailed,
            lastAnalysisError: friendlyError,
          );
      try {
        await ref.read(questionRepositoryProvider).saveDraft(failedDraft);
        ref.read(currentQuestionProvider.notifier).state = failedDraft;
        await _replaceWorksheetQueueItem(failedDraft);
        invalidateQuestionList(ref);
      } catch (_) {
        // 持久化异常不能掩盖原始 AI 错误；错误页仍保留重试入口。
      }
      if (mounted) {
        if (_continueWorksheetQueue(failedDraft)) return;
        // 极速模式下没有"已校对题干"，文案需调整；否则保留原文案。
        final suffix = _isQuickCapture
            ? '原图已保存到错题本，可重试、切换引擎，或重新裁剪/重新拍照。'
            : '原图和已校对题干已保存到错题本，可重试、切换引擎，或稍后手动补充。';
        setState(() {
          _isTimeout = false;
          _errorMessage = '$friendlyError\n\n$suffix';
          _debugInfo = debugInfo;
        });
      }
    }
  }

  bool _continueWorksheetQueue(QuestionRecord completed) {
    if (!ref.read(worksheetAutoAnalyzeProvider)) return false;
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null || worksheet.sourcePageIds.contains(completed.id)) {
      // 队列结束：把 autoAnalyze 持久化为 false，避免重启后误以为仍在批量分析。
      Future<void>.microtask(() => setWorksheetAutoAnalyze(ref, false));
      return false;
    }
    final next = worksheet.pages.where((item) =>
        !worksheet.sourcePageIds.contains(item.id) &&
        item.contentStatus == ContentStatus.processing &&
        item.id != completed.id).toList();
    if (next.isEmpty) {
      Future<void>.microtask(() => setWorksheetAutoAnalyze(ref, false));
      return false;
    }
    ref.read(currentQuestionProvider.notifier).state = next.first;
    context.go('/analysis/loading');
    return true;
  }

  Future<void> _replaceWorksheetQueueItem(QuestionRecord record) async {
    final worksheet = ref.read(currentWorksheetImportProvider);
    if (worksheet == null || worksheet.sourcePageIds.contains(record.id)) {
      return;
    }
    final next = worksheet.pages
        .map((item) => item.id == record.id ? record : item)
        .toList();
    await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
  }

  Future<QuestionRecord?> _findReusableLocalAnalysis(QuestionRecord current) async {
    final fingerprint = ImageFingerprintCodec.read(current.tags);
    if (fingerprint == null || fingerprint.isEmpty) return null;
    final existing = await ref.read(questionRepositoryProvider).listAll();
    for (final item in existing) {
      if (item.id == current.id || item.contentStatus != ContentStatus.ready ||
          item.analysisResult == null ||
          ImageFingerprintCodec.read(item.tags) != fingerprint) {
        continue;
      }
      // Do not overwrite a user-corrected text variant with analysis from an
      // earlier version of the same image.
      if (current.correctedText.isNotEmpty &&
          current.correctedText != item.correctedText) {
        continue;
      }
      return current.copyWith(
        contentStatus: ContentStatus.ready,
        analysisResult: item.analysisResult,
        savedExercises: item.savedExercises,
        subject: item.subject,
        aiTags: item.aiTags,
        aiKnowledgePoints: item.aiKnowledgePoints,
        candidateAnalyses: item.candidateAnalyses,
      );
    }
    return null;
  }

  bool _shouldAnalyzeImageDirectly(QuestionRecord question) {
    final subject = question.subject;
    final text = question.correctedText.trim();
    if (subject == Subject.english ||
        subject == Subject.chinese ||
        subject == Subject.history ||
        subject == Subject.geography ||
        subject == Subject.politics) {
      return text.isEmpty ||
          isCompositeLanguageWorksheet(text, subject: subject);
    }
    return false;
  }

  bool _shouldUseImageForAnalysis(QuestionRecord question) {
    final text = question.correctedText.trim();
    final service = ref.read(aiAnalysisServiceProvider);
    if (service.isGraphicalQuestion(
      text,
      question.subject.name,
      imagePath: question.imagePath,
    )) {
      return true;
    }
    if (text.length < 20) return true;

    return RegExp(
      '如图|图中|图示|下图|上图|左图|右图|根据图|观察图|函数图像|坐标系|电路图|表格|统计图|示意图',
    ).hasMatch(text);
  }

  String _splitSeedText(QuestionRecord question) {
    final normalized = question.normalizedQuestionText.trim();
    if (normalized.isNotEmpty) return normalized;
    final extracted = question.extractedQuestionText.trim();
    if (extracted.isNotEmpty) return extracted;
    return question.correctedText.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 解析'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          // 极速模式下没有校对页可返回，回到首页（用户可重新打开拍照入口）。
          onPressed: () => context.go(_isQuickCapture ? '/' : '/capture/correction'),
        ),
      ),
      body: _errorMessage != null
          ? _buildErrorView()
          : _LoadingView(
              step: _step,
              steps: _steps,
              progressText: _progressText,
            ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFFEA580C).withValues(alpha: 0.16)
                    : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                CupertinoIcons.exclamationmark_circle,
                color: Color(0xFFEA580C),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF9A3412)),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('调试信息:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(_debugInfo ?? '',
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // 主操作行：重试 + 切换引擎。所有失败场景（含极速模式和超时态）
            // 都提供"重试"和"切换引擎"两个核心恢复入口。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(CupertinoIcons.arrow_clockwise),
                  label: const Text('重试'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 40)),
                ),
                OutlinedButton.icon(
                  onPressed: _showEngineSwitchDialog,
                  icon: const Icon(CupertinoIcons.arrow_2_squarepath),
                  label: const Text('切换引擎'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 次要操作：极速模式给"重新裁剪/重新拍照"，非极速给"返回校对"。
            if (_isQuickCapture)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 10,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => context.go('/capture/crop'),
                    icon: const Icon(CupertinoIcons.crop),
                    label: const Text('重新裁剪'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(CupertinoIcons.camera),
                    label: const Text('重新拍照'),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => context.go('/capture/correction'),
                    icon: const Icon(CupertinoIcons.pencil),
                    label: const Text('返回校对'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/notebook'),
                    icon: const Icon(CupertinoIcons.book),
                    label: const Text('查看已保存草稿'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _progressText = null;
      _step = 0;
    });
    _runAnalysis();
    _animateSteps();
  }

  /// 弹出引擎选择器，让用户在普通 AI / PaddleOCR / MinerU 间切换。
  /// - 选 AI：等同 [_retry]（重跑当前 AI 服务）。
  /// - 选 PaddleOCR/MinerU：设置一次性 provider type，确保当前题目在
  ///   worksheet session 中，跳转 `/worksheet/regions` 走文档识别流程。
  Future<void> _showEngineSwitchDialog() async {
    final choice = await showModalBottomSheet<_EngineChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('切换识别引擎',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '当前题目识别失败或超时。可重试当前引擎，或切换到其他引擎继续识别。',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ..._EngineChoice.values.map((item) => ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    subtitle: Text(item.description),
                    onTap: () => Navigator.pop(ctx, item),
                  )),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case _EngineChoice.ai:
        _retry();
      case _EngineChoice.paddle:
        await _switchToWorksheetEngine(LayoutProviderType.paddleCloud);
      case _EngineChoice.mineru:
        await _switchToWorksheetEngine(LayoutProviderType.mineruCloud);
    }
  }

  /// 切换到 PaddleOCR/MinerU 文档识别流程。
  /// 若当前题目已在 worksheet session 中（典型：从 capture 进入），直接
  /// 复用；否则把当前题目加入现有 session（或新建一个），再跳转。
  Future<void> _switchToWorksheetEngine(LayoutProviderType type) async {
    final current = ref.read(currentQuestionProvider);
    if (current == null) {
      if (mounted) context.go('/');
      return;
    }
    ref.read(oneShotLayoutProviderTypeProvider.notifier).state = type;

    final existing = ref.read(currentWorksheetImportProvider);
    final alreadyInSession =
        existing != null && existing.pages.any((p) => p.id == current.id);
    if (!alreadyInSession) {
      // WorksheetImportSession 的 sourcePageIds 是 final，无法通过 copyWith
      // 修改，因此这里直接构造新会话。保留已有 pages 以避免丢历史草稿。
      final pages = <QuestionRecord>[
        ...?existing?.pages,
        current,
      ];
      final sourcePageIds = <String>{
        ...?existing?.sourcePageIds,
        current.id,
      };
      await persistWorksheetImport(
        ref,
        WorksheetImportSession(
          id: existing?.id ?? '',
          pages: pages,
          sourcePageIds: sourcePageIds,
          createdAt: existing?.createdAt ?? DateTime.now(),
        ),
      );
    }
    if (mounted) context.go('/worksheet/regions');
  }
}

enum _EngineChoice {
  ai('普通 AI', '重新调用当前 AI 服务重试'),
  paddle('PaddleOCR', '文档识别：文字、公式、表格、选项'),
  mineru('MinerU', 'VLM 文档理解：复杂公式、多栏试卷');

  const _EngineChoice(this.label, this.description);
  final String label;
  final String description;

  IconData get icon => switch (this) {
        _EngineChoice.ai => CupertinoIcons.sparkles,
        _EngineChoice.paddle => CupertinoIcons.doc_text_search,
        _EngineChoice.mineru => CupertinoIcons.doc_richtext,
      };
}

class _LoadingView extends StatefulWidget {
  const _LoadingView({
    required this.step,
    required this.steps,
    this.progressText,
  });

  final int step;
  final List<String> steps;
  final String? progressText;

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    const accent = Color(0xFF6366F1);
    final hasProgress = widget.progressText != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: isDark
                    ? accent.withValues(alpha: 0.18)
                    : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(44),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) => Transform.rotate(
                  angle: _controller.value * 2 * 3.14159,
                  child: Icon(_stepIcon(widget.step),
                      size: 44, color: accent),
                ),
              ),
            ),
            const SizedBox(height: 28),
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF6366F1),
            ),
            const SizedBox(height: 28),
            // 阶段进度条：4 个圆点 + 当前阶段高亮
            if (!hasProgress) ...<Widget>[
              _StageIndicator(
                steps: widget.steps,
                current: widget.step,
                accent: accent,
                dimColor: colorScheme.outlineVariant,
              ),
              const SizedBox(height: 20),
            ],
            Text(
              hasProgress
                  ? widget.progressText!
                  : '阶段 ${widget.step + 1}/${widget.steps.length}：${widget.steps[widget.step]}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasProgress
                  ? '多题并行分析中，请稍候...'
                  : 'AI 正在生成学习分析，请稍候...',
              style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 各阶段对应图标，让用户从图标就能判断当前在做什么。
  IconData _stepIcon(int step) {
    const icons = <IconData>[
      CupertinoIcons.doc_text_search,  // 识别题目
      CupertinoIcons.lightbulb,         // 理解题意
      CupertinoIcons.wand_stars,        // 生成解析
      CupertinoIcons.checkmark_seal,    // 即将完成
    ];
    return icons[step.clamp(0, icons.length - 1)];
  }
}

/// 横向阶段进度指示器：4 个圆点 + 连接线，当前阶段高亮。
///
/// 替换原来仅靠文案滚动的展示，让用户一眼看到总进度与当前位置，
/// 减少长时间等待的焦虑感。
class _StageIndicator extends StatelessWidget {
  const _StageIndicator({
    required this.steps,
    required this.current,
    required this.accent,
    required this.dimColor,
  });

  final List<String> steps;
  final int current;
  final Color accent;
  final Color dimColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // 连接线
          final filled = i < current * 2 + 1;
          return Container(
            width: 18,
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            color: filled ? accent : dimColor,
          );
        }
        final idx = i ~/ 2;
        final isDone = idx < current;
        final isCurrent = idx == current;
        final color = isCurrent
            ? accent
            : isDone
                ? accent.withValues(alpha: 0.6)
                : dimColor;
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isCurrent ? accent : (isDone ? color : null),
            border: Border.all(color: color, width: 1.5),
            shape: BoxShape.circle,
          ),
          child: isDone
              ? const Icon(CupertinoIcons.checkmark,
                  size: 8, color: Colors.white)
              : null,
        );
      }),
    );
  }
}
