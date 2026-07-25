import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

class AiResponseDiagnosticsRetentionService {
  const AiResponseDiagnosticsRetentionService();

  QuestionRecord stripRawResponses(QuestionRecord record) {
    return _mapRecord(record, _stripRaw);
  }

  QuestionRecord expireRawResponses(
    QuestionRecord record, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    return _mapRecord(record, (analysis) {
      final diagnostics = analysis.responseDiagnostics;
      if (diagnostics == null || !diagnostics.hasRawResponse) return analysis;
      final days = diagnostics.retentionDays;
      if (days == null) return analysis;
      final expiresAt = diagnostics.capturedAt.add(Duration(days: days));
      if (reference.isBefore(expiresAt)) return analysis;
      return _stripRaw(analysis);
    });
  }

  QuestionRecord _mapRecord(
    QuestionRecord record,
    AnalysisResult Function(AnalysisResult) mapper,
  ) {
    final analysis = record.analysisResult;
    final mappedAnalysis = analysis == null ? null : mapper(analysis);
    final mappedCandidates = record.candidateAnalyses
        .map((candidate) {
          final candidateAnalysis = candidate.analysisResult;
          if (candidateAnalysis == null) return candidate;
          return candidate.copyWith(analysisResult: mapper(candidateAnalysis));
        })
        .toList(growable: false);
    return record.copyWith(
      analysisResult: mappedAnalysis,
      candidateAnalyses: mappedCandidates,
    );
  }

  AnalysisResult _stripRaw(AnalysisResult analysis) {
    final diagnostics = analysis.responseDiagnostics;
    if (diagnostics == null || !diagnostics.hasRawResponse) return analysis;
    return analysis.copyWith(
      responseDiagnostics: diagnostics.withoutRawResponse(),
    );
  }
}
