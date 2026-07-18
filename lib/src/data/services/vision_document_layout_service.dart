import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

/// First layout provider: reuses the user's existing configured vision model.
class VisionDocumentLayoutService implements DocumentLayoutService {
  VisionDocumentLayoutService(this._aiService);

  final AiAnalysisService _aiService;

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
  }) async {
    final regions =
        await _aiService.detectWorksheetQuestionRegions(imagePath: imagePath);
    return LayoutDetectionResult(
      regions: regions,
      providerLabel: '当前 AI 视觉模型',
    );
  }
}
