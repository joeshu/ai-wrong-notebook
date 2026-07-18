import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/data/services/custom_http_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/auto_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/mineru_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/paddle_cloud_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:uuid/uuid.dart';

/// Manual multi-region editor. A tap places a question-sized candidate box;
/// confirmed boxes are cropped into independent question drafts.
class WorksheetRegionEditorScreen extends ConsumerStatefulWidget {
  const WorksheetRegionEditorScreen({super.key});

  @override
  ConsumerState<WorksheetRegionEditorScreen> createState() =>
      _WorksheetRegionEditorScreenState();
}

class _WorksheetRegionEditorScreenState
    extends ConsumerState<WorksheetRegionEditorScreen> {
  final List<QuestionRegion> _regions = <QuestionRegion>[];
  bool _isCropping = false;
  bool _isDetecting = false;
  String? _detectionMessage;
  String? _detectionProvider;
  String? _detectionWarning;
  Duration? _detectionDuration;
  String? _selectedRegionId;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() => restoreLayoutProviderConfig(ref));
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(currentQuestionProvider);
    if (page == null || !File(page.imagePath).existsSync()) {
      return Scaffold(
        appBar: AppBar(title: const Text('整页框选切题')),
        body: const Center(child: Text('未找到可框选的试卷页面')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final layoutConfig = ref.watch(layoutProviderConfigProvider);
    final oneShotType = ref.watch(oneShotLayoutProviderTypeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('整页框选切题'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: _isCropping ? null : () => context.go('/worksheet/import'),
        ),
      ),
      body: SafeArea(
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: _DetectionActionCard(
              isDetecting: _isDetecting,
              selectedType: _selectedStrategyLabel(
                oneShotType == null
                    ? layoutConfig
                    : LayoutProviderConfig(type: oneShotType),
              ),
              onAuto: _isCropping || _isDetecting ? null : () => _detectRegions(page, override: oneShotType),
              onPaddle: _isCropping || _isDetecting || !_hasPaddleToken(layoutConfig) ? null : () => _detectRegions(page, override: LayoutProviderType.paddleCloud),
              onMineru: _isCropping || _isDetecting || !_hasMineruToken(layoutConfig) ? null : () => _detectRegions(page, override: LayoutProviderType.mineruCloud),
              onManual: _isCropping || _isDetecting ? null : _clearForManual,
              paddleReady: _hasPaddleToken(layoutConfig),
              mineruReady: _hasMineruToken(layoutConfig),
            ),
          ),
          if (_detectionProvider != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _DetectionResultCard(
                provider: _detectionProvider!,
                regions: _regions,
                duration: _detectionDuration,
                warning: _detectionWarning,
              ),
            )
          else if (_detectionMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(_detectionMessage!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              '拖动蓝色题框调整位置；拖动右下角圆点缩放；点击红色 × 删除。每个蓝框会裁成一张独立题图。自动识别题框仅为候选，确认前请逐一检查。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (_regions.isNotEmpty)
            SizedBox(
              height: MediaQuery.sizeOf(context).width < 600 ? 402 : 330,
              child: _RecognizedQuestionWorkbench(
                regions: _regions,
                defaultSubject: page.subject,
                onUpdate: (index, next) => setState(() {
                  final previous = _regions[index];
                  _regions[index] = next.copyWith(
                    originalRecognizedText: previous.originalRecognizedText ?? previous.recognizedText,
                  );
                }),
                onIgnore: (index) => setState(() {
                  final region = _regions[index];
                  _regions[index] = region.copyWith(
                    reviewStatus: region.reviewStatus == QuestionRegionReviewStatus.ignored
                        ? QuestionRegionReviewStatus.accepted
                        : QuestionRegionReviewStatus.ignored,
                  );
                }),
                selectedRegionId: _selectedRegionId,
                sourceImagePath: page.imagePath,
                onSelect: (region) => setState(() => _selectedRegionId = region.id),
              ),
            ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                onTapDown: _isCropping ? null : (details) {
                  final x = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
                  final y = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
                  setState(() {
                    final region = QuestionRegion(
                      id: const Uuid().v4(),
                      normalizedRect: Rect.fromLTWH(
                        (x - .40).clamp(0.0, .80).toDouble(),
                        (y - .10).clamp(0.0, .80).toDouble(),
                        .80,
                        .20,
                      ),
                    );
                    _regions.add(region);
                    _selectedRegionId = region.id;
                  });
                },
                child: Stack(fit: StackFit.expand, children: <Widget>[
                  Image.file(File(page.imagePath), fit: BoxFit.fill),
                  ..._regions.asMap().entries.map((entry) {
                    final quality = _RegionQuality.evaluate(_regions, entry.key);
                    return _RegionOverlay(
                      region: entry.value.copyWith(confidence: quality),
                      number: entry.key + 1,
                      canvasSize: size,
                      onDelete: () => setState(() => _regions.removeAt(entry.key)),
                      selected: entry.value.id == _selectedRegionId,
                      onSelect: () => setState(() => _selectedRegionId = entry.value.id),
                      onChanged: (rect) => setState(() {
                        _regions[entry.key] = entry.value.copyWith(
                          normalizedRect: rect,
                          confidence: entry.value.source == QuestionRegionSource.manual ? 1 : .90,
                        );
                      }),
                    );
                  }),
                ]),
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              onPressed: _isCropping || _regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.accepted).isEmpty
                  ? null
                  : () => _confirmAndCrop(page),
              icon: _isCropping
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.crop),
              label: Text(_isCropping
                  ? '正在生成独立题图...'
                  : '确认 ${_regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.accepted).length} 题：${_regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.accepted && region.analyzeWithAi).length} 题深度分析 / ${_regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.accepted && !region.analyzeWithAi).length} 题仅保存 OCR${_regions.any((region) => region.reviewStatus == QuestionRegionReviewStatus.ignored) ? ' / ${_regions.where((region) => region.reviewStatus == QuestionRegionReviewStatus.ignored).length} 题忽略' : ''}'),
              style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
            ),
          ),
        ]),
      ),
    );
  }

  bool _hasPaddleToken(LayoutProviderConfig config) =>
      config.type == LayoutProviderType.autoCloud ? config.apiKey.isNotEmpty :
      config.type == LayoutProviderType.paddleCloud && config.apiKey.isNotEmpty;

  bool _hasMineruToken(LayoutProviderConfig config) =>
      config.type == LayoutProviderType.autoCloud ? config.secondaryApiKey.isNotEmpty :
      config.type == LayoutProviderType.mineruCloud && config.apiKey.isNotEmpty;

  String _selectedStrategyLabel(LayoutProviderConfig? config) {
    switch (config?.type) {
      case LayoutProviderType.autoCloud:
        return '自动智能识别 · PaddleOCR → MinerU 兜底';
      case LayoutProviderType.paddleCloud:
        return 'PaddleOCR AI Studio · 快速识别';
      case LayoutProviderType.mineruCloud:
        return 'MinerU VLM · 深度解析';
      case LayoutProviderType.currentVision:
        return '当前 AI 视觉模型';
      case LayoutProviderType.customHttp:
        return '自定义 HTTP 版面服务';
      case LayoutProviderType.manualOnly:
        return '仅手动框选';
      case null:
        return '正在读取识别设置…';
    }
  }

  void _clearForManual() {
    setState(() {
      _regions.clear();
      _detectionProvider = null;
      _detectionWarning = null;
      _detectionDuration = null;
      _detectionMessage = '已切换为手动框选：点击试卷空白处可新增题框。';
    });
  }

  Future<void> _detectRegions(QuestionRecord page, {LayoutProviderType? override}) async {
    final startedAt = DateTime.now();
    setState(() {
      _isDetecting = true;
      _detectionMessage = override == LayoutProviderType.paddleCloud
          ? '正在使用 PaddleOCR 快速识别…'
          : override == LayoutProviderType.mineruCloud
              ? '正在使用 MinerU VLM 深度解析…'
              : '正在准备识别试卷版面…';
      _detectionProvider = null;
      _detectionWarning = null;
      _detectionDuration = null;
    });
    try {
      final config = override == null
          ? await restoreLayoutProviderConfig(ref)
          : await ref.read(layoutProviderRepositoryProvider).loadForType(override);
      final type = override ?? config.type;
      final effectiveConfig = config;
      if (type == LayoutProviderType.manualOnly) {
        if (mounted) setState(() => _detectionMessage = '当前设置为仅手动框选；可直接点击页面新增题框。');
        return;
      }
      final result = type == LayoutProviderType.customHttp
          ? await CustomHttpDocumentLayoutService(effectiveConfig)
              .detectQuestionRegions(imagePath: page.imagePath)
          : type == LayoutProviderType.paddleCloud
              ? await PaddleCloudDocumentLayoutService(effectiveConfig)
                  .detectQuestionRegions(imagePath: page.imagePath)
              : type == LayoutProviderType.mineruCloud
                  ? await MineruDocumentLayoutService(effectiveConfig)
                      .detectQuestionRegions(imagePath: page.imagePath)
                  : type == LayoutProviderType.autoCloud
                      ? await AutoDocumentLayoutService(
                          effectiveConfig,
                          onProgress: (message) {
                            if (mounted) setState(() => _detectionMessage = message);
                          },
                        ).detectQuestionRegions(imagePath: page.imagePath)
                  : await ref
                      .read(visionDocumentLayoutServiceProvider)
                      .detectQuestionRegions(imagePath: page.imagePath);
      if (!mounted) return;
      setState(() {
        _regions
          ..clear()
          ..addAll(result.regions);
        _selectedRegionId = _regions.isEmpty ? null : _regions.first.id;
        _detectionProvider = result.providerLabel;
        _detectionWarning = result.warning;
        _detectionDuration = DateTime.now().difference(startedAt);
        _detectionMessage = '已生成候选框，请逐一检查后确认裁切。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _detectionMessage = '自动识别失败：$e。你仍可手动点击页面新增题框。');
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _editRecognizedText(int index) async {
    final region = _regions[index];
    final controller = TextEditingController(text: region.recognizedText ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('编辑第 ${region.detectedNumber ?? index + 1} 题文字'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '可校对文字、公式 LaTex 与表格 Markdown',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('采用文字')),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    setState(() {
      _regions[index] = region.copyWith(
        recognizedText: saved,
        contentFormatHint: saved.contains(r'$') || saved.contains(r'\\')
            ? 'latexMixed'
            : 'plain',
      );
    });
  }

  Future<void> _confirmAndCrop(QuestionRecord source) async {
    final accepted = _regions.where((item) => item.reviewStatus == QuestionRegionReviewStatus.accepted).toList();
    final aiCount = accepted.where((item) => item.analyzeWithAi).length;
    final ocrCount = accepted.length - aiCount;
    final ignoredCount = _regions.length - accepted.length;
    final risky = accepted.where((item) {
      final edge = item.normalizedRect.left < .01 || item.normalizedRect.top < .01 ||
          item.normalizedRect.right > .99 || item.normalizedRect.bottom > .99;
      return (item.recognizedText ?? '').trim().isEmpty ||
          (item.source == QuestionRegionSource.layoutModel && item.confidence < .60) || edge;
    }).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认本页处理方式'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('本页共 ${_regions.length} 道候选题：'),
          const SizedBox(height: 8),
          Text('✓ $aiCount 题：裁切后交给普通 AI 深度分析'),
          Text('✓ $ocrCount 题：仅保存 OCR / 文档结果'),
          if (ignoredCount > 0) Text('⊘ $ignoredCount 题：忽略，不裁切也不保存'),
          if (risky > 0) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('⚠ $risky 题存在空题干、低可信度或贴边题框；建议返回继续校对。', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
          ),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('返回继续校对')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('确认生成')),
        ],
      ),
    );
    if (confirmed == true && mounted) await _cropAndQueue(source);
  }

  Future<void> _cropAndQueue(QuestionRecord source) async {
    setState(() => _isCropping = true);
    try {
      final cropper = ref.read(questionRegionCropServiceProvider);
      final candidates = <QuestionRecord>[];
      for (final region in _regions.where((item) => item.reviewStatus == QuestionRegionReviewStatus.accepted)) {
        final path = await cropper.cropToStoredImage(sourcePath: source.imagePath, region: region);
        final fingerprint = await ImageFingerprintCodec.fromFile(File(path));
        candidates.add(QuestionRecord.draft(
          id: const Uuid().v4(),
          imagePath: path,
          subject: region.subject ?? source.subject,
          recognizedText: region.recognizedText ?? '',
          contentFormat: region.contentFormatHint == 'latexMixed'
              ? QuestionContentFormat.latexMixed
              : QuestionContentFormat.plain,
        ).copyWith(
          contentStatus: region.analyzeWithAi
              ? ContentStatus.processing
              : ContentStatus.ready,
          tags: (ImageFingerprintCodec.write(source.tags, fingerprint)
            ..removeWhere((tag) => tag.startsWith('layout_provider:') || tag.startsWith('question_type:') || tag.startsWith('document_blocks:'))
            ..add('layout_provider:${_detectionProvider ?? '手动框选'}')
            ..addAll(region.questionType == null || region.questionType!.isEmpty ? const <String>[] : <String>['question_type:${region.questionType}'])
            ..addAll(region.recognizedBlockTypes.isEmpty ? const <String>[] : <String>['document_blocks:${region.recognizedBlockTypes.join('+')}'])),
          parentQuestionId: source.id,
          rootQuestionId: source.rootQuestionId ?? source.id,
        ));
      }
      final worksheet = ref.read(currentWorksheetImportProvider);
      if (worksheet != null) {
        final next = worksheet.pages.where((item) => item.id != source.id).toList()
          ..addAll(candidates);
        await persistWorksheetImport(ref, worksheet.copyWith(pages: next));
      }
      final nextForAnalysis = candidates.firstWhere(
        (candidate) => candidate.contentStatus == ContentStatus.processing,
        orElse: () => candidates.first,
      );
      ref.read(currentQuestionProvider.notifier).state = nextForAnalysis;
      if (!mounted) return;
      if (nextForAnalysis.contentStatus == ContentStatus.ready) {
        context.go('/worksheet/import');
      } else {
        context.go('/analysis/loading');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成题图失败: $e')));
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }
}

class _RegionOverlay extends StatelessWidget {
  const _RegionOverlay({
    required this.region,
    required this.number,
    required this.canvasSize,
    required this.onDelete,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
  });
  final QuestionRegion region;
  final int number;
  final Size canvasSize;
  final VoidCallback onDelete;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Rect> onChanged;

  @override
  Widget build(BuildContext context) {
    final r = region.normalizedRect;
    return Positioned(
      left: r.left * canvasSize.width,
      top: r.top * canvasSize.height,
      width: r.width * canvasSize.width,
      height: r.height * canvasSize.height,
      child: _ResizableRegion(
        region: r,
        canvasSize: canvasSize,
        number: number,
        source: region.source,
        confidence: region.confidence,
        detectedNumber: region.detectedNumber,
        selected: selected,
        onSelect: onSelect,
        onDelete: onDelete,
        onChanged: onChanged,
      ),
    );
  }
}


class _ResizableRegion extends StatefulWidget {
  const _ResizableRegion({
    required this.region,
    required this.canvasSize,
    required this.number,
    required this.source,
    required this.confidence,
    required this.detectedNumber,
    required this.selected,
    required this.onSelect,
    required this.onDelete,
    required this.onChanged,
  });

  final Rect region;
  final Size canvasSize;
  final int number;
  final QuestionRegionSource source;
  final double confidence;
  final String? detectedNumber;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  final ValueChanged<Rect> onChanged;

  @override
  State<_ResizableRegion> createState() => _ResizableRegionState();
}

class _ResizableRegionState extends State<_ResizableRegion> {
  late Rect _region;

  @override
  void initState() {
    super.initState();
    _region = widget.region;
  }

  @override
  void didUpdateWidget(covariant _ResizableRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region != widget.region) _region = widget.region;
  }

  void _move(Offset delta) {
    final dx = delta.dx / widget.canvasSize.width;
    final dy = delta.dy / widget.canvasSize.height;
    _update(Rect.fromLTWH(
      (_region.left + dx).clamp(0.0, 1 - _region.width).toDouble(),
      (_region.top + dy).clamp(0.0, 1 - _region.height).toDouble(),
      _region.width,
      _region.height,
    ));
  }

  void _resize(Offset delta) {
    final width = (_region.width + delta.dx / widget.canvasSize.width)
        .clamp(.10, 1 - _region.left)
        .toDouble();
    final height = (_region.height + delta.dy / widget.canvasSize.height)
        .clamp(.06, 1 - _region.top)
        .toDouble();
    _update(Rect.fromLTWH(_region.left, _region.top, width, height));
  }

  void _update(Rect next) {
    setState(() => _region = next);
    widget.onChanged(next);
  }

  Color _qualityColor() {
    if (widget.source == QuestionRegionSource.manual) return const Color(0xFF64748B);
    if (widget.confidence >= .80) return const Color(0xFF16A34A);
    if (widget.confidence >= .60) return const Color(0xFF2563EB);
    return const Color(0xFFEA580C);
  }

  String _qualityLabel() {
    if (widget.source == QuestionRegionSource.manual) return '手动';
    if (widget.confidence >= .80) return '较可靠';
    if (widget.confidence >= .60) return '建议检查';
    return '建议调整';
  }

  @override
  Widget build(BuildContext context) {
    final qualityColor = _qualityColor();
    final borderColor = widget.selected ? const Color(0xFF7C3AED) : qualityColor;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: widget.selected ? 4 : 2),
        color: borderColor.withValues(alpha: widget.selected ? .18 : .08),
      ),
      child: Stack(children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onSelect,
            onPanUpdate: (details) => _move(details.delta),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(
              color: qualityColor,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text(widget.source == QuestionRegionSource.manual
                  ? '手动 · 题 ${widget.number}'
                  : '${widget.detectedNumber ?? widget.number}题 · ${_qualityLabel()} ${(widget.confidence * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            Material(
              color: const Color(0xFFDC2626),
              child: InkWell(
                onTap: widget.onDelete,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Icon(CupertinoIcons.xmark,
                      color: Colors.white, size: 14),
                ),
              ),
            ),
          ]),
        ),
        Positioned(
          right: -8,
          bottom: -8,
          child: GestureDetector(
            onPanUpdate: (details) => _resize(details.delta),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: qualityColor, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(CupertinoIcons.arrow_down_right,
                  size: 14, color: qualityColor),
            ),
          ),
        ),
      ]),
    );
  }
}


