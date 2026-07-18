import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_response_contract.dart';

void main() {
  test('normalizes omitted optional analysis fields', () {
    final result = AiAnalysisResponseContract.normalize({
      'finalAnswer': '42',
      'steps': ['列式'],
    });

    expect(result['subject'], '');
    expect(result['aiTags'], isEmpty);
    expect(result['knowledgePoints'], isEmpty);
    expect(result['steps'], ['列式']);
  });

  test('rejects non-string AI list members', () {
    expect(
      () => AiAnalysisResponseContract.normalize({
        'finalAnswer': '42',
        'steps': ['第一步', 2],
      }),
      throwsFormatException,
    );
  });

  test('rejects an empty AI analysis response', () {
    expect(
      () => AiAnalysisResponseContract.normalize({}),
      throwsFormatException,
    );
  });
}
