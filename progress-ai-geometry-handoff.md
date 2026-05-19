# AI 图形题解析质量门进展交接

## 背景

当前问题来自半圆面积图片题：图中标注 `3`、`7`、`10`，内部写“半圆”，要求括号区域面积。真机/本地 AI 回归中，模型会在 `13π`、`10π`、`29π/2` 等答案之间波动，并且可能出现 `finalAnswer`、`finalAnswerDerivation`、`steps` 自相矛盾。

用户要求：
- 不要靠本地硬编码修答案。
- 不要大幅增加 token/性能成本。
- 不要动 LaTeX 渲染引擎。
- 图形读图不确定时，UI 不能显示绿色确定“正确答案”，应显示“可能解法/需核对”。
- 希望能把图片丢给助手，用本地回归测试代替反复真机测试。

## 已完成

### 1. 视觉假设质量门

涉及文件：
- `lib/src/domain/models/analysis_result.dart`
- `lib/src/data/remote/ai/ai_analysis_service.dart`
- `lib/src/features/analysis/presentation/analysis_result_screen.dart`
- `lib/src/features/notebook/presentation/question_detail_screen.dart`
- 相关测试文件

已加入：
- `VisualAssumptionStatus.none | reliable | needsReview`
- `VisualAssumptions`
- `VisualMeasurementAssumption`
- AI prompt 要求输出 `visualAssumptions`
- 如果关键读图项不确定，结果标记为 `visualAssumptionStatus.needsReview`
- UI 在 `needsReview` 时显示“可能解法”，不是绿色“正确解答/正确答案”

### 2. 答案一致性质量门

涉及文件：
- `lib/src/data/remote/ai/ai_analysis_service.dart`
- `lib/src/domain/models/analysis_result.dart`

已有字段：
- `AnalysisConsistencyStatus.unchecked | consistent | repaired | needsReview | unverifiable`
- `consistencyNote`
- `wasVerifierUsed`
- `finalAnswerDerivation`
- `reconstructedQuestionText`

关键逻辑：
- 本地检测只判断可疑，不直接改答案。
- 发现 `finalAnswer`、`finalAnswerDerivation`、`steps` 明显冲突时才触发模型 verifier。
- verifier 高/中置信且 `needsManualReview=false` 时才修正答案。
- 如果视觉假设仍不确定，即使 verifier 修正了答案，也保持 `consistencyStatus.needsReview`，避免 UI 误显示确定答案。

已修过的重要漏洞：
- 之前 `visualAssumptionStatus.needsReview` 会让一致性检测提前返回，导致答案/步骤冲突不触发 verifier；已改为先跑一致性检测，再处理视觉假设状态。

### 3. 本地图片回归测试

新增文件：
- `test/tool/analyze_image_fixture_test.dart`

用法：

```bash
AI_BASE_URL="https://www.vbcode.io/v1" AI_API_KEY="..." AI_MODEL="gpt-5.4" \
AI_FIXTURE_IMAGE="/Users/tangjun/.claude/image-cache/ddc915e2-b4a0-4676-9aae-77af41cae7f8/3.png" \
AI_FIXTURE_SUBJECT=math \
AI_FIXTURE_TEXT="图中标注上边为3、底边为7、右边高为10，图内为半圆，求图中括号所示区域面积。" \
flutter test test/tool/analyze_image_fixture_test.dart
```

说明：
- 这是 Flutter test，不是普通 Dart CLI，因为 `AiAnalysisService` 依赖 Flutter/foundation，普通 `dart run` 会因 `dart:ui` 不可用失败。
- 无 `AI_FIXTURE_IMAGE` 时测试自动 skip。
- 会输出：
  - `finalAnswer`
  - `finalAnswerDerivation`
  - `steps`
  - `visualAssumptions`
  - `visualAssumptionStatus`
  - `consistencyStatus`
  - `consistencyNote`
  - `wasVerifierUsed`
  - `generatedExercises`
  - `qualityGate`

## 最新一次本地图片测试结果

图片：
- `/Users/tangjun/.claude/image-cache/ddc915e2-b4a0-4676-9aae-77af41cae7f8/3.png`

命令已跑通，请求模型成功。

模型第一次返回时出现明显矛盾：
- `finalAnswer`: `10π`
- `finalAnswerDerivation`: 先写 `10π`，又推导出 `29π/2`
- `steps` 最终为 `29π/2`