class _DetectionActionCard extends StatelessWidget {
  const _DetectionActionCard({
    required this.isDetecting,
    required this.selectedType,
    required this.onAuto,
    required this.onPaddle,
    required this.onMineru,
    required this.onManual,
    required this.paddleReady,
    required this.mineruReady,
  });
  final bool isDetecting;
  final String selectedType;
  final VoidCallback? onAuto;
  final VoidCallback? onPaddle;
  final VoidCallback? onMineru;
  final VoidCallback? onManual;
  final bool paddleReady;
  final bool mineruReady;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFFF0F9FF),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const Icon(CupertinoIcons.viewfinder_circle, color: Color(0xFF0369A1)),
          const SizedBox(width: 8),
          Expanded(child: Text(isDetecting ? selectedType : '识别策略：$selectedType', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (isDetecting) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 6),
        Text(isDetecting ? '请保持页面打开；会显示最终采用的服务与耗时。' : '自动策略会先快速识别，结果不足才升级深度解析。', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          FilledButton.tonalIcon(onPressed: onAuto, icon: const Icon(CupertinoIcons.sparkles, size: 16), label: const Text('按当前策略识别')),
          OutlinedButton(onPressed: onPaddle, child: Text(paddleReady ? '快速 PaddleOCR' : 'PaddleOCR · 未配置')),
          OutlinedButton(onPressed: onMineru, child: Text(mineruReady ? '深度 MinerU' : 'MinerU · 未配置')),
          TextButton(onPressed: onManual, child: const Text('仅手动框选')),
        ]),
        if (!paddleReady || !mineruReady) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('未配置的服务不可用；请到「设置 → 试卷版面识别」填写 Token。', style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412))),
        ),
      ]),
    ),
  );
}

