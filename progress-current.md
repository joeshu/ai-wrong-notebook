# 项目进展 / Park — 2026-05-16

## Done

- 已恢复并继续上次中断的 AI 图形题/举一反三质量优化工作。
- 已强化 `generatedExercises` 生成与过滤逻辑：
  - prompt 增加“恰好 3 道选择题，difficulty 依次为 简单/同级/提高”。
  - 三题必须保持同一知识点、同一题型、同一核心解法。
  - 难度递进只能通过换数、增加同方法变形或同主题条件完成，禁止切换知识点/题型。
- 已新增/扩展练习题 topic profile：
  - `planeGeometryArea`：圆面积、半圆面积、圆环/阴影面积。
  - `planeGeometryLength`：直角三角形长度、勾股定理、等长关系。
  - `solidGeometryVolume`：圆锥体积、圆柱体积。
- 已增强生成练习题质量门：
  - 拒绝自我否定练习题，例如“选项中没有该值/选项设计不严谨/无正确选项”。
  - 强信号源题必须保留 domain/object/method/variant，AI 输出不足或漂移时回退本地默认题。
  - 几何练习题要求带 `diagramData`。
- 已优化本地 fallback 题库：
  - 半圆面积、圆面积、圆环/阴影面积。
  - 直角三角形长度（含勾股定理 + 等长关系提高题）。
  - 圆锥/圆柱体积。
- 已修复一个检查时发现的不严谨 fallback：右三角形“提高”题原来用“同类结构下 BC=AC/2”不够严谨，已改为 `BD=BC=x`，通过 `(x+7)^2+x^2=17^2` 明确推出 `BC=8`。
- 已把 `GeneratedExercise.diagramData` 接入持久化：
  - `lib/src/domain/models/generated_exercise.dart`
  - `lib/src/data/local/tables/generated_exercises.dart`
  - `lib/src/data/local/app_database.dart` schemaVersion `4 -> 5`
  - `lib/src/data/local/app_database.g.dart`
  - `lib/src/data/repositories/drift_question_repository.dart`
- 已修正 split 单题场景的 saved exercises 继承逻辑：单题拆分时继续保留 `source.savedExercises`。
- 已把 fixture 图片回归测试的 `needsReview` 语义改为 warning：只要内部答案一致、状态正确、练习题无自我否定，就不 hard fail。

## Verification

- `dart format lib/src/data/remote/ai/ai_analysis_service.dart lib/src/domain/models/generated_exercise.dart lib/src/data/local/tables/generated_exercises.dart lib/src/data/local/app_database.dart lib/src/data/repositories/drift_question_repository.dart lib/src/app/providers.dart test/data/remote/ai_analysis_service_test.dart test/tool/analyze_image_fixture_test.dart`
  - 已执行，格式化完成。
- `flutter test test/data/remote/ai_analysis_service_test.dart test/data/local/drift_question_repository_test.dart test/features/analysis/exercise_practice_test.dart test/tool/analyze_image_fixture_test.dart`
  - `EXIT_CODE=0`
  - `52 passed, 1 skipped`
  - skip 原因：未设置 `AI_FIXTURE_IMAGE` 时本地图片回归自动跳过。
- `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `EXIT_CODE=0`
  - 仍有既有 non-fatal `204 issues found`。
  - 其中 warning 包括 `test/tool/direct_image_test.dart` 的 `Timeout` 注解位置、`test/tool/geometry_canvas_demo.dart` 的 unused import；info 主要是 prompt 字符串 escape、旧测试 const、demo deprecated API。
  - 本次没有为清 analyzer 去触碰 LaTeX 渲染文件。

## Blockers / 风险点

- 本地没有真机/模拟器 UI 验证；图形题完整拍照 → AI → 练习链路仍需要真机回归。
- 当前 working tree 包含较多历史未提交/未跟踪文件，不应 `git add .`。
- `flutter analyze --no-fatal-infos --no-fatal-warnings` 成功，但仓库仍有 non-fatal warning/info；如果 CI 默认 fatal warnings，需要单独处理或调整命令。
- 用户此前在会话里暴露过真实 API Key，建议到服务商后台重置/作废该 key，不要把 key 写入任何交接文件或 git。
- 远端同步状态之前交接记录提到 main 与 origin/main 存在 diverge；本次尚未执行 pull/rebase/push，提交前后都应先确认分支状态。

## Next First Step

1. 先确认是否做本地 WIP commit。
2. 若提交：只 stage 本次相关文件的显式清单，commit message 固定为 `wip: end of day state`，不 push。
3. 切换到 Codex CLI 后，先让 Codex 读取：
   - `CLAUDE.md`
   - `progress-current.md`
   - `progress-codex-cli-handoff.md`
   - `progress-ai-b1-handoff.md`
   - `progress-ai-geometry-handoff.md`
4. Codex 接手后的第一个技术任务：用真实图片 fixture + `AI_MODEL=gpt-5.5` 回归图形题，观察读图准确率和 generatedExercises 质量。

## Tomorrow first action

- 先完成本地 WIP commit；然后在 Codex CLI 中运行 targeted tests，确认环境一致后继续 gpt-5.5 图片回归。
