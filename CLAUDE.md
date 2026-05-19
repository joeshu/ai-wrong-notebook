# Project: Smart Wrong Notebook (AI 错题本)

面向学生的 AI 错题本 Flutter 移动应用。一期单机 Android，后续扩 iOS/登录/同步。

## 构建与开发

- Flutter 项目，Android APK 构建
- APK 命名格式：`ai-wrong-notebook-v{版本号}-{YYYYMMDD}-{HHmm}.apk`
  - 小改动只更新时间戳，不递增版本号
  - 较大功能/发版节点才递增 v 编号
  - 不加功能描述后缀
- APK 输出目录：`build/app/outputs/flutter-apk/`，不要复制到 Desktop 或其他位置
- 当前版本：v62

## 工作模式

- 常规实现与本地验证可直接自动执行，不需要每步确认
- 危险操作（push/PR/删除/生产环境）仍需暂停确认
- 参考现有产品时，借鉴交互流程和能力链路，不照抄 UI
- 支持浅色/深色双主题

## 核心链路

拍照 → 直接 AI 解题/识别 → 展示解析 → 用户保存时确认文本并入库

不要回到"拍照 → OCR 确认 → AI 分析"的旧流程。

## LaTeX 渲染

四层防御体系：
1. System Prompt 约束 LLM 输出标准 LaTeX
2. `flutter_math_fork` 原生 Dart 渲染 (~90%)
3. KaTeX WebView 兜底 (~10%)
4. 纯文本 fallback

关键文件：
- `lib/src/shared/widgets/math_content_view.dart` — 渲染主控 + 规范化逻辑
- `lib/src/shared/widgets/katex_math_view.dart` — KaTeX WebView 兜底
- `assets/katex/` — KaTeX 离线资源

### 正则修改原则

修改 LaTeX 正则前必须检查冲突：
- 新正则会误匹配什么已有内容？
- 需要加前后缀保护 `(?<![A-Za-z\\])` 吗？
- 会影响已定界的 `$`/`$$` 区域吗？
- 有对应的单元测试（正向+负向）吗？

已知冲突模式：triangle+angle、定界符内裸括号、cases行分隔符、单位命令误拆。

## 几何图形分析

- 单次调用 + 后验证架构（af45035）
- 图形题自动走 `shouldAnalyzeImageFirst` 流程
- `GeometryDiagramWidget` 基于 CustomPaint 渲染结构化 JSON
- 下一步：升级 gpt-5.5 提升读图准确率

## 近期方向

1. PDF 导出（家长打印练习）
2. 生成练习题质量优化（fallback 题与原题关联度）
3. 模型升级 gpt-5.5
4. 拍照框选/裁剪提效
