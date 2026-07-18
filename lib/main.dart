import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/router.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/katex_math_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KatexMathView.preload();

  final db = AppDatabase();
  final settingsRepo = DriftSettingsRepository(db);
  final questionRepo = DriftQuestionRepository(db);
  await _migrateLegacyQuestionBankIfNeeded(settingsRepo, questionRepo);

  final router = buildRouter(settingsRepo);

  // Defer onboarding check to avoid blocking startup
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final onboardingDone = await settingsRepo.getString('onboarding_done');
      if (onboardingDone == null) {
        router.go('/onboarding');
      }
    } catch (_) {}
  });

  runApp(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        questionRepositoryProvider.overrideWithValue(questionRepo),
        // 注意：不要 override aiAnalysisServiceProvider，让它使用 settingsRepo
        imageStorageServiceProvider.overrideWithValue(ImageStorageService()),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          title: 'AI错题本',
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ref.watch(themeModeProvider),
          routerConfig: router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    ),
  );
}


/// One-way import for installations created before the Drift question store.
/// The marker is written only after a successful read so a transient storage
/// failure cannot silently discard the user's opportunity to migrate.
Future<void> _migrateLegacyQuestionBankIfNeeded(
  DriftSettingsRepository settings,
  DriftQuestionRepository questions,
) async {
  const migrationKey = 'legacy_questions_to_drift_v1';
  if (await settings.getString(migrationKey) == 'done') return;

  try {
    final existing = await questions.listAll();
    if (existing.isEmpty) {
      final legacy = await SharedPrefsQuestionRepository().listAll();
      if (legacy.isNotEmpty) await questions.saveDrafts(legacy);
    }
    await settings.setString(migrationKey, 'done');
  } catch (_) {
    // Keep the marker unset. The next launch retries rather than risking loss.
  }
}
