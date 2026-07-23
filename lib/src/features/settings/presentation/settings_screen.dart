import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_components.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final reminderEnabled = ref.watch(reviewReminderEnabledProvider);
    final colorScheme = Theme.of(context).colorScheme;
    // Phase 9-5：watch AI / Layout 配置状态徽章
    final aiConfig = ref.watch(aiProviderConfigSnapshotProvider).valueOrNull;
    final layoutConfig = ref.watch(layoutProviderConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSectionTitle(AppStrings.settingsAppearance),
            const SizedBox(height: AppSpace.sm),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppThemeCard(
                    label: AppStrings.settingsThemeSystem,
                    icon: CupertinoIcons.device_phone_portrait,
                    isSelected: themeMode == ThemeMode.system,
                    onTap: () => ref
                        .read(themeModeProvider.notifier)
                        .setMode(ThemeMode.system),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: AppThemeCard(
                    label: AppStrings.settingsThemeLight,
                    icon: CupertinoIcons.sun_max,
                    isSelected: themeMode == ThemeMode.light,
                    onTap: () => ref
                        .read(themeModeProvider.notifier)
                        .setMode(ThemeMode.light),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: AppThemeCard(
                    label: AppStrings.settingsThemeDark,
                    icon: CupertinoIcons.moon,
                    isSelected: themeMode == ThemeMode.dark,
                    onTap: () => ref
                        .read(themeModeProvider.notifier)
                        .setMode(ThemeMode.dark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            AppSectionTitle(AppStrings.settingsReminders),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: AppListTile(
                icon: CupertinoIcons.bell,
                iconColor: AppColors.warning,
                iconBackgroundColor: AppColors.warningContainerLight,
                title: AppStrings.settingsReviewReminder,
                subtitle: AppStrings.settingsReviewReminderSubtitle,
                trailing: Switch(
                  value: reminderEnabled,
                  onChanged: (value) => _setReminderEnabled(context, ref, value),
                ),
                onTap: () => _setReminderEnabled(context, ref, !reminderEnabled),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            // Phase 9-3：学习设置区块
            AppSectionTitle(AppStrings.settingsLearning),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: AppListTile(
                icon: CupertinoIcons.flag_fill,
                iconColor: AppColors.primary,
                iconBackgroundColor: AppColors.primaryContainerLight,
                title: AppStrings.settingsLearning,
                subtitle: '每日目标 · 难度偏好 · 知识树层级',
                onTap: () => context.go('/settings/learning'),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppSectionTitle(AppStrings.settingsAiService),
            const SizedBox(height: AppSpace.sm),
            // Phase 9-5：状态聚合徽章
            _EngineStatusRow(
              aiConfig: aiConfig,
              layoutConfig: layoutConfig,
            ),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    icon: CupertinoIcons.sparkles,
                    iconColor: AppColors.primary,
                    iconBackgroundColor: AppColors.primaryContainerLight,
                    title: AppStrings.settingsAiProvider,
                    trailing: _StatusBadge(
                      ready: _isAiReady(aiConfig),
                      label: _isAiReady(aiConfig) ? '就绪' : '未配置',
                    ),
                    onTap: () => context.go('/settings/provider'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.doc_text,
                    iconColor: AppColors.accentTeal,
                    iconBackgroundColor: AppColors.accentTealContainerLight,
                    title: AppStrings.settingsLayoutProvider,
                    subtitle: AppStrings.settingsLayoutProviderSubtitle,
                    trailing: _StatusBadge(
                      ready: layoutConfig.isReady,
                      label: _layoutLabel(layoutConfig),
                    ),
                    onTap: () => context.go('/settings/layout'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.pencil,
                    iconColor: AppColors.accentAmber,
                    iconBackgroundColor: AppColors.accentAmberContainerLight,
                    title: AppStrings.settingsAiPrompts,
                    onTap: () => context.go('/settings/prompts'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppSectionTitle(AppStrings.settingsContent),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    icon: CupertinoIcons.tree,
                    iconColor: AppColors.accentTeal,
                    iconBackgroundColor: AppColors.accentTealContainerLight,
                    title: '知识树',
                    subtitle: '查看知识点掌握度、薄弱点与知识点管理',
                    onTap: () => context.go('/settings/knowledge-tree'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.folder,
                    iconColor: AppColors.success,
                    iconBackgroundColor: AppColors.successContainerLight,
                    title: AppStrings.settingsSubjects,
                    onTap: () => context.go('/settings/subjects'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppSectionTitle(AppStrings.settingsLearningAnalytics),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    icon: CupertinoIcons.chart_bar_alt_fill,
                    iconColor: AppColors.accentPurple,
                    iconBackgroundColor: AppColors.accentPurpleContainerLight,
                    title: AppStrings.settingsSubjectRadar,
                    subtitle: AppStrings.settingsSubjectRadarSubtitle,
                    onTap: () => context.go('/settings/subject-radar'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.flame_fill,
                    iconColor: AppColors.warning,
                    iconBackgroundColor: AppColors.warningContainerLight,
                    title: AppStrings.settingsMistakeTrend,
                    subtitle: AppStrings.settingsMistakeTrendSubtitle,
                    onTap: () => context.go('/settings/mistake-trend'),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.calendar,
                    iconColor: AppColors.accentTeal,
                    iconBackgroundColor: AppColors.accentTealContainerLight,
                    title: AppStrings.settingsWeeklyReport,
                    subtitle: AppStrings.settingsWeeklyReportSubtitle,
                    onTap: () => context.go('/settings/weekly-report'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            // Phase 11-1：导出工作台提升为独立区块（原位于"学习分析"区块末尾）
            AppSectionTitle(AppStrings.settingsExportShare),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: AppListTile(
                icon: CupertinoIcons.square_arrow_up,
                iconColor: AppColors.info,
                iconBackgroundColor: AppColors.infoContainerLight,
                title: AppStrings.settingsExportWorkbench,
                subtitle: AppStrings.settingsExportWorkbenchSubtitle,
                onTap: () => context.go('/settings/export-workbench'),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            AppSectionTitle(AppStrings.settingsDataSecurity),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: AppListTile(
                icon: CupertinoIcons.shield_lefthalf_fill,
                iconColor: AppColors.warning,
                iconBackgroundColor: AppColors.warningContainerLight,
                title: AppStrings.settingsDataManagement,
                subtitle: AppStrings.settingsDataManagementSubtitle,
                onTap: () => context.go('/settings/data'),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            // Phase 9-4：关于区块
            AppSectionTitle(AppStrings.settingsAbout),
            const SizedBox(height: AppSpace.sm),
            AppCard(
              child: AppListTile(
                icon: CupertinoIcons.info,
                iconColor: AppColors.slate,
                iconBackgroundColor: AppColors.slateContainerLight,
                title: AppStrings.settingsAbout,
                subtitle: '版本 · 检查更新 · 反馈',
                onTap: () => context.go('/settings/about'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _setReminderEnabled(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    await ref
        .read(reviewReminderEnabledProvider.notifier)
        .setEnabled(value);
    if (!context.mounted) return;
    final svc = ref.read(notificationServiceProvider);
    if (value) {
      // Phase 9-3：开启主开关时，按已保存的提醒时间调度每日推送。
      // 同时保留旧的即时检查行为：立刻查一次到期错题并推送通知。
      final time = ref.read(reviewReminderTimeProvider);
      final scheduled = await svc.scheduleDailyReminder(
        hour: time.hour,
        minute: time.minute,
      );
      final sent = await svc.checkAndNotify();
      if (context.mounted) {
        final hh = time.hour.toString().padLeft(2, '0');
        final mm = time.minute.toString().padLeft(2, '0');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sent
                ? AppStrings.settingsReviewReminderSent
                : (scheduled
                    ? '${AppStrings.settingsReviewReminderTimeScheduled}（$hh:$mm）'
                    : AppStrings.settingsReviewReminderNoDue)),
          ),
        );
      }
    } else {
      // 关闭主开关：取消定时与即时通知。
      await svc.cancelScheduledReminder();
      await svc.cancelAll();
    }
  }
}

/// AI 服务配置快照 Provider（Phase 9-5）。
///
/// 在设置页构建时拉取当前 `AiProviderConfig`，供状态徽章展示。
/// 用 FutureProvider 形式，缓存最近一次结果。
final FutureProvider<AiProviderConfig?> aiProviderConfigSnapshotProvider =
    FutureProvider<AiProviderConfig?>((ref) async {
  return ref.read(settingsRepositoryProvider).getAiProviderConfig();
});

bool _isAiReady(AiProviderConfig? config) {
  return config != null &&
      config.baseUrl.isNotEmpty &&
      config.apiKey.isNotEmpty &&
      config.model.isNotEmpty;
}

String _layoutLabel(LayoutProviderConfig config) {
  if (config.isReady) return '就绪';
  switch (config.type) {
    case LayoutProviderType.paddleCloud:
      return '未配置';
    case LayoutProviderType.mineruCloud:
      return '未配置';
    case LayoutProviderType.autoCloud:
      return '部分';
    case LayoutProviderType.customHttp:
      return '未配置';
    case LayoutProviderType.currentVision:
    case LayoutProviderType.manualOnly:
      return '就绪';
  }
}

/// AI 引擎 + 版面识别引擎状态徽章聚合行（Phase 9-5）。
class _EngineStatusRow extends StatelessWidget {
  const _EngineStatusRow({required this.aiConfig, required this.layoutConfig});

  final AiProviderConfig? aiConfig;
  final LayoutProviderConfig layoutConfig;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _StatusBadge(
          ready: _isAiReady(aiConfig),
          label: _isAiReady(aiConfig) ? '普通AI ✓' : '普通AI ✗',
        ),
        const SizedBox(width: AppSpace.sm),
        _StatusBadge(
          ready: layoutConfig.type == LayoutProviderType.paddleCloud &&
              layoutConfig.isReady,
          warning: layoutConfig.type == LayoutProviderType.paddleCloud &&
              !layoutConfig.isReady,
          label: layoutConfig.type == LayoutProviderType.paddleCloud
              ? (layoutConfig.isReady ? 'PaddleOCR ✓' : 'PaddleOCR ⚠')
              : 'PaddleOCR —',
        ),
        const SizedBox(width: AppSpace.sm),
        _StatusBadge(
          ready: layoutConfig.type == LayoutProviderType.mineruCloud &&
              layoutConfig.isReady,
          warning: layoutConfig.type == LayoutProviderType.mineruCloud &&
              !layoutConfig.isReady,
          label: layoutConfig.type == LayoutProviderType.mineruCloud
              ? (layoutConfig.isReady ? 'MinerU ✓' : 'MinerU ✗')
              : 'MinerU —',
        ),
      ],
    );
  }
}

/// 配置状态徽章。
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.ready,
    required this.label,
    this.warning = false,
  });

  final bool ready;
  final bool warning;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color bg;
    if (ready) {
      color = AppColors.success;
      bg = AppColors.successContainerLight;
    } else if (warning) {
      color = AppColors.warning;
      bg = AppColors.warningContainerLight;
    } else {
      color = AppColors.danger;
      bg = AppColors.dangerContainerLight;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
