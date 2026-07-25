import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/recognition_confirmation_screen.dart';

void main() {
  Future<void> selectCompactSegment(WidgetTester tester, bool showImage) async {
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    segmented.onSelectionChanged?.call(<bool>{showImage});
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pumpWorkbench(
    WidgetTester tester, {
    required Size size,
    required ThemeMode themeMode,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state = QuestionRecord.draft(
      id: 'phase2-review',
      imagePath: '/tmp/missing-phase2-image.jpg',
      subject: Subject.math,
      recognizedText: '求 x 的值\nA. 1\nB. 2',
    ).copyWith(
      extractedQuestionText: 'OCR: 求x值 A1 B2',
      normalizedQuestionText: '求 x 的值\nA. 1\nB. 2',
      ocrConfidence: .55,
      studentAnswer: 'B',
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: themeMode,
        home: const RecognitionConfirmationScreen(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('320px compact layout switches between image and review', (tester) async {
    await pumpWorkbench(tester, size: const Size(320, 700), themeMode: ThemeMode.light);
    expect(find.text('原图附件缺失，请手动录入或放弃此草稿'), findsOneWidget);
    await selectCompactSegment(tester, false);
    expect(find.text('识别来源对照'), findsOneWidget);
    expect(find.text('OCR 原文'), findsNothing);
    await tester.tap(find.text('识别来源对照'));
    await tester.pumpAndSettle();
    expect(find.text('OCR 原文'), findsOneWidget);
    expect(find.text('AI 规范化文本'), findsOneWidget);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.length, greaterThanOrEqualTo(2));
    expect(fields.map((field) => field.decoration?.labelText),
        contains('用户修正题干'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet dark layout shows image and layered text side by side', (tester) async {
    await pumpWorkbench(tester, size: const Size(1024, 900), themeMode: ThemeMode.dark);
    expect(find.text('原图附件缺失，请手动录入或放弃此草稿'), findsOneWidget);
    expect(find.text('识别来源对照'), findsOneWidget);
    expect(find.text('OCR 原文'), findsNothing);
    await tester.tap(find.text('识别来源对照'));
    await tester.pumpAndSettle();
    expect(find.text('OCR 原文'), findsOneWidget);
    expect(find.text('AI 规范化文本'), findsOneWidget);
    expect(find.textContaining('确认低置信度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
