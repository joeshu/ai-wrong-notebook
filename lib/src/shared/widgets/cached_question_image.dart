import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

/// 带内存缓存的本地图片 widget。
///
/// - 首次加载时在后台 isolate 把原图解码并缩放到 [maxWidth]（默认 1400px），
///   重新编码为 JPEG/PNG，避免列表/详情页加载 4K 原图导致内存峰值与卡顿。
/// - 缩放后的字节数据按文件路径+mtime 做 LRU 内存缓存，二次进入秒开。
/// - [highRes=true] 时跳过缩放，用于需要看原图细节的 InteractiveViewer 场景。
class CachedQuestionImage extends StatefulWidget {
  const CachedQuestionImage(
    this.path, {
    super.key,
    this.fit = BoxFit.contain,
    this.maxWidth = 1400,
    this.highRes = false,
    this.borderRadius,
  });

  final String path;
  final BoxFit fit;
  final int maxWidth;

  /// 是否加载原图（不缩放）。用于 InteractiveViewer 等需要细节的场景。
  final bool highRes;

  /// 可选圆角，包装在 ClipRRect 里。
  final BorderRadius? borderRadius;

  @override
  State<CachedQuestionImage> createState() => _CachedQuestionImageState();

  /// 简易 LRU 缓存：path → 缩略图字节。最多保留 40 张。
  // ignore: prefer_collection_literals
  static final Map<String, Uint8List> _cache =
      _BoundedMap<String, Uint8List>(maxSize: 40);
}

class _CachedQuestionImageState extends State<CachedQuestionImage> {
  Uint8List? _bytes;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedQuestionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.highRes != widget.highRes) {
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    final cacheKey = '${widget.highRes ? 'hr' : 'th'}:$path';
    final cached = CachedQuestionImage._cache[cacheKey];
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached;
          _loading = false;
          _error = null;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final result = await compute(
        _decodeAndScale,
        _ScaleRequest(path, widget.maxWidth, widget.highRes),
      );
      if (result != null) {
        CachedQuestionImage._cache[cacheKey] = result;
      }
      if (mounted) {
        setState(() {
          _bytes = result;
          _loading = false;
          _error = result == null ? 'decode_failed' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_bytes != null) {
      content = Image.memory(_bytes!, fit: widget.fit);
    } else {
      content = const Icon(Icons.broken_image_outlined);
    }
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: content);
    }
    return content;
  }
}

class _ScaleRequest {
  const _ScaleRequest(this.path, this.maxWidth, this.highRes);
  final String path;
  final int maxWidth;
  final bool highRes;
}

/// 在后台 isolate 执行：解码图片，缩放，重新编码返回字节。
Uint8List? _decodeAndScale(_ScaleRequest req) {
  final file = image.decodeImage(File(req.path).readAsBytesSync());
  if (file == null) return null;
  if (req.highRes || file.width <= req.maxWidth) {
    final ext = req.path.split('.').last.toLowerCase();
    if (ext == 'png') {
      return Uint8List.fromList(image.encodePng(file, level: 6));
    }
    return Uint8List.fromList(image.encodeJpg(file, quality: 85));
  }
  final scaled = image.copyResize(file, width: req.maxWidth);
  final ext = req.path.split('.').last.toLowerCase();
  if (ext == 'png') {
    return Uint8List.fromList(image.encodePng(scaled, level: 6));
  }
  return Uint8List.fromList(image.encodeJpg(scaled, quality: 85));
}

/// 简单的有界 Map：插入时若超过 maxSize，移除最早插入的 key。
class _BoundedMap<K, V> {
  _BoundedMap({required this.maxSize});
  final int maxSize;
  final Map<K, V> _map = {};

  V? operator [](K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v;
    return v;
  }

  operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}
