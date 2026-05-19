# B1 两阶段读图假设锁定 — 交接文件

## 背景

图形题（如半圆面积）用一次 LLM 请求同时完成读图+解题时，模型会在同一次请求内对图中数字含义摇摆（如"10 是直径还是高"），导致 steps 内部自相矛盾。

B1 核心思路：把"读图假设"和"基于假设解题"拆成两次请求。

## 已完成内容

### 提交记录

```
fc87f8b feat: two-stage visual hypothesis locking for geometry image analysis (B1)
c2c5073 feat: add visual assumption & consistency quality gates for geometry image analysis
```

### 改动文件

| 文件 | 改动 |
|------|------|
| `lib/src/data/remote/ai/ai_analysis_service.dart` | 新增阶段 1 `_extractVisualHypotheses` + `_buildLockedHypothesesPrompt` + 数据类 |
| `lib/src/domain/models/analysis_result.dart` | `VisualAssumptions`、`VisualMeasurementAssumption`、`VisualAssumptionStatus`、`AnalysisConsistencyStatus` |
| `lib/src/features/analysis/presentation/analysis_result_screen.dart` | needsReview 时显示"可能解法" |
| `lib/src/features/notebook/presentation/question_detail_screen.dart` | needsReview 时不显示绿色确定答案 |
| `test/data/remote/ai_analysis_service_test.dart` | B1 解析测试 |
| `test/tool/analyze_image_fixture_test.dart` | 端到端图片回归测试 |

### 两阶段流程

1. **阶段 1**（`_extractVisualHypotheses`）：
   - 轻量请求（~300 token output），temperature 0.2
   - 只做读图，输出结构化 JSON：targetObject、labelInterpretations、geometricRelationships、uncertainItems、needsManualReview
   - 只对图形题生效（`shouldAnalyzeImageFirst && imageBytes != null`）

2. **阶段 2**（正常分析）：
   - 收到锁定假设后，prompt 追加"已锁定的读图假设 — 不得修改"
   - 步骤中使用的每个数字必须引用已声明的标注含义
   - 阶段 1 假设直接映射到 `VisualAssumptions`，不依赖阶段 2 模型自行报告

### 质量门体系

- `VisualAssumptionStatus.none | reliable | needsReview`
- `AnalysisConsistencyStatus.unchecked | consistent | repaired | needsReview | unverifiable`
- `consistencyNote`、`wasVerifierUsed`、`finalAnswerDerivation`
- 生成练习题自我否定过滤（`_hasGeneratedExerciseSelfInvalidation`）
- fixture test 中 `needsReview` 且内部一致 → warning 不 fail

### Fixture 测试用法

```bash
AI_BASE_URL="https://www.vbcode.io/v1" \
AI_API_KEY="..." \
AI_MODEL="gpt-5.4" \
AI_FIXTURE_IMAGE="/path/to/image.png" \
AI_FIXTURE_SUBJECT=math \
flutter test test/tool/analyze_image_fixture_test.dart
```

## 最新测试结果（2026-05-10）

4 张图逐张测试全部通过：

| 图片 | 题型 | 答案 | 一致性 | 质量门 |
|------|------|------|--------|--------|
| 1 | 半圆面积 | 29π/2 | needsReview | passed |
| 2 | 圆锥体积 | 12π | needsReview | passed |
| 3 | 行程相遇 | 上午12:30 | consistent | passed |
| 4 | 长方形面积 | 9500 cm² | consistent | passed |

## 已知问题

1. **半圆面积准确率**：模型给出 29π/2（假设"10 是外框高度，水平差 7-3=4，斜边=√116=2√29"），正确答案可能是 25π/2（假设"10 是半圆直径"）。B1 确保了内部一致且标记 needsReview，App 不会误导学生，但准确率仍依赖模型读图能力。

2. **生成练习题 fallback 质量**：过滤自我否定题后回退到默认题，默认题与原题关联度低。

3. **一张图多题**：图 2 包含两道题（圆锥+三角形），模型只解析了一道。多题拆分是后续方向。

4. **git diverge**：本地 main 比 origin/main 多 2 个提交（c2c5073 + fc87f8b），origin 多 7 个提交，需要 pull/rebase 后再 push。

## 下一步建议

1. **升级模型到 gpt-5.5**：看是否能提升半圆面积题的读图准确率（把"10"正确识别为直径而非外框高度）。
2. **生成练习题质量优化**：让 `_defaultGeneratedExercises` 更贴合原题题型。
3. **多题拆分**：一张图包含多道题时，分别解析。
4. **git 同步**：pull/rebase 后 push。

## 重要约束（不要动）

- 不要动 `lib/src/shared/widgets/math_content_view.dart` 或 LaTeX 渲染引擎
- 不要做本地硬编码答案修复
- 继续保持：本地检测只判冲突/触发 verifier，不直接改数学答案
- 当前重点不是强迫 AI 给确定答案，而是防止错误答案以确定态展示给学生

## 关键代码位置

- 阶段 1 入口：`ai_analysis_service.dart` 搜索 `_extractVisualHypotheses`
- 锁定假设 prompt：搜索 `_buildLockedHypothesesPrompt`
- 图形题判断：搜索 `shouldAnalyzeImageFirst`
- 一致性检测：搜索 `_ensureAnalysisConsistency`
- 练习题过滤：搜索 `_hasGeneratedExerciseSelfInvalidation`
- fixture test：`test/tool/analyze_image_fixture_test.dart`
