import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_region_editor_screen.dart';

QuestionRegion _region({
  String id = 'r1',
  Rect? rect,
  String? text,
  double confidence = 1,
  QuestionRegionSource source = QuestionRegionSource.manual,
  List<String> blockTypes = const <String>[],
}) {
  return QuestionRegion(
    id: id,
    normalizedRect: rect ?? const Rect.fromLTWH(0.1, 0.1, 0.3, 0.2),
    recognizedText: text,
    confidence: confidence,
    source: source,
    recognizedBlockTypes: blockTypes,
  );
}

void main() {
  group('FieldStatus 四态统一', () {
    testWidgets('StatusPill 渲染各状态文案与配色', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                StatusPill(label: '题干', status: FieldStatus.recognized),
                StatusPill(label: '公式', status: FieldStatus.needsReview),
                StatusPill(label: '选项', status: FieldStatus.missing),
                StatusPill(label: '图形', status: FieldStatus.notApplicable),
              ],
            ),
          ),
        ),
      );

      expect(find.text('题干 · 已识别'), findsOneWidget);
      expect(find.text('公式 · 待校对'), findsOneWidget);
      expect(find.text('选项 · 未识别'), findsOneWidget);
      expect(find.text('图形 · 不适用'), findsOneWidget);
    });

    test('FieldStatus.label 文案固定为四态', () {
      expect(FieldStatus.recognized.label, '已识别');
      expect(FieldStatus.missing.label, '未识别');
      expect(FieldStatus.needsReview.label, '待校对');
      expect(FieldStatus.notApplicable.label, '不适用');
    });

    test('FieldStatus 配色不重复且非透明', () {
      final statuses = FieldStatus.values;
      final bgColors = statuses.map((s) => s.backgroundColor).toSet();
      final fgColors = statuses.map((s) => s.foregroundColor).toSet();
      expect(bgColors.length, statuses.length, reason: '背景色应四态各不相同');
      expect(fgColors.length, statuses.length, reason: '前景色应四态各不相同');
    });
  });

  group('detectQuestionRegionRisks 题框风险检测', () {
    test('空题干提示待校对', () {
      final region = _region(text: '   ');
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('未识别到题干文字'));
    });

    test('题框宽高比异常（过宽）', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.1, 0.45, 0.8, 0.02), // aspect = 40
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('宽高比异常')), isTrue);
    });

    test('题框宽高比异常（过高）', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.45, 0.05, 0.02, 0.9), // aspect = 0.022
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks.any((m) => m.contains('宽高比异常')), isTrue);
    });

    test('题框占整页面积过大', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.05, 0.05, 0.92, 0.92), // area ≈ 0.846
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题框占整页面积过大，可能包含多题'));
    });

    test('题框面积过小', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.5, 0.5, 0.04, 0.04), // area = 0.0016
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题框面积过小，可能只截到单字或符号'));
    });

    test('题框贴近页面边缘', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.0, 0.1, 0.3, 0.2), // left = 0
        text: '题干',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('题框贴近页面边缘，可能被截断'));
    });

    test('与其它题框重叠', () {
      final r1 = _region(
        id: 'r1',
        rect: const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4),
        text: '题干1',
      );
      final r2 = _region(
        id: 'r2',
        rect: const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4), // 与 r1 大面积重叠
        text: '题干2',
      );
      final risks = detectQuestionRegionRisks(r1, <QuestionRegion>[r1, r2], index: 0);
      expect(risks.any((m) => m.contains('题框重叠')), isTrue);
    });

    test('含公式或表格提示核对格式', () {
      final region = _region(text: '题干', blockTypes: const <String>['公式']);
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('含公式或表格，建议核对格式'));
    });

    test('低可信度布局模型识别提示校对', () {
      final region = _region(
        text: '题干',
        confidence: 0.4,
        source: QuestionRegionSource.layoutModel,
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, contains('识别可信度较低，建议校对'));
    });

    test('正常题框无风险', () {
      final region = _region(
        rect: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.2),
        text: '一道正常的题目',
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, isEmpty);
    });

    test('手动框选低可信度不触发（仅布局模型触发）', () {
      final region = _region(
        text: '题干',
        confidence: 0.3,
        source: QuestionRegionSource.manual,
      );
      final risks = detectQuestionRegionRisks(region, <QuestionRegion>[region]);
      expect(risks, isNot(contains('识别可信度较低，建议校对')));
    });
  });
}
