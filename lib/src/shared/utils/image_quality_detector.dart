import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;

/// 图片质量检测结果。
class ImageQualityResult {
  const ImageQualityResult({
    required this.isAcceptable,
    required this.sharpnessScore,
    required this.brightnessScore,
    required this.minDimensionPixels,
    required this.primaryIssue,
  });

  /// 总体是否可接受（无任何质量问题）。
  final bool isAcceptable;

  /// 锐度分数（0-1），由拉普拉斯方差归一化得到；越接近 1 越清晰。
  final double sharpnessScore;

  /// 亮度分数（0-1），由平均亮度归一化得到；0.3-0.7 为正常范围。
  final double brightnessScore;

  /// 图片最短边的像素数。
  final int minDimensionPixels;

  /// 主要质量问题（若有）。多个问题同时存在时取最严重的一个。
  final ImageQualityIssue? primaryIssue;
}

/// 图片质量问题的种类。
enum ImageQualityIssue { blurry, tooDark, tooBright, lowResolution }

/// 图片质量检测的阈值常量。
///
/// 这些阈值基于拍题场景的经验值，可按需调整。
class ImageQualityThresholds {
  const ImageQualityThresholds._();

  /// 拉普拉斯方差低于此值判定为模糊。
  static const double blurryVariance = 100.0;

  /// 用于将拉普拉斯方差映射到 0-1 分数的归一化上限。
  static const double sharpnessNormalization = 1000.0;

  /// 亮度低于此值判定为过暗。
  static const double tooDarkBrightness = 0.2;

  /// 亮度高于此值判定为过亮。
  static const double tooBrightBrightness = 0.85;

  /// 最短边低于此像素值判定为低分辨率。
  static const int lowResolutionPixels = 800;

  /// 检测时分析图像的最长边像素上限，避免大图在 isolate 中耗时过久。
  static const int maxAnalysisDimension = 768;
}

/// 检测图片质量。
///
/// 在后台 isolate 中执行：解码图片，计算拉普拉斯方差（模糊）、平均亮度
/// （明暗）、最短边像素数（分辨率），返回 [ImageQualityResult]。
///
/// 如果文件不存在或解码失败，抛出 [StateError]。
Future<ImageQualityResult> detectImageQuality(String imagePath) {
  return compute(_detectImageQualityIsolate, imagePath);
}

ImageQualityResult _detectImageQualityIsolate(String imagePath) {
  final file = File(imagePath);
  if (!file.existsSync()) {
    throw StateError('图片文件不存在: $imagePath');
  }
  final decoded = image.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    throw StateError('无法解码图片: $imagePath');
  }

  final originalWidth = decoded.width;
  final originalHeight = decoded.height;
  final minDim = math.min(originalWidth, originalHeight);

  // 缩放到最长边 <= maxAnalysisDimension 用于分析（保留宽高比），避免
  // 4K 原图在 isolate 里跑拉普拉斯卷积耗时过久。
  image.Image working = decoded;
  final longestSide = math.max(originalWidth, originalHeight).toDouble();
  if (longestSide > ImageQualityThresholds.maxAnalysisDimension) {
    final scale = ImageQualityThresholds.maxAnalysisDimension / longestSide;
    final newWidth =
        (originalWidth * scale).round().clamp(1, originalWidth).toInt();
    final newHeight =
        (originalHeight * scale).round().clamp(1, originalHeight).toInt();
    working = image.copyResize(decoded, width: newWidth, height: newHeight);
  }

  final w = working.width;
  final h = working.height;

  // 计算灰度图（BT.601 luma）。
  final gray = List<double>.filled(w * h, 0.0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = working.getPixel(x, y);
      gray[y * w + x] = 0.299 * p.r.toDouble() +
          0.587 * p.g.toDouble() +
          0.114 * p.b.toDouble();
    }
  }

  // 平均亮度归一化到 0-1。
  var sum = 0.0;
  for (final v in gray) {
    sum += v;
  }
  final meanBrightness = gray.isNotEmpty ? sum / gray.length : 0.0;
  final brightnessScore = (meanBrightness / 255.0).clamp(0.0, 1.0);

  // 拉普拉斯卷积：kernel = [0,1,0; 1,-4,1; 0,1,0]，仅在 [1, w-2] x [1, h-2]
  // 范围内计算（忽略边缘 1 像素）。同时累计一阶矩与二阶矩用于方差。
  var lapSum = 0.0;
  var lapSumSq = 0.0;
  var lapCount = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final center = gray[y * w + x];
      final up = gray[(y - 1) * w + x];
      final down = gray[(y + 1) * w + x];
      final left = gray[y * w + (x - 1)];
      final right = gray[y * w + (x + 1)];
      final lap = -4.0 * center + up + down + left + right;
      lapSum += lap;
      lapSumSq += lap * lap;
      lapCount++;
    }
  }
  final lapMean = lapCount > 0 ? lapSum / lapCount : 0.0;
  final lapVariance = lapCount > 0
      ? (lapSumSq / lapCount) - (lapMean * lapMean)
      : 0.0;

  final sharpnessScore = (lapVariance / ImageQualityThresholds.sharpnessNormalization)
      .clamp(0.0, 1.0);

  final primaryIssue = _pickPrimaryIssue(
    lapVariance: lapVariance,
    brightness: brightnessScore,
    minDim: minDim,
  );

  return ImageQualityResult(
    isAcceptable: primaryIssue == null,
    sharpnessScore: sharpnessScore,
    brightnessScore: brightnessScore,
    minDimensionPixels: minDim,
    primaryIssue: primaryIssue,
  );
}

ImageQualityIssue? _pickPrimaryIssue({
  required double lapVariance,
  required double brightness,
  required int minDim,
}) {
  // 各问题的严重度（0-1，越大越严重）。
  final Map<ImageQualityIssue, double> severities = <ImageQualityIssue, double>{};

  if (lapVariance < ImageQualityThresholds.blurryVariance) {
    severities[ImageQualityIssue.blurry] =
        ((ImageQualityThresholds.blurryVariance - lapVariance) /
                ImageQualityThresholds.blurryVariance)
            .clamp(0.0, 1.0);
  }

  if (brightness < ImageQualityThresholds.tooDarkBrightness) {
    severities[ImageQualityIssue.tooDark] =
        ((ImageQualityThresholds.tooDarkBrightness - brightness) /
                ImageQualityThresholds.tooDarkBrightness)
            .clamp(0.0, 1.0);
  }

  if (brightness > ImageQualityThresholds.tooBrightBrightness) {
    severities[ImageQualityIssue.tooBright] =
        ((brightness - ImageQualityThresholds.tooBrightBrightness) /
                (1.0 - ImageQualityThresholds.tooBrightBrightness))
            .clamp(0.0, 1.0);
  }

  if (minDim < ImageQualityThresholds.lowResolutionPixels) {
    severities[ImageQualityIssue.lowResolution] =
        ((ImageQualityThresholds.lowResolutionPixels - minDim) /
                ImageQualityThresholds.lowResolutionPixels)
            .clamp(0.0, 1.0);
  }

  if (severities.isEmpty) return null;

  ImageQualityIssue? worst;
  var worstSeverity = -1.0;
  for (final entry in severities.entries) {
    if (entry.value > worstSeverity) {
      worstSeverity = entry.value;
      worst = entry.key;
    }
  }
  return worst;
}
