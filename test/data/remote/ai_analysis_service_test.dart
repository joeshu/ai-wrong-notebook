import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_controller.dart';

void main() {
  test(
      'fake analysis controller returns ready record with persistent exercises',
      () async {
    final controller = AnalysisController.fake();
    final record = await controller.analyze(
      questionId: 'q-1',
      correctedText: '解方程 x+2=5',
      subjectName: '数学',
    );

    expect(record.analysisResult?.finalAnswer, 'x = 3');
    expect(record.savedExercises.length, 3);
    expect(record.savedExercises.first.difficulty, '简单');
  });

  test('service parses final answer derivation and consistency metadata', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "25\pi/2",
  "finalAnswerDerivation": "由最后一步 \frac{1}{2}\times25\pi 得到 25\pi/2。",
  "reconstructedQuestionText": "如图，求半圆面积。",
  "steps": ["圆面积为 25\pi", "阴影面积为 25\pi/2"],
  "aiTags": ["几何"],
  "knowledgePoints": ["圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "注意目标区域"
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);

    expect(analysis.finalAnswer, r'25\pi/2');
    expect(analysis.finalAnswerDerivation, contains(r'\frac{1}{2}'));
    expect(analysis.reconstructedQuestionText, contains('半圆面积'));
    final restored = AnalysisResult.fromJson(
      analysis
          .copyWith(
            consistencyStatus: AnalysisConsistencyStatus.repaired,
            consistencyNote: 'AI 已复核并修正答案。',
            wasVerifierUsed: true,
          )
          .toJson(),
    );
    expect(restored.consistencyStatus, AnalysisConsistencyStatus.repaired);
    expect(restored.wasVerifierUsed, isTrue);
    expect(restored.finalAnswerDerivation, contains(r'\frac{1}{2}'));
  });

  test('service parses visual assumptions and marks low confidence for review',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "25\pi/2",
  "finalAnswerDerivation": "按半圆面积公式得到 25\pi/2。",
  "reconstructedQuestionText": "如图，求阴影半圆面积。",
  "visualAssumptions": {
    "targetObject": "阴影半圆",
    "targetQuestion": "求面积",
    "measurements": [
      {
        "label": "10",
        "meaning": "半圆直径",
        "usedInSolution": true,
        "evidence": "image",
        "confidence": "low"
      }
    ],
    "solutionBasis": ["半径为 5"],
    "uncertainItems": ["10 是否为直径"],
    "needsManualReview": true,
    "reviewReason": "需核对 10 的标注含义"
  },
  "steps": ["若 10 为直径，则半径为 5。", "面积为 25\pi/2。"],
  "aiTags": ["几何"],
  "knowledgePoints": ["半圆面积"],
  "mistakeReason": "未核对标注含义",
  "studyAdvice": "先确认图中关键长度"
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);
    final restored = AnalysisResult.fromJson(analysis.toJson());

    expect(restored.visualAssumptions?.targetObject, '阴影半圆');
    expect(restored.visualAssumptions?.measurements.single.label, '10');
    expect(restored.visualAssumptionStatus, VisualAssumptionStatus.needsReview);
  });

  test(
      'visual assumption uncertainty keeps consistent verifier result in review',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi/2',
      finalAnswerDerivation: r'按半圆面积公式得到 25\pi/2。',
      steps: <String>[r'若 10 为直径，则半径为 5。', r'面积为 25\pi/2。'],
      aiTags: <String>['几何'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '图中标注含义可能不稳定。',
      studyAdvice: '先确认关键标注。',
      visualAssumptions: VisualAssumptions(
        targetObject: '阴影半圆',
        targetQuestion: '求面积',
        measurements: <VisualMeasurementAssumption>[
          VisualMeasurementAssumption(
            label: '10',
            meaning: '半圆直径',
            usedInSolution: true,
            confidence: 'low',
          ),
        ],
        uncertainItems: <String>['10 是否为直径'],
        needsManualReview: true,
        reviewReason: '需核对 10 的标注含义',
      ),
      visualAssumptionStatus: VisualAssumptionStatus.needsReview,
    );
    const verification = r'''
{
  "isConsistent": true,
  "correctFinalAnswer": "",
  "correctedFinalAnswerDerivation": "",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "答案与步骤一致。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.consistencyNote, '需核对 10 的标注含义');
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service does not let visual assumption review skip answer mismatch',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'先得到 29\pi/2，但结合常见构型改成 25\pi。',
      steps: <String>[
        r'圆心为 (-5,5)，半径为 5。',
        r'半圆面积为 \frac{1}{2}\pi\times5^2=\frac{25\pi}{2}。最终答案是 \frac{25\pi}{2}。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '读图假设不稳定。',
      studyAdvice: '核对关键标注。',
      visualAssumptions: VisualAssumptions(
        targetObject: '半圆',
        targetQuestion: '求面积',
        uncertainItems: <String>['3 与 7 的对应关系'],
        needsManualReview: true,
        reviewReason: '关键标注需核对',
      ),
      visualAssumptionStatus: VisualAssumptionStatus.needsReview,
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "步骤最终得到 25\\pi/2。",
  "confidence": "low",
  "needsManualReview": true,
  "reason": "finalAnswer 与步骤最终结论不同。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, r'25\pi');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.consistencyNote, 'finalAnswer 与步骤最终结论不同。');
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service keeps repaired visual assumptions in review state', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'误把半圆当整圆。',
      steps: <String>[r'半圆面积最终应为 25\pi/2。'],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '读图假设不稳定。',
      studyAdvice: '核对关键标注。',
      visualAssumptions: VisualAssumptions(
        targetObject: '半圆',
        targetQuestion: '求面积',
        uncertainItems: <String>['10 是否为直径'],
        needsManualReview: true,
        reviewReason: '需核对 10 的标注含义',
      ),
      visualAssumptionStatus: VisualAssumptionStatus.needsReview,
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "步骤最终得到 25\\pi/2。",
  "correctedSteps": ["半圆面积最终应为 25\\pi/2。"],
  "confidence": "high",
  "needsManualReview": false,
  "reason": "finalAnswer 写成整圆面积。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, r'25\pi/2');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.consistencyNote, contains('AI 已复核并修正答案'));
    expect(reviewed.consistencyNote, contains('需核对 10 的标注含义'));
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service applies high confidence verifier repair conservatively', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'误把整圆面积 25\pi 当作最终答案。',
      steps: <String>[
        r'圆面积为 25\pi',
        r'阴影面积为 \frac{1}{2}\times25\pi=25\pi/2，所以答案为 25\pi/2。',
      ],
      aiTags: <String>['几何'],
      knowledgePoints: <String>['圆面积'],
      mistakeReason: r'漏乘 \frac{1}{2}',
      studyAdvice: '区分整圆和半圆面积',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "最后一步得到 25\\pi/2，因此最终答案应为 25\\pi/2。",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "finalAnswer 写成整圆面积，步骤最终结论是半圆面积。"
}
''';

    final repaired = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(repaired.finalAnswer, r'25\pi/2');
    expect(repaired.consistencyStatus, AnalysisConsistencyStatus.repaired);
    expect(repaired.wasVerifierUsed, isTrue);
  });

  test('service marks low confidence verifier result as needs review', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: 'C. 10',
      finalAnswerDerivation: '根据 finalAnswer 选择 C。',
      steps: <String>['设未知数', '解得 20，所以选 D。'],
      aiTags: <String>['应用题'],
      knowledgePoints: <String>['方程'],
      mistakeReason: '审题错误',
      studyAdvice: '列式后验算',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "D. 20",
  "correctedFinalAnswerDerivation": "步骤结论为 D. 20。",
  "confidence": "low",
  "needsManualReview": true,
  "reason": "题干信息不足，无法确认。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, 'C. 10');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service does not let mistake reason mask final answer mismatch', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'最终答案写成 25\pi。',
      steps: <String>[
        r'由图形关系得到半圆半径为 \sqrt{29}。',
        r'半圆面积为 \frac{1}{2}\pi\times29=29\pi/2，所以答案为 29\pi/2。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: r'原答案 25\pi 可能来自把半圆误当整圆。',
      studyAdvice: '核对半径或直径关系。',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "29\\pi/2",
  "correctedFinalAnswerDerivation": "步骤最终得到 29\\pi/2。",
  "confidence": "low",
  "needsManualReview": true,
  "reason": "finalAnswer 与步骤最终结论不同，需要人工核对图形关系。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, r'25\pi');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service detects semicircle area formula chain contradiction', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'最后得到 \(25\pi\)。',
      steps: <String>[
        r'解得半径 \(r=5\)。',
        r'半圆面积公式为 \(S=\frac{1}{2}\pi r^2\)，代入 \(r=5\)，得 \(S=\frac{25\pi}{2}\times2=25\pi\)。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: r'把 \(25\pi/2\) 又乘以 2。',
      studyAdvice: '确认求的是半圆还是整圆。',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "半圆面积为整圆面积的一半，因此最终答案是 25\\pi/2。",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "步骤中半圆面积公式已给出 25π/2，后续多乘 2 得到 25π 是错误的。"
}
''';

    final repaired = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(repaired.finalAnswer, r'25\pi/2');
    expect(repaired.consistencyStatus, AnalysisConsistencyStatus.repaired);
  });

  test('service repairs semicircle formula chain steps from verifier', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'最后得到 \(25\pi\)。',
      steps: <String>[
        r'解得半径 \(r=5\)。',
        r'半圆面积公式为 \(S=\frac{1}{2}\pi r^2\)，代入 \(r=5\)，得 \(S=\frac{25\pi}{2}\times2=25\pi\)。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: r'把 \(25\pi/2\) 又乘以 2。',
      studyAdvice: '确认求的是半圆还是整圆。',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "半圆面积为整圆面积的一半，因此最终答案是 25\\pi/2。",
  "correctedSteps": [
    "解得半径 \\(r=5\\)。",
    "半圆面积公式为 \\(S=\\frac{1}{2}\\pi r^2\\)，代入 \\(r=5\\)，得 \\(S=\\frac{1}{2}\\pi\\times5^2=\\frac{25\\pi}{2}\\)。"
  ],
  "correctedMistakeReason": "误把半圆面积又乘以 2，变成了整圆面积。",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "原步骤中半圆面积已经是 25π/2，后续多乘 2 得到 25π 是错误的。"
}
''';

    final repaired = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(repaired.finalAnswer, r'25\pi/2');
    expect(repaired.steps.join(' '), isNot(contains(r'\times2=25\pi')));
    expect(repaired.steps.join(' '), contains(r'\frac{25\pi}{2}'));
    expect(repaired.mistakeReason, contains('又乘以 2'));
    expect(repaired.consistencyStatus, AnalysisConsistencyStatus.repaired);
  });

  test('service detects generic step internal contradiction', () {
    final service = AiAnalysisService.fake();
    // A single step has two separate conclusion statements pointing to
    // different numeric values — should be flagged.
    const analysis = AnalysisResult(
      finalAnswer: r'10\pi',
      finalAnswerDerivation: r'最终面积为 10\pi。',
      steps: <String>[
        r'设半径 r，则面积为 \pi r^2。',
        r'所以面积为 25\pi/2，因此最终答案为 10\pi。',
      ],
      aiTags: <String>['圆', '面积'],
      knowledgePoints: <String>['圆面积'],
      mistakeReason: '计算有误。',
      studyAdvice: '检查计算。',
    );

    final isSuspicious = service.detectConsistencyIssueForTest(analysis);
    expect(isSuspicious, isTrue);
  });

  test(
      'service does not flag steps as contradictory when conclusions are consistent',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi/2',
      finalAnswerDerivation: r'半圆面积为 25\pi/2。',
      steps: <String>[
        r'半径为 5。',
        r'整圆面积为 25\pi。',
        r'半圆面积为 25\pi/2。',
      ],
      aiTags: <String>['半圆'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '无。',
      studyAdvice: '理解半圆公式。',
    );

    final isSuspicious = service.detectConsistencyIssueForTest(analysis);
    // Different steps in a derivation chain naturally have different values
    // (step 2: 整圆=25π, step 3: 半圆=25π/2). Only intra-step contradictions
    // are flagged, not inter-step intermediate calculations.
    expect(isSuspicious, isFalse);
  });

  test('service detects graphical math question conservatively', () {
    final service = AiAnalysisService.fake();

    expect(
      service.isGraphicalQuestion(
        '如图，大矩形长 175cm，高 95cm，右下角空白矩形宽 95cm，高 75cm，求其余部分面积。',
        '数学',
        imagePath: '/tmp/question.jpg',
      ),
      isTrue,
    );
    expect(
      service.isGraphicalQuestion(
        '小明去图书馆借书，第一次借了 3 本，第二次借了 2 本，一共借了几本？',
        '数学',
        imagePath: '/tmp/question.jpg',
      ),
      isFalse,
    );
    expect(
      service.isGraphicalQuestion(
        '如图所示，求阴影部分面积。',
        '语文',
        imagePath: '/tmp/question.jpg',
      ),
      isFalse,
    );
    expect(
      service.isGraphicalQuestion(
        '如图所示，求阴影部分面积。',
        '数学',
      ),
      isFalse,
    );
  });

  test('graphical analysis prompt asks model to read diagram first', () {
    final service = AiAnalysisService.fake();

    final prompt = service.buildAnalysisPromptForTest(
      '如图，求阴影部分面积。',
      '数学',
      isGraphicalQuestion: true,
    );

    expect(prompt, contains('图形/示意图题分析要求'));
    expect(prompt, contains('图片题输入说明'));
    expect(prompt, contains('只能作为参考线索，不是已确认题干'));
    expect(prompt, contains('第一目标是直接根据原图理解题目并完成解题'));
    expect(prompt, contains('不要把人工确认作为解题前置条件'));
    expect(prompt, contains('不要因此跳过解题'));
    expect(prompt, contains('不要为了写完整题干而强行命名外部轮廓'));
    expect(prompt, contains('不能自动解释成上底、下底、高、半径或直径'));
    expect(
        prompt, contains('reconstructedQuestionText 只重构与求解目标直接相关且能从图片确认的条件'));
    expect(prompt, isNot(contains('已确认题目文本')));
    expect(prompt, isNot(contains('举一反三锚点')));
  });

  test('normal analysis prompt does not include graphical instructions', () {
    final service = AiAnalysisService.fake();

    final prompt = service.buildAnalysisPromptForTest('解方程 x+2=5', '数学');

    expect(prompt, isNot(contains('图形/示意图题分析要求')));
    expect(prompt, contains('请分析以下数学科目的错题'));
  });

  test('service parses extracted question structure json', () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "物理",
  "extractedQuestionText": "如图所示，求电阻 R 两端电压。",
  "normalizedQuestionText": "如图所示，求电阻 R 两端的电压。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.physics);
    expect(extraction.extractedQuestionText, '如图所示，求电阻 R 两端电压。');
    expect(extraction.normalizedQuestionText, '如图所示，求电阻 R 两端的电压。');
  });

  test('service parses extraction json with raw latex backslashes', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "已知 \angle A=30^\circ，求 \frac{1}{2}x 的值。",
  "normalizedQuestionText": "已知 \angle A=30^\circ，求 \frac{1}{2}x 的值。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText,
        r'已知 \angle A=30^\circ，求 \frac{1}{2}x 的值。');
  });

  test('service parses extraction json with raw parenthesis latex delimiters',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。\n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "normalizedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。\n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, contains(r'\frac{a}{b}'));
    expect(extraction.normalizedQuestionText, contains('\n'));
  });
  test('service repairs mixed escaped delimiters and raw latex commands', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \\(x^2+1=5\\)，求 \\(x\\) 的值。\n2. 若 \\(\frac{a}{b}=2\\)，求 \\(a\\)。",
  "normalizedQuestionText": "1. 已知 \\(x^2+1=5\\)，求 \\(x\\) 的值。\n2. 若 \\(\frac{a}{b}=2\\)，求 \\(a\\)。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, isNot(contains(r'\\(')));
    expect(extraction.normalizedQuestionText, contains(r'\(\frac{a}{b}=2\)'));
    expect(extraction.normalizedQuestionText, contains('\n'));
  });
  test('service parses extraction json with literal newline in string', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。
2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "normalizedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。
2. 若 \(\frac{a}{b}=2\)，求 \(a\)。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, contains(r'\(\frac{a}{b}=2\)'));
  });
  test(
      'service recovers extraction json with doubled delimiters around raw frac',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。 \n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "normalizedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。 \n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "extra": "尾部字段"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, isNot(contains(r'\\(')));
    expect(extraction.normalizedQuestionText, contains(r'\(\frac{a}{b}=2\)'));
  });
  test('service preserves valid json escape sequences when repairing latex',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "第一行\n第二行，公式 \frac{1}{2}",
  "steps": ["使用公式 \times 2", "保留换行\n继续"],
  "aiTags": ["几何"],
  "knowledgePoints": ["角度与分式"],
  "mistakeReason": "漏看 \angle 标记",
  "studyAdvice": "规范书写"
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(raw,
        questionId: 'q-latex');

    expect(exercises.length, 3);
  });

  test('service falls back to default exercises when raw json has none', () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "数学",
  "finalAnswer": "x=3",
  "steps": ["移项", "求解"],
  "aiTags": ["方程"],
  "knowledgePoints": ["一元一次方程"],
  "mistakeReason": "计算粗心",
  "studyAdvice": "多练习"
}
''';

    final exercises =
        service.extractGeneratedExercisesFromContent(raw, questionId: 'q-2');

    expect(exercises.length, 3);
    expect(exercises.first.questionId, 'q-2');
    expect(exercises.first.generationMode.name, 'practice');
  });

  test('service normalizes double backslashes in generated exercise content',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "答案为 \\(x=2\\)",
  "steps": ["使用 \\frac{1}{2}"],
  "aiTags": ["方程"],
  "knowledgePoints": ["一元一次方程"],
  "mistakeReason": "计算粗心",
  "studyAdvice": "多练习",
  "generatedExercises": [
    {
      "id": "g-latex",
      "difficulty": "同级",
      "question": "解方程：\\(x^2+1=5\\)",
      "options": ["A. \\(1\\)", "B. \\(2\\)", "C. \\(3\\)", "D. \\(4\\)"],
      "answer": "B",
      "explanation": "因为 \\frac{4}{2}=2"
    }
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(raw,
        questionId: 'q-latex-normalized');

    expect(exercises.single.question, r'解方程：\(x^2+1=5\)');
    expect(exercises.single.question, isNot(contains(r'\\(')));
    expect(exercises.single.explanation, r'因为 \frac{4}{2}=2');
    expect(exercises.single.options, <String>[
      r'A. \(1\)',
      r'B. \(2\)',
      r'C. \(3\)',
      r'D. \(4\)',
    ]);
  });
  test('service extracts generated exercises from raw ai json', () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "数学",
  "finalAnswer": "x=2",
  "steps": ["移项", "求解"],
  "aiTags": ["方程"],
  "knowledgePoints": ["一元一次方程"],
  "mistakeReason": "计算粗心",
  "studyAdvice": "多练习",
  "generatedExercises": [
    {
      "id": "g1",
      "difficulty": "同级",
      "question": "2x+1=5，求 x 的值",
      "options": ["A. 1", "B. 2", "C. 3", "D. 4"],
      "answer": "B",
      "explanation": "2x=4，所以 x=2"
    }
  ]
}
''';

    final exercises =
        service.extractGeneratedExercisesFromContent(raw, questionId: 'q-1');

    expect(exercises.length, 1);
    expect(exercises.first.id, 'g1');
    expect(exercises.first.questionId, 'q-1');
    expect(exercises.first.question, '2x+1=5，求 x 的值');
    expect(exercises.first.options, ['A. 1', 'B. 2', 'C. 3', 'D. 4']);
  });

  test('service rejects linear drift for quadratic root source and falls back',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "由 \(x^2+1=5\) 可得 \(x=\pm 2\)。",
  "steps": ["先得到 \(x^2=4\)", "再开平方，得到 \(x=\pm 2\)"],
  "aiTags": ["一元二次", "平方根", "解方程"],
  "knowledgePoints": ["解含平方项的简单方程", "由 \(x^2=a\) 得 \(x=\pm \sqrt{a}\)"],
  "mistakeReason": "容易漏掉负根",
  "studyAdvice": "整理成 \(x^2=a\) 后再开平方",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "x+1=4，求 x 的值", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项得 x=4-1=3"},
    {"id": "bad2", "difficulty": "同级", "question": "2x=8，求 x 的值", "options": ["A. 2", "B. 3", "C. 4", "D. 6"], "answer": "C", "explanation": "两边同时除以 2 得 x=4"},
    {"id": "bad3", "difficulty": "提高", "question": "3x+2=11，求 x 的值", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "先减 2 再除以 3 得 x=3"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-quadratic',
      sourceQuestionText: r'已知 \(x^2+1=5\)，求 \(x\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), isNot(contains('bad1')));
    expect(exercises.first.question, contains('x^2'));
    expect(exercises.any((exercise) => exercise.explanation.contains(r'\pm')),
        isTrue);
  });

  test(
      'service falls back to function evaluation exercises for function source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "把 x=3 代入 f(x)=x^2-2x+1，得 f(3)=4。",
  "steps": ["代入 x=3", "计算 3^2-2\\times3+1=4"],
  "aiTags": ["函数"],
  "knowledgePoints": ["函数值", "代入求值"],
  "mistakeReason": "代入计算错误",
  "studyAdvice": "按运算顺序计算",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x^2=9，求 x", "options": ["A. 3", "B. -3", "C. \\pm3", "D. 9"], "answer": "C", "explanation": "开平方得 x=\\pm3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 (x-1)^2=16", "options": ["A. 5", "B. -3", "C. 5或-3", "D. 16"], "answer": "C", "explanation": "开平方"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 x^2+4=20", "options": ["A. 4", "B. \\pm4", "C. 8", "D. \\pm8"], "answer": "B", "explanation": "开平方"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-function',
      sourceQuestionText: r'已知函数 \(f(x)=x^2-2x+1\)，求 \(f(3)\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('函数'));
    expect(exercises.first.question, contains(r'f('));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('x^2=9')));
  });

  test('service falls back to volume exercises for cone volume source', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "V=12\\pi",
  "steps": ["V=\\frac{1}{3}\\pi r^2h", "代入 r=3，h=4"],
  "aiTags": ["立体几何"],
  "knowledgePoints": ["圆锥体积", "公式代入"],
  "mistakeReason": "公式记错",
  "studyAdvice": "记住圆锥体积是圆柱的三分之一",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x^2=49，则 x 的值是", "options": ["A. 7", "B. -7", "C. \\pm7", "D. 49"], "answer": "C", "explanation": "开平方"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 (x-1)^2=16", "options": ["A. 5", "B. -3", "C. 5或-3", "D. 16"], "answer": "C", "explanation": "开平方"},
    {"id": "bad3", "difficulty": "提高", "question": "x^2+1=50，求 x", "options": ["A. 7", "B. \\pm7", "C. 49", "D. 50"], "answer": "B", "explanation": "先移项再开平方"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-volume',
      sourceQuestionText: r'圆锥底面半径 r=3，高 h=4，求体积 V=\frac{1}{3}\pi r^2h。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('圆锥'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('解方程')));
  });

  test('service rejects equation system drift to linear equation', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "x=4,y=3",
  "steps": ["两式相加消元", "代入求 y"],
  "aiTags": ["方程组"],
  "knowledgePoints": ["加减消元"],
  "mistakeReason": "消元错误",
  "studyAdvice": "先观察系数",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 2x=8", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "C", "explanation": "除以 2"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 3x+2=11", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-system',
      sourceQuestionText: r'解方程组：\begin{cases} x+y=7 \\ x-y=1 \end{cases}',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('方程组'));
    expect(exercises.first.question, contains('cases'));
  });

  test('service rejects triangle angle drift to algebra equation', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "70°",
  "steps": ["三角形内角和为 180°", "180-50-60=70"],
  "aiTags": ["三角形"],
  "knowledgePoints": ["内角和"],
  "mistakeReason": "角度关系不清",
  "studyAdvice": "先标出已知角",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 2x=8", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "C", "explanation": "除以 2"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 3x+2=11", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-triangle',
      sourceQuestionText:
          r'在 \triangle ABC 中，\angle A=50^\circ，\angle B=60^\circ，求 \angle C。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains(r'\triangle'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('解方程 x+1')));
  });

  test('service preserves valid function evaluation generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "4",
  "steps": ["代入 x=3"],
  "aiTags": ["函数"],
  "knowledgePoints": ["函数值"],
  "mistakeReason": "代入错误",
  "studyAdvice": "先代入再计算",
  "generatedExercises": [
    {"id": "good-f", "difficulty": "同级", "question": "已知函数 f(x)=x^2+1，求 f(2)", "options": ["A. 3", "B. 4", "C. 5", "D. 6"], "answer": "C", "explanation": "代入 x=2，f(2)=4+1=5"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-function-valid',
      sourceQuestionText: r'已知函数 \(f(x)=x^2-2x+1\)，求 \(f(3)\) 的值。',
    );

    expect(exercises.length, 1);
    expect(exercises.single.id, 'good-f');
  });

  test('service preserves valid volume generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "12\\pi",
  "steps": ["代入体积公式"],
  "aiTags": ["立体几何"],
  "knowledgePoints": ["圆锥体积"],
  "mistakeReason": "公式错误",
  "studyAdvice": "区分圆锥和圆柱公式",
  "generatedExercises": [
    {"id": "good-v", "difficulty": "同级", "question": "圆锥底面半径为 2，高为 6，求体积", "options": ["A. 6π", "B. 8π", "C. 10π", "D. 12π"], "answer": "B", "explanation": "体积 V=1/3πr^2h=1/3π×4×6=8π"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-volume-valid',
      sourceQuestionText: r'圆锥底面半径 r=3，高 h=4，求体积 V=\frac{1}{3}\pi r^2h。',
    );

    expect(exercises.length, 1);
    expect(exercises.single.id, 'good-v');
  });

  test(
      'service falls back to proportional relation exercises for fraction source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "a=6,b=3",
  "steps": ["由 \\(\\frac{a}{b}=2\\) 得 \\(a=2b\\)", "代入 \\(a+b=9\\)"],
  "aiTags": ["分式关系", "代入法", "二元关系"],
  "knowledgePoints": ["比值关系", "和式条件"],
  "mistakeReason": "比例关系转化错误",
  "studyAdvice": "先把比值转成倍数关系",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 \\(x^2=9\\)，求 \\(x\\)", "options": ["A. \\(3\\)", "B. \\(-3\\)", "C. \\(\\pm3\\)", "D. \\(9\\)"], "answer": "C", "explanation": "开平方"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程组：\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "加减消元"},
    {"id": "bad3", "difficulty": "提高", "question": "已知函数 f(x)=x^2，求 f(3)", "options": ["A. 3", "B. 6", "C. 9", "D. 12"], "answer": "C", "explanation": "代入"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-proportion',
      sourceQuestionText: r'若 \(\frac{a}{b}=2\)，且 \(a+b=9\)，求 \(a,b\)。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains(r'\frac'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('方程组')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('x^2')));
  });

  test('service preserves valid proportional relation generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "a=6,b=3",
  "steps": ["由 \\(\\frac{a}{b}=2\\) 得 \\(a=2b\\)"],
  "aiTags": ["分式关系", "代入法"],
  "knowledgePoints": ["比值关系", "和式条件"],
  "mistakeReason": "比例关系转化错误",
  "studyAdvice": "先转化再代入",
  "generatedExercises": [
    {"id": "good-ratio", "difficulty": "同级", "question": "若 \\(\\frac{x}{y}=3\\)，且 \\(x+y=16\\)，求 \\(x\\) 的值。", "options": ["A. \\(4\\)", "B. \\(8\\)", "C. \\(12\\)", "D. \\(16\\)"], "answer": "C", "explanation": "由 \\(\\frac{x}{y}=3\\) 得 \\(x=3y\\)，代入 \\(x+y=16\\) 得 \\(4y=16\\)，所以 \\(x=12\\)。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-proportion-valid',
      sourceQuestionText: r'若 \(\frac{a}{b}=2\)，且 \(a+b=9\)，求 \(a,b\)。',
    );

    expect(exercises.length, 1);
    expect(exercises.single.id, 'good-ratio');
  });

  test('service triangle fallback wraps angle latex in inline math', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "70°",
  "steps": ["三角形内角和为 180°"],
  "aiTags": ["三角形"],
  "knowledgePoints": ["内角和"],
  "mistakeReason": "角度关系不清",
  "studyAdvice": "先标出已知角",
  "generatedExercises": []
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-triangle-fallback-format',
      sourceQuestionText:
          r'在 \(\triangle ABC\) 中，若 \(AB=AC\)，且 \(\angle A=40^\circ\)，求 \(\angle B\)。',
    );

    expect(exercises.first.question, contains(r'\(\angle A=50^\circ\)'));
    expect(exercises.first.question, isNot(contains(r'\\angle')));
    expect(exercises.first.explanation, contains(r'\(180^\circ\)'));
  });
  test('service preserves valid quadratic root generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(x=\pm2\)",
  "steps": ["\(x^2=4\)", "\(x=\pm2\)"],
  "aiTags": ["一元二次", "平方根"],
  "knowledgePoints": ["由 \(x^2=a\) 求正负根"],
  "mistakeReason": "漏负根",
  "studyAdvice": "注意正负根",
  "generatedExercises": [
    {"id": "good1", "difficulty": "同级", "question": "已知 \(x^2=16\)，求 \(x\) 的值。", "options": ["A. \(4\)", "B. \(-4\)", "C. \(\pm4\)", "D. \(16\)"], "answer": "C", "explanation": "由 \(x^2=16\) 得 \(x=\pm4\)。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-valid-quadratic',
      sourceQuestionText: r'已知 \(x^2+1=5\)，求 \(x\) 的值。',
    );

    expect(exercises.length, 1);
    expect(exercises.single.id, 'good1');
    expect(exercises.single.question, contains('x^2'));
  });

  test('service rejects equation drift for circle area source and falls back',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{25\pi}{2}\)",
  "steps": ["整圆面积是 \(25\pi\)", "半圆面积是 \(\frac{25\pi}{2}\)"],
  "aiTags": ["圆", "面积", "半圆"],
  "knowledgePoints": ["圆面积", "半圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "先判断目标区域是整圆还是部分圆",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4，求 x 的值", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 2x=8", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "C", "explanation": "除以 2"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 3x+2=11", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-circle-area',
      sourceQuestionText: r'如图，一个半径为 5 cm 的圆，求阴影半圆面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), isNot(contains('bad1')));
    expect(exercises.first.question, contains('圆'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('解方程')));
    expect(
      exercises.map((exercise) => exercise.question).join(' '),
      anyOf(contains('半圆'), contains('圆环')),
    );
  });

  test('service preserves valid circle area generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{25\pi}{2}\)",
  "steps": ["整圆面积是 \(25\pi\)", "半圆面积是 \(\frac{25\pi}{2}\)"],
  "aiTags": ["圆", "面积", "半圆"],
  "knowledgePoints": ["圆面积", "半圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "先判断目标区域是整圆还是部分圆",
  "generatedExercises": [
    {"id": "good-circle", "difficulty": "同级", "question": "一个半圆的半径为 6 cm，求半圆面积。", "options": ["A. \(12\pi\)", "B. \(18\pi\)", "C. \(36\pi\)", "D. \(72\pi\)"], "answer": "B", "explanation": "整圆面积为 \(36\pi\)，半圆面积是一半，所以是 \(18\pi\)。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-circle-valid',
      sourceQuestionText: r'如图，一个半径为 5 cm 的圆，求阴影半圆面积。',
    );

    expect(exercises.length, 1);
    expect(exercises.single.id, 'good-circle');
  });

  test('service rejects solid geometry drift for trapezoid semicircle area',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(25\pi\)",
  "steps": ["半圆面积公式为 \(S=\frac{1}{2}\pi r^2\)", "代入 \(r=5\)，得 \(S=\frac{25\pi}{2}\times2=25\pi\)"],
  "aiTags": ["半圆", "面积", "梯形"],
  "knowledgePoints": ["半圆面积", "切线关系"],
  "mistakeReason": "混淆半圆和整圆面积",
  "studyAdvice": "先确认目标区域",
  "generatedExercises": [
    {"id": "bad-solid", "difficulty": "简单", "question": "圆锥底面半径为 r=2，高为 h=3，则体积 V 为", "options": ["A. \(4\pi\)", "B. \(8\pi\)", "C. \(12\pi\)", "D. \(6\pi\)"], "answer": "A", "explanation": "\(V=\frac{1}{3}\pi r^2h=4\pi\)"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-semicircle-no-solid',
      sourceQuestionText: '如图，一个梯形的上底为3，下底为7，高为10。梯形内有一个半圆，求该半圆的面积。',
    );

    expect(exercises.length, 3);
    expect(
        exercises.map((exercise) => exercise.id), isNot(contains('bad-solid')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('圆锥')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('体积')));
    expect(exercises.first.question, contains('圆'));
  });

  test('service rejects self-invalidating generated exercises and falls back',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "13\pi",
  "steps": ["直径为 2\sqrt{26}", "半圆面积为 13\pi"],
  "aiTags": ["半圆", "面积", "勾股定理"],
  "knowledgePoints": ["半圆面积", "勾股定理"],
  "mistakeReason": "读图假设需核对",
  "studyAdvice": "先确认直径",
  "generatedExercises": [
    {"id": "bad-self", "difficulty": "简单", "question": "某半圆直径两端点水平差为 6，竖直差为 8，求面积", "options": ["A. 10\\pi", "B. 20\\pi", "C. 25\\pi", "D. 50\\pi"], "answer": "B", "explanation": "直径为 10，半径为 5，半圆面积应为 25\\pi/2。注意四个选项中没有该值，原选项设计不严谨。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-self-invalidating',
      sourceQuestionText: '如图，一个梯形内有一个半圆，求该半圆的面积。',
    );

    expect(exercises.length, 3);
    expect(
        exercises.map((exercise) => exercise.id), isNot(contains('bad-self')));
    expect(
      exercises.map((exercise) => exercise.explanation).join(' '),
      isNot(contains('选项中没有')),
    );
  });

  group('B1: visual hypotheses parsing and prompt building', () {
    test('parses well-formed visual hypotheses JSON', () {
      final service = AiAnalysisService.fake();
      const content = '''
```json
{
  "targetObject": "阴影半圆",
  "targetQuestion": "求面积",
  "labelInterpretations": [
    {"label": "10", "meaning": "右侧竖边高度", "confidence": "high"},
    {"label": "3", "meaning": "上边水平长度", "confidence": "medium"},
    {"label": "7", "meaning": "下边水平长度", "confidence": "medium"}
  ],
  "geometricRelationships": ["半圆直径 = 左侧斜边 = √(4²+10²) = 2√29"],
  "uncertainItems": ["3 和 7 是否为端点到竖边的水平距离"],
  "needsManualReview": false
}
```
''';

      final assumptions = service.parseVisualHypothesesForTest(content);

      expect(assumptions.targetObject, '阴影半圆');
      expect(assumptions.targetQuestion, '求面积');
      expect(assumptions.measurements.length, 3);
      expect(assumptions.measurements[0].label, '10');
      expect(assumptions.measurements[0].meaning, '右侧竖边高度');
      expect(assumptions.measurements[0].confidence, 'high');
      expect(assumptions.solutionBasis,
          contains('半圆直径 = 左侧斜边 = √(4²+10²) = 2√29'));
      expect(assumptions.uncertainItems, contains('3 和 7 是否为端点到竖边的水平距离'));
      expect(assumptions.needsManualReview, isFalse);
    });

    test('parses hypotheses with needsManualReview true', () {
      final service = AiAnalysisService.fake();
      const content = '''
{
  "targetObject": "半圆",
  "targetQuestion": "面积",
  "labelInterpretations": [
    {"label": "10", "meaning": "可能是直径也可能是高", "confidence": "low"}
  ],
  "geometricRelationships": [],
  "uncertainItems": ["10 的含义不确定"],
  "needsManualReview": true
}
''';

      final assumptions = service.parseVisualHypothesesForTest(content);

      expect(assumptions.needsManualReview, isTrue);
      expect(assumptions.measurements[0].confidence, 'low');
      expect(assumptions.uncertainItems, contains('10 的含义不确定'));
    });

    test('returns fallback with needsManualReview on malformed JSON', () {
      final service = AiAnalysisService.fake();
      const content = 'This is not JSON at all, just plain text.';

      final assumptions = service.parseVisualHypothesesForTest(content);

      expect(assumptions.needsManualReview, isTrue);
      expect(assumptions.measurements, isEmpty);
    });

    test('builds locked hypotheses prompt with all fields', () {
      final service = AiAnalysisService.fake();
      const hypothesesJson = '''
{
  "targetObject": "阴影半圆",
  "targetQuestion": "求面积",
  "labelInterpretations": [
    {"label": "10", "meaning": "右侧竖边高度", "confidence": "high"},
    {"label": "3", "meaning": "上边水平长度", "confidence": "medium"}
  ],
  "geometricRelationships": ["半圆直径 = 斜边长"],
  "uncertainItems": ["3 是否参与计算"],
  "needsManualReview": false
}
''';

      final prompt = service.buildLockedHypothesesPromptForTest(hypothesesJson);

      expect(prompt, contains('【已锁定的读图假设 — 不得修改】'));
      expect(prompt, contains('求解目标：阴影半圆 求面积'));
      expect(prompt, contains('10 → 右侧竖边高度 (high)'));
      expect(prompt, contains('3 → 上边水平长度 (medium)'));
      expect(prompt, contains('半圆直径 = 斜边长'));
      expect(prompt, contains('3 是否参与计算'));
      expect(prompt, contains('不得临时赋予新含义'));
    });

    test('builds locked hypotheses prompt with empty optional fields', () {
      final service = AiAnalysisService.fake();
      const hypothesesJson = '''
{
  "targetObject": "圆",
  "targetQuestion": "求周长",
  "labelInterpretations": [],
  "geometricRelationships": [],
  "uncertainItems": [],
  "needsManualReview": false
}
''';

      final prompt = service.buildLockedHypothesesPromptForTest(hypothesesJson);

      expect(prompt, contains('【已锁定的读图假设 — 不得修改】'));
      expect(prompt, contains('求解目标：圆 求周长'));
      expect(prompt, isNot(contains('标注含义：')));
      expect(prompt, isNot(contains('几何关系：')));
      expect(prompt, isNot(contains('不确定项：')));
    });
  });
}
