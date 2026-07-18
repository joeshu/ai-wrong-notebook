import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

/// MinerU precision API adapter. It uploads a local page using a presigned URL,
/// polls the batch job, then groups MinerU layout blocks by question numbers.
/// Groups are only editable candidates; nothing is saved without confirmation.
class MineruDocumentLayoutService implements DocumentLayoutService {
  MineruDocumentLayoutService(this.config);
  final LayoutProviderConfig config;
  static const _base = 'https://mineru.net/api/v4';
  static final _questionStart = RegExp(r'^\s*(?:第\s*)?(\d{1,3})\s*(?:[\.．、:：]|[（(])');

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({required String imagePath}) async {
    if (config.apiKey.trim().isEmpty) throw StateError('请先在“试卷版面识别”中填写 MinerU Token');
    final source = File(imagePath);
    if (!await source.exists()) throw StateError('未找到试卷图片');
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw StateError('无法读取试卷图片尺寸');
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30), receiveTimeout: const Duration(seconds: 90),
      headers: <String, String>{'Authorization': 'Bearer ${config.apiKey.trim()}', 'Content-Type': 'application/json'},
    ));
    try {
      final name = source.uri.pathSegments.last;
      final dataId = 'worksheet-${DateTime.now().microsecondsSinceEpoch}';
      final applied = await dio.post<dynamic>('$_base/file-urls/batch', data: <String, dynamic>{
        'files': <Map<String, String>>[<String, String>{'name': name, 'data_id': dataId}],
        'model_version': 'vlm', 'language': 'ch', 'enable_formula': true, 'enable_table': true,
      });
      final root = _map(applied.data);
      if (root?['code'] != 0) throw StateError('MinerU 创建上传任务失败：${root?['msg'] ?? '未知错误'}');
      final request = _map(root?['data']);
      final batchId = request?['batch_id']?.toString();
      final urls = request?['file_urls'];
      if (batchId == null || urls is! List || urls.isEmpty) throw StateError('MinerU 未返回上传地址');
      final uploadDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        contentType: null,
      ));
      try {
        await uploadDio.put<dynamic>(urls.first.toString(), data: bytes);
      } finally {
        uploadDio.close();
      }

      Map<String, dynamic>? item;
      for (var attempt = 0; attempt < 90; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final poll = await dio.get<dynamic>('$_base/extract-results/batch/$batchId');
        final pollRoot = _map(poll.data);
        if (pollRoot?['code'] != 0) throw StateError('MinerU 查询任务失败：${pollRoot?['msg'] ?? '未知错误'}');
        final data = _map(pollRoot?['data']);
        final raw = data?['extract_result'];
        item = raw is List ? _map(raw.isEmpty ? null : raw.first) : _map(raw);
        final state = item?['state']?.toString();
        if (state == 'done') break;
        if (state == 'failed') throw StateError('MinerU 解析失败：${item?['err_msg'] ?? '未知错误'}');
      }
      if (item?['state'] != 'done') throw StateError('MinerU 解析超时，请稍后重试');
      final zipUrl = item?['full_zip_url']?.toString();
      if (zipUrl == null || zipUrl.isEmpty) throw StateError('MinerU 未返回版面结果');
      final zip = await dio.get<List<int>>(zipUrl, options: Options(responseType: ResponseType.bytes));
      final regions = _regionsFromZip(zip.data ?? const <int>[], Size(decoded.width.toDouble(), decoded.height.toDouble()));
      if (regions.isEmpty) throw StateError('MinerU 未生成可用题目候选框；请手动框选');
      return LayoutDetectionResult(regions: regions, providerLabel: 'MinerU VLM', warning: 'MinerU 根据题号和版面块聚合候选框，请逐题检查。');
    } on DioException catch (e) {
      throw StateError('MinerU 服务请求失败：${e.response?.data ?? e.message ?? '网络错误'}');
    } finally { dio.close(); }
  }

  List<QuestionRegion> _regionsFromZip(List<int> bytes, Size imageSize) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final blocks = <_Block>[];
    for (final entry in archive.files) {
      final n = entry.name.toLowerCase();
      if (!entry.isFile || !n.endsWith('.json') || (!n.contains('middle') && !n.contains('layout') && !n.contains('content_list'))) continue;
      try { _collect(jsonDecode(utf8.decode(entry.content as List<int>)), blocks); } catch (_) { /* try other JSON result files */ }
    }
    final unique = <String, _Block>{};
    for (final block in blocks) { if (block.rect.width > 8 && block.rect.height > 8) unique['${block.rect.left.round()},${block.rect.top.round()},${block.rect.right.round()},${block.rect.bottom.round()}'] = block; }
    final sorted = unique.values.toList()..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    final starts = <int>[];
    for (var i = 0; i < sorted.length; i++) { if (_questionStart.hasMatch(sorted[i].text)) starts.add(i); }
    if (starts.isEmpty) return const <QuestionRegion>[];
    final regions = <QuestionRegion>[];
    for (var group = 0; group < starts.length; group++) {
      final from = starts[group]; final to = group + 1 < starts.length ? starts[group + 1] : sorted.length;
      final groupBlocks = sorted.sublist(from, to);
      final rect = groupBlocks.map((b) => b.rect).reduce((a, b) => a.expandToInclude(b));
      final normalized = Rect.fromLTRB(rect.left / imageSize.width, rect.top / imageSize.height, rect.right / imageSize.width, rect.bottom / imageSize.height);
      final clip = Rect.fromLTRB(normalized.left.clamp(0, 1).toDouble(), normalized.top.clamp(0, 1).toDouble(), normalized.right.clamp(0, 1).toDouble(), normalized.bottom.clamp(0, 1).toDouble());
      if (clip.width < .10 || clip.height < .05) continue;
      regions.add(QuestionRegion(id: 'mineru-$group', normalizedRect: clip, detectedNumber: _questionStart.firstMatch(sorted[from].text)?.group(1), confidence: .75, source: QuestionRegionSource.layoutModel));
    }
    return regions;
  }

  void _collect(dynamic value, List<_Block> out) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final rect = _rect(map['bbox'] ?? map['box'] ?? map['poly'] ?? map['position']);
      final text = (map['text'] ?? map['content'] ?? map['text_content'] ?? '').toString();
      if (rect != null && text.isNotEmpty) out.add(_Block(rect, text));
      for (final child in map.values) { _collect(child, out); }
    } else if (value is List) { for (final child in value) { _collect(child, out); } }
  }
  Map<String, dynamic>? _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;
  double? _n(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value');
  Rect? _rect(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    if (value.first is List) { final points = value.whereType<List>().where((p) => p.length >= 2).map((p) => Offset(_n(p[0]) ?? 0, _n(p[1]) ?? 0)).toList(); if (points.isEmpty) return null; return Rect.fromLTRB(points.map((p) => p.dx).reduce((a,b)=>a<b?a:b), points.map((p) => p.dy).reduce((a,b)=>a<b?a:b), points.map((p) => p.dx).reduce((a,b)=>a>b?a:b), points.map((p) => p.dy).reduce((a,b)=>a>b?a:b)); }
    final n = value.map(_n).toList();
    return n.length >= 4 && n.take(4).every((v) => v != null) ? Rect.fromLTRB(n[0]!, n[1]!, n[2]!, n[3]!) : null;
  }
}
class _Block { const _Block(this.rect, this.text); final Rect rect; final String text; }
