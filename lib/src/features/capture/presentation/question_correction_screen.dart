import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/utils/image_quality_detector.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';

class QuestionCorrectionScreen extends ConsumerStatefulWidget {
  const QuestionCorrectionScreen({super.key});

  @override
  ConsumerState<QuestionCorrectionScreen> createState() =>
      _QuestionCorrectionScreenState();
}

class _QuestionCorrectionScreenState
    extends ConsumerState<QuestionCorrectionScreen> {
  ImageQualityResult? _qualityResult;
  bool _warningDismissed = false;
  bool _detecting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeDetectQuality();
  }

  Future<void> _maybeDetectQuality() async {
    if (_detecting || _qualityResult != null) return;
    final current = ref.read(currentQuestionProvider);
    final imagePath = current?.imagePath;
    if (imagePath == null || imagePath.isEmpty) return;
    if (!File(imagePath).existsSync()) return;

    setState(() => _detecting = true);
    try {
      final result = await detectImageQuality(imagePath);
      if (!mounted) return;
      setState(() {
        _qualityResult = result;
        _detecting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _detecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentQuestionProvider);
    final imagePath = current?.imagePath;
    final showWarning = _qualityResult != null &&
        !_qualityResult!.isAcceptable &&
        !_warningDismissed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('题目预览'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Column(
        children: <Widget>[
          if (showWarning) _buildQualityWarning(_qualityResult!.primaryIssue),
          Expanded(
            child: imagePath != null && File(imagePath).existsSync()
                ? Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: CachedQuestionImage(imagePath,
                          fit: BoxFit.contain, highRes: true),
                    ),
                  )
                : Center(
                    child: Text(
                      '未选择图片',
                      style: TextStyle(
                          fontSize: 14,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.go('/capture/crop'),
                  child: const Text('重新框选'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.go('/analysis/loading'),
                  child: const Text('开始分析'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityWarning(ImageQualityIssue? issue) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? AppColors.accentAmber.withValues(alpha: 0.14)
        : AppColors.accentAmberContainerLight;
    final borderColor = AppColors.accentAmber.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
      padding: const EdgeInsets.fromLTRB(AppSpace.md, 10, AppSpace.sm, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(CupertinoIcons.exclamationmark_triangle,
                color: AppColors.accentAmber, size: 20),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _warningText(issue),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.go('/'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '重拍',
                      style: TextStyle(
                        color: AppColors.accentAmber,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: () => setState(() => _warningDismissed = true),
              icon: Icon(
                CupertinoIcons.xmark,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _warningText(ImageQualityIssue? issue) {
    switch (issue) {
      case ImageQualityIssue.blurry:
        return '图片可能模糊，建议重拍以提升识别准确率';
      case ImageQualityIssue.tooDark:
        return '光线过暗，建议在明亮环境重拍';
      case ImageQualityIssue.tooBright:
        return '光线过亮/反光，建议调整角度重拍';
      case ImageQualityIssue.lowResolution:
        return '分辨率较低，可能识别不准，建议靠近拍摄';
      case null:
        return '';
    }
  }
}
