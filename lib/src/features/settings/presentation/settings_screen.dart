import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final reminderEnabled = ref.watch(reviewReminderEnabledProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSectionTitle(AppStrings.settingsAppearance),
            const SizedBox(height: AppSpace.md),
            Row(
              children: <Widget>[
                _ThemeButton(
                  label: AppStrings.settingsThemeSystem,
                  icon: CupertinoIcons.device_phone_portrait,
                  isSelected: themeMode == ThemeMode.system,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.system),
                ),
                const SizedBox(width: AppSpace.sm),
                _ThemeButton(
                  label: AppStrings.settingsThemeLight,
                  icon: CupertinoIcons.sun_max,
                  isSelected: themeMode == ThemeMode.light,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.light),
                ),
                const SizedBox(width: AppSpace.sm),
                _ThemeButton(
                  label: AppStrings.settingsThemeDark,
                  icon: CupertinoIcons.moon,
                  isSelected: themeMode == ThemeMode.dark,
                  onTap: () => ref
                      .read(themeModeProvider.notifier)
                      .setMode(ThemeMode.dark),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            AppSectionTitle(AppStrings.settingsReminders),
            const SizedBox(height: AppSpace.md),
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
            const SizedBox(height: AppSpace.xl),
            AppSectionTitle(AppStrings.settingsAiService),
            const SizedBox(height: AppSpace.md),
            AppCard(
              child: Column(
                children: <Widget>[
                  AppListTile(
                    icon: CupertinoIcons.sparkles,
                    iconColor: AppColors.primary,
                    iconBackgroundColor: AppColors.primaryContainerLight,
                    title: AppStrings.settingsAiProvider,
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
            const SizedBox(height: AppSpace.xl),
            AppSectionTitle(AppStrings.settingsContent),
            const SizedBox(height: AppSpace.md),
            AppCard(
              child: AppListTile(
                icon: CupertinoIcons.folder,
                iconColor: AppColors.success,
                iconBackgroundColor: AppColors.successContainerLight,
                title: AppStrings.settingsSubjects,
                onTap: () => context.go('/settings/subjects'),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            AppSectionTitle(AppStrings.settingsLearningAnalytics),
            const SizedBox(height: AppSpace.md),
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
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colorScheme.outlineVariant,
                  ),
                  AppListTile(
                    icon: CupertinoIcons.square_arrow_up,
                    iconColor: AppColors.info,
                    iconBackgroundColor: AppColors.infoContainerLight,
                    title: AppStrings.settingsExportWorkbench,
                    subtitle: AppStrings.settingsExportWorkbenchSubtitle,
                    onTap: () => context.go('/settings/export-workbench'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            AppSectionTitle(AppStrings.settingsDataSecurity),
            const SizedBox(height: AppSpace.md),
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
    if (value) {
      final svc = ref.read(notificationServiceProvider);
      final sent = await svc.checkAndNotify();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(sent
                ? AppStrings.settingsReviewReminderSent
                : AppStrings.settingsReviewReminderNoDue),
          ),
        );
      }
    } else {
      await ref.read(notificationServiceProvider).cancelAll();
    }
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.small),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
