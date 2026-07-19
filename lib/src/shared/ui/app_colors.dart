import 'package:flutter/material.dart';

/// 语义化颜色常量，避免在多个文件中硬编码十六进制色值。
/// 使用时应结合当前主题判断是否需要降饱和或替换为背景色。
abstract final class AppColors {
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryDark = Color(0xFF4338CA);
  static const Color primaryContainerLight = Color(0xFFEEF2FF);

  static const Color success = Color(0xFF16A34A);
  static const Color successContainerLight = Color(0xFFF0FDF4);
  static const Color successDark = Color(0xFF166534);

  static const Color warning = Color(0xFFEA580C);
  static const Color warningContainerLight = Color(0xFFFFF7ED);
  static const Color warningDark = Color(0xFF9A3412);

  static const Color danger = Color(0xFFDC2626);
  static const Color dangerContainerLight = Color(0xFFFEF2F2);

  static const Color info = Color(0xFF2563EB);
  static const Color infoContainerLight = Color(0xFFE0F2FE);

  static const Color accentTeal = Color(0xFF0F766E);
  static const Color accentTealContainerLight = Color(0xFFF0FDFA);

  static const Color accentAmber = Color(0xFFD97706);
  static const Color accentAmberContainerLight = Color(0xFFFFFBEB);

  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color accentPurpleContainerLight = Color(0xFFF5F3FF);

  static const Color slate = Color(0xFF64748B);
  static const Color slateContainerLight = Color(0xFFF8FAFC);

  /// 返回对应语义色在深色模式下的容器背景（默认使用带透明度的同色）。
  static Color semanticContainer(Color semantic, {bool isDark = false, double darkAlpha = 0.14}) {
    return isDark ? semantic.withValues(alpha: darkAlpha) : semantic.withValues(alpha: 0.08);
  }
}
