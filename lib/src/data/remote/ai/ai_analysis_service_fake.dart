part of 'ai_analysis_service.dart';

class _FakeAiAnalysisService extends AiAnalysisService {
  _FakeAiAnalysisService()
      : super(settingsRepository: InMemorySettingsRepository());

  @override
  Future<AiQuestionExtractionResult> extractQuestionStructure({
    required String subjectName,
    required String imagePath,
    String textHint = '',
    CaptureMode mode = CaptureMode.printed,
  }) async {
    final normalized = textHint.isNotEmpty ? textHint : '示例题目文本';
    final splitResult = await splitQuestionCandidates(
        text: normalized, subjectName: subjectName);
    return AiQuestionExtractionResult(
      extractedQuestionText: normalized,
      normalizedQuestionText: normalized,
      subject: _parseSubject(subjectName) ?? Subject.math,
      splitResult: splitResult,
    );
  }

  @override
  Future<AnalysisResult> analyzeExtractedQuestion({
    required String correctedText,
    required String subjectName,
    String? imagePath,
  }) async {
    return _fakeResult();
  }

  @override
  Future<AnalysisResult> analyzeQuestion({
    required String correctedText,
    required String subjectName,
    String? imagePath,
  }) async {
    return _fakeResult();
  }

  @override
  Future<bool> judgeAnswer({
    required String question,
    required String userAnswer,
    required String correctAnswer,
    List<String>? options,
  }) async {
    return userAnswer == correctAnswer;
  }
}
