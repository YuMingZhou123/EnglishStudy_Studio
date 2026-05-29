# 第一版当前状态

更新时间：2026-05-29 08:46
分支：`develop`  
当前结论：工程 MVP 已经基本跑通，可以进入人工内容审核和真实用户内测；但还不能宣布第一版完成。

## 1. 总体进度

| 范围 | 状态 | 说明 |
| --- | --- | --- |
| 产品与技术文档 | 已完成第一版 | PRD、功能规格、技术架构、开发计划、DDD 架构、权限模型、MVP 范围和开发流程文档已建立 |
| 工程骨架 | 已完成 | `apps/api` 后端、`apps/web` 前端、`infra` 本地 PostgreSQL + MinIO、`scripts` 辅助脚本已建立 |
| 后端核心链路 | 已实现并通过自动化检查 | 登录注册、用户资料、听写取题、提交判题、错词、学习记录、后台内容管理、媒体存储、TTS 音频生成 |
| 前端核心链路 | 已实现并通过自动化检查 | 登录、学习台、三档听写、词汇本、学习记录、后台内容管理，已覆盖桌面和移动视口 smoke test |
| DDD 分层 | 已建立并通过边界检查 | 当前采用模块化单体，后端按 Domain / Application / Infrastructure / Controllers 分层 |
| 权限模型 | 第一版完整模型已建立，启用核心权限 | 已包含 `User`、`Role`、`Permission`、`UserRole`、`RolePermission`，后台内容接口已校验 `content:manage` |
| MVP 内容包 | 已准备并通过结构与质量体检 | 120 条句子、5 个场景、335 个关键词配置项、324 个独立词形 |
| 本地音频覆盖 | 已达标 | 本地已发布句子缺失音频为 0 |
| 自动化验证 | 已通过完整本地检查 | `.\scripts\check-mvp-readiness.ps1 -IncludeBuild` 已通过 API smoke、UI smoke、领域规则、后端构建、前端 lint 和前端构建 |
| 人工内容审核 | 未完成 | 审核表已生成，但 120 行均未填写审核结果 |
| 真实用户内测反馈 | 未完成 | 反馈表已生成，但还没有真实内测用户记录 |

## 2. 最新 readiness 结果

运行命令：

```powershell
.\scripts\check-mvp-readiness.ps1 -IncludeBuild
```

关键结果：

| 指标 | 当前值 | 含义 |
| --- | --- | --- |
| `automatedReady` | `true` | 工程自动化、内容规模、权限、音频覆盖等检查已通过 |
| `productReviewReady` | `false` | 人工内容审核和内测反馈还没达标 |
| `firstVersionReady` | `false` | 第一版还不能宣布完成 |

本轮完整检查已通过：

- `content-pack`
- `content-quality-audit`
- `ddd-boundaries`
- `domain-rules`
- `api-health`
- `api-ready`
- `web-home`
- `admin-content-counts`
- `permission-policy`
- `database-audio-coverage`
- `api-smoke-tts`
- `ui-smoke`
- `dotnet-build`
- `web-lint`
- `web-build`

人工验收 CSV 当前也已通过格式和可统计字段校验：

| 校验项 | 当前值 | 说明 |
| --- | --- | --- |
| `contentReviewValidation.valid` | `true` | 内容审核表结构和状态字段合法 |
| `betaFeedbackValidation.valid` | `true` | 内测反馈表结构和关键枚举字段合法 |

内容审核门槛：

| 指标 | 当前值 | 达标要求 |
| --- | ---: | --- |
| 总行数 | 120 | `>= 120` |
| 通过行数 | 0 | `>= 100` |
| 需修复行数 | 0 | `0` |
| 空白行数 | 120 | `0` |
| 每个场景通过数 | 0 | `>= 15` |
| 每个难度通过数 | 0 | `>= 15` |

内测反馈门槛：

| 指标 | 当前值 | 达标要求 |
| --- | ---: | --- |
| 已填写用户 | 0 | 建议至少 5 |
| 完成测试用户 | 0 | `>= 5` |
| 独立完成用户 | 0 | `>= 4` |
| 理解难度用户 | 0 | `>= 4` |
| 愿意继续下一题用户 | 0 | `>= 3` |
| P0 问题 | 0 | `0` |

## 3. 已实现的第一版能力

用户端：

- 注册、登录、获取当前用户、更新用户资料。
- 学习首页。
- 初级关键词填空。
- 中级多关键词填空。
- 高级整句听写。
- 原速播放和慢速播放。
- 首字母提示和中文提示。
- 提交答案、展示分数、正确答案、翻译和目标词释义。
- 答错词进入错词本。
- 错词复习。
- 学习记录和基础统计。

管理端：

- 管理员登录。
- 场景管理。
- 单词管理。
- 句子管理。
- 句子发布和下架。
- 批量导入句子。
- 上传音频到 MinIO。
- 生成句子 TTS 音频。
- 为缺失音频的已发布句子批量生成音频。

技术能力：

- ASP.NET Core Web API 后端。
- Next.js + React + TypeScript 前端。
- PostgreSQL 数据库。
- MinIO 对象存储。
- EF Core 迁移。
- 本地健康检查和 ready 检查。
- DDD 边界检查脚本。
- 听写领域规则测试。
- API smoke test。
- 页面级 smoke test。
- MVP readiness 汇总脚本。
- 内容审核和内测反馈生成、会话启动、导入、汇总脚本。
- 本地验收看板和任务清单生成脚本。

## 4. 当前不能算完成的原因

第一版目标不是只把代码写完，还要证明它能被真实使用。当前代码层面已经到“可内测”的状态，但还缺两个产品验收动作：

1. 人工审核 120 条 MVP 句子，确认英语、翻译、关键词和难度没有明显问题。
2. 找 5 到 10 名真实用户走完整流程，记录是否能独立完成、是否理解难度、是否愿意继续使用。

这两个结果需要真实填写，不能由脚本自动伪造。

## 5. 下一步执行顺序

先准备人工验收入口：

```powershell
.\scripts\start-first-version-work.ps1 -Open
.\scripts\prepare-mvp-acceptance.ps1 -Open
```

然后按生成的任务清单执行。优先使用会话启动脚本，它会自动定位下一批内容或下一位测试用户：

```powershell
.\scripts\start-content-review-batch.ps1 -Open
.\scripts\start-beta-feedback-session.ps1 -Open
```

关键入口：

```text
acceptance/mvp-acceptance-dashboard.html
acceptance/mvp-acceptance-tasks.md
acceptance/first-version-work-session.md
acceptance/content-review-session.md
acceptance/beta-feedback-session.md
content/mvp-content-review.html
feedback/internal-beta-feedback.html
```

内容审核完成后：

```powershell
.\scripts\import-acceptance-csv.ps1 -Kind content -ValidateOnly
.\scripts\import-acceptance-csv.ps1 -Kind content -RefreshArtifacts
```

每轮内测反馈完成后：

```powershell
.\scripts\import-acceptance-csv.ps1 -Kind beta -ValidateOnly
.\scripts\import-acceptance-csv.ps1 -Kind beta -RefreshArtifacts
```

最终验收：

```powershell
.\scripts\check-mvp-readiness.ps1 -IncludeBuild
.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady
```

只有当输出同时满足下面三个结果时，才能宣布第一版完成：

```text
automatedReady: true
productReviewReady: true
firstVersionReady: true
```
