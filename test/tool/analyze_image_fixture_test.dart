import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';

void main() {
  test('analyzes a local image fixture with app AI service', () async {
    final imagePath = _env('AI_FIXTURE_IMAGE');
    if (imagePath == null || imagePath.trim().isEmpty) {
      markTestSkipped('Set AI_FIXTURE_IMAGE to run local image regression.');
      return;
    }

    final imageFile = File(imagePath);
    expect(imageFile.existsSync(), isTrue, reason: 'Image file must exist.');

    final config = _readConfigFromEnvironment();
    final service = AiAnalysisService(
      settingsRepository: _ToolSettingsRepository(config),
    );

    final result = await service.analyzeExtractedQuestion(
      correctedText: _env('AI_FIXTURE_TEXT') ?? '请根据图片识别题目并解答。',
      subjectName: _env('AI_FIXTURE_SUBJECT') ?? 'math',
      imagePath: imageFile.path,
    );
    // ignore: avoid_print
    print(
        '[TEST] result type: ${result.runtimeType}, isParsed: ${result is ParsedAnalysisResult}');
    final generatedExercises = result is ParsedAnalysisResult
        ? service.extractGeneratedExercisesFromContent(
            result.rawContent,
            questionId: 'fixture',
            analysis: result,
            sourceQuestionText: _env('AI_FIXTURE_TEXT'),
          )
        : service.extractGeneratedExercises(
            result,
            questionId: 'fixture',
            sourceQuestionText: _env('AI_FIXTURE_TEXT'),
          );
    // ignore: avoid_print
    print('[TEST] generatedExercises count: ${generatedExercises.length}');
    for (final ex in generatedExercises) {
      // ignore: avoid_print
      print(
          '[TEST] exercise: ${ex.id}, hasDiagram: ${ex.diagramData != null}, q: ${ex.question.substring(0, ex.question.length.clamp(0, 40))}');
    }

    final report = _buildReport(result, generatedExercises);
    const encoder = JsonEncoder.withIndent('  ');
    // ignore: avoid_print
    print(encoder.convert(report));

    final qualityGate = report['qualityGate']! as Map<String, dynamic>;
    final warnings = qualityGate['warnings'] as List;
    if (warnings.isNotEmpty) {
      // ignore: avoid_print
      print('\n⚠️  WARNINGS (needs manual review, not a test failure):');
      for (final w in warnings) {
        // ignore: avoid_print
        print('  - $w');
      }
    }

    expect(
      qualityGate['passed'],
      isTrue,
      reason: (qualityGate['issues'] as List).join('\n'),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

AiProviderConfig _readConfigFromEnvironment() {
  final baseUrl = _env('AI_BASE_URL');
  final apiKey = _env('AI_API_KEY');
  final model = _env('AI_MODEL');

  final missing = <String>[
    if (baseUrl == null || baseUrl.trim().isEmpty) 'AI_BASE_URL',
    if (apiKey == null || apiKey.trim().isEmpty) 'AI_API_KEY',
    if (model == null || model.trim().isEmpty) 'AI_MODEL',
  ];
  if (missing.isNotEmpty) {
    fail('Missing environment variables: ${missing.join(', ')}.');
  }

  return AiProviderConfig(
    id: 'tool-env',
    displayName: 'Tool Environment',
    baseUrl: baseUrl!.trim(),
    model: model!.trim(),
    apiKey: apiKey!.trim(),
  );
}

Map<String, dynamic> _buildReport(
  AnalysisResult result,
  List<GeneratedExercise> generatedExercises,
) {
  return <String, dynamic>{
    'finalAnswer': result.finalAnswer,
    'finalAnswerDerivation': result.finalAnswerDerivation,
    'steps': result.steps,
    'visualAssumptions': result.visualAssumptions?.toJson(),
    'visualAssumptionStatus': result.visualAssumptionStatus.name,
    'consistencyStatus': result.consistencyStatus.name,
    'consistencyNote': result.consistencyNote,
    'wasVerifierUsed': result.wasVerifierUsed,
    'generatedExercises': generatedExercises
        .map((exercise) => <String, dynamic>{
              'id': exercise.id,
              'difficulty': exercise.difficulty,
              'question': exercise.question,
              'options': exercise.options,
              'answer': exercise.answer,
              'explanation': exercise.explanation,
            })
        .toList(),
    'qualityGate': _evaluateQualityGate(result, generatedExercises),
  };
}

Map<String, dynamic> _evaluateQualityGate(
  AnalysisResult result,
  List<GeneratedExercise> generatedExercises,
) {
  final issues = <String>[];
  final warnings = <String>[];
  final finalAnswerTokens = _extractConclusionTokens(result.finalAnswer);
  final derivationTokens =
      _extractConclusionTokens(result.finalAnswerDerivation);
  final stepTokens = <String>{
    for (final step in result.steps.reversed.take(2))
      ..._extractConclusionTokens(step),
  };

  if (result.finalAnswer.trim().isEmpty) {
    issues.add('finalAnswer is empty');
  }
  if (result.steps.isEmpty) {
    issues.add('steps is empty');
  }

  final hasAnswerStepConflict = finalAnswerTokens.isNotEmpty &&
      stepTokens.isNotEmpty &&
      finalAnswerTokens.intersection(stepTokens).isEmpty;
  if (hasAnswerStepConflict) {
    issues.add(
      'finalAnswer conflicts with final steps: '
      '${finalAnswerTokens.join(', ')} vs ${stepTokens.join(', ')}',
    );
  }

  final hasAnswerDerivationConflict = finalAnswerTokens.isNotEmpty &&
      derivationTokens.isNotEmpty &&
      finalAnswerTokens.intersection(derivationTokens).isEmpty;
  if (hasAnswerDerivationConflict) {
    issues.add(
      'finalAnswer conflicts with finalAnswerDerivation: '
      '${finalAnswerTokens.join(', ')} vs ${derivationTokens.join(', ')}',
    );
  }

  final answerFamily = <String>{
    ...finalAnswerTokens,
    ...derivationTokens,
    ...stepTokens,
  }.where(_isHighRiskPiAreaAnswer).toSet();
  if (answerFamily.length > 1) {
    issues.add(
      'multiple high-risk area answers appear: ${answerFamily.join(', ')}',
    );
  }

  if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview &&
      result.consistencyStatus != AnalysisConsistencyStatus.needsReview) {
    issues.add(
        'visual assumptions need review but consistencyStatus is not needsReview');
  }

  // needsReview with internally consistent results is a warning, not a failure.
  // The App will correctly show "可能解法/需核对" — this is the desired behavior
  // for image-based geometry problems where label interpretation is uncertain.
  if (result.consistencyStatus == AnalysisConsistencyStatus.needsReview) {
    final isInternallyConsistent =
        !hasAnswerStepConflict && !hasAnswerDerivationConflict;
    if (isInternallyConsistent) {
      warnings.add(
          'analysis needs manual review (App will show 可能解法): ${result.consistencyNote}');
    } else {
      issues.add(
          'analysis requires manual review with internal conflicts: ${result.consistencyNote}');
    }
  }

  for (final exercise in generatedExercises) {
    if (_hasGeneratedExerciseSelfInvalidation(exercise)) {
      issues.add('generated exercise self-invalidates: ${exercise.id}');
    }
  }

  return <String, dynamic>{
    'passed': issues.isEmpty,
    'issues': issues,
    'warnings': warnings,
    'finalAnswerTokens': finalAnswerTokens.toList(),
    'derivationTokens': derivationTokens.toList(),
    'stepConclusionTokens': stepTokens.toList(),
  };
}

Set<String> _extractConclusionTokens(String text) {
  final normalized = text
      .replaceAll('\\(', ' ')
      .replaceAll('\\)', ' ')
      .replaceAll('\\[', ' ')
      .replaceAll('\\]', ' ')
      .replaceAll('π', r'\pi')
      .replaceAll(' ', '')
      .toLowerCase();
  final tokens = <String>{};

  for (final match in RegExp(r'[a-z][\.、:]?').allMatches(normalized)) {
    final token = match.group(0)!.replaceAll(RegExp(r'[\.、:]'), '');
    if (token.length == 1) tokens.add(token.toUpperCase());
  }

  for (final match
      in RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}').allMatches(normalized)) {
    tokens.add('${match.group(1)!}/${match.group(2)!}');
  }

  for (final match in RegExp(
    r'\d+(?:\.\d+)?(?:\\pi|pi)?(?:/\d+(?:\.\d+)?)?|(?:\\pi|pi)(?:/\d+(?:\.\d+)?)?',
  ).allMatches(normalized)) {
    final token = match.group(0)!;
    if (RegExp(r'\d|\\pi|pi').hasMatch(token)) {
      tokens.add(token.replaceAll('pi', r'\pi'));
    }
  }

  return tokens.where((token) => token.isNotEmpty).toSet();
}

bool _hasGeneratedExerciseSelfInvalidation(GeneratedExercise exercise) {
  final text =
      '${exercise.question} ${exercise.explanation} ${exercise.options?.join(' ') ?? ''}';
  return <String>[
    '选项中没有',
    '没有该值',
    '无正确选项',
    '选项设计不严谨',
    '选项有误',
    '原选项设计',
    '需重新检查',
    '需要重新检查',
    '修正后应',
    '应为修正',
    '无法从选项',
    '题目不严谨',
    '本题无解',
  ].any(text.contains);
}

bool _isHighRiskPiAreaAnswer(String token) {
  final normalized = token.replaceAll(' ', '').replaceAll('pi', r'\pi');
  return normalized == r'25\pi' ||
      normalized == r'25\pi/2' ||
      normalized == r'29\pi/2' ||
      normalized == r'25\pi}{2' ||
      normalized == r'29\pi}{2';
}

String? _env(String key) => Platform.environment[key];

class _ToolSettingsRepository implements SettingsRepository {
  _ToolSettingsRepository(this._config);

  AiProviderConfig _config;
  final Map<String, String> _strings = <String, String>{};

  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => _config;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {
    _config = config;
  }

  @override
  Future<String?> getString(String key) async => _strings[key];

  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
  }
}
