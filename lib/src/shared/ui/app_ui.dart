import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppRadius {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
}

abstract final class AppStatusColor {
  static const Color success = Color(0xFF16A34A);
  static const Color info = Color(0xFF2563EB);
  static const Color warning = Color(0xFFEA580C);
  static const Color danger = Color(0xFFDC2626);
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
