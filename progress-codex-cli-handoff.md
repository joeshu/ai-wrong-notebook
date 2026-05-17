# Codex CLI 交接文件 — Smart Wrong Notebook — 2026-05-18

## 项目定位

Smart Wrong Notebook 是 Flutter 移动应用，面向学生的 AI 错题本。一期重点是单机 Android。核心链路是：

> 拍照/框选图片 → AI 识别与解析 → 展示解析结果 → 生成举一反三 → 用户确认并保存到错题本

当前不要退回旧流程“拍照 → OCR 确认 → AI 分析”。

## 必守约束

- 不要 push 到 GitHub，除非用户明确要求。
- 不要 `git add .`。如需提交，先给用户精确文件清单确认。
- 不要把 API Key 写入代码、日志、Markdown 或 commit。
- 不要硬编码某张 fixture 图的答案。
- 图形题读图不确定时，App 应显示“可能解法/需核对”，不要显示确定绿色答案。
- 不要修改 LaTeX 渲染引擎：
  - `lib/src/shared/widgets/math_content_view.dart`
  - `lib/src/shared/widgets/katex_math_view.dart`
  - `assets/katex/`

## 本轮最新完成

- 错题本列表页右上角 camera 入口已修正：
  - 旧逻辑直接进入 `/capture/correction`，可能展示上一张残留图片。
  - 新逻辑弹出 `CaptureEntrySheet`，让用户先选“拍照 / 相册”，再进入裁剪/分析。
  - 文件：`lib/src/features/notebook/presentation/notebook_screen.dart`。
- 三角形外角配图已按语义契约系统修复：
  - Prompt 增加外角 diagramData 规则：延长线必须共线，外角弧必须 `role: "external"`。
  - `AiAnalysisService` 质量门会从题干解析外角延长线语义，校验：点位存在、延长点/顶点/原边点共线、延长点在顶点另一侧、延长线 line 元素存在、外角弧显式标记。
  - `GeometryDiagramWidget` 遇到 `angleArc.role == external/explicit` 时尊重显式角度，不自动按 polygon 内角重算。
  - 默认三角形提高题兜底改为：`D 在 AB 的延长线上，∠DAC=120°，求 ∠B`，配正确图。
  - 新增回归测试覆盖用户反馈坏图被拒绝并替换为兜底图。
  - 文件：
    - `lib/src/data/remote/ai/ai_analysis_service.dart`
    - `lib/src/features/analysis/presentation/widgets/geometry_diagram_widget.dart`
    - `test/data/remote/ai_analysis_service_test.dart`
- Superpowers Codex 插件已正式安装：
  - `/Users/tangjun/.codex/plugins/superpowers`
  - 元数据：`/Users/tangjun/.codex/plugins/superpowers/.codex-plugin/plugin.json`
  - 版本：`5.1.0`
  - 需要新开 Codex 会话后确认 runtime skills 是否加载。
- 新 APK 已构建：
  - `build/app/outputs/flutter-apk/ai-wrong-notebook-v62-20260518-0047.apk`
  - 大小：`68M`
  - SHA256：`9b8f32a75f0cc808f807e8dd6db9ac0033e30a0907705ec0ca972275ade4b06a`

## 关键文件

- `lib/src/data/remote/ai/ai_analysis_service.dart`
  - AI prompt、JSON repair、生成练习题解析、质量门、fallback/profile。
  - 本轮新增外角 diagramData 语义校验。
- `lib/src/features/analysis/presentation/widgets/geometry_diagram_widget.dart`
  - 举一反三几何配图渲染。
  - 本轮新增外角/显式角弧不自动重算逻辑。
- `lib/src/features/notebook/presentation/notebook_screen.dart`
  - 错题本列表页。
  - 本轮 camera 入口改为 `CaptureEntrySheet`。
- `test/data/remote/ai_analysis_service_test.dart`
  - generatedExercises 质量门、fallback、外角坏图回归。
- `test/features/analysis/exercise_practice_test.dart`
  - 练习页与 diagramData 渲染回归。

## 验证结果

- `flutter test test/data/remote/ai_analysis_service_test.dart test/features/analysis/exercise_practice_test.dart`
  - `EXIT_CODE=0`
  - `62 passed`
- `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `EXIT_CODE=0`
  - 仍有 `100 issues found`，均 non-fatal。
  - 主要来自既有 math 渲染测试和未跟踪 geometry demo。
- `git diff --check`
  - 通过。
- `dart format`
  - 已对本轮涉及文件运行。
- `flutter build apk --release`
  - `EXIT_CODE=0`
  - 默认产物：`build/app/outputs/flutter-apk/app-release.apk (71.6MB)`
  - 已复制为：`build/app/outputs/flutter-apk/ai-wrong-notebook-v62-20260518-0047.apk`

## APK / 真机待测

安装并测试：

- `build/app/outputs/flutter-apk/ai-wrong-notebook-v62-20260518-0047.apk`

重点看：

- 错题本列表页右上角 camera 是否弹出“拍照 / 相册”。
- 等腰三角形外角举一反三图是否清晰：D 在 AB 延长线上，外角弧显示 `120°` 且不是三角形内角。
- 多题拆分与练习生成旧链路是否仍稳定。

## 当前 Git 状态摘要

Modified tracked files:

- `lib/src/data/remote/ai/ai_analysis_service.dart`
- `lib/src/features/analysis/presentation/widgets/geometry_diagram_widget.dart`
- `lib/src/features/notebook/presentation/notebook_screen.dart`
- `test/data/remote/ai_analysis_service_test.dart`
- `progress-current.md`
- `progress-codex-cli-handoff.md`

Untracked files include:

- `CLAUDE.md`
- multiple `docs/*.html` drafts and `docs/jilu.txt`
- `progress-2026-04-29.md`
- `progress-ai-b1-handoff.md`
- `progress-ai-geometry-handoff.md`
- `test/fixtures/*.png`
- `test/tool/geometry_*` demo files

Do not stage all files.

## 风险点

- 本轮尚未 commit、未 push。
- 旧保存记录中的坏外角 diagramData 不会自动迁移；需要重新生成练习或删除旧异常记录。
- Analyzer 仍有 non-fatal info/warning；不要为了清它去碰 LaTeX 渲染引擎。
- Superpowers 插件已安装到目录，但新会话需要确认 runtime 是否加载。

## 下一步

1. 重新进入 Codex 后，先读 `progress-current.md` 和本文件。
2. 真机安装 `ai-wrong-notebook-v62-20260518-0047.apk`。
3. 根据真机反馈决定是否继续修。
4. 如果真机 OK，准备精确文件清单，请用户确认是否做本地 WIP commit。
5. 如用户确认 commit：
   - 只 `git add <明确文件列表>`。
   - commit message 固定：`wip: end of day state`。
   - 不 push。
