# 项目进展 / Park — 2026-05-18

## Done

- 修复错题本右上角 camera 入口语义：
  - 原逻辑从错题本列表直接 `go('/capture/correction')`，会复用 `currentQuestionProvider` 中残留的上一张图片，导致用户点“添加错题”却看到旧图片预览。
  - 已改为与首页一致：点击 camera 弹出 `CaptureEntrySheet`，让用户明确选择“拍照 / 相册”，选图成功后再进入裁剪和 AI 分析。
  - 改动文件：`lib/src/features/notebook/presentation/notebook_screen.dart`。
- 系统性修复三角形外角配图问题，不只是改单个坐标：
  - 在 AI prompt 中明确外角图的 diagramData 语义契约：如“D 在 AB 的延长线上”时，D、A、B 必须共线且 D 在 A 的另一侧；外角弧必须使用 `role: "external"`。
  - `AiAnalysisService` 增加外角图质量门：从题干解析“点 X 在 YZ 的延长线上”和外角 `∠...`，校验点位、共线、反向、延长线元素存在、外角弧显式标记。
  - `GeometryDiagramWidget` 支持 `angleArc.role == external/explicit` 时尊重 `startAngle/sweepAngle`，不再自动按 polygon 顶点重算成三角形内角。
  - 默认三角形“提高”兜底题已换成清晰的等腰三角形外角构型：`D 在 AB 的延长线上，∠DAC=120°，求 ∠B`，并配正确 diagramData。
  - 新增回归测试，覆盖用户反馈的坏图：D 不在 AB 延长线上时会被拒绝并替换为本地可靠兜底图。
  - 改动文件：
    - `lib/src/data/remote/ai/ai_analysis_service.dart`
    - `lib/src/features/analysis/presentation/widgets/geometry_diagram_widget.dart`
    - `test/data/remote/ai_analysis_service_test.dart`
- 已正式安装 Superpowers Codex 插件：
  - 安装目录：`/Users/tangjun/.codex/plugins/superpowers`
  - 插件元数据：`/Users/tangjun/.codex/plugins/superpowers/.codex-plugin/plugin.json`
  - 版本：`5.1.0`
  - 包含 14 个 skills，如 `brainstorming`、`writing-plans`、`test-driven-development`、`systematic-debugging`、`subagent-driven-development`、`verification-before-completion`。
  - 通常需要新开 Codex 会话后才能进入可用 skills 列表。
- 已构建新的 release APK 供真机测试：
  - `build/app/outputs/flutter-apk/ai-wrong-notebook-v62-20260518-0047.apk`
  - 大小：`68M`
  - SHA256：`9b8f32a75f0cc808f807e8dd6db9ac0033e30a0907705ec0ca972275ade4b06a`
  - 默认产物仍保留：`build/app/outputs/flutter-apk/app-release.apk`

## Verification

- `flutter test test/data/remote/ai_analysis_service_test.dart test/features/analysis/exercise_practice_test.dart`
  - `EXIT_CODE=0`
  - `62 passed`
  - 覆盖 generatedExercises 质量门、三角形外角坏图拒绝/兜底、练习页 diagramData 渲染。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `EXIT_CODE=0`
  - 仍有 `100 issues found`，均为 non-fatal info/warning。
  - 主要来自既有 `test/shared/widgets/math_content_view_test.dart` 和未跟踪 `test/tool/geometry_canvas_demo.dart`。
- `git diff --check`
  - 通过。
- `dart format`
  - 已对本轮涉及文件运行。
- `flutter build apk --release`
  - `EXIT_CODE=0`
  - 构建成功：`app-release.apk (71.6MB)`，并复制为 v62 时间戳 APK。

## Blockers / 风险点

- 当前本轮改动尚未 commit、未 push。
- 不要 `git add .`。工作区有较多未跟踪文档/fixture/demo 文件，很多不是本轮改动。
- 新 APK 还需要用户真机验证：
  - 错题本右上角 camera 是否弹出“拍照 / 相册”。
  - 新生成的三角形外角举一反三配图中，D 是否在 AB 延长线上，外角弧是否清楚表示 `∠DAC=120°`。
- 旧保存记录中的坏 diagramData 不会自动迁移；如已保存旧记录，可能需要重新生成练习或手动删除旧异常记录。
- Analyzer 仍有 non-fatal warning；不要为了清 analyzer 去碰 LaTeX 渲染引擎：
  - `lib/src/shared/widgets/math_content_view.dart`
  - `lib/src/shared/widgets/katex_math_view.dart`
  - `assets/katex/`
- 不要把 API Key 写入文件、日志、Markdown 或 commit。

## Current Git State

Modified tracked files:

- `lib/src/data/remote/ai/ai_analysis_service.dart`
- `lib/src/features/analysis/presentation/widgets/geometry_diagram_widget.dart`
- `lib/src/features/notebook/presentation/notebook_screen.dart`
- `test/data/remote/ai_analysis_service_test.dart`
- `progress-current.md`
- `progress-codex-cli-handoff.md`（本 park 更新后）

Untracked files currently present:

- `CLAUDE.md`
- `docs/ai-analysis-layout-proposal.html`
- `docs/current-layout-home-review-proposal.html`
- `docs/home-review-ux-proposal.html`
- `docs/icon-style-comparison.html`
- `docs/jilu.txt`
- `docs/layout-preview.html`
- `docs/review-flow-stats-proposal.html`
- `docs/review-top-stats-proposal.html`
- `docs/theme-palette-analysis-result-preview.html`
- `progress-2026-04-29.md`
- `progress-ai-b1-handoff.md`
- `progress-ai-geometry-handoff.md`
- `test/fixtures/duoti.png`
- `test/fixtures/shuxue-jihe.png`
- `test/fixtures/wuli-dianzu.png`
- `test/fixtures/yingyu.png`
- `test/fixtures/yuwen.png`
- `test/tool/geometry_canvas_demo.dart`
- `test/tool/geometry_svg_auxiliary_demo.html`
- `test/tool/geometry_svg_samples.html`

## Next First Step

1. 重新进入 Codex 后，先读本文件和 `progress-codex-cli-handoff.md`。
2. 安装真机测试 APK：`build/app/outputs/flutter-apk/ai-wrong-notebook-v62-20260518-0047.apk`。
3. 重点测：
   - 错题本列表页右上角 camera 是否进入“拍照 / 相册”选择。
   - 等腰三角形外角练习图是否语义正确。
   - 旧的多题拆分/举一反三链路是否仍稳定。
4. 如果真机 OK，再决定是否做本地 WIP commit。
5. 如需 commit，必须先确认精确文件清单；只使用 `git add <明确文件>`，不要 `git add .`，commit message 固定为 `wip: end of day state`，不要 push。

## Tomorrow first action

- 从真机反馈开始；如果 v62 `20260518-0047` 包通过，就准备精确提交清单给用户确认是否做 WIP commit。

Good night.
