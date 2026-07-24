import 'dart:async';
import 'dart:io';

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

    final bg = backgroundColor ??
        (isDark ? colorScheme.surfaceContainerLow : colorScheme.surface);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? colorScheme.outlineVariant,
        ),
        boxShadow: shadow ?? (isDark ? null : AppShadows.sm),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
class AppInfoSection extends StatefulWidget {
  const AppInfoSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor = AppColors.primary,
    this.backgroundColor = AppColors.primaryContainerLight,
    this.borderColor,
    this.titleColor = AppColors.primaryDark,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;

  /// 是否可折叠。为 `false`（默认）时内容始终展开，行为与改造前一致。
  final bool collapsible;

  /// 可折叠时的初始展开状态。仅 [collapsible] 为 `true` 时生效。
  final bool initiallyExpanded;

  @override
  State<AppInfoSection> createState() => _AppInfoSectionState();
}

class _AppInfoSectionState extends State<AppInfoSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final header = Row(
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isDark ? widget.iconColor.withValues(alpha: 0.16) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.small),
          ),
          child: Icon(widget.icon, size: 15, color: widget.iconColor),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            widget.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? colorScheme.onSurface : widget.titleColor,
            ),
          ),
        ),
        if (widget.collapsible)
          Icon(
            _expanded
                ? CupertinoIcons.chevron_down
                : CupertinoIcons.chevron_right,
            size: 16,
            color: isDark ? colorScheme.onSurfaceVariant : widget.titleColor,
          ),
      ],
    );

    // 深色模式下忽略调用方传入的浅色边框，改用图标主色低透明描边，
    // 避免浅蓝/浅橙/浅绿边框在深色背景上突兀；浅色保持原色以区分区块色调。
    final resolvedBorder = isDark
        ? widget.iconColor.withValues(alpha: 0.28)
        : (widget.borderColor ?? const Color(0xFFC7D2FE));
    return AppCard(
      borderRadius: AppRadius.large,
      backgroundColor: isDark ? colorScheme.surface : widget.backgroundColor,
      borderColor: resolvedBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.collapsible)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: header,
            )
          else
            header,
          if (!widget.collapsible || _expanded) ...<Widget>[
            const SizedBox(height: AppSpace.md),
            widget.child,
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
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
  const AppErrorState({
    super.key,
    this.error,
    this.message,
    this.onRetry,
  }) : assert(
          error == null || message == null,
          'Either provide an error object for auto-friendly mapping, '
          'or an explicit message, but not both.',
        );

  /// 原始错误对象，会根据常见异常类型映射为友好文案；为 null 时使用默认文案。
  final Object? error;

  /// 显式文案，会覆盖 [error] 的自动映射；同时提供 [error] 与 [message] 会触发断言。
  final String? message;

  /// 重试回调。为 null 时不展示重试按钮。
  final VoidCallback? onRetry;

  String _resolveMessage() {
    if (message != null) return message!;
    final source = error;
    if (source == null) return '加载失败，请重试';
    if (source is FormatException) return '数据格式异常';
    if (source is FileSystemException) return '文件读取失败';
    if (source is TimeoutException) return '请求超时';
    if (source is SocketException) return '网络连接失败';
    return '加载失败，请重试';
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveMessage();
    return AppEmptyState(
      icon: CupertinoIcons.exclamationmark_triangle,
      title: '加载失败',
      description: resolved,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(CupertinoIcons.arrow_clockwise),
              label: const Text('重试'),
            ),
    );
  }
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.label = '正在加载…'}) : child = null;

  /// 直接渲染调用方提供的骨架布局，常用于需要更贴近真实内容的占位场景。
  const AppLoadingState.skeleton({super.key, required this.child})
      : label = '正在加载…';

  final String label;

  /// 调用方提供的骨架布局。非 null 时 [build] 直接返回该 widget，
  /// 不再渲染默认的转圈加载指示器。
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final skeleton = child;
    if (skeleton != null) return skeleton;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpace.md),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用 shimmer 占位组件：用 [AnimationController] 在 1.2s 内做
/// #E5E7EB → #F3F4F6 → #E5E7EB 的扫光循环。child 通常是几个圆角灰条
/// [Container]；通过 [ShaderMask] + [BlendMode.srcIn] 把动画渐变叠加在
/// child 的可见像素上，从而实现"灰色扫光"效果。
class AppShimmer extends StatefulWidget {
  const AppShimmer({super.key, required this.child});

  final Widget child;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  static const Color _base = Color(0xFFE5E7EB);
  static const Color _highlight = Color(0xFFF3F4F6);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        // value 在 [0, 1] 间来回，将高光带从左侧扫到右侧再回来。
        final shift = _controller.value * 2 - 1;
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment(shift - 0.6, 0),
              end: Alignment(shift + 0.6, 0),
              colors: const <Color>[_base, _highlight, _base],
              stops: const <double>[0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 默认渲染 6 个列表项骨架：左侧 48x48 圆角方块 + 右侧两行灰条
/// （上行宽 70% 下行宽 40%），整体用 [AppShimmer] 包裹。可通过
/// [itemCount] 调整数量。
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpace.lg),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (BuildContext context, int index) => const Padding(
          padding: EdgeInsets.only(bottom: AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SkeletonBox(
                width: 48,
                height: 48,
                borderRadius: 12,
              ),
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SkeletonBar(widthFactor: 0.7),
                    SizedBox(height: AppSpace.xs),
                    _SkeletonBar(widthFactor: 0.4),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = AppRadius.small,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
