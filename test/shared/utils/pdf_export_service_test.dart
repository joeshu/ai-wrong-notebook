import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 禁用网络：让 [PdfGoogleFonts] 立即抛错，触发 [_loadCjkFont] 的 catch 分支
/// 回退到 Helvetica，避免测试在 CI 等无外网环境卡住 HTTP 超时。
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw const SocketException('Network disabled in PDF export test');
  }
}

void main() {
  late Directory tempDir;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('pdf_export_test_');
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });
    HttpOverrides.global = _NoNetworkHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  List<QuestionRecord> _sampleQuestions() => <QuestionRecord>[
        QuestionRecord.draft(
          id: 'q-1',
          imagePath: '',
          subject: Subject.math,
          recognizedText: '已知 2x+1=5，求 x 的值',
        ).copyWith(
          analysisResult: const AnalysisResult(
            finalAnswer: 'x=2',
            steps: <String>['移项得 2x=4'],
            aiTags: <String>['方程'],
            knowledgePoints: <String>['代数'],
            mistakeReason: '审题不清',
            studyAdvice: '多复习',
          ),
        ),
        QuestionRecord.draft(
          id: 'q-2',
          imagePath: '',
          subject: Subject.english,
          recognizedText: 'Choose the correct answer',
        ),
      ];

  test('generatePdf writes a non-empty file beginning with %PDF', () async {
    final file = await PdfExportService.generatePdf(
      _sampleQuestions(),
      title: '错题本PDF测试',
      mode: WorksheetExportMode.answer,
    );

    expect(file.existsSync(), isTrue);
    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    // PDF magic bytes: %PDF-1.x
    final magic = String.fromCharCodes(bytes.take(4));
    expect(magic, '%PDF');
  });

  test('generatePdf writes file under the exports directory of the temp root',
      () async {
    final file = await PdfExportService.generatePdf(
      _sampleQuestions(),
      mode: WorksheetExportMode.answer,
    );

    expect(file.path, startsWith(tempDir.path));
    expect(file.path, contains('exports'));
    expect(file.path, endsWith('.pdf'));
  });

  test('generatePdf in practice mode still produces a valid PDF', () async {
    final file = await PdfExportService.generatePdf(
      _sampleQuestions(),
      mode: WorksheetExportMode.practice,
    );

    final bytes = await file.readAsBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
