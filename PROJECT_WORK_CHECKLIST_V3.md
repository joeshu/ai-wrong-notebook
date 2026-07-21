# v3.0 设计方案落地任务清单

> 更新时间:2026-07-21
> 基线:`main` commit `01c83bc`(Phase 4 已收口)
> 对照文档:《AI 错题本 产品设计方案 v3.0》
> 使用方式:完成一项后勾选 `[x]`,并在提交中记录对应 commit

## 现状总览

| 模块 | 状态 | 主要差距 |
|---|---|---|
| 底部导航 | ❌ | 4 入口 → 需扩到 6 入口(加"添加""知识树") |
| 首页 | 🟡 | 今日行动非统一面板;缺知识树快照、7 天趋势 |
| 添加采集 | ✅🟡 | 4 入口齐全;缺批量绑定知识点 |
| 错题列表 | 🟡 | 仅卡片视图;筛选/排序维度不足 |
| 复习中心 | 🟡 | 评价规则齐全;缺模式切换、统计、闭环刷新 |
| 知识树 | ❌ | 无独立页面;模型无类型化层级 |
| 设置 | 🟡 | 缺学习设置/知识树管理/关于三大区块 |
| 识别引擎 | ✅🟡 | 6 引擎齐全;三处入口不一致、无分阶段进度 |
| 校对页 | 🟡 | 完整能力仅在 worksheet_region_editor;三屏名不副实 |
| 错题详情 | 🟡 | 4 Tab 齐全;缺知识点关联区、AI 区不可折叠 |
| 组卷 | 🟡 | 草稿管理好;缺智能组卷、参数、预览 |
| 导出工作台 | ✅🟡 | 6 格式 + 3 模板 + 筛选/排版/预览/sticky 条齐全;缺 Word/图片、入口分散、内容选项不足、桌面端 PDF 公式不渲染 |
| 状态模型 | ✅ | 四维状态完整 |

---

# Phase 5:导航重构与知识树页面(P0) ✅ 基本完成(CI 通过)

## 1. 底部导航 6 入口

