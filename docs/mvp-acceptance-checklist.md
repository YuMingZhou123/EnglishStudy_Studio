# 第一版 MVP 验收清单

版本：v0.1
日期：2026-05-28
状态：工程主链路已跑通，内容规模与真实用户内测仍需继续推进

## 1. 验收目标

第一版的核心目标是验证“语境听写”学习闭环是否可用：

```text
注册/登录 -> 学习首页 -> 三档语境听写 -> 提交判题 -> 错词入库 -> 错词复习 -> 学习记录
```

管理端需要支撑最小内容生产闭环：

```text
管理员登录 -> 维护场景/单词/句子 -> 上传或生成音频 -> 发布句子 -> 用户端可练习
```

## 2. 当前验收命令

本地基础设施启动：

```powershell
docker compose -f infra/docker-compose.yml up -d
```

后端启动：

```powershell
dotnet run --project apps/api --launch-profile http
```

前端启动：

```powershell
cd apps/web
npm run dev
```

主链路 smoke test：

```powershell
.\scripts\smoke-test.ps1
```

包含 TTS 的完整 smoke test：

```powershell
.\scripts\smoke-test.ps1 -IncludeTts
```

页面级 smoke test：

```powershell
node .\scripts\ui-smoke-test.mjs
```

导入 MVP 内容包：

```powershell
.\scripts\validate-mvp-content.ps1
.\scripts\import-mvp-content.ps1
```

构建检查：

```powershell
dotnet build EnglishStudy.Studio.slnx
cd apps/web
npm run lint
npm run build
```

## 3. 产品验收映射

| 验收项 | 当前状态 | 证据 |
| --- | --- | --- |
| 用户可以注册登录 | 已实现 | 登录页、`POST /api/auth/register`、`POST /api/auth/login`、smoke test 登录 learner/admin |
| 用户可以选择学习目标和当前水平 | 已实现 | 注册页选择项、学习台资料设置、`PUT /api/auth/me` |
| 用户可以进入学习首页 | 已实现 | `/dashboard` |
| 用户可以完成初级语境听写 | 已实现 | `GET /api/dictation/next?mode=beginner`、`POST /api/dictation/submit`、smoke test |
| 用户可以完成中级语境听写 | 已实现 | `mode=intermediate`、smoke test |
| 用户可以完成高级整句听写 | 已实现 | `mode=advanced`、服务端整句评分、smoke test |
| 用户可以播放音频 | 已实现 | 听写页 `<audio>` 播放、媒体 API 回读、浏览器 TTS fallback |
| 用户可以慢速播放 | 已实现 | 听写页 `playbackRate=0.75`，存在慢速音频时优先使用 `slowAudioUrl` |
| 用户可以使用首字母提示 | 已实现 | 听写页首字母按钮，后端返回 `firstLetter` |
| 用户可以使用中文提示 | 已实现 | 听写页中文提示按钮，后端返回目标词中文释义 |
| 用户提交答案后可以看到反馈 | 已实现 | 听写结果区显示分数、正确/错误、完整句子、翻译和目标词 |
| 答错词可以进入错词本 | 已实现 | `UserWordState` 状态流转、`GET /api/vocabulary/words`、smoke test wrongScore |
| 用户可以进行错词复习 | 已实现 | `/vocabulary`、`GET /api/vocabulary/review/next`、smoke test |
| 用户可以查看基础学习记录 | 已实现 | `/reports`、`GET /api/dictation/history`、`GET /api/dictation/summary` |
| 管理员可以录入并发布句子 | 已实现 | `/admin`、句子创建/发布/下架 API、smoke test |
| 管理员可以维护单词 | 已实现 | `/admin`、单词创建/编辑 API、smoke test |
| 管理员可以维护场景 | 已实现 | `/admin`、场景创建/编辑/启停 API、smoke test |
| 管理员可以上传音频到 MinIO | 已实现 | `POST /api/admin/media/upload`、smoke test |
| 管理员可以生成 TTS 音频并绑定句子 | 已实现 | `POST /api/admin/sentences/{id}/generate-audio`、`.\scripts\smoke-test.ps1 -IncludeTts` |

