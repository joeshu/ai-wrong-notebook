enum AiAnalysisReviewDisposition {
  unknown,
  autoApproved,
  needsConfirmation,
}

class AiAnalysisReviewDecision {
  const AiAnalysisReviewDecision({
    required this.disposition,
    this.fields = const <String>[],
    this.reasons = const <String>[],
    this.evaluatedAt,
  });

  const AiAnalysisReviewDecision.unknown()
      : disposition = AiAnalysisReviewDisposition.unknown,
        fields = const <String>[],
        reasons = const <String>[],
        evaluatedAt = null;

  final AiAnalysisReviewDisposition disposition;
  final List<String> fields;
  final List<String> reasons;
  final DateTime? evaluatedAt;

  bool get requiresConfirmation =>
      disposition == AiAnalysisReviewDisposition.needsConfirmation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'disposition': disposition.name,
        'fields': fields,
        'reasons': reasons,
        'evaluatedAt': evaluatedAt?.toIso8601String(),
      };

  factory AiAnalysisReviewDecision.fromJson(Map<String, dynamic> json) {
    final rawDisposition = json['disposition'];
    final disposition = AiAnalysisReviewDisposition.values.firstWhere(
      (value) => value.name == rawDisposition,
      orElse: () => AiAnalysisReviewDisposition.unknown,
    );
    return AiAnalysisReviewDecision(
      disposition: disposition,
      fields: List<String>.from(json['fields'] as List? ?? const <String>[]),
      reasons: List<String>.from(json['reasons'] as List? ?? const <String>[]),
      evaluatedAt: DateTime.tryParse(json['evaluatedAt'] as String? ?? ''),
    );
  }
}

enum AiAnalysisPipelineStage {
  imageQuality,
  questionRecognition,
  questionConfirmation,
  solving,
  mistakeAnalysis,
  knowledgeExtraction,
  exerciseGeneration,
  reviewPlanning,
}

enum AiAnalysisPipelineStatus {
  notStarted,
  inProgress,
  waitingForConfirmation,
  completed,
  failed,
}

class AiAnalysisPipelineSnapshot {
  const AiAnalysisPipelineSnapshot({
    required this.status,
    this.currentStage,
    this.completedStages = const <AiAnalysisPipelineStage>[],
    this.failedStage,
    this.message = '',
  });

  const AiAnalysisPipelineSnapshot.notStarted()
      : status = AiAnalysisPipelineStatus.notStarted,
        currentStage = null,
        completedStages = const <AiAnalysisPipelineStage>[],
        failedStage = null,
        message = '';

  final AiAnalysisPipelineStatus status;
  final AiAnalysisPipelineStage? currentStage;
  final List<AiAnalysisPipelineStage> completedStages;
  final AiAnalysisPipelineStage? failedStage;
  final String message;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status.name,
        'currentStage': currentStage?.name,
        'completedStages': completedStages.map((stage) => stage.name).toList(),
        'failedStage': failedStage?.name,
        'message': message,
      };

  factory AiAnalysisPipelineSnapshot.fromJson(Map<String, dynamic> json) =>
      AiAnalysisPipelineSnapshot(
        status: _pipelineStatus(json['status']),
        currentStage: _pipelineStage(json['currentStage']),
        completedStages: (json['completedStages'] as List? ?? const <Object>[])
            .map(_pipelineStage)
            .whereType<AiAnalysisPipelineStage>()
            .toList(growable: false),
        failedStage: _pipelineStage(json['failedStage']),
        message: json['message'] as String? ?? '',
      );

  static AiAnalysisPipelineStatus _pipelineStatus(Object? raw) =>
      AiAnalysisPipelineStatus.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => AiAnalysisPipelineStatus.notStarted,
      );

  static AiAnalysisPipelineStage? _pipelineStage(Object? raw) {
    for (final stage in AiAnalysisPipelineStage.values) {
      if (stage.name == raw) return stage;
    }
    return null;
  }
}
