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

  static final _questionStart = RegExp(r'^\s*(?:第\s*)?(\d{1,3})\s*(?:[\.．、:：]|[（(])');

  List<QuestionRegion> _extractRegions(String jsonl) {
    final blocks = <_PaddleBlock>[];
    for (final line in const LineSplitter().convert(jsonl)) {
      try {
        _collectBlocks(jsonDecode(line), blocks, null);
      } catch (_) {
        // Skip malformed JSONL rows; other result rows remain usable.
      }
    }
    final unique = <String, _PaddleBlock>{};
    for (final block in blocks) {
      final rect = block.rect;
      if (rect.width >= .10 && rect.height >= .025) {
        unique['${rect.left.toStringAsFixed(3)},${rect.top.toStringAsFixed(3)},${rect.right.toStringAsFixed(3)},${rect.bottom.toStringAsFixed(3)}'] = block;
      }
    }
    final ordered = unique.values.toList()
      ..sort((a, b) {
        final row = (a.rect.top - b.rect.top).abs() < .015
            ? a.rect.left.compareTo(b.rect.left)
            : a.rect.top.compareTo(b.rect.top);
        return row;
      });
    final starts = <int>[];
    for (var index = 0; index < ordered.length; index++) {
      if (_questionStart.hasMatch(ordered[index].text)) starts.add(index);
    }
    if (starts.isEmpty) return _fallbackBlockRegions(ordered);

    final regions = <QuestionRegion>[];
    for (var group = 0; group < starts.length; group++) {
      final from = starts[group];
      final to = group + 1 < starts.length ? starts[group + 1] : ordered.length;
      final questionBlocks = ordered.sublist(from, to);
      final rect = questionBlocks.map((block) => block.rect).reduce((a, b) => a.expandToInclude(b));
      final text = questionBlocks.map((block) => block.text.trim()).where((text) => text.isNotEmpty).join('\n');
      if (rect.width < .10 || rect.height < .06) continue;
      regions.add(QuestionRegion(
        id: 'paddle-question-$group',
        normalizedRect: rect,
        detectedNumber: _questionStart.firstMatch(ordered[from].text)?.group(1),
        recognizedText: text.isEmpty ? null : text,
        contentFormatHint: text.contains(r'$') || text.contains(r'\\') ? 'latexMixed' : 'plain',
        recognizedBlockTypes: _classifyText(text),
        confidence: .76,
        source: QuestionRegionSource.layoutModel,
      ));
    }
    return regions.isEmpty ? _fallbackBlockRegions(ordered) : regions;
  }

  List<QuestionRegion> _fallbackBlockRegions(List<_PaddleBlock> blocks) => blocks
      .where((block) => block.rect.width >= .10 && block.rect.height >= .06)
      .take(30)
      .toList()
      .asMap()
      .entries
      .map((entry) => QuestionRegion(
            id: 'paddle-block-${entry.key}',
            normalizedRect: entry.value.rect,
            recognizedText: entry.value.text.isEmpty ? null : entry.value.text,
            contentFormatHint: entry.value.text.contains(r'$') || entry.value.text.contains(r'\\') ? 'latexMixed' : 'plain',
            recognizedBlockTypes: _classifyText(entry.value.text),
            confidence: .55,
            source: QuestionRegionSource.layoutModel,
          ))
      .toList();

  List<String> _classifyText(String text) {
    final types = <String>['文字'];
    if (text.contains(r'$') || text.contains(r'\\') || RegExp(r'[∑√∫≠≤≥]').hasMatch(text)) types.add('公式');
    if (text.contains('|') && text.split('\n').where((line) => line.contains('|')).length >= 2) types.add('表格');
    if (RegExp(r'(?:^|\n)\s*[A-DＡ-Ｄ][\.．、]').hasMatch(text)) types.add('选项');
    return types;
  }

  void _collectBlocks(dynamic value, List<_PaddleBlock> out, Size? inheritedSize) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final pageSize = _size(map) ?? inheritedSize;
      final label = (map['label'] ?? map['block_label'] ?? map['type'] ?? '').toString().toLowerCase();
      final box = _box(map['bbox'] ?? map['box'] ?? map['coordinate'] ?? map['poly']);
      final text = (map['text'] ?? map['content'] ?? map['text_content'] ?? '').toString().trim();
      if (box != null && text.isNotEmpty && !label.contains('header') && !label.contains('footer') && !label.contains('image')) {
        final raw = pageSize == null ? box : Rect.fromLTWH(box.left / pageSize.width, box.top / pageSize.height, box.width / pageSize.width, box.height / pageSize.height);
        final rect = Rect.fromLTRB(raw.left.clamp(0, 1).toDouble(), raw.top.clamp(0, 1).toDouble(), raw.right.clamp(0, 1).toDouble(), raw.bottom.clamp(0, 1).toDouble());
        if (!rect.isEmpty) out.add(_PaddleBlock(rect, text));
      }
      for (final child in map.values) {
        _collectBlocks(child, out, pageSize);
      }
    } else if (value is List) {
      for (final child in value) {
        _collectBlocks(child, out, inheritedSize);
      }
    }
  }

  Map<String, dynamic>? _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;
  Size? _size(Map<String, dynamic> map) { final width = _number(map['pageWidth'] ?? map['width']); final height = _number(map['pageHeight'] ?? map['height']); return width != null && height != null && width > 1 && height > 1 ? Size(width, height) : null; }
  double? _number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value');
  Rect? _box(dynamic value) { if (value is! List || value.isEmpty) return null; final n = value.map(_number).toList(); if (n.length >= 4 && n.take(4).every((x) => x != null)) return Rect.fromLTRB(n[0]!, n[1]!, n[2]!, n[3]!); if (value.first is List) { final points = value.whereType<List>().map((p) => p.length >= 2 ? Offset(_number(p[0]) ?? 0, _number(p[1]) ?? 0) : null).whereType<Offset>().toList(); if (points.isNotEmpty) return Rect.fromPoints(Offset(points.map((p) => p.dx).reduce((a,b) => a < b ? a : b), points.map((p) => p.dy).reduce((a,b) => a < b ? a : b)), Offset(points.map((p) => p.dx).reduce((a,b) => a > b ? a : b), points.map((p) => p.dy).reduce((a,b) => a > b ? a : b))); } return null; }
}


class _PaddleBlock {
  const _PaddleBlock(this.rect, this.text);
  final Rect rect;
  final String text;
}
