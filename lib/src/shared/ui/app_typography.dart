import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 全局字体层级（Typography Scale）。
///
/// 大厂级产品的“质感”有相当部分来自稳定的字阶与字重节奏：
/// 同一屏内字号档位收敛、字重对比明确（标题重、正文常规、辅助轻）。
///
/// 中文采用思源黑体（Noto Sans SC），西文/数字采用 Inter，二者字形
/// 风格接近，混排时不突兀。所有 TextStyle 经 [AppTextStyle.apply]
/// 统一注入字体家族，避免散落的 `fontSize:` 裸写法。
abstract final class AppTextStyle {
  // ---------- Display：页面级大标题 / Hero 数字 ----------
  static const TextStyle display = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.5,
  );

  // ---------- Headline：区块大标题 ----------
  static const TextStyle headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  // ---------- Title：卡片标题 / 小节标题 ----------
  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
  );

  // ---------- Subtitle：次级标题 ----------
  static const TextStyle subtitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.1,
  );

  // ---------- Body：正文 ----------
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  // ---------- BodyStrong：强调正文 ----------
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  // ---------- Label：标签 / 按钮文字 ----------
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.1,
  );

  // ---------- Caption：辅助说明 ----------
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.1,
  );

  // ---------- Overline：极小标注 ----------
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: 0.6,
  );

  /// 将家族字体注入到任意基础样式上，保持全站字体一致。
  static TextStyle apply(TextStyle base) => googleFontsNotoSansScTextStyle(
        fontSize: base.fontSize,
        fontWeight: base.fontWeight,
        height: base.height,
        letterSpacing: base.letterSpacing,
        color: base.color,
        decoration: base.decoration,
        fontStyle: base.fontStyle,
      );

  /// 便捷构造：在 [apply] 基础上覆盖颜色。
  static TextStyle colored(TextStyle base, Color color) =>
      apply(base).copyWith(color: color);
}
