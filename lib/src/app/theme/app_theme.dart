import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_typography.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 构建浅色主题。
///
/// 基于 FlexScheme.indigo 并叠加统一组件默认样式与字体层级，
/// 确保 Material 3 组件（按钮、卡片、输入框、Chip、导航栏）与自定义组件视觉一致。
ThemeData buildLightTheme() {
  final base = FlexThemeData.light(
    scheme: FlexScheme.indigo,
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    scaffoldBackground: AppColors.surfaceLight,
    appBarBackground: AppColors.surfaceLight,
    appBarElevation: AppElevation.flat,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 10,
      blendOnColors: false,
      useM2StyleDividerInM3: true,
      inputDecoratorBorderType: FlexInputBorderType.outline,
      inputDecoratorRadius: AppRadius.medium,
      chipRadius: AppRadius.xlarge,
      navigationBarIndicatorRadius: AppRadius.medium,
      navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
      navigationBarIndicatorSchemeColor: SchemeColor.primary,
      cardRadius: AppRadius.large,
      elevatedButtonRadius: AppRadius.pill,
      filledButtonRadius: AppRadius.pill,
      outlinedButtonRadius: AppRadius.pill,
      textButtonRadius: AppRadius.pill,
      popupMenuRadius: AppRadius.medium,
      dialogRadius: AppRadius.large,
      bottomSheetRadius: AppRadius.xlarge,
    ),
  );

  final textTheme = _buildTextTheme(base.textTheme, base.colorScheme);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surfaceLight,
    cardTheme: base.cardTheme.copyWith(
      elevation: AppElevation.flat,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
    ),
    elevatedButtonTheme: _elevatedButtonTheme(base.colorScheme),
    filledButtonTheme: _filledButtonTheme(base.colorScheme),
    outlinedButtonTheme: _outlinedButtonTheme(base.colorScheme),
    textButtonTheme: _textButtonTheme(base.colorScheme),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: base.colorScheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: base.colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: base.colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: base.colorScheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: base.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xlarge)),
    ),
    iconTheme: IconThemeData(
      color: base.colorScheme.onSurfaceVariant,
      size: AppControlSize.icon,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: base.colorScheme.surface,
      elevation: AppElevation.flat,
      indicatorColor: base.colorScheme.primaryContainer,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: base.colorScheme.primary, size: AppControlSize.icon);
        }
        return IconThemeData(color: base.colorScheme.onSurfaceVariant, size: AppControlSize.icon);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? base.colorScheme.primary : base.colorScheme.onSurfaceVariant,
        );
      }),
    ),
    textTheme: textTheme,
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: base.colorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: base.colorScheme.onSurfaceVariant),
    ),
  );
}

/// 构建深色主题。
ThemeData buildDarkTheme() {
  final base = FlexThemeData.dark(
    scheme: FlexScheme.indigo,
    useMaterial3: true,
    surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
    scaffoldBackground: AppColors.surfaceDark,
    appBarBackground: AppColors.slateContainerDark,
    appBarElevation: AppElevation.flat,
    subThemesData: const FlexSubThemesData(
      blendOnLevel: 20,
      useM2StyleDividerInM3: true,
      inputDecoratorBorderType: FlexInputBorderType.outline,
      inputDecoratorRadius: AppRadius.medium,
      chipRadius: AppRadius.xlarge,
      navigationBarIndicatorRadius: AppRadius.medium,
      navigationBarSelectedLabelSchemeColor: SchemeColor.primary,
      navigationBarIndicatorSchemeColor: SchemeColor.primary,
      cardRadius: AppRadius.large,
      elevatedButtonRadius: AppRadius.pill,
      filledButtonRadius: AppRadius.pill,
      outlinedButtonRadius: AppRadius.pill,
      textButtonRadius: AppRadius.pill,
      popupMenuRadius: AppRadius.medium,
      dialogRadius: AppRadius.large,
      bottomSheetRadius: AppRadius.xlarge,
    ),
  );

  final textTheme = _buildTextTheme(base.textTheme, base.colorScheme);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surfaceDark,
    cardTheme: base.cardTheme.copyWith(
      elevation: AppElevation.flat,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
    ),
    elevatedButtonTheme: _elevatedButtonTheme(base.colorScheme),
    filledButtonTheme: _filledButtonTheme(base.colorScheme),
    outlinedButtonTheme: _outlinedButtonTheme(base.colorScheme),
    textButtonTheme: _textButtonTheme(base.colorScheme),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: base.colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: base.colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: base.colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: base.colorScheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: base.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xlarge)),
    ),
    iconTheme: IconThemeData(
      color: base.colorScheme.onSurfaceVariant,
      size: AppControlSize.icon,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: base.colorScheme.surface,
      elevation: AppElevation.flat,
      indicatorColor: base.colorScheme.primaryContainer.withValues(alpha: 0.5),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: base.colorScheme.primary, size: AppControlSize.icon);
        }
        return IconThemeData(color: base.colorScheme.onSurfaceVariant, size: AppControlSize.icon);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? base.colorScheme.primary : base.colorScheme.onSurfaceVariant,
        );
      }),
    ),
    textTheme: textTheme,
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: base.colorScheme.onSurface,
      ),
      iconTheme: IconThemeData(color: base.colorScheme.onSurfaceVariant),
    ),
  );
}

TextTheme _buildTextTheme(TextTheme base, ColorScheme scheme) {
  final themed = base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
    bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w400, fontSize: 16),
    bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w400, fontSize: 14),
    bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w400, fontSize: 12),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
    labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
    labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11),
  );
  // 统一注入品牌字体家族（思源黑体 Noto Sans SC），保证全站字形一致。
  return GoogleFonts.notoSansScTextTheme(themed);
}

ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.standard),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      elevation: AppElevation.flat,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

FilledButtonThemeData _filledButtonTheme(ColorScheme scheme) {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.standard),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme scheme) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.standard),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xl,
        vertical: AppSpace.md,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: BorderSide(color: scheme.outlineVariant),
      foregroundColor: scheme.primary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}

TextButtonThemeData _textButtonTheme(ColorScheme scheme) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, AppControlSize.compact),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      foregroundColor: scheme.primary,
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  );
}