一致性 verifier 被触发并修正：
- 修正后 `finalAnswer`: `\frac{29\pi}{2}`
- `wasVerifierUsed`: `true`
- `consistencyStatus`: `needsReview`
- `consistencyNote`: `AI 已复核并修正答案；...读图关系需核对...`

这是符合“不要给确定绿答案”的目标的：UI 应显示可能解法/需核对。

但测试最终仍失败，因为 fixture quality gate 当前把 `consistencyStatus.needsReview` 当作失败：

```text
analysis requires manual review: AI 已复核并修正答案；本题主要依赖读图关系...
```

这个失败是预期的“需要人工核对”信号，不代表 App 崩溃。

## 生成练习题新问题与已加防线

最新发现：AI 原始 `generatedExercises` 里曾生成自我否定题，例如解释中写：

```text
四个选项中没有该值，原选项设计不严谨
```

已在 `lib/src/data/remote/ai/ai_analysis_service.dart` 加过滤：

新增方法：
- `_hasGeneratedExerciseSelfInvalidation(GeneratedExercise exercise)`

触发词包括：
- `选项中没有`
- `没有该值`
- `无正确选项`
- `选项设计不严谨`
- `选项有误`
- `原选项设计`
- `需重新检查`
- `需要重新检查`
- `修正后应`
- `应为修正`
- `无法从选项`
- `题目不严谨`
- `本题无解`

并在 `_isGeneratedExerciseAcceptable` 中先过滤，过滤后不足 expected count 时回退 `_defaultGeneratedExercises`。

新增测试：
- `service rejects self-invalidating generated exercises and falls back`

## 当前验证结果

已通过：

```bash
flutter test test/data/remote/ai_analysis_service_test.dart test/tool/analyze_image_fixture_test.dart
```

结果：
- `39 passed`
- `1 skipped`（因为没有 fixture env 时自动 skip）

已跑：

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

结果：
- 退出成功
- 仍有既有 117 个 info 级提示
- 主要是 `ai_analysis_service.dart` prompt 字符串 escape info、`math_content_view.dart` 和旧测试 const info
- 未处理，因为用户明确不想动 LaTeX 渲染引擎

## 仍需解决/建议下一步

### A. 明确 fixture 测试的 pass/fail 语义

当前 `test/tool/analyze_image_fixture_test.dart` 把 `consistencyStatus.needsReview` 视为失败，因此这张图会失败。这里需要产品决策：

1. 如果目标是“模型必须给确定答案”，那当前失败合理，但图形读图不确定时会经常失败。
2. 如果目标是“App 不要误导用户”，则 `needsReview` 应该算测试通过，只要：
   - `finalAnswer/finalAnswerDerivation/steps` 不冲突；
   - `visualAssumptionStatus.needsReview` 时 `consistencyStatus.needsReview`；
   - UI 会显示“可能解法/需核对”；
   - generated exercises 没有自我否定内容。

推荐改成两级结果：
- `passed`: 无内部冲突、无坏练习题、状态标记正确。
- `requiresManualReview`: 单独字段，只提示人工核对，不让测试失败。

也就是说，把当前这类输出从 hard fail 改成 warning/report。

### B. 生成练习题 fallback 质量仍需观察

本次过滤后，生成题回退成本地默认题，但默认题可能变成普通圆面积/半圆面积/圆环面积，不一定完全贴合“斜直径 + 坐标/勾股”题型。

如果要更好，需要优化 `_defaultGeneratedExercises` 对 `planeGeometryArea + circleFamily + 半圆 + 勾股/端点求直径` 的 fallback，让默认题更像：
- 给两个端点坐标/水平差竖直差；
- 求半圆面积；
- 答案选项严格一致。

### C. API Key 已暴露

用户在本会话中粘贴过真实 API Key：
- 建议用户到服务商后台重置/作废该 key。

## 重要注意

- 不要动 `lib/src/shared/widgets/math_content_view.dart` 或 LaTeX 渲染引擎。
- 不要做本地硬编码答案修复，例如专门把本图修成 `29π/2`。
- 继续保持：本地检测只判冲突/触发 verifier，不直接改数学答案。
- 当前重点不是强迫 AI 给确定答案，而是防止错误答案以确定态展示给学生。