- [x] 新增"添加"Tab(图标 `CupertinoIcons.plus_circle`),路由 `/add`,内容为 `CaptureEntrySheet` 持久化版
- [x] 新增"知识树"Tab(路由 `/knowledge-tree`);注:`CupertinoIcons.tree_documentation` 在当前 SDK 不存在,改用 `Icons.account_tree_outlined`
- [x] 调整导航顺序为:首页 / 添加 / 错题 / 复习 / 知识树 / 设置
- [x] 首页"+"按钮改为跳转 `/add` Tab
- [x] 更新 [router.dart](file:///workspace/lib/src/app/router.dart) `StatefulShellRoute.indexedStack` branches
- [x] 更新 [app_strings.dart](file:///workspace/lib/src/core/constants/app_strings.dart) Tab 常量
- [x] 验证各 Tab 状态独立保持(`StatefulShellRoute.indexedStack` 内置各 branch 独立栈)

## 2. 知识树页面骨架

- [x] 新建 `lib/src/features/knowledge_tree/presentation/knowledge_tree_screen.dart`
- [x] 顶部科目筛选 chip(全部 + Subject.values,含数学/物理/化学/英语等)
- [x] 树形结构展示(自建 `_KnowledgeTreeTile` 递归,可展开/折叠)
- [x] 节点行:名称 + 掌握度胶囊 + 错题数
- [x] 点击节点进入知识点详情页
- [x] 接入 `knowledgePointTreeProvider` + `weakPointRecommendationsProvider`(合并为 `knowledgeTreeOverviewProvider`)

## 3. 知识树热力图与统计

- [x] 掌握度 4 档颜色映射(0-30% 红 / 31-60% 橙 / 61-85% 绿 / 86-100% 深绿)
- [x] 4 档配色在 UI 层 `_masteryColor` 实现(未改 `MasteryLevel` 阈值,避免影响现有掌握度判定逻辑)
- [x] 薄弱知识点 TOP5(基于 `KnowledgePointMastery.masteryPercentage` 升序 take(5))
- [x] 掌握度分布卡(掌握/一般/模糊三档题数 + 占比)

## 4. 知识点详情页

- [x] 新建 `lib/src/features/knowledge_tree/presentation/knowledge_point_detail_screen.dart`
- [x] 顶部:科目面包屑 + 知识点名 + 掌握度进度条
- [x] 统计区:错题数 / 待复习数 / 正确率(三宫格)
- [x] 错题列表(该知识点下所有题,通过 `questionIdsForKnowledgePoint`)
- [x] 专项练习入口(跳 `KnowledgePointPracticeController.buildRound`,`PracticeContext.returnRoute='/knowledge-tree'`)
- [ ] 学习建议(基于复习历史生成文案)— 延后
- [ ] "在知识树中查看"按钮(返回树并定位节点)— 延后

## 5. 知识树模型类型化(可选,延后)

- [ ] `KnowledgePoint` 加 `level` 字段(0=科目 / 1=模块 / 2=章节 / 3=知识点 / 4=考点)
- [ ] 迁移现有数据(根据 parentId 深度推断 level)
- [ ] 种子数据补全到 4-5 层(模块层缺失)

---

# Phase 6:错题列表与详情页升级(P0)

## 1. 错题列表三视图

- [ ] 新增视图切换控件(卡片 / 列表 / 时间线)
- [ ] 卡片视图(已有,保留)
- [ ] 列表视图(紧凑表格:科目/题型/知识点/状态/掌握度)
- [ ] 时间线视图(按日期分组:添加/复习/分析事件流)
- [ ] 视图偏好持久化到 SharedPreferences

## 2. 筛选与排序补全

- [ ] 新增题型筛选(QuestionType 下拉)
- [ ] 新增独立识别状态筛选(待识别/识别中/待校对/已识别/识别失败)
- [ ] 新增 AI 状态筛选(未分析/分析中/已分析/分析失败)
- [ ] 新增掌握度三档筛选(模糊/一般/掌握)替代现有二态
- [ ] 新增"已掌握"快速 chip
- [ ] 排序新增:按掌握度(低到高)、按科目、按知识点
- [ ] 更新 [providers.dart](file:///workspace/lib/src/app/providers.dart) `QuestionSort` 枚举

## 3. 错题详情页知识点关联区

- [ ] `QuestionKnowledgeLink` 加 `isPrimary` 字段(主知识点 vs 关联知识点)
- [ ] 数据迁移:现有 link 默认 `isPrimary = true`
- [ ] 详情页新增"知识点关联"区块(独立 section 或新 Tab)
- [ ] 主知识点行:名称 + 该知识点掌握度徽章 + "在知识树中查看"
- [ ] 关联知识点列表:名称 + 掌握度
- [ ] "添加关联知识点"按钮(弹 `_KnowledgePointPickerDialog`)
- [ ] "设为主知识点"操作(长按或菜单)
- [ ] 接入 `knowledgePointMasteryServiceProvider` 显示掌握度

## 4. 错题详情页 AI 分析区折叠

- [ ] `AppInfoSection` 加展开/折叠能力(用 `ExpansionTile` 或自定义)
- [ ] 默认折叠长内容(解题步骤、学习建议)
- [ ] 顶部摘要补展示主知识点标签

## 5. 学习记录区增强

- [ ] 读取 `ReviewLog` 列表展示复习历史时间线
- [ ] 掌握度变化轨迹(简单文字链:模糊→一般→掌握)
- [ ] 后续可升级为迷你折线图(Phase 8)

---

# Phase 7:复习中心闭环(P1)

## 1. 复习模式切换

- [ ] 复习中心顶部新增模式选择:顺序 / 随机 / 专项
- [ ] 顺序模式:按 nextReviewAt 升序
- [ ] 随机模式:打乱顺序
- [ ] 专项模式:从薄弱知识点 TOP 列表选择,加载该知识点题目
- [ ] 薄弱点专项复习入口卡(显示 TOP5 + 题数 + "开始专项")

## 2. 复习界面作答步骤

- [ ] 题目展示后加"作答"输入框(文本/选择)
- [ ] "提交作答"按钮 → 显示答案与解析 → 对照评价
- [ ] 作答记录写入 `ReviewLog`(可选,延后)

## 3. 复习统计

- [ ] 近 7 天复习数(从 `ReviewLog` 按日聚合)
- [ ] 掌握率(mastered / 总题数)
- [ ] 连续复习天数(复用 `todayReviewPlanProvider` 的 `streakDays`)
- [ ] 统计卡显示在复习中心顶部

## 4. 复习后更新知识树掌握度

- [ ] `ReviewController._applyRating` 评分成功后触发 `KnowledgePointMasteryService.calculate` 重算相关知识点
- [ ] invalidate `weakPointRecommendationsProvider` 刷新首页薄弱卡片
- [ ] invalidate 知识树页面 provider(Phase 5 新增)

---

# Phase 8:首页与组卷升级(P1)

## 1. 首页今日行动面板统一

- [ ] 合并 `_BatchActionCard` + `_TodayPlanCard` 为统一行动面板
- [ ] 3 行动卡:待复习 / 添加新错题 / 继续未完成识别
- [ ] 动态优先级:复习优先 → 识别优先 → 添加优先(按文档规则)
- [ ] 空状态引导(无任何待办时)

## 2. 首页知识树快照

- [ ] 新增区块:各科目掌握度进度条(数学/物理/化学...)
- [ ] 点击跳转 `/knowledge-tree` 并定位该科目
- [ ] 数据源:按科目聚合 `KnowledgePointMastery`

## 3. 首页学习趋势折线图

- [ ] 新增区块:近 7 天复习数 + 掌握数折线图
- [ ] 数据源:从 `ReviewLog` 按日聚合
- [ ] 复用 `stats_chart.dart` 或新增 `LineChart` 组件

## 4. 组卷系统升级

- [ ] 组卷入口扩展:知识树详情页 / 复习中心
- [ ] 新增"按知识点组卷"模式(从知识树多选知识点)
- [ ] 新增"智能推荐组卷"模式(基于 `RecommendationService` 薄弱点)
- [ ] 组卷参数设置页:总题数 / 难度分布(基础60% 进阶30% 提高10%) / 题型分布
- [ ] 试卷预览页(正式预览,非页数估算)
- [ ] 智能选题算法(按参数从题库筛选 + 去重 + 补足)

---

# Phase 9:知识树管理与设置补全(P2)

## 1. 知识树管理 UI

- [ ] 新建 `lib/src/features/knowledge_tree/presentation/knowledge_tree_management_screen.dart`
- [ ] 接入 `KnowledgePointManagementService`(create/rename/move/merge/delete/setEnabled)
- [ ] 树形编辑器:新增 / 重命名 / 移动 / 合并 / 删除节点
- [ ] 启用/停用切换
- [ ] 入口:设置页"知识树管理"区块 + 知识树页面右上角编辑按钮

## 2. 知识树模板

- [ ] 新建 `lib/src/domain/models/knowledge_point_template.dart` 模板注册
- [ ] 预设模板:初中数学人教版 / 北师大版 / 高中数学 / 高中物理 / 自定义
- [ ] 模板导入流程(选择模板 → 预览 → 确认覆盖/合并)
- [ ] 导出当前知识树为 JSON
- [ ] 重置为默认(二次确认)

## 3. 设置页·学习设置区块

- [ ] 新增"学习设置"区块(在"提醒"和"AI 服务"之间)
- [ ] 每日复习目标(从 `/goals` 迁移或保留独立路由并在设置页加入口)
- [ ] 复习提醒时间设置(扩展 `NotificationService` 支持定时)
- [ ] 难度偏好下拉(基础/中等/挑战)
- [ ] 知识树显示层级下拉(科目/模块/章节/知识点)

## 4. 设置页·关于区块

- [ ] 新增"关于"区块(底部)
- [ ] 版本号显示(从 `pubspec.yaml` 读取)
- [ ] 检查更新入口(预留,Phase 11)
- [ ] 使用帮助(跳帮助页或弹窗)
- [ ] 反馈建议(跳 GitHub issues 或邮件)

## 5. 设置页·配置状态聚合

- [ ] 设置页"AI 服务"区块加状态徽章(普通AI ✓ / PaddleOCR ⚠ / MinerU ✗)
- [ ] 一眼可见所有引擎就绪状态
- [ ] 点击徽章跳对应配置页

---

# Phase 10:识别引擎与校对页统一(P2)

## 1. 引擎选项一致性

- [ ] 统一三处入口(capture_entry_sheet / analysis_loading_screen / worksheet_region_editor)的引擎选项为完整 6 种
- [ ] 抽取公共 `_EngineChoiceSheet` 组件
- [ ] 未配置引擎统一禁用 + "去设置"跳转

## 2. 分阶段进度条

- [ ] PaddleOCR 识别进度分阶段(图片上传 → 文字识别 → 公式提取 → 结构分析)
- [ ] MinerU 识别进度分阶段(同上 + VLM 解析)
- [ ] Auto 策略进度条(3 步骤升级为阶段条)
- [ ] 复用 `_StageIndicator` 组件样式

## 3. "是否交给 AI"决策统一

- [ ] 决策弹窗在 autoCloud / 默认 currentVision 路径也触发
- [ ] 或在设置页加"识别后默认是否交给 AI"开关

## 4. 校对页统一

- [ ] 评估是否废弃 `question_correction_screen`(实为预览页)
- [ ] `question_save_confirmation_screen` 接入 `FieldStatus` 5 态徽章
- [ ] `question_split_confirmation_screen` 接入 `FieldStatus` 5 态徽章
- [ ] 三屏统一提供 LaTeX 公式独立编辑入口
- [ ] 三屏统一提供"重新识别/换引擎"入口(条件显示)

---

# Phase 11:导出工作台保留并优化(P2)

> 现状:[export_workbench_screen.dart](file:///workspace/lib/src/features/settings/presentation/export_workbench_screen.dart) 已是统一入口页(876 行),支持 6 格式(HTML/PDF/Markdown/Anki/CSV/JSON)+ 3 模板(错题报告/学习报告/复习卡)+ 筛选/内容选项/排版选项/预览/sticky 导出条。本 Phase 保留现有架构,在此基础上优化与补全。

## 1. 入口与发现性优化

- [ ] 设置页"导出工作台"入口提升优先级(从"学习分析"区块提到独立区块或顶部)
- [ ] 错题本多选模式加"导出选中题"快捷入口(直接跳工作台并预选)
- [ ] 组卷工作台加"导出本组卷"入口(预填选中题 ID)
- [ ] 知识点详情页加"导出该知识点错题"入口(Phase 5/6 完成后接线)
- [ ] 导出工作台支持预填 `initialQuestionIds` 参数(从入口传入筛选条件)

## 2. 模板系统增强

- [ ] 新增"试卷模板"(题目 + 答案分离,适合打印考试)
- [ ] 新增"错题卡模板"(单题一卡,适合裁剪复习)
- [ ] 模板预览缩略图(选择模板时显示样例截图)
- [ ] 模板支持自定义(保存当前内容选项组合为自定义模板)
- [ ] 模板说明文档(每个模板适用场景)

## 3. 格式扩展

- [ ] 新增 Word 导出(`docx` 包,基于模板,优先支持错题报告模板)
- [ ] 新增图片导出(逐题 PNG,基于 `RepaintBoundary` 截图)
- [ ] 移动端直接打印入口(走 `printing` 包)
- [ ] Anki 导出增强(.apkg 包,支持图片媒体包)
- [ ] 导出格式分组:文档类(HTML/PDF/Word/MD) vs 数据类(CSV/JSON/Anki)

## 4. 筛选与内容选项

- [ ] `ExportContentOptions` 新增 `includeOcrText`(识别文本)
- [ ] `ExportContentOptions` 新增 `includeAiAnalysis`(完整 AI 分析)
- [ ] `ExportContentOptions` 新增 `includeReviewHistory`(复习历史)
- [ ] `ExportContentOptions` 新增 `includeKnowledgeTree`(知识点树路径)
- [ ] 导出工作台 UI 加上述选项开关
- [ ] 筛选支持按知识点多选(从知识树选择)
- [ ] 筛选支持按掌握度三档
- [ ] 筛选支持按难度(QuestionDifficulty)
- [ ] 筛选条件持久化(下次进入保留上次筛选)

## 5. PDF 排版优化

- [ ] 桌面端 PDF 公式渲染(集成 KaTeX 或 MathJax-node,替代源码输出)
- [ ] 移动端纸张大小生效(A4/A5/Letter/B5,当前硬编码 A4)
- [ ] 公式字体回退方案优化(桌面端 CJK + 数学符号)
- [ ] PDF 目录(TOC)支持知识点分组
- [ ] PDF 封面支持自定义标题/学生姓名/日期
- [ ] PDF 页眉页脚支持知识点路径
- [ ] 长题干自动分页优化(避免题图与题干分离)

## 6. 预览能力

- [ ] HTML 预览支持知识点分组折叠
- [ ] PDF 预览(生成后用 `printing` 或系统查看器预览)
- [ ] 预览支持快速返回调整(保留上次选项)
- [ ] 预览页加"导出为其他格式"快捷按钮

## 7. 导出执行与反馈

- [ ] 导出进度对话框显示当前格式 + 总进度(已有,优化文案)
- [ ] 多格式批量导出时显示文件列表
- [ ] 导出失败按格式分别提示(部分成功允许保留成功文件)
- [ ] 导出历史记录(最近 10 次导出,可重新下载)
- [ ] 导出文件命名规范优化(模板名_科目_日期.格式)

## 8. 组卷导出模式

- [ ] `WorksheetExportMode`(practice/answer/correction)集成到工作台
- [ ] practice 模式:仅题目,无答案
- [ ] answer 模式:题目 + 答案 + 解析
- [ ] correction 模式:题目 + 学生答案 + 正确答案 + 错因
- [ ] 模式切换影响内容选项默认值

## 9. 质量保障

- [ ] 导出回归测试覆盖新增 Word/图片格式
- [ ] 导出回归测试覆盖新内容选项(OCR/AI/复习历史/知识点树)
- [ ] 桌面端 PDF 公式渲染验收
- [ ] 移动端纸张大小切换验收
- [ ] 大题量(100+ 题)导出性能与内存
- [ ] 空字段/缺失附件导出不报错

---

# Phase 12:掌握度算法与数据管理(P2)

## 1. 掌握度算法补全

- [ ] `KnowledgePointMasteryService.calculate` 加"最近复习正确率"因子(权重 40%)
- [ ] 加"累计复习次数"正向因子(权重 20%)
- [ ] 加"难度分布"因子(权重 10%)
- [ ] 调整现有因子权重(错因扣分 / 新题占比降权)
- [ ] 单测覆盖新算法

## 2. 数据管理补全

- [ ] 清理缓存入口(独立于"清空所有数据")
  - [ ] 清理图片缓存(`CachedNetworkImage` 缓存)
  - [ ] 清理临时题图(`worksheet_import` 生成的裁切图)
  - [ ] 清理 AI 响应缓存
- [ ] 备份包包含知识点树(序列化 `KnowledgePoint` + `QuestionKnowledgeLink`)
- [ ] 备份包包含组卷草稿(`WorksheetDraft`)
- [ ] 云端备份(WebDAV / iCloud Drive,Phase 13 评估)

## 3. 引擎配置增强

- [ ] `AiProviderConfig` 加 `timeout` 字段
- [ ] `provider_config_screen` 加超时设置输入
- [ ] AI 服务类型选择下拉(OpenAI / Anthropic / 自定义)

---

# Phase 13:高级功能(P3,未来)

- [ ] 智能组卷算法(基于薄弱点 + 难度 + 题型的加权选题)
- [ ] 跨知识点关联分析(图谱)
- [ ] 学习报告生成(周报 / 月报)
- [ ] 云端同步(WebDAV / iCloud)
- [ ] 多人协作 / 班级管理
- [ ] FSRS 复习算法替换现有固定间隔
- [ ] AI 生成变式题(举一反三真实生成)

---

# 推进顺序建议

## 当前迭代(Phase 5,2-3 周)

1. [ ] 底部导航 6 入口
2. [ ] 知识树页面骨架 + 热力图
3. [ ] 知识点详情页
4. [ ] 提交 + CI + 合并

## 下一迭代(Phase 6,2 周)

1. [ ] 错题列表三视图
2. [ ] 筛选排序补全
3. [ ] 详情页知识点关联区
4. [ ] AI 区折叠 + 学习记录增强

## 再下一迭代(Phase 7-8,2-3 周)

1. [ ] 复习模式切换 + 闭环刷新
2. [ ] 首页今日行动面板统一
3. [ ] 组卷系统升级

## 后续(Phase 9-12,按需)

1. [ ] 知识树管理 + 模板
2. [ ] 设置页补全
3. [ ] 识别引擎统一
4. [ ] 导出工作台优化(入口/模板/格式/内容选项/PDF/预览/组卷模式)
5. [ ] 掌握度算法升级

---

# 完成定义

- [ ] 底部导航 6 入口,知识树独立 Tab
- [ ] 知识树页面:树形 + 热力图 + TOP5 + 详情页
- [ ] 错题列表三视图 + 完整筛选排序
- [ ] 详情页:知识点关联区 + AI 区可折叠 + 学习记录时间线
- [ ] 复习中心:三模式 + 闭环刷新 + 7 天统计
- [ ] 首页:统一行动面板 + 知识树快照 + 7 天趋势
- [ ] 组卷:4 种方式 + 参数 + 预览
- [ ] 导出工作台:Word/图片格式 + 多入口 + 桌面端 PDF 公式渲染 + 组卷导出模式
- [ ] 设置:学习设置 + 知识树管理 + 关于 + 状态聚合
- [ ] `flutter analyze`、`flutter test`、构建检查全部通过
