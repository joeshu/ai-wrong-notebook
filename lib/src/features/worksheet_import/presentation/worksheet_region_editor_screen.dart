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
              selectedType: _selectedStrategyLabel(layoutConfig),
              onAuto: _isCropping || _isDetecting ? null : () => _detectRegions(page),
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
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                onTapDown: _isCropping ? null : (details) {
                  final x = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
                  final y = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
                  setState(() => _regions.add(QuestionRegion(
                        id: const Uuid().v4(),
                        normalizedRect: Rect.fromLTWH(
                          (x - .40).clamp(0.0, .80).toDouble(),
                          (y - .10).clamp(0.0, .80).toDouble(),
                          .80,
                          .20,
                        ),
                      )));
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
              onPressed: _isCropping || _regions.isEmpty
                  ? null
                  : () => _cropAndQueue(page),
              icon: _isCropping
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.crop),
              label: Text(_isCropping ? '正在生成独立题图...' : '确认 ${_regions.length} 个题框并逐题分析'),
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
      final config = await restoreLayoutProviderConfig(ref);
      final type = override ?? config.type;
      final effectiveConfig = override == null
          ? config
          : LayoutProviderConfig(
              type: type,
              apiKey: type == LayoutProviderType.mineruCloud
                  ? (config.type == LayoutProviderType.autoCloud ? config.secondaryApiKey : config.apiKey)
                  : config.apiKey,
              secondaryApiKey: config.secondaryApiKey,
            );
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

  Future<void> _cropAndQueue(QuestionRecord source) async {
    setState(() => _isCropping = true);
    try {
      final cropper = ref.read(questionRegionCropServiceProvider);
      final candidates = <QuestionRecord>[];
      for (final region in _regions) {
        final path = await cropper.cropToStoredImage(sourcePath: source.imagePath, region: region);
        final fingerprint = await ImageFingerprintCodec.fromFile(File(path));
        candidates.add(QuestionRecord.draft(
          id: const Uuid().v4(), imagePath: path, subject: source.subject, recognizedText: '',
        ).copyWith(
          contentStatus: ContentStatus.processing,
          tags: ImageFingerprintCodec.write(source.tags, fingerprint),
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
      ref.read(currentQuestionProvider.notifier).state = candidates.first;
      if (mounted) context.go('/analysis/loading');
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
    required this.onChanged,
  });
  final QuestionRegion region;
  final int number;
  final Size canvasSize;
  final VoidCallback onDelete;
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
    required this.onDelete,
    required this.onChanged,
  });

  final Rect region;
  final Size canvasSize;
  final int number;
  final QuestionRegionSource source;
  final double confidence;
  final String? detectedNumber;
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
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: qualityColor, width: 2),
        color: qualityColor.withValues(alpha: .08),
      ),
      child: Stack(children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
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
