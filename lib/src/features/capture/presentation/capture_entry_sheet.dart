import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:uuid/uuid.dart';

class CaptureEntrySheet extends ConsumerStatefulWidget {
  const CaptureEntrySheet({super.key});

  @override
  ConsumerState<CaptureEntrySheet> createState() => _CaptureEntrySheetState();
}

class _CaptureEntrySheetState extends ConsumerState<CaptureEntrySheet> {
  bool _isLoading = false;
  String? _errorMessage;
  _RecognitionChoice _choice = _RecognitionChoice.ai;
  // 极速模式开关：拍照/选图后跳过裁剪与校对，直接进入 AI 解析。
  // 默认 false；启动时从 SettingsRepository 异步加载。
  bool _isQuickCaptureEnabled = false;
  bool _quickCaptureSettingLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadQuickCaptureSetting();
  }

  Future<void> _loadQuickCaptureSetting() async {
    try {
      final enabled = await ref
          .read(settingsRepositoryProvider)
          .isQuickCaptureEnabled();
      if (!mounted) return;
      setState(() {
        _isQuickCaptureEnabled = enabled;
        _quickCaptureSettingLoaded = true;
      });
    } catch (_) {
      // 在未初始化 SharedPreferences 的测试环境下读取可能抛出
      // MissingPluginException，这里默认关闭极速模式即可。
      if (!mounted) return;
      setState(() => _quickCaptureSettingLoaded = true);
    }
  }

  Future<void> _setQuickCaptureEnabled(bool enabled) async {
    setState(() => _isQuickCaptureEnabled = enabled);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setQuickCaptureEnabled(enabled);
    } catch (_) {
      // 持久化失败时不阻塞 UI；用户切换仍生效到当前会话。
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const orange = Color(0xFFEA580C);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '录入错题',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _CaptureModeSelector(
              mode: ref.watch(captureModeProvider),
              onChanged: (mode) =>
                  ref.read(captureModeProvider.notifier).state = mode,
            ),
            const SizedBox(height: 12),
            _RecognitionChoiceSelector(
              selected: _choice,
              onChanged: (choice) => setState(() => _choice = choice),
            ),
            const SizedBox(height: 12),
            if (_choice != _RecognitionChoice.ai)
              Text(
                '${_choice.label} 会先识别题目、文字、公式、表格与选项，再进入逐题校对；普通 AI 只在你确认后做解析。',
                style: TextStyle(fontSize: 11, height: 1.4, color: colorScheme.onSurfaceVariant),
              ),
            if (_choice != _RecognitionChoice.ai) const SizedBox(height: 10),
            if (_isLoading)
              Container(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: <Widget>[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('正在打开相机...',
                        style: TextStyle(color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              )
            else ...<Widget>[
              _EntryOption(
                icon: CupertinoIcons.camera,
                iconColor: const Color(0xFF6366F1),
                iconBg: isDark
                    ? const Color(0xFF6366F1).withValues(alpha: 0.16)
                    : const Color(0xFFEEF2FF),
                label: '拍照',
                description: '使用相机拍摄错题',
                onTap: () => _pickWithChoice(fromCamera: true),
              ),
              const SizedBox(height: 10),
              _EntryOption(
                icon: CupertinoIcons.photo,
                iconColor: const Color(0xFFD97706),
                iconBg: isDark
                    ? const Color(0xFFD97706).withValues(alpha: 0.16)
                    : const Color(0xFFFFFBEB),
                label: '相册',
                description: '从相册选择图片',
                onTap: () => _pickWithChoice(fromCamera: false),
              ),
              const SizedBox(height: 10),
              _EntryOption(
                icon: CupertinoIcons.photo_on_rectangle,
                iconColor: const Color(0xFF0F766E),
                iconBg: isDark
                    ? const Color(0xFF0F766E).withValues(alpha: 0.18)
                    : const Color(0xFFF0FDFA),
                label: '试卷批量导入',
                description: '一次选择多页，逐页确认切题',
                onTap: _pickWorksheetPages,
              ),
              const SizedBox(height: 10),
              Text(
                '说明：拍照/相册的单题会使用“AI 服务”中的当前模型解析；PaddleOCR 与 MinerU 仅用于“试卷批量导入 → 整页框选切题”的候选题框识别，识别后会显示实际服务名称。',
                style: TextStyle(fontSize: 11, height: 1.4, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              _buildQuickCaptureSwitch(colorScheme),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? orange.withValues(alpha: 0.14)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark
                          ? orange.withValues(alpha: 0.35)
                          : const Color(0xFFFED7AA)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(CupertinoIcons.exclamationmark_triangle,
                        size: 18, color: orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMessage!,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  isDark ? orange : const Color(0xFF9A3412))),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark, size: 16),
                      onPressed: () => setState(() => _errorMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }

  Future<void> _pickWithChoice({required bool fromCamera}) async {
    if (_choice == _RecognitionChoice.ai) {
      await _pickAndNavigate(fromCamera: fromCamera);
      return;
    }
    await _pickForDocumentUnderstanding(fromCamera: fromCamera);
  }

  /// 构建极速模式开关。极速模式开启后，普通 AI 入口的拍照/选图会跳过
  /// 裁剪与校对页，直接进入 AI 解析加载页。
  Widget _buildQuickCaptureSwitch(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text(
          '极速模式',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: const Text(
          '拍照后直接 AI 解析，跳过裁剪与校对',
          style: TextStyle(fontSize: 11),
        ),
        value: _isQuickCaptureEnabled,
        onChanged: _quickCaptureSettingLoaded
            ? (value) => _setQuickCaptureEnabled(value)
            : null,
      ),
    );
  }

  Future<void> _pickForDocumentUnderstanding({required bool fromCamera}) async {
    final router = GoRouter.of(context);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final capture = ref.read(captureServiceProvider);
      final result = fromCamera ? await capture.pickFromCamera() : await capture.pickFromGallery();
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (result.isCancelled) return;
      if (result.errorMessage != null || result.record == null) {
        setState(() => _errorMessage = '获取图片失败：${result.errorMessage ?? '未返回图片'}');
        return;
      }
      final providerType = _choice == _RecognitionChoice.paddle
          ? LayoutProviderType.paddleCloud
          : LayoutProviderType.mineruCloud;
      ref.read(oneShotLayoutProviderTypeProvider.notifier).state = providerType;
      await persistWorksheetImport(ref, WorksheetImportSession(
        id: const Uuid().v4(),
        pages: <QuestionRecord>[result.record!],
        sourcePageIds: <String>{result.record!.id},
        createdAt: DateTime.now(),
      ));
      ref.read(currentQuestionProvider.notifier).state = result.record!;
      if (!mounted) return;
      Navigator.pop(context);
      router.go('/worksheet/regions');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '打开文档识别流程失败：$e';
      });
    }
  }

  Future<void> _pickWorksheetPages() async {
    ref.read(oneShotLayoutProviderTypeProvider.notifier).state = null;
    final router = GoRouter.of(context);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final pages =
          await ref.read(captureServiceProvider).pickMultipleFromGallery();
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (pages.isEmpty) return;
      await persistWorksheetImport(
        ref,
        WorksheetImportSession(
          id: const Uuid().v4(),
          pages: pages,
          sourcePageIds: pages.map((page) => page.id).toSet(),
          createdAt: DateTime.now(),
        ),
      );
      Navigator.pop(context);
      router.go('/worksheet/import');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '导入试卷页面失败: $e';
      });
    }
  }

  Future<void> _pickAndNavigate({required bool fromCamera}) async {
    final router = GoRouter.of(context);

    // 先检查 AI 是否已配置
    final config =
        await ref.read(settingsRepositoryProvider).getAiProviderConfig();
    if (config == null ||
        config.baseUrl.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      setState(() => _isLoading = false);
      setState(() => _errorMessage = '请先在设置中配置 AI 服务');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final capture = ref.read(captureServiceProvider);
      final result = fromCamera
          ? await capture.pickFromCamera()
          : await capture.pickFromGallery();

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (result.isCancelled) {
        // User cancelled - just close the sheet silently
        Navigator.pop(context);
        return;
      }

      if (result.errorMessage != null) {
        // Show error message
        String message;
        final error = result.errorMessage!;
        if (error.contains('permission') ||
            error.contains('camera_access_denied') ||
            error.contains('camera access') ||
            error.contains('denied')) {
          message = '相机权限被拒绝，请在系统设置 → 智能错题本 中开启相机权限';
        } else {
          message = '打开失败: $error';
        }
        setState(() => _errorMessage = message);
        return;
      }

      if (result.record != null) {
        Navigator.pop(context);
        ref.read(currentQuestionProvider.notifier).state = result.record;
        if (_isQuickCaptureEnabled) {
          // 极速模式：跳过裁剪、校对、保存确认页，直接进入 AI 解析加载页。
          // AnalysisLoadingScreen 会读取 currentQuestionProvider 拿到刚拍好的图。
          debugPrint('[CaptureEntrySheet] Quick mode: navigating to /analysis/loading');
          router.go('/analysis/loading');
        } else {
          debugPrint('[CaptureEntrySheet] Navigating to /capture/crop');
          router.go('/capture/crop');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '操作失败: $e';
      });
    }
  }
}