class _DetectionResultCard extends StatelessWidget {
  const _DetectionResultCard({required this.provider, required this.regions, required this.duration, required this.warning});
  final String provider;
  final List<QuestionRegion> regions;
  final Duration? duration;
  final String? warning;

  String _structureSummary(List<QuestionRegion> regions) {
    final counts = <String, int>{};
    for (final region in regions) {
      for (final type in region.recognizedBlockTypes.where((type) => type != '文字')) {
        counts[type] = (counts[type] ?? 0) + 1;
      }
    }
    return counts.entries.map((entry) => '${entry.key} ${entry.value}').join(' · ');
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: const Color(0xFFF0FDF4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Row(children: <Widget>[Icon(CupertinoIcons.check_mark_circled_solid, color: Color(0xFF16A34A)), SizedBox(width: 8), Text('候选题框已生成', style: TextStyle(fontWeight: FontWeight.w700))]),
        const SizedBox(height: 7),
        Text('最终服务：$provider', style: const TextStyle(fontSize: 12)),
        Text('识别结果：${regions.length} 道候选题${duration == null ? '' : ' · 耗时 ${duration!.inSeconds}s'}', style: const TextStyle(fontSize: 12)),
        if (regions.any((region) => (region.recognizedText ?? '').trim().isNotEmpty)) ...<Widget>[
          const SizedBox(height: 6),
          Text('已同时提取题目文字/公式：${regions.where((region) => (region.recognizedText ?? '').trim().isNotEmpty).length} 道。确认题框后会带入下一步校对，不会丢弃。', style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
          if (_structureSummary(regions).isNotEmpty)
            Text('结构识别：${_structureSummary(regions)}', style: const TextStyle(fontSize: 12, color: Color(0xFF166534))),
        ],
        if (warning != null && warning!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5), child: Text('提示：$warning', style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)))),
        const Padding(padding: EdgeInsets.only(top: 5), child: Text('请检查蓝框边界；可拖动、缩放、删除，或点击试卷增加题框。', style: TextStyle(fontSize: 12, color: Color(0xFF475569)))),
      ]),
    ),
  );
}


