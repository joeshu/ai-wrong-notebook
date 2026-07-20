import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
    String? pageRanges,
  }) async {
    if (config.apiKey.trim().isEmpty) {
      throw StateError('请先在“试卷版面识别”中填写 PaddleOCR AI Studio Token');
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      // Authorization 规范为大写 Bearer（RFC 7235 大小写不敏感，但统一更规范）。
      headers: <String, String>{'Authorization': 'Bearer ${config.apiKey.trim()}'},
    ));
    try {
      // P6a: pageRanges 作为顶层 multipart 字段下发（仅在调用方提供时附加）。
      final formData = <String, dynamic>{
        'file': await MultipartFile.fromFile(imagePath, filename: File(imagePath).uri.pathSegments.last),
        'model': 'PP-StructureV3',
        'optionalPayload': jsonEncode(const <String, bool>{
          'useDocOrientationClassify': false,
          'useDocUnwarping': false,
          'useChartRecognition': false,
        }),
      };
      if (pageRanges != null && pageRanges.isNotEmpty) {
        formData['pageRanges'] = pageRanges;
      }

      // P3: 提交任务带指数退避重试（1s/2s/4s，最多 3 次）。
      // 业务码 10010（队列已满）的检查必须放在 action 内部，才能触发 _retry 退避；
      // 其它非零业务码不可重试，直接抛 StateError 穿透 _retry 上报给调用方。
      final submit = await _retry<Response<dynamic>>(
        '提交任务',
        () async {
          final response = await dio.post<dynamic>(_jobUrl, data: FormData.fromMap(formData));
          final root = _map(response.data);
          final code = _int(root?['code']);
          if (root != null && code != null && code != 0) {
            final msg = root['msg']?.toString() ?? '';
            if (code == 10010) {
              throw _RetryableBusinessError(code, msg);
            }
            throw StateError(classifyError(businessCode: code, rawMessage: msg));
          }
          return response;
        },
      );
      final submittedRoot = _map(submit.data);
      final submittedData = _map(submittedRoot?['data']);
      final jobId = submittedData?['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) throw StateError('PaddleOCR 未返回任务编号');

      // P1 + P4: 显式区分 4 态轮询；前 5 次 2s、第 6 次起 5s，最多 36 次。
      Map<String, dynamic>? job;
      for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
        await Future<void>.delayed(Duration(seconds: attempt < _fastPollThreshold ? 2 : 5));
        final response = await dio.get<dynamic>('$_jobUrl/$jobId');
        job = _map(response.data)?['data'] is Map ? _map(_map(response.data)!['data']) : null;
        final state = job?['state']?.toString();
        if (state == 'done') break;
        if (state == 'failed') {
          throw StateError('PaddleOCR 识别失败：${job?['errorMsg'] ?? '未知错误'}');
        }
        // pending（排队）/ running（解析中）/ null：继续轮询。
        // running 时记录 extractProgress 到日志，便于排查长任务。
        if (state == 'running') {
          final progress = _map(job?['extractProgress']);
          final extracted = progress?['extractedPages']?.toString();
          final total = progress?['totalPages']?.toString();
          if (extracted != null || total != null) {
            debugPrint('[PaddleOCR] 任务 $jobId running: $extracted/$total 页');
          }
        }
      }
      if (job?['state'] != 'done') throw StateError('PaddleOCR 识别超时，请稍后重试');

      // P6b: 优先 jsonUrl；为空时退回 markdownUrl 构造整页文本块兜底。
      final resultUrlMap = _map(job?['resultUrl']);
      final jsonUrl = resultUrlMap?['jsonUrl']?.toString();
      final markdownUrl = resultUrlMap?['markdownUrl']?.toString();
      final List<QuestionRegion> regions;
      if (jsonUrl != null && jsonUrl.isNotEmpty) {
        final result = await _retry<Response<String>>(
          '下载结果',
          () => dio.get<String>(jsonUrl, options: Options(responseType: ResponseType.plain)),
        );
        regions = _extractRegions(result.data ?? '');
      } else if (markdownUrl != null && markdownUrl.isNotEmpty) {
        final result = await _retry<Response<String>>(
          '下载 Markdown 结果',
          () => dio.get<String>(markdownUrl, options: Options(responseType: ResponseType.plain)),
        );
        regions = _regionsFromMarkdown(result.data ?? '');
      } else {
        throw StateError('PaddleOCR 未返回结果地址');
      }
      if (regions.isEmpty) throw StateError('PaddleOCR 未识别到可用题框；请改为手动框选');
      return LayoutDetectionResult(regions: regions, providerLabel: 'PaddleOCR PP-StructureV3', warning: '候选题框请在裁切前逐一确认。');
    } on DioException catch (error) {
      // P2: 把网络/HTTP 错误翻译成用户可读文案；保留原始响应体作为 rawMessage。
      final httpStatus = error.response?.statusCode;
      final rawBody = error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      final businessCode = _extractBusinessCode(error.response?.data);
      throw StateError(classifyError(httpStatus: httpStatus, businessCode: businessCode, rawMessage: rawBody));
    } on _RetryableBusinessError catch (error) {
      // 重试耗尽后，把队列已满错误翻译成中文文案。
      throw StateError(classifyError(businessCode: error.code, rawMessage: error.message));
    } finally {
      dio.close();
    }
  }

  // P4: 前 5 次快速轮询（2s），第 6 次起 5s，最多 36 次（5×2 + 31×5 = 165s）。
  static const _fastPollThreshold = 5;
  static const _maxPollAttempts = 36;

  // P3: 对网络敏感操作（提交任务 / 下载结果）做指数退避重试。
  // 轮询查询（GET /jobs/{jobId}）不重试，因为已经在轮询循环里。
  Future<T> _retry<T>(String opLabel, Future<T> Function() action, {int maxRetries = 3}) async {
    var attempt = 0;
    var delay = const Duration(seconds: 1);
    while (true) {
      try {
        return await action();
      } on DioException catch (e) {
        attempt++;
        if (attempt >= maxRetries || !isRetryable(e)) rethrow;
        debugPrint('[PaddleOCR] $opLabel 第 $attempt 次重试（${e.type}/${e.response?.statusCode}），${delay.inSeconds}s 后再试');
        await Future<void>.delayed(delay);
        delay *= 2;
      } on _RetryableBusinessError catch (e) {
        attempt++;
        if (attempt >= maxRetries) rethrow;
        debugPrint('[PaddleOCR] $opLabel 第 $attempt 次重试（业务码 ${e.code}），${delay.inSeconds}s 后再试');
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  @visibleForTesting
  bool isRetryable(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = e.response?.statusCode ?? 0;
    return status == 502 || status == 503 || status == 504;
  }

  // P2: HTTP 状态码 + 业务 code → 用户可读中文文案。优先业务 code，其次 HTTP 状态。
  @visibleForTesting
  String classifyError({int? httpStatus, int? businessCode, String? rawMessage}) {
    if (businessCode != null) {
      switch (businessCode) {
        case 10010: return '任务队列已满，请稍后重试';
        case 11002: return '任务结果已过期，请重新提交';
        case 12001: return '已达单日 3000 页配额，请次日再试';
        case 12002: return '请求频率过高，请稍后重试';
      }
    }
    switch (httpStatus) {
      case 401: return 'Token 无效或已过期，请重新填写 AI Studio 访问令牌';
      case 403: return 'Token 无权限或已达到单日 3000 页配额，请次日再试或到 AI Studio 申请配额';
      case 413: return '文件过大（>50MB），请压缩后再上传';
      case 422: return '请求参数错误：${rawMessage ?? ''}';
      case 429: return '请求频率过高，请稍后重试';
      case 500:
      case 502:
      case 504: return 'PaddleOCR 服务暂时不可用，请稍后重试或切换到 MinerU';
      case 503: return '服务繁忙，请稍后重试';
    }
    return 'PaddleOCR 服务请求失败：${rawMessage ?? '未知错误'}';
  }

  int? _extractBusinessCode(dynamic data) {
    final map = _map(data);
    if (map == null) return null;
    return _int(map['code']);
  }

  int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  // P6b 兜底：把 markdown 当成单个整页文本块，让 _fallbackBlockRegions 仍能产出候选框。
  List<QuestionRegion> _regionsFromMarkdown(String markdown) {
    final text = markdown.trim();
    if (text.isEmpty) return const <QuestionRegion>[];
    return _fallbackBlockRegions(<_PaddleBlock>[_PaddleBlock(const Rect.fromLTWH(0, 0, 1, 1), text)]);
  }

  static final _questionStart = RegExp(r'^\s*(?:第\s*)?(\d{1,3})\s*(?:[\.．、:：]|[（(])');

  @visibleForTesting
  List<QuestionRegion> extractRegionsForTesting(String jsonl) => _extractRegions(jsonl);

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
        documentBlocks: questionBlocks.where((block) => block.text.trim().isNotEmpty).map((block) =>
            DocumentBlock(type: _blockType(block.text), content: block.text.trim())).toList(),
        contentFormatHint: text.contains(r'$') || text.contains(r'\\') ? 'latexMixed' : 'plain',
        recognizedBlockTypes: _classifyText(text),
        confidence: .76,
        source: QuestionRegionSource.layoutModel,
      ));
    }
    return regions.isEmpty ? _fallbackBlockRegions(ordered) : regions;
  }

  DocumentBlockType _blockType(String text) {
    if (text.contains('|') && text.split('\n').where((line) => line.contains('|')).length >= 2) {
      return DocumentBlockType.table;
    }
    if (text.contains(r'$') || text.contains(r'\\') || RegExp(r'[∑√∫≠≤≥]').hasMatch(text)) {
      return DocumentBlockType.formula;
    }
    return DocumentBlockType.text;
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

/// P3: 业务码 10010（队列已满）视为可重试错误，让 _retry 退避后重试提交。
class _RetryableBusinessError implements Exception {
  const _RetryableBusinessError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => '业务码 $code: $message';
}
