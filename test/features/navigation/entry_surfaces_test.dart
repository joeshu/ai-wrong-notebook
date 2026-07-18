import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/worksheet_workbench_screen.dart';

void main() {
  final override = questionRepositoryProvider.overrideWithValue(
    InMemoryQuestionRepository(),
  );

  testWidgets('worksheet workbench renders its empty-state action', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: WorksheetWorkbenchScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有可组卷的错题'), findsOneWidget);
    expect(find.text('去添加错题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add-question sheet renders on a dark surface', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [override],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(body: CaptureEntrySheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('添加错题'), findsOneWidget);
    expect(find.text('试卷批量导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