class _RegionQuality {
  static double evaluate(List<QuestionRegion> regions, int index) {
    final region = regions[index];
    if (region.source == QuestionRegionSource.manual) return 1;
    var score = region.confidence.clamp(0.0, 1.0).toDouble();
    for (var i = 0; i < regions.length; i++) {
      if (i == index) continue;
      if (_iou(region.normalizedRect, regions[i].normalizedRect) > .35) {
        score = (score * .65).clamp(0.0, 1.0).toDouble();
      }
    }
    if (region.normalizedRect.left < .01 || region.normalizedRect.top < .01 ||
        region.normalizedRect.right > .99 || region.normalizedRect.bottom > .99) {
      score = (score * .8).clamp(0.0, 1.0).toDouble();
    }
    return score;
  }

  static double _iou(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) return 0;
    final intersection = overlap.width * overlap.height;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}


class _RecognizedQuestionWorkbench extends StatefulWidget {
  const _RecognizedQuestionWorkbench({
    required this.regions,
    required this.defaultSubject,
    required this.onUpdate,
    required this.onIgnore,
    required this.selectedRegionId,
    required this.sourceImagePath,
    required this.onSelect,
  });
  final List<QuestionRegion> regions;
  final Subject defaultSubject;
  final void Function(int index, QuestionRegion region) onUpdate;
  final ValueChanged<int> onIgnore;
  final String? selectedRegionId;
  final String sourceImagePath;
  final ValueChanged<QuestionRegion> onSelect;

