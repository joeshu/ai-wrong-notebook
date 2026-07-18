import 'dart:ui';

import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

class LayoutDetectionResult {
  const LayoutDetectionResult({
    required this.regions,
    required this.providerLabel,
    this.warning,
  });

  final List<QuestionRegion> regions;
  final String providerLabel;
  final String? warning;
}

abstract class DocumentLayoutService {
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
  });
}
