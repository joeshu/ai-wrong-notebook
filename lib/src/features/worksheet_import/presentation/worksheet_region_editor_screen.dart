import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: FilledButton.tonalIcon(
              onPressed: _isCropping || _isDetecting
                  ? null
                  : () => _detectRegions(page),
              icon: _isDetecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.sparkles, size: 18),
              label: Text(_isDetecting ? '正在识别候选题框...' : '使用当前 AI 识别候选题框'),
            ),
          ),
          if (_detectionMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(_detectionMessage!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          Padding(
            child: Text('拖动蓝色题框调整位置；拖动右下角圆点缩放；点击红色 × 删除。每个蓝框会裁成一张独立题图。自动识别题框将在后续版面服务接入后作为候选框提供。',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
                  ..._regions.asMap().entries.map((entry) => _RegionOverlay(
                        region: entry.value,
                        number: entry.key + 1,
                        canvasSize: size,
                        onDelete: () => setState(() => _regions.removeAt(entry.key)),
                        onChanged: (rect) => setState(() =>
                            _regions[entry.key] = entry.value.copyWith(
                                normalizedRect: rect)),
                      )),
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

  Future<void> _detectRegions(QuestionRecord page) async {
    setState(() {
      _isDetecting = true;
      _detectionMessage = null;
    });
    try {
      final result = await ref
          .read(visionDocumentLayoutServiceProvider)
          .detectQuestionRegions(imagePath: page.imagePath);
      if (!mounted) return;
      setState(() {
        _regions
          ..clear()
          ..addAll(result.regions);
        _detectionMessage = '已由${result.providerLabel}生成 ${result.regions.length} 个候选框，请逐一检查后确认裁切。';
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
    required this.onDelete,
    required this.onChanged,
  });

  final Rect region;
  final Size canvasSize;
  final int number;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF2563EB), width: 2),
        color: const Color(0xFF2563EB).withValues(alpha: .06),
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
              color: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Text('题 ${widget.number}',
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
                border: Border.all(color: const Color(0xFF2563EB), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(CupertinoIcons.arrow_down_right,
                  size: 14, color: Color(0xFF2563EB)),
            ),
          ),
        ),
      ]),
    );
  }
}