## 4. 技术验收映射

| 验收项 | 当前状态 | 证据 |
| --- | --- | --- |
| 前端项目可以本地启动 | 已验证 | `http://localhost:3000` 返回 200，smoke test |
| 后端项目可以本地启动 | 已验证 | `http://localhost:5180/health` 返回 Healthy |
| Swagger 可以访问 | 已验证 | `http://localhost:5180/swagger/index.html` 返回 200，smoke test |
| PostgreSQL 可以连接 | 已验证 | `/health/ready` database Healthy |
| MinIO 可以访问 | 已验证 | `/health/ready` storage Healthy |
| 音频可以上传到 MinIO | 已验证 | `POST /api/admin/media/upload`，smoke test |
| 前端可以播放媒体 API 音频 | 基础能力已具备 | 听写页使用 `<audio>`；smoke test 已验证媒体 API 可回读，仍建议浏览器手工听一次 |
| 答题记录可以保存到 PostgreSQL | 已验证 | 提交后 `history` 和 `summary` 数量变化，smoke test |
| EF Core 迁移可执行 | 已验证 | API 开发环境启动自动 `MigrateAsync`，`dotnet build` 通过 |
| DDD 分层边界清晰 | 已实现 | `Domain/Application/Infrastructure/Controllers`，`Domain/Dictation` 已承载核心规则 |

## 5. 当前未完全完成的非代码项

以下事项不阻塞工程 MVP 跑通，但阻塞“正式内测/商业化前”的完整完成：

| 事项 | 当前状态 | 下一步 |
| --- | --- | --- |
| 第一批内容规模 100 到 300 句 | 已有可导入内容包 | `content/mvp-sentence-pack.json` 提供 120 条原创句子，运行 `.\scripts\import-mvp-content.ps1` 导入 |
| 核心词 300 到 800 个 | 已达到 MVP 下限 | 内容包提供 335 个目标词配置项、324 个独立词形；内容质量仍需人工审核 |
| 5 到 10 名真实用户内测 | 未完成 | 用 smoke test 确认环境后，安排用户按清单试用并收集反馈 |
| 前端真实听音体验 | 待人工验收 | 浏览器中手工播放上传音频和 TTS 音频，确认音量、加载、慢速体验 |
| 内容质量审核 | 待完善 | 为每条句子检查英文自然度、中文翻译、关键词位置、音频质量 |

## 6. 内测手工验收流程

每位内测用户按以下流程走一遍：

1. 打开 `http://localhost:3000`。
2. 注册或使用演示账号登录。
3. 设置当前水平和学习目标。
4. 在学习首页进入语境听写。
5. 分别完成初级、中级、高级各 2 题。
6. 故意答错 1 题，确认错词进入词汇本。
7. 从词汇本进入复习，完成 1 题。
8. 打开学习记录，确认练习明细和统计变化。
9. 用管理员账号进入 `/admin`，新增并发布 1 条句子。
10. 回到用户端确认新句子可被练习。

## 7. 第一版完成判断

工程第一版可以认为“可内测”的条件：

- `.\scripts\smoke-test.ps1 -IncludeTts` 通过。
- `node .\scripts\ui-smoke-test.mjs` 通过。
- `.\scripts\validate-mvp-content.ps1` 可以通过内容结构校验。
- `.\scripts\import-mvp-content.ps1` 可以成功导入 120 条 MVP 句子包。
- `dotnet build EnglishStudy.Studio.slnx` 通过。
- `npm run lint` 和 `npm run build` 通过。
- 浏览器手工走完内测流程，无阻断问题。

产品第一版可以认为“可对外小范围试用”的条件：

- 内容库达到至少 100 条高质量句子。
- 每条发布句子都有可播放音频或可接受的浏览器 TTS fallback。
- 5 到 10 名用户能独立完成第一轮练习。
- 用户能理解三种难度，并愿意继续做下一题。
