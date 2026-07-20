import 'analysis_result.dart';
import 'generated_exercise.dart';
import 'question_record.dart';
import 'subject.dart';

class ParsedAnalysisResult extends AnalysisResult {
  const ParsedAnalysisResult({
    required super.finalAnswer,
    required super.steps,
    required super.aiTags,
    required super.knowledgePoints,
    required super.mistakeReason,
    required super.studyAdvice,
    required this.rawContent,
    super.subject,
    super.finalAnswerDerivation,
    super.reconstructedQuestionText,
    super.visualAssumptions,
    super.visualAssumptionStatus,
    super.consistencyStatus,
    super.consistencyNote,
    super.wasVerifierUsed,
  });

  final String rawContent;

  @override
  AnalysisResult copyWith({
    Subject? subject,
    String? finalAnswer,
    String? finalAnswerDerivation,
    String? reconstructedQuestionText,
    VisualAssumptions? visualAssumptions,
    VisualAssumptionStatus? visualAssumptionStatus,
    List<String>? steps,
    List<String>? aiTags,
    List<String>? knowledgePoints,
    String? mistakeReason,
    String? studyAdvice,
    AnalysisConsistencyStatus? consistencyStatus,
    String? consistencyNote,
    bool? wasVerifierUsed,
  }) {
    return ParsedAnalysisResult(
      rawContent: rawContent,
      subject: subject ?? this.subject,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      finalAnswerDerivation:
          finalAnswerDerivation ?? this.finalAnswerDerivation,
      reconstructedQuestionText:
          reconstructedQuestionText ?? this.reconstructedQuestionText,
      visualAssumptions: visualAssumptions ?? this.visualAssumptions,
      visualAssumptionStatus:
          visualAssumptionStatus ?? this.visualAssumptionStatus,
      steps: steps ?? this.steps,
      aiTags: aiTags ?? this.aiTags,
      knowledgePoints: knowledgePoints ?? this.knowledgePoints,
      mistakeReason: mistakeReason ?? this.mistakeReason,
      studyAdvice: studyAdvice ?? this.studyAdvice,
      consistencyStatus: consistencyStatus ?? this.consistencyStatus,
      consistencyNote: consistencyNote ?? this.consistencyNote,
      wasVerifierUsed: wasVerifierUsed ?? this.wasVerifierUsed,
    );
  }
}

class CandidateAnalysisPayload {
  const CandidateAnalysisPayload({
    required this.candidateId,
    required this.order,
    required this.questionText,
    required this.analysisResult,
    required this.savedExercises,
    this.subject,
    this.aiTags = const [],
    this.aiKnowledgePoints = const [],
    this.status = CandidateAnalysisStatus.success,
    this.errorMessage,
  });

  const CandidateAnalysisPayload.failed({
    required this.candidateId,
    required this.order,
    required this.questionText,
    required this.errorMessage,
  })  : analysisResult = null,
        savedExercises = const [],
        subject = null,
        aiTags = const [],
        aiKnowledgePoints = const [],
        status = CandidateAnalysisStatus.failed;

  final String candidateId;
  final int order;
  final String questionText;
  final AnalysisResult? analysisResult;
  final List<GeneratedExercise> savedExercises;
  final Subject? subject;
  final List<String> aiTags;
  final List<String> aiKnowledgePoints;
  final CandidateAnalysisStatus status;
  final String? errorMessage;

  bool get isSuccessful =>
      status == CandidateAnalysisStatus.success && analysisResult != null;
}
