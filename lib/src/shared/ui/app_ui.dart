import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
}

@Deprecated('Use AppColors instead')
abstract final class AppStatusColor {
  static const Color success = AppColors.success;
  static const Color info = AppColors.info;
  static const Color warning = AppColors.warning;
  static const Color danger = AppColors.danger;
}

/// 统一卡片容器。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.margin,
    this.borderRadius = AppRadius.medium,
    this.backgroundColor,
    this.borderColor,
    this.shadow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? colorScheme.outlineVariant,
        ),
        boxShadow: shadow ??
            (isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]),
      ),
      child: child,
    );
  }
}

/// 统一标签 Chip。
class AppTag extends StatelessWidget {
  const AppTag({
    super.key,
    required this.label,
    this.textColor = AppColors.primary,
    this.backgroundColor = AppColors.primaryContainerLight,
    this.onTap,
    this.fontSize = 12,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? textColor.withValues(alpha: 0.14) : backgroundColor;
    final borderColor = isDark
        ? textColor.withValues(alpha: 0.24)
        : colorScheme.outlineVariant.withValues(alpha: 0.5);

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          color: isDark ? colorScheme.onSurface : textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }
}

/// 带图标标题的信息卡片，用于解析、答案、错因、建议等区块。
class AppInfoSection extends StatelessWidget {
  const AppInfoSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor = AppColors.primary,
    this.backgroundColor = AppColors.primaryContainerLight,
    this.borderColor = const Color(0xFFC7D2FE),
    this.titleColor = AppColors.primaryDark,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      borderRadius: AppRadius.large,
      backgroundColor: isDark ? colorScheme.surface : backgroundColor,
      borderColor: isDark ? iconColor.withValues(alpha: 0.28) : borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isDark ? iconColor.withValues(alpha: 0.16) : Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? colorScheme.onSurface : titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          child,
        ],
      ),
    );
  }
}

/// 区块标题。
class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle(this.label, {super.key, this.padding});

  final String label;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

/// 设置页风格列表项。
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor = AppColors.primary,
    this.iconBackgroundColor = AppColors.primaryContainerLight,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? iconColor.withValues(alpha: 0.16) : iconBackgroundColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, color: colorScheme.onSurface)),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: AppSpace.xs),
                    Text(subtitle!,
                        style: TextStyle(
                            fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(
                CupertinoIcons.chevron_right,
                size: 22,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({super.key, required this.icon, required this.title, this.description, this.action});
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(AppSpace.xl),
    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(icon, size: 44, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(height: AppSpace.md),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      if (description != null) ...<Widget>[const SizedBox(height: AppSpace.xs), Text(description!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))],
      if (action != null) ...<Widget>[const SizedBox(height: AppSpace.lg), action!],
    ]),
  ));
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, this.message = '暂时无法加载，请稍后重试。', required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => AppEmptyState(icon: CupertinoIcons.exclamationmark_triangle, title: '加载失败', description: message, action: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(CupertinoIcons.arrow_clockwise), label: const Text('重试')));
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.label = '正在加载…'});
  final String label;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[const CircularProgressIndicator(), const SizedBox(height: AppSpace.md), Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))]));
}
