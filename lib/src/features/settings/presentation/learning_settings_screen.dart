import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 学习设置页面（Phase 9-3）。
///
/// 承载每日复习目标入口（跳 `/goals`）、复习提醒时间显示、难度偏好、
/// 知识树显示层级四项设置。难度偏好与层级用 SharedPreferences 持久化。
class LearningSettingsScreen extends ConsumerStatefulWidget {
  const LearningSettingsScreen({super.key});

  @override
  ConsumerState<LearningSettingsScreen> createState() =>
      _LearningSettingsScreenState();
}

class _LearningSettingsScreenState
    extends ConsumerState<LearningSettingsScreen> {
  static const _difficultyKey = 'pref_difficulty';
  static const _treeDepthKey = 'pref_knowledge_tree_depth';

  QuestionDifficulty? _difficulty;
  int _treeDepth = 3; // 默认知识点层
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final diffStr = prefs.getString(_difficultyKey);
    final depth = prefs.getInt(_treeDepthKey) ?? 3;
    QuestionDifficulty? diff;
    if (diffStr != null) {
      for (final d in QuestionDifficulty.values) {
        if (d.name == diffStr) {
          diff = d;
          break;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _difficulty = diff;
      _treeDepth = depth;
      _loading = false;
    });
  }

  Future<void> _setDifficulty(QuestionDifficulty? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_difficultyKey);
    } else {
      await prefs.setString(_difficultyKey, value.name);
    }
    setState(() => _difficulty = value);
  }

  Future<void> _setTreeDepth(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_treeDepthKey, value);
    setState(() => _treeDepth = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsLearning)),
      body: _loading
          ? const AppLoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppSectionTitle(AppStrings.settingsDailyGoal),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: AppListTile(
                      icon: CupertinoIcons.flag_fill,
                      iconColor: AppColors.primary,
                      iconBackgroundColor: AppColors.primaryContainerLight,
                      title: AppStrings.settingsDailyGoal,
                      subtitle: AppStrings.settingsDailyGoalSubtitle,
                      onTap: () => context.push('/goals'),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  AppSectionTitle(AppStrings.settingsDifficultyPreference),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg, vertical: AppSpace.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppStrings.settingsDifficultyPreferenceSubtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Wrap(
                            spacing: AppSpace.sm,
                            children: <Widget>[
                              _buildDifficultyChip(null, '不指定'),
                              _buildDifficultyChip(
                                  QuestionDifficulty.foundation, '基础'),
                              _buildDifficultyChip(
                                  QuestionDifficulty.advanced, '进阶'),
                              _buildDifficultyChip(
                                  QuestionDifficulty.challenge, '挑战'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  AppSectionTitle(AppStrings.settingsKnowledgeTreeDepth),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppStrings.settingsKnowledgeTreeDepthSubtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          for (var i = 1; i <= 4; i++)
                            RadioListTile<int>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: i,
                              groupValue: _treeDepth,
                              title: Text(_depthLabel(i)),
                              onChanged: (v) {
                                if (v != null) _setTreeDepth(v);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDifficultyChip(QuestionDifficulty? value, String label) {
    final selected = _difficulty == value;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setDifficulty(selected ? null : value),
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        fontSize: 13,
      ),
    );
  }

  String _depthLabel(int depth) {
    switch (depth) {
      case 1:
        return '科目层';
      case 2:
        return '模块层';
      case 3:
        return '章节 / 知识点';
      case 4:
        return '考点（最深）';
      default:
        return '层级 $depth';
    }
  }
}
