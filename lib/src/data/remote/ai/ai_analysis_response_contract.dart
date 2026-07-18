/// Versioned, dependency-free contract for the AI analysis JSON payload.
///
/// It intentionally validates at the network boundary so malformed model
/// responses cannot leak dynamic values into the domain model. Optional text
/// fields are normalized to an empty string; list fields must be arrays of
/// strings, otherwise the response is rejected as retryable/repairable.
class AiAnalysisResponseContract {
  const AiAnalysisResponseContract._();

  static const version = 1;

  static Map<String, dynamic> normalize(Map<String, dynamic> input) {
    const textKeys = <String>[
      'subject',
      'finalAnswer',
      'finalAnswerDerivation',
      'reconstructedQuestionText',
      'mistakeReason',
      'studyAdvice',
    ];
    const listKeys = <String>[
      'steps',
      'aiTags',
      'knowledgePoints',
    ];

    final result = Map<String, dynamic>.from(input);
    for (final key in textKeys) {
      final value = result[key];
      if (value == null) {
        result[key] = '';
      } else if (value is! String) {
        throw FormatException('AI 响应字段 $key 必须是文本');
      }
    }
    for (final key in listKeys) {
      final value = result[key];
      if (value == null) {
        result[key] = <String>[];
      } else if (value is List && value.every((item) => item is String)) {
        result[key] = List<String>.from(value);
      } else {
        throw FormatException('AI 响应字段 $key 必须是文本数组');
      }
    }

    final hasUsableContent = textKeys.any((key) =>
        (result[key] as String).trim().isNotEmpty) ||
        listKeys.any((key) => (result[key] as List).isNotEmpty);
    if (!hasUsableContent) {
      throw const FormatException('AI 响应不包含可用分析内容');
    }
    return result;
  }
}