class _EntryOption extends StatelessWidget {
  const _EntryOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 22,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}


enum _RecognitionChoice {
  ai('普通 AI', '直接识别并分析单题'),
  paddle('PaddleOCR', '文档识别：文字、公式、表格、选项'),
  mineru('MinerU', 'VLM 文档理解：复杂公式、多栏试卷');

  const _RecognitionChoice(this.label, this.description);
  final String label;
  final String description;
}

/// 录入模式选择器：决定 AI 识别时如何处理图片中的印刷与手写内容。
///
/// - [CaptureMode.printed]：只识别印刷题干，忽略手写批改（默认）
/// - [CaptureMode.handwritten]：忠实转录手写解答过程，包括错误步骤
/// - [CaptureMode.mixed]：同时识别印刷题干和手写批注
class _CaptureModeSelector extends StatelessWidget {
  const _CaptureModeSelector({required this.mode, required this.onChanged});

  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;

  String _description(CaptureMode mode) {
    switch (mode) {
      case CaptureMode.printed:
        return '只识别印刷题干，忽略手写批改痕迹、圈画、红叉等';
      case CaptureMode.handwritten:
        return '忠实转录手写解答过程，包括错误步骤';
      case CaptureMode.mixed:
        return '同时识别印刷题干和手写批注';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('本次录入的内容主要是？',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<CaptureMode>(
          segments: const <ButtonSegment<CaptureMode>>[
            ButtonSegment<CaptureMode>(
              value: CaptureMode.printed,
              label: Text('印刷题'),
              icon: Icon(CupertinoIcons.doc_text, size: 16),
            ),
            ButtonSegment<CaptureMode>(
              value: CaptureMode.handwritten,
              label: Text('手写解答'),
              icon: Icon(CupertinoIcons.pencil, size: 16),
            ),
            ButtonSegment<CaptureMode>(
              value: CaptureMode.mixed,
              label: Text('混合'),
              icon: Icon(CupertinoIcons.doc_richtext, size: 16),
            ),
          ],
          selected: <CaptureMode>{mode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onChanged(selection.first);
          },
          showSelectedIcon: true,
          style: const ButtonStyle(
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _description(mode),
          style: TextStyle(
              fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RecognitionChoiceSelector extends StatelessWidget {
  const _RecognitionChoiceSelector({required this.selected, required this.onChanged});
  final _RecognitionChoice selected;
  final ValueChanged<_RecognitionChoice> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const Text('本次采用哪种识别？', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _RecognitionChoice.values.map((choice) {
          final active = choice == selected;
          return ChoiceChip(
            label: Text(choice.label),
            selected: active,
            onSelected: (_) => onChanged(choice),
            avatar: Icon(
              choice == _RecognitionChoice.ai
                  ? CupertinoIcons.sparkles
                  : choice == _RecognitionChoice.paddle
                      ? CupertinoIcons.doc_text_search
                      : CupertinoIcons.doc_richtext,
              size: 16,
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 5),
      Text(selected.description, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ],
  );
}
