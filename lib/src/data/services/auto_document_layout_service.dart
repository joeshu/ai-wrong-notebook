import 'dart:ui';

import 'package:smart_wrong_notebook/src/data/services/mineru_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/data/services/paddle_cloud_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

typedef LayoutProgressCallback = void Function(String message);

/// Cost-aware layout routing: use PaddleOCR first, and only use MinerU VLM
/// when the fast candidate set is not credible enough for user review.
class AutoDocumentLayoutService implements DocumentLayoutService {
  AutoDocumentLayoutService(this.config, {this.onProgress});
  final LayoutProviderConfig config;
  final LayoutProgressCallback? onProgress;

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({required String imagePath, String? pageRanges}) async {
    String? fallbackReason;
    try {
      onProgress?.call('① 正在调用 PaddleOCR 快速识别…');
      final paddleConfig = LayoutProviderConfig(type: LayoutProviderType.paddleCloud, apiKey: config.apiKey);
      final fast = await PaddleCloudDocumentLayoutService(paddleConfig).detectQuestionRegions(imagePath: imagePath, pageRanges: pageRanges);
      onProgress?.call('② 正在检查 PaddleOCR 候选题框质量…');
      final qualityIssue = _qualityIssue(fast.regions);
      if (qualityIssue == null) {
        return LayoutDetectionResult(regions: fast.regions, providerLabel: '${fast.providerLabel}（自动策略：快速结果可用）', warning: fast.warning);
      }
      fallbackReason = qualityIssue;
    } catch (e) {
      // 保留 PaddleOCR 抛出的具体错误（如 "HTTP 401 Token 无效或已过期"），
      // 让 UI 升级提示能反映真实失败原因，而非模糊的 "未返回可用结果"。
      fallbackReason = 'PaddleOCR 不可用：${e.toString()}';
    }
    onProgress?.call('③ $fallbackReason，已自动升级 MinerU 深度解析…');
    final mineruConfig = LayoutProviderConfig(type: LayoutProviderType.mineruCloud, apiKey: config.secondaryApiKey);
    final precise = await MineruDocumentLayoutService(mineruConfig).detectQuestionRegions(imagePath: imagePath, pageRanges: pageRanges);
    return LayoutDetectionResult(
      regions: precise.regions,
      providerLabel: '${precise.providerLabel}（自动策略：已升级）',
      warning: '升级原因：$fallbackReason。${precise.warning ?? '请逐题检查候选框。'}',
    );
  }

  String? _qualityIssue(List<QuestionRegion> regions) {
    if (regions.length < 2) return 'PaddleOCR 仅识别到 ${regions.length} 个候选框';
    final coverage = regions.fold<double>(0, (sum, item) => sum + item.normalizedRect.width * item.normalizedRect.height);
    if (coverage < .12 || coverage > 1.35) return 'PaddleOCR 候选框覆盖范围异常';
    for (var i = 0; i < regions.length; i++) {
      for (var j = i + 1; j < regions.length; j++) {
        if (_iou(regions[i].normalizedRect, regions[j].normalizedRect) > .55) return 'PaddleOCR 候选框重叠较多';
      }
    }
    return null;
  }

  double _iou(Rect a, Rect b) {
    final overlap = a.intersect(b);
    if (overlap.isEmpty) return 0;
    final intersection = overlap.width * overlap.height;
    final union = a.width * a.height + b.width * b.height - intersection;
    return union <= 0 ? 0 : intersection / union;
  }
}
