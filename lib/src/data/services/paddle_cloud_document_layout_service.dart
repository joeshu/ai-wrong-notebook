import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

/// Adapter for PaddleOCR AI Studio's asynchronous PP-StructureV3 API.
/// The API key is supplied through [LayoutProviderConfig] and is stored only
/// in flutter_secure_storage by LayoutProviderRepository.
class PaddleCloudDocumentLayoutService implements DocumentLayoutService {
  PaddleCloudDocumentLayoutService(this.config);
  final LayoutProviderConfig config;

  static const _jobUrl = 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs';

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({required String imagePath}) async {
    if (config.apiKey.trim().isEmpty) {
      throw StateError('请先在“试卷版面识别”中填写 PaddleOCR AI Studio Token');
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      headers: <String, String>{'Authorization': 'bearer ${config.apiKey.trim()}'},
    ));
    try {
      final submit = await dio.post<dynamic>(_jobUrl, data: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(imagePath, filename: File(imagePath).uri.pathSegments.last),
        'model': 'PP-StructureV3',
        'optionalPayload': jsonEncode(const <String, bool>{
          'useDocOrientationClassify': false,
          'useDocUnwarping': false,
          'useChartRecognition': false,
        }),
      }));
      final submittedRoot = _map(submit.data);
      final submittedData = _map(submittedRoot?['data']);
      final jobId = submittedData?['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) throw StateError('PaddleOCR 未返回任务编号');

      Map<String, dynamic>? job;
      for (var attempt = 0; attempt < 60; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final response = await dio.get<dynamic>('$_jobUrl/$jobId');
        job = _map(response.data)?['data'] is Map ? _map(_map(response.data)!['data']) : null;
        final state = job?['state']?.toString();
        if (state == 'done') break;
        if (state == 'failed') throw StateError('PaddleOCR 识别失败：${job?['errorMsg'] ?? '未知错误'}');
      }
      if (job?['state'] != 'done') throw StateError('PaddleOCR 识别超时，请稍后重试');
      final resultUrl = _map(job?['resultUrl'])?['jsonUrl']?.toString();
      if (resultUrl == null || resultUrl.isEmpty) throw StateError('PaddleOCR 未返回结果地址');
      final result = await dio.get<String>(resultUrl, options: Options(responseType: ResponseType.plain));
      final regions = _extractRegions(result.data ?? '');
      if (regions.isEmpty) throw StateError('PaddleOCR 未识别到可用题框；请改为手动框选');
      return LayoutDetectionResult(regions: regions, providerLabel: 'PaddleOCR PP-StructureV3', warning: '候选题框请在裁切前逐一确认。');
    } on DioException catch (error) {
      final message = error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      throw StateError('PaddleOCR 服务请求失败：$message');
    } finally {
      dio.close();
    }
  }

  List<QuestionRegion> _extractRegions(String jsonl) {
    final regions = <QuestionRegion>[];
    var index = 0;
    for (final line in const LineSplitter().convert(jsonl)) {
      try {
        final root = jsonDecode(line);
        _walk(root, (map) {
          final label = (map['label'] ?? map['block_label'] ?? map['type'] ?? '').toString().toLowerCase();
          if (label.contains('header') || label.contains('footer') || label.contains('image')) return;
          final box = _box(map['bbox'] ?? map['box'] ?? map['coordinate'] ?? map['poly']);
          if (box == null) return;
          // Paddle commonly emits pixel coordinates; normalized coordinates are
          // accepted as well when a gateway has already normalized them.
          final pageSize = _size(map);
          if (pageSize == null && (box.right > 1 || box.bottom > 1)) return;
          final rect = pageSize == null ? box : Rect.fromLTWH(box.left / pageSize.width, box.top / pageSize.height, box.width / pageSize.width, box.height / pageSize.height);
          final clipped = Rect.fromLTWH(rect.left.clamp(0, 1).toDouble(), rect.top.clamp(0, 1).toDouble(), rect.width.clamp(0, 1 - rect.left.clamp(0, 1)).toDouble(), rect.height.clamp(0, 1 - rect.top.clamp(0, 1)).toDouble());
          if (clipped.width < .10 || clipped.height < .06) return;
          final text = (map['text'] ?? map['content'] ?? map['text_content'] ?? '').toString().trim();
          regions.add(QuestionRegion(
            id: 'paddle-${index++}',
            normalizedRect: clipped,
            recognizedText: text.isEmpty ? null : text,
            contentFormatHint: text.contains(r'$') || text.contains(r'\\') ? 'latexMixed' : 'plain',
            confidence: .70,
            source: QuestionRegionSource.layoutModel,
          ));
        });
      } catch (_) { /* Skip malformed JSONL rows. */ }
    }
    return regions;
  }

  void _walk(dynamic value, void Function(Map<String, dynamic>) visit) {
    if (value is Map) { final map = Map<String, dynamic>.from(value); visit(map); for (final child in map.values) { _walk(child, visit); } }
    if (value is List) { for (final child in value) { _walk(child, visit); } }
  }
  Map<String, dynamic>? _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;
  Size? _size(Map<String, dynamic> map) { final width = _number(map['pageWidth'] ?? map['width']); final height = _number(map['pageHeight'] ?? map['height']); return width != null && height != null && width > 1 && height > 1 ? Size(width, height) : null; }
  double? _number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value');
  Rect? _box(dynamic value) { if (value is! List || value.isEmpty) return null; final n = value.map(_number).toList(); if (n.length >= 4 && n.take(4).every((x) => x != null)) return Rect.fromLTRB(n[0]!, n[1]!, n[2]!, n[3]!); if (value.first is List) { final points = value.whereType<List>().map((p) => p.length >= 2 ? Offset(_number(p[0]) ?? 0, _number(p[1]) ?? 0) : null).whereType<Offset>().toList(); if (points.isNotEmpty) return Rect.fromPoints(Offset(points.map((p) => p.dx).reduce((a,b) => a < b ? a : b), points.map((p) => p.dy).reduce((a,b) => a < b ? a : b)), Offset(points.map((p) => p.dx).reduce((a,b) => a > b ? a : b), points.map((p) => p.dy).reduce((a,b) => a > b ? a : b))); } return null; }
}