  @override
  State<_RecognizedQuestionWorkbench> createState() =>
      _RecognizedQuestionWorkbenchState();
}

class _RecognizedQuestionWorkbenchState
    extends State<_RecognizedQuestionWorkbench> {
  static const _questionTypes = <String>[
    '未指定', '选择题', '填空题', '计算题', '证明题', '应用题',
  ];
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant _RecognizedQuestionWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.regions.length) {
      _selectedIndex = widget.regions.isEmpty ? 0 : widget.regions.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.regions.isEmpty) return const SizedBox.shrink();
    final selectedById = widget.selectedRegionId == null
        ? -1
        : widget.regions.indexWhere((item) => item.id == widget.selectedRegionId);
    final index = (selectedById >= 0 ? selectedById : _selectedIndex)
        .clamp(0, widget.regions.length - 1);
    final region = widget.regions[index];
    final subject = region.subject ?? widget.defaultSubject;
    final type = region.questionType ?? '未指定';
    final risks = _riskMessages(index);
    final acceptedCount = widget.regions.where((item) => item.reviewStatus == QuestionRegionReviewStatus.accepted).length;
    final ignoredCount = widget.regions.length - acceptedCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(children: <Widget>[
        ListTile(
          dense: true,
          leading: const Icon(CupertinoIcons.doc_text_search),
          title: Text('逐题确认工作台 · 第 ${index + 1}/${widget.regions.length} 题'),
          subtitle: Text('已采用 $acceptedCount 题${ignoredCount > 0 ? ' · 已忽略 $ignoredCount 题' : ''}；可切换题目完整校对', style: const TextStyle(fontSize: 11)),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final list = _buildQuestionList(context, index, horizontal: compact);
            final detail = _buildDetail(context, index, region, subject, type, risks, widget.sourceImagePath);
            if (compact) {
              return Column(children: <Widget>[
                SizedBox(height: 78, child: list),
                const Divider(height: 1),
                Expanded(child: detail),
              ]);
            }
            return Row(children: <Widget>[
              SizedBox(width: 132, child: list),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ]);
          }),
        ),
      ]),
    );
  }

  List<String> _riskMessages(int index) {
    final region = widget.regions[index];
    final risks = <String>[];
    if ((region.recognizedText ?? '').trim().isEmpty) {
      risks.add('未识别到题干文字');
    }
    if (region.source == QuestionRegionSource.layoutModel && region.confidence < .60) {
      risks.add('识别可信度较低，建议校对');
    }
    if (region.normalizedRect.left < .01 || region.normalizedRect.top < .01 ||
        region.normalizedRect.right > .99 || region.normalizedRect.bottom > .99) {
      risks.add('题框贴近页面边缘，可能被截断');
    }
    for (var i = 0; i < widget.regions.length; i++) {
      if (i == index) continue;
      final overlap = region.normalizedRect.intersect(widget.regions[i].normalizedRect);
      final union = region.normalizedRect.width * region.normalizedRect.height +
          widget.regions[i].normalizedRect.width * widget.regions[i].normalizedRect.height -
          overlap.width * overlap.height;
      if (!overlap.isEmpty && union > 0 && overlap.width * overlap.height / union > .35) {
        risks.add('与第 ${widget.regions[i].detectedNumber ?? i + 1} 题题框重叠');
        break;
      }
    }
    if (region.recognizedBlockTypes.any((item) => item == '公式' || item == '表格')) {
      risks.add('含公式或表格，建议核对格式');
    }
    return risks;
  }

  Widget _buildQuestionList(BuildContext context, int selectedIndex,
      {required bool horizontal}) {
    return ListView.builder(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      padding: const EdgeInsets.all(6),
      itemCount: widget.regions.length,
      itemBuilder: (context, itemIndex) {
        final item = widget.regions[itemIndex];
        final selected = itemIndex == selectedIndex;
        final ignored = item.reviewStatus == QuestionRegionReviewStatus.ignored;
        return Padding(
          padding: horizontal
              ? const EdgeInsets.only(right: 6)
              : const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            width: horizontal ? 112 : double.infinity,
            child: Material(
              color: ignored
                  ? Theme.of(context).colorScheme.surfaceContainerLow
                  : selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  setState(() => _selectedIndex = itemIndex);
                  widget.onSelect(item);
                },
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text('第 ${item.detectedNumber ?? itemIndex + 1} 题', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        Icon(ignored ? CupertinoIcons.minus_circle_fill : item.analyzeWithAi ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.doc_text, size: 14, color: ignored ? const Color(0xFF64748B) : item.analyzeWithAi ? const Color(0xFF16A34A) : const Color(0xFF2563EB)),
                      ]),
                      const SizedBox(height: 3),
                      Wrap(spacing: 2, runSpacing: 2, children: item.recognizedBlockTypes.where((block) => block != '文字').take(2).map(_MiniTypeTag.new).toList()),
                      const SizedBox(height: 3),
                      Text(ignored ? '⊘ 已忽略' : item.analyzeWithAi ? '✓ 采用 + AI' : '✓ 采用 · 仅 OCR', style: const TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int? _nextRiskIndex(int current) {
    for (var step = 1; step <= widget.regions.length; step++) {
      final index = (current + step) % widget.regions.length;
      if (_riskMessages(index).isNotEmpty) return index;
    }
    return null;
  }

  Future<Size> _sourceImageSize(String imagePath) async {
    final image = await decodeImageFromList(await File(imagePath).readAsBytes());
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Future<void> _showCropPreview(BuildContext context, QuestionRegion region, String imagePath) async {
    final sourceSize = await _sourceImageSize(imagePath);
    if (!context.mounted) return;
    final cropAspect = sourceSize.width * region.normalizedRect.width /
        (sourceSize.height * region.normalizedRect.height);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('最终裁切预览'),
        content: AspectRatio(
          aspectRatio: cropAspect,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LayoutBuilder(builder: (context, constraints) {
              final scale = constraints.maxWidth / region.normalizedRect.width;
              return Stack(children: <Widget>[
                Positioned(
                  left: -region.normalizedRect.left * scale,
                  top: -region.normalizedRect.top * scale,
                  width: scale,
                  child: Image.file(File(imagePath), fit: BoxFit.fitWidth),
                ),
              ]);
            }),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('返回调整题框')),
        ],
      ),
    );
  }

  String _stemFor(QuestionRegion region) {
    if (region.questionStem != null) return region.questionStem!;
    final formula = RegExp(r'\$[^$]+\$');
    return (region.recognizedText ?? '').split('\n')
        .where((line) => !formula.hasMatch(line) && !line.trimLeft().startsWith('|'))
        .join('\n').trim();
  }

  List<String> _formulasFor(QuestionRegion region) {
    if (region.formulas.isNotEmpty) return region.formulas;
    return RegExp(r'\$[^$]+\$').allMatches(region.recognizedText ?? '')
        .map((match) => match.group(0)!).toList();
  }

  List<String> _tablesFor(QuestionRegion region) {
    if (region.tables.isNotEmpty) return region.tables;
    final lines = (region.recognizedText ?? '').split('\n')
        .where((line) => line.trimLeft().startsWith('|')).toList();
    return lines.isEmpty ? const <String>[] : <String>[lines.join('\n')];
  }

  List<DocumentBlock> _orderedBlocks(QuestionRegion region, String stem,
      List<String> formulas, List<String> tables) {
    if (region.documentBlocks.isEmpty) return <DocumentBlock>[
      if (stem.trim().isNotEmpty) DocumentBlock(type: DocumentBlockType.text, content: stem),
      ...formulas.map((item) => DocumentBlock(type: DocumentBlockType.formula, content: item)),
      ...tables.map((item) => DocumentBlock(type: DocumentBlockType.table, content: item)),
    ];
    final remaining = <DocumentBlockType, List<String>>{
      DocumentBlockType.text: <String>[stem],
      DocumentBlockType.formula: List<String>.from(formulas),
      DocumentBlockType.table: List<String>.from(tables),
    };
    final next = <DocumentBlock>[];
    for (final block in region.documentBlocks) {
      final values = remaining[block.type]!;
      if (values.isNotEmpty) next.add(DocumentBlock(type: block.type, content: values.removeAt(0)));
    }
    for (final type in DocumentBlockType.values) {
      next.addAll(remaining[type]!.where((item) => item.trim().isNotEmpty)
          .map((item) => DocumentBlock(type: type, content: item)));
    }
    return next;
  }

  void _updateStructured(int index, QuestionRegion region, {
    String? stem, List<String>? formulas, List<String>? tables,
  }) {
    final nextStem = stem ?? _stemFor(region);
    final nextFormulas = formulas ?? _formulasFor(region);
    final nextTables = tables ?? _tablesFor(region);
    final blocks = _orderedBlocks(region, nextStem, nextFormulas, nextTables);
    final combined = blocks.where((block) => block.content.trim().isNotEmpty)
        .map((block) => block.content).join('\n\n');
    widget.onUpdate(index, region.copyWith(
      questionStem: nextStem,
      formulas: nextFormulas,
      tables: nextTables,
      documentBlocks: blocks,
      recognizedText: combined,
      contentFormatHint: nextFormulas.isEmpty ? 'plain' : 'latexMixed',
    ));
  }

  Widget _buildDetail(BuildContext context, int index, QuestionRegion region,
      Subject subject, String type, List<String> risks, String sourceImagePath) {
    final stem = _stemFor(region);
    final formulas = _formulasFor(region);
    final tables = _tablesFor(region);
    final original = region.originalRecognizedText ?? region.recognizedText ?? '';
    final modified = region.originalRecognizedText != null && region.recognizedText != original;
    return ListView(
      key: ValueKey(region.id),
      padding: const EdgeInsets.all(10),
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('第 ${region.detectedNumber ?? index + 1} 题详情', style: const TextStyle(fontWeight: FontWeight.w700))),
          ...region.recognizedBlockTypes.where((block) => block != '文字').map(_MiniTypeTag.new),
          TextButton.icon(
            onPressed: () => widget.onIgnore(index),
            icon: Icon(region.reviewStatus == QuestionRegionReviewStatus.ignored
                ? CupertinoIcons.arrow_counterclockwise
                : CupertinoIcons.minus_circle, size: 16),
            label: Text(region.reviewStatus == QuestionRegionReviewStatus.ignored ? '恢复采用' : '忽略'),
          ),
        ]),
        Row(children: <Widget>[
          TextButton.icon(
            onPressed: index == 0 ? null : () {
              setState(() => _selectedIndex = index - 1);
              widget.onSelect(widget.regions[index - 1]);
            },
            icon: const Icon(CupertinoIcons.chevron_left, size: 15),
            label: const Text('上一题'),
          ),
          Text('${index + 1} / ${widget.regions.length}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          TextButton.icon(
            onPressed: index >= widget.regions.length - 1 ? null : () {
              setState(() => _selectedIndex = index + 1);
              widget.onSelect(widget.regions[index + 1]);
            },
            icon: const Icon(CupertinoIcons.chevron_right, size: 15),
            label: const Text('下一题'),
          ),
        ]),
        if (risks.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final next = _nextRiskIndex(index);
                if (next == null || next == index) return;
                setState(() => _selectedIndex = next);
                widget.onSelect(widget.regions[next]);
              },
              icon: const Icon(CupertinoIcons.exclamationmark_triangle, size: 15),
              label: const Text('下一道风险题'),
            ),
          ),
        if (region.reviewStatus == QuestionRegionReviewStatus.ignored)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('⊘ 此题已忽略，不会被裁切、保存或交给 AI；可点击“恢复采用”撤销。', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ),
        if (risks.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(6)),
            child: Text('⚠ ${risks.join('；')}', style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412))),
          ),
        Text('题框区域：x ${region.normalizedRect.left.toStringAsFixed(2)} · y ${region.normalizedRect.top.toStringAsFixed(2)} · ${region.normalizedRect.width.toStringAsFixed(2)} × ${region.normalizedRect.height.toStringAsFixed(2)}。可在下方试卷图拖动蓝框调整。', style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showCropPreview(context, region, sourceImagePath),
            icon: const Icon(CupertinoIcons.crop, size: 15),
            label: const Text('查看最终裁切预览'),
          ),
        ),
        const SizedBox(height: 8),
        if (modified)
          Row(children: <Widget>[
            const Icon(CupertinoIcons.pencil_circle_fill, size: 15, color: Color(0xFF2563EB)),
            const SizedBox(width: 4),
            const Text('已修改识别结果', style: TextStyle(fontSize: 11, color: Color(0xFF2563EB))),
            const Spacer(),
            TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('识别原文对照'),
                  content: SingleChildScrollView(
                    child: SelectableText(original.isEmpty ? '没有可用的识别原文。' : original),
                  ),
                  actions: <Widget>[TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭'))],
                ),
              ),
              child: const Text('查看原文'),
            ),
            TextButton(
              onPressed: () => widget.onUpdate(index, region.copyWith(
                questionStem: original,
                formulas: const <String>[],
                tables: const <String>[],
                recognizedText: original,
              )),
              child: const Text('恢复识别原文'),
            ),
          ]),
        TextFormField(
          key: ValueKey('${region.id}-stem-$stem'),
          initialValue: stem,
          minLines: 3,
          maxLines: 6,
          onChanged: (value) => _updateStructured(index, region, stem: value),
          decoration: const InputDecoration(
            isDense: true,
            labelText: '题干',
            helperText: '正文可独立校对；公式和表格在下方分别维护。',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        if (region.recognizedBlockTypes.contains('公式') || formulas.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${region.id}-formula-${formulas.join()}'),
            initialValue: formulas.join('\n\n'),
            minLines: 2,
            maxLines: 5,
            onChanged: (value) => _updateStructured(index, region,
              formulas: value.split('\n\n').where((item) => item.trim().isNotEmpty).toList()),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'LaTex 公式（每段公式以空行分隔）',
              helperText: r'请保留 $...$ 或 \(...\) 等 LaTex 标记。',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (region.recognizedBlockTypes.contains('表格') || tables.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${region.id}-table-${tables.join()}'),
            initialValue: tables.join('\n\n'),
            minLines: 3,
            maxLines: 7,
            onChanged: (value) => _updateStructured(index, region,
              tables: value.trim().isEmpty ? const <String>[] : <String>[value]),
            decoration: const InputDecoration(
              isDense: true,
              labelText: '表格 Markdown',
              helperText: '可直接编辑 | 列 | 的 Markdown 表格内容。',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (tables.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _MarkdownTablePreview(tables.first),
          ],
        ],
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: DropdownButtonFormField<Subject>(
            value: subject,
            isDense: true,
            decoration: const InputDecoration(labelText: '学科', border: OutlineInputBorder()),
            items: Subject.values.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
            onChanged: (value) { if (value != null) widget.onUpdate(index, region.copyWith(subject: value)); },
          )),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(
            value: _questionTypes.contains(type) ? type : '未指定',
            isDense: true,
            decoration: const InputDecoration(labelText: '题目类型', border: OutlineInputBorder()),
            items: _questionTypes.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => widget.onUpdate(index, region.copyWith(questionType: value == '未指定' ? '' : value)),
          )),
        ]),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: region.analyzeWithAi,
          onChanged: (value) => widget.onUpdate(index, region.copyWith(analyzeWithAi: value)),
          title: Text(region.analyzeWithAi ? '✓ 采用，并交给普通 AI 深度分析' : '✓ 采用，仅保存 OCR / 文档结果', style: const TextStyle(fontSize: 12)),
          subtitle: Text(region.analyzeWithAi ? '生成讲解、错因、知识点与练习' : '不调用普通 AI，可稍后在错题本中分析', style: const TextStyle(fontSize: 10)),
        ),
      ],
    );
  }
}

class _MarkdownTablePreview extends StatelessWidget {
  const _MarkdownTablePreview(this.markdown);
  final String markdown;

  List<List<String>> get _rows => markdown.split('\n')
      .where((line) => line.trim().startsWith('|'))
      .map((line) => line.trim().replaceFirst(RegExp(r'^\|'), '')
          .replaceFirst(RegExp(r'\|$'), '').split('|')
          .map((cell) => cell.trim()).toList())
      .where((cells) => !cells.every((cell) => RegExp(r'^:?-{2,}:?$').hasMatch(cell)))
      .toList();

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final header = rows.first;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 28,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 40,
          columns: header.map((cell) => DataColumn(label: Text(cell, style: const TextStyle(fontSize: 11)))).toList(),
          rows: rows.skip(1).map((row) => DataRow(cells: List<DataCell>.generate(
            header.length,
            (index) => DataCell(Text(index < row.length ? row[index] : '', style: const TextStyle(fontSize: 11))),
          ))).toList(),
        ),
      ),
    );
  }
}

class _MiniTypeTag extends StatelessWidget {
  const _MiniTypeTag(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6D28D9))),
  );
}
