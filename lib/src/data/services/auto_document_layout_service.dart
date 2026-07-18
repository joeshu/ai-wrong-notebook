import 'dart:ui';

import 'package:smart_wrong_notebook/src/data/services/mineru_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/paddle_cloud_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

/// Cost-aware layout routing: use PaddleOCR first, and only use MinerU VLM
/// when the fast candidate set is not credible enough for user review.
class AutoDocumentLayoutService implements DocumentLayoutService {
  AutoDocumentLayoutService(this.config);
  final LayoutProviderConfig config;

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({required String imagePath}) async {
    try {
      final paddleConfig = LayoutProviderConfig(type: LayoutProviderType.paddleCloud, apiKey: config.apiKey);
      final fast = await PaddleCloudDocumentLayoutService(paddleConfig)
          .detectQuestionRegions(imagePath: imagePath);
      if (_isCredible(fast.regions)) {
        return LayoutDetectionResult(
          regions: fast.regions,
          providerLabel: '${fast.providerLabel}（自动策略：快速结果可用）',
          warning: fast.warning,
        );
      }
    } catch (_) {
      // MinerU is the deliberate fallback. Its detailed error is shown below
      // if it also cannot produce candidates.
    }
    final mineruConfig = LayoutProviderConfig(type: LayoutProviderType.mineruCloud, apiKey: config.secondaryApiKey);
    final precise = await MineruDocumentLayoutService(mineruConfig)
        .detectQuestionRegions(imagePath: imagePath);
    return LayoutDetectionResult(
      regions: precise.regions,
      providerLabel: '${precise.providerLabel}（自动策略：PaddleOCR 结果不足，已升级）',
      warning: precise.warning,
    );
  }

  bool _isCredible(List<QuestionRegion> regions) {
    if (regions.length < 2) return false;
    final coverage = regions.fold<double>(0, (sum, item) => sum + item.normalizedRect.width * item.normalizedRect.height);
    if (coverage < .12 || coverage > 1.35) return false;
    for (var i = 0; i < regions.length; i++) {
      for (var j = i + 1; j < regions.length; j++) {
        if (_iou(regions[i].normalizedRect, regions[j].normalizedRect) > .55) return false;
      }
    }
    return true;
  }

  double _iou(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) return 0;
    final intersection = overlap.width * overlap.height;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}
