# Codex CLI 交接文件 — Smart Wrong Notebook — 2026-05-16

## 项目定位

Smart Wrong Notebook 是 Flutter 移动应用，面向学生的 AI 错题本。一期重点是单机 Android；核心链路是：

> 拍照 → 直接 AI 解题/识别 → 展示解析 → 用户保存时确认文本并入库

不要退回旧流程“拍照 → OCR 确认 → AI 分析”。

## 切换到 Codex CLI 前需要准备什么

1. **从当前仓库根目录启动 Codex CLI**
   - 目录：`/Users/tangjun/opencode/smart-wrong-notebook`
   - 先让 Codex 读取本文件、`CLAUDE.md`、`progress-current.md`。

2. **确认 Flutter 环境可用**
   - 建议先跑：
     ```bash
     flutter --version
     flutter pub get
     ```
   - 不要清理 build 或删除文件，除非用户明确确认。

3. **准备 AI fixture 环境变量，但不要写入文件或 git**
   - 本地图片回归测试需要：
     ```bash
     AI_BASE_URL="..." \
     AI_API_KEY="..." \
     AI_MODEL="gpt-5.5" \
     AI_FIXTURE_IMAGE="/path/to/image.png" \
     AI_FIXTURE_SUBJECT=math \
     AI_FIXTURE_TEXT="题目描述" \
     flutter test test/tool/analyze_image_fixture_test.dart
     ```
   - 不要把真实 API Key 放进 Markdown、代码、测试文件或 commit。
   - 之前会话中用户暴露过真实 key，建议重置。

4. **先做 git 状态确认**
   - 必跑：
     ```bash
     git status --short
     git status -sb
     git diff --stat
     ```
   - 不要 `git add .`。
   - 如果需要提交，显式 `git add <file...>`。
   - 不要 push；push/PR/force/rebase 都需要用户明确确认。

## 当前 WIP 主题

本轮主要围绕“AI 生成举一反三练习题质量”与“图形题练习配图持久化”。

### 已实现的关键点

- `AiAnalysisService` 的 generatedExercises prompt 更严格：
  - 必须保持同 domain/object/method。
  - 必须 3 道选择题。
  - difficulty 依次为 简单、同级、提高。
  - 三题必须保持同知识点、同题型、同核心解法。
  - 几何题必须包含 `diagramData`。
- 质量门会拒绝题型漂移：
  - 半圆面积题不能漂到方程/函数/体积。
  - 圆锥体积题不能漂到平方根方程。
  - 函数求值题不能漂到解方程。
  - 直角三角形长度题不能漂到面积/角度/体积。
- 质量门会拒绝自我否定题：
  - “选项中没有”
  - “无正确选项”
  - “选项设计不严谨”
  - “题目不严谨”
  - “本题无解”等。
- 本地 fallback 练习题已经按题型拆分：
  - 圆面积
  - 半圆面积
  - 圆环/阴影面积
  - 直角三角形长度
  - 圆锥体积
  - 圆柱体积
- `GeneratedExercise.diagramData` 已进入 domain model、Drift 表、migration、repository 保存/读取。
- fixture 测试中 `needsReview` 表示“App 应显示可能解法/需核对”，不再必然测试失败。

## 关键文件

- `lib/src/data/remote/ai/ai_analysis_service.dart`
  - generatedExercises prompt、topic profile、质量门、fallback 题库、fixture 解析核心。
  - 关键词：`_ExerciseTopicProfile`、`_ExerciseVariant`、`_parseGeneratedExercises`、`_isGeneratedExerciseAcceptable`、`_buildExerciseTopicProfile`、`_defaultGeneratedExercises`、`_hasGeneratedExerciseSelfInvalidation`、`_hasRightTriangleLengthSignal`。
- `lib/src/domain/models/generated_exercise.dart`
  - `diagramData` 字段与 JSON parse/toJson/copyWith。
- `lib/src/data/local/tables/generated_exercises.dart`
  - Drift 表新增 `diagramDataJson`。
- `lib/src/data/local/app_database.dart`
  - schemaVersion 当前为 `5`，migration `from < 5` 添加 `diagramDataJson`。
- `lib/src/data/local/app_database.g.dart`
  - Drift 生成文件，已随 schema 更新。
- `lib/src/data/repositories/drift_question_repository.dart`
  - `diagramData` 的 jsonEncode/jsonDecode 保存读取。
- `lib/src/app/providers.dart`
  - split 单题场景保留 source savedExercises。
- `test/data/remote/ai_analysis_service_test.dart`
  - generatedExercises 质量门和 fallback 测试。
- `test/data/local/drift_question_repository_test.dart`
  - Drift 持久化回归。
- `test/features/analysis/exercise_practice_test.dart`
  - `diagramData` 刷新/渲染路径回归。
- `test/tool/analyze_image_fixture_test.dart`
  - 本地图片 fixture 回归入口。

## 必守约束

- 不要修改 LaTeX 渲染引擎，除非用户明确要求：
  - `lib/src/shared/widgets/math_content_view.dart`
  - `lib/src/shared/widgets/katex_math_view.dart`
  - `assets/katex/`
- 不要通过本地硬编码把特定图片答案修成某个值。
- 当前策略是：本地检测冲突、触发 verifier、标记 needsReview；不直接替模型“算出正确答案”。
- 图形题读图不确定时，UI 不应显示绿色确定答案，应显示“可能解法/需核对”。
- 不要为清 analyzer info 去大改 prompt 或 LaTeX 相关字符串。

## 当前验证命令

建议 Codex 接手后先复跑：

```bash
dart format lib/src/data/remote/ai/ai_analysis_service.dart lib/src/domain/models/generated_exercise.dart lib/src/data/local/tables/generated_exercises.dart lib/src/data/local/app_database.dart lib/src/data/repositories/drift_question_repository.dart lib/src/app/providers.dart test/data/remote/ai_analysis_service_test.dart test/tool/analyze_image_fixture_test.dart
```

```bash
flutter test test/data/remote/ai_analysis_service_test.dart test/data/local/drift_question_repository_test.dart test/features/analysis/exercise_practice_test.dart test/tool/analyze_image_fixture_test.dart
```

最近一次结果：

- `EXIT_CODE=0`
- `52 passed, 1 skipped`
- skip：未设置 `AI_FIXTURE_IMAGE` 时 fixture 测试自动 skip。

Analyzer：

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

最近一次结果：

- `EXIT_CODE=0`
- `204 issues found`，均为 non-fatal info/warning。

## 建议 Codex 接手后的第一个任务

1. 用真实图片 fixture + `AI_MODEL=gpt-5.5` 跑 `test/tool/analyze_image_fixture_test.dart`。
2. 对比 `gpt-5.4` 和 `gpt-5.5`：
   - 半圆面积题是否仍把 `10` 读成高度/直径混乱。
   - `finalAnswer`、`finalAnswerDerivation`、`steps` 是否一致。
   - `visualAssumptionStatus` / `consistencyStatus` 是否正确显示 needsReview。
   - generatedExercises 是否保持同题型，是否有 `diagramData`，是否无自我否定。
3. 如果 gpt-5.5 改善明显，再考虑把默认模型/配置升级路径写入 app 设置或 provider 管理方案。

## 当前已知风险

- working tree 有较多历史未提交/未跟踪文件，Codex 不应盲目提交全部。
- 之前交接中提到本地 main 和 origin/main 可能 diverge；同步远端前必须确认用户意图。
- 本地没有真机 UI 自动验证，拍照链路仍需要用户安装 APK 或连接设备测试。
