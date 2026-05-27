# 英语学习平台技术架构设计文档

版本：v0.1  
日期：2026-05-27  
状态：初稿，待技术评审

## 1. 技术目标

本平台需要支持 PC Web、移动 H5、微信小程序三端学习体验，并提供语境听写、AI 口语、发音评测、词汇复习、学习报告和后台内容管理能力。

第一阶段技术目标：

- 快速交付 MVP。
- 前后端边界清晰。
- 支持音频播放、录音上传、AI 对话和学习记录。
- 内容数据结构可扩展，便于后续自动生成和人工审核。
- 三端尽量复用业务接口和核心逻辑。

## 2. 总体架构

```text
用户端 Web / H5 / 小程序
        |
        | HTTPS
        v
API 网关 / 后端服务
        |
        +-- 用户与权限模块
        +-- 学习任务模块
        +-- 语境听写模块
        +-- 单词复习模块
        +-- AI 口语模块
        +-- 内容管理模块
        +-- 会员与订单模块
        |
        +-- PostgreSQL
        +-- Redis
        +-- MinIO / S3 兼容对象存储
        +-- AI / ASR / TTS / 发音评测服务
```

## 3. 技术选型建议

### 3.1 推荐 MVP 方案

| 层级 | 技术 | 说明 |
| --- | --- | --- |
| Web / H5 | Next.js + React + TypeScript | 构建 PC Web 与移动 H5，适合页面路由、SEO、学习端体验和后续增长页 |
| UI | Tailwind CSS + shadcn/ui | 快速搭建一致、现代、可维护的学习端和管理端界面 |
| 小程序 | Taro + React + TypeScript | 后续复用 React 经验接入微信小程序，不进入第一阶段 MVP |
| 后端 | ASP.NET Core Web API + C# | 独立后端服务，业务逻辑清晰，适合个人开发和长期扩展 |
| 数据库 | PostgreSQL | 结构化业务数据、学习记录、内容库 |
| 缓存 | Redis | 验证码、会话、限流、排行榜、短期任务状态 |
| ORM | Entity Framework Core | 与 ASP.NET Core 配套成熟，支持模型映射、迁移和 LINQ 查询 |
| 接口文档 | Swagger / OpenAPI | 自动生成接口文档，便于前后端联调和 AI 辅助开发 |
| 文件存储 | MinIO，S3 兼容对象存储 | 本地和 MVP 默认使用 MinIO 保存音频、录音、图片，生产可切换 OSS / R2 / COS |
| AI 服务 | 可插拔 Provider | 支持后续替换 LLM、ASR、TTS、发音评测供应商 |

### 3.2 备选方案

如果未来团队更熟悉 Java：

- 后端可使用 Spring Boot + MyBatis Plus。
- 前端仍可使用 Next.js。
- AI 服务封装为独立 Provider 层。

如果希望前后端统一 TypeScript：

- 后端可使用 NestJS + Prisma。
- 优点是语言统一，缺点是后端工程边界不如 C# / Java 对传统后端开发者直观。

如果希望最快覆盖小程序、H5 和 App：

- 可考虑 uni-app。
- 代价是复杂交互和大型 Web 管理端体验可能不如 React / Next.js 方案。

### 3.3 本项目确认方案

本项目第一版确认使用：

```text
前端：Next.js + React + TypeScript + Tailwind CSS + shadcn/ui
后端：ASP.NET Core Web API + C#
后端架构：DDD 风格模块化单体
数据库：PostgreSQL
ORM：Entity Framework Core
接口文档：Swagger / OpenAPI
缓存：Redis，MVP 可后置
文件存储：MinIO，本地和 MVP 默认使用；生产可切换阿里云 OSS / 腾讯云 COS / Cloudflare R2
AI 能力：后端封装 Provider，统一接入 LLM / ASR / TTS / 发音评测
```

Next.js 只承担前端页面、路由、交互和 Web/H5 体验，不作为主要后端业务承载。核心业务逻辑、数据库访问、判题、学习记录、AI 调用、权限控制均放在 ASP.NET Core 后端。

### 3.4 多端适配策略

需要明确的是，Next.js 适合 PC Web 和移动 H5，但不能直接编译成微信小程序。因此本项目的多端策略不是“一套前端代码发布所有端”，而是“统一后端 API + 分端前端适配”。

第一阶段确认支持：

- PC Web：Next.js 响应式页面。
- 移动 H5：Next.js 响应式页面，重点优化手机学习体验。
- 管理后台：优先放在 Next.js 同一前端项目中，通过 `/admin` 路由承载。

第二阶段扩展：

- 微信小程序：使用 Taro + React + TypeScript 单独开发轻量学习端。
- 小程序复用后端 API、接口类型、设计规范和核心业务规则。
- 小程序第一版只承载每日语境听写、错词复习、打卡和分享。

如果项目强要求“一套前端代码同时覆盖 H5 和微信小程序”，则应优先考虑 Taro 或 uni-app。但该方案在 PC Web、管理后台、复杂交互和长期维护体验上弱于 Next.js。因此本项目推荐先用 Next.js 做 Web/H5，把小程序作为独立轻量端后置开发。

## 4. 应用划分

### 4.1 前端应用

建议目录：

```text
apps/
  web/        # Next.js，PC Web + 移动 H5 + 管理端页面
  api/        # ASP.NET Core Web API
  miniapp/    # 微信小程序，v0.3 接入
packages/
  ui/         # 通用 UI 组件，后续抽取
  shared/     # 类型、工具函数、常量，后续抽取
  api-client/ # OpenAPI 生成或手写的接口请求封装
```

第一阶段也可以先使用单体仓库：

```text
apps/web/
apps/api/
docs/
```

待业务变复杂后再迁移到 monorepo。

### 4.2 后端 DDD 分层

本项目后端采用 DDD 风格的模块化单体。第一版不拆微服务，先在一个 ASP.NET Core Web API 工程内保持清晰边界，后续如果业务量增长，再按限界上下文拆分服务。

当前目录约定：

```text
apps/api/
  Domain/              # 领域层：核心业务对象、聚合、领域状态
    Identity/          # 用户、角色、权限
    Content/           # 场景、单词、句子、音频素材
    Learning/          # 听写记录、错词状态
  Application/         # 应用层：用例服务、DTO、接口定义
    Auth/
    Content/
    Dictation/
    Common/Interfaces/
  Infrastructure/      # 基础设施层：EF Core、MinIO、JWT、TTS Provider
    Persistence/
    Storage/
    Tts/
    Auth/
    Options/
  Controllers/         # 接口层：HTTP API 入口，只做鉴权、参数接收、结果返回
  Program.cs
```

分层依赖方向：

```text
Controllers -> Application -> Domain
Infrastructure -> Application / Domain
Program.cs 负责组合依赖注入
```

实现约定：

- `Domain` 不依赖 EF Core、HTTP、MinIO、TTS、JWT 等外部技术。
- `Application` 编排业务用例，例如注册登录、出题、提交判题、内容管理。
- `Application/Common/Interfaces` 定义外部能力接口，例如数据库上下文、文件存储、TTS。
- `Infrastructure` 实现这些接口，例如 `AppDbContext`、`MinioFileStorageService`、`LocalTtsProvider`。
- `Controllers` 不直接写业务逻辑，也不直接访问数据库。
- MVP 阶段可以先使用应用服务直接协调 EF Core；当单个领域变复杂后，再补 Repository、Domain Service、领域事件等更完整的 DDD 组件。

## 5. 核心领域模型

### 5.1 用户模型

```text
User
- id
- phone
- email
- passwordHash
- nickname
- avatarUrl
- currentLevel
- learningGoal
- membershipStatus
- createdAt
- updatedAt
```

### 5.2 句子模型

```text
Sentence
- id
- text
- translation
- audioUrl
- slowAudioUrl
- level
- sceneId
- source
- status
- createdBy
- createdAt
- updatedAt
```

### 5.3 目标词模型

```text
SentenceKeyword
- id
- sentenceId
- wordId
- surfaceText
- startIndex
- endIndex
- blankGroup
- priority
```

说明：

- `surfaceText` 保存句子中实际出现的文本，例如 `scheduled`。
- `wordId` 指向词条标准形式，例如 `schedule`。
- `blankGroup` 用于短语整体挖空，例如 `take care of`。

### 5.4 单词模型

```text
Word
- id
- lemma
- phonetic
- partOfSpeech
- meaningCn
- cefrLevel
- examTags
- collocations
- createdAt
- updatedAt
```

### 5.5 听写练习记录

```text
DictationAttempt
- id
- userId
- sentenceId
- mode
- userAnswer
- normalizedAnswer
- score
- isCorrect
- detailJson
- hintCount
- replayCount
- durationMs
- createdAt
```

### 5.6 用户词汇状态

```text
UserWordState
- id
- userId
- wordId
- status
- source
- mistakeCount
- correctStreak
- nextReviewAt
- lastReviewedAt
- createdAt
- updatedAt
```

### 5.7 AI 口语会话

```text
SpeakingSession
- id
- userId
- sceneId
- level
- status
- summary
- feedbackJson
- startedAt
- endedAt
```

```text
SpeakingMessage
- id
- sessionId
- role
- text
- audioUrl
- asrText
- createdAt
```

## 6. 数据库表建议

MVP 表：

- users
- user_profiles
- scenes
- words
- sentences
- sentence_keywords
- dictation_attempts
- user_word_states
- learning_tasks
- learning_task_items
- speaking_sessions
- speaking_messages
- admin_users
- media_assets

后续扩展表：

- orders
- memberships
- payment_records
- classes
- teachers
- organizations
- content_review_tasks
- ai_generation_jobs

## 7. 语境听写技术设计

### 7.1 出题逻辑

输入：

- 用户 ID
- 学习目标
- 当前难度
- 场景
- 最近学习记录
- 错词列表

输出：

- 句子
- 音频地址
- 展示文本
- 空位配置
- 目标词
- 允许答案

### 7.2 挖空策略

初级：

- 选择优先级最高的 1 个关键词。
- 适合目标词学习。

中级：

- 选择 2 到 4 个关键词。
- 优先选择动词、名词、形容词、核心短语。

高级：

- 不返回正文展示文本。
- 前端只展示整句输入区域。

### 7.3 答案标准化

提交后后端处理：

1. 去除首尾空格。
2. 合并连续空格。
3. 统一大小写。
4. 处理常见标点。
5. 处理英美拼写映射。
6. 对高级整句进行词级别对齐。

### 7.4 判分策略

初级：

- 标准化后完全匹配为正确。
- 可配置同义答案和变体答案。

中级：

- 每个空独立评分。
- 总分 = 正确空数 / 总空数 * 100。

高级：

- 使用编辑距离、词级别匹配和语序判断。
- MVP 可先用规则算法。
- 后续可加入语义相似度模型或 LLM 辅助解释。

### 7.5 本地判题与服务端判题

建议：

- 初级和中级可以前端即时展示基础判断，但最终记录以后端为准。
- 高级由后端判题，便于统一评分规则和后续升级。

## 8. AI 与语音能力

### 8.1 能力拆分

| 能力 | 用途 | MVP 优先级 |
| --- | --- | --- |
| TTS | 生成句子标准音频，AI 口语回复音频 | 高 |
| ASR | 识别用户口语录音 | 高 |
| LLM | AI 对话、纠错、解释 | 高 |
| 发音评测 | 跟读评分 | 中 |
| 语义相似度 | 高级听写评分辅助 | 中 |

### 8.2 TTS 使用策略

TTS 本质上可以输入文本后直接生成语音，但本项目按场景分为“提前生成”和“实时生成”两种模式。

#### 语境听写：提前生成

语境听写使用固定或半固定题库，同一句话会被多个用户反复练习，因此 MVP 阶段建议提前生成音频：

```text
后台录入英文句子
↓
Piper TTS 本地生成音频
↓
上传音频到 MinIO
↓
数据库保存 audio object key / audio url
↓
用户练习时直接播放现成音频
```

优点：

- 用户播放速度快。
- 同一句话只生成一次，节省计算成本。
- 可以在发布前检查音频质量。
- 适合 100 到 300 条 MVP 题库的批量生成。

MVP 推荐使用开源免费的 Piper TTS 作为本地 TTS 引擎。后续如果需要更自然的声音或更多音色，可以切换到云 TTS 服务。

#### AI 口语：实时生成

AI 口语回复是动态生成的，不适合提前准备音频，因此后续 AI 口语模块使用实时 TTS：

```text
用户语音输入
↓
ASR 转文本
↓
LLM 生成英文回复
↓
TTS 实时生成回复音频
↓
前端播放
```

MVP 第一阶段可以暂缓 AI 口语，先保留后端 Provider 抽象。

#### 音色策略

第一版建议后台生成音频时支持少量标准音色：

- 美式女声，默认。
- 美式男声。
- 英式女声。
- 英式男声。

用户端第一版只提供：

- 原速播放。
- 慢速播放。

慢速播放可优先使用前端 audio playbackRate 实现，后续再考虑单独生成慢速音频。

### 8.3 Provider 抽象

后端应定义统一接口，避免业务代码绑定单一供应商。

```csharp
public interface ITtsProvider
{
    Task<TtsResult> SynthesizeAsync(TtsRequest request, CancellationToken cancellationToken = default);
}

public interface IAsrProvider
{
    Task<AsrResult> TranscribeAsync(AsrRequest request, CancellationToken cancellationToken = default);
}

public interface ILlmProvider
{
    Task<LlmResult> ChatAsync(LlmChatRequest request, CancellationToken cancellationToken = default);
}

public sealed record TtsRequest(string Text, string? Voice = null, double? Speed = null);
public sealed record TtsResult(string AudioUrl, int DurationMs);

public sealed record AsrRequest(string AudioUrl, string Language = "en");
public sealed record AsrResult(string Text, double? Confidence = null);

public sealed record LlmChatMessage(string Role, string Content);
public sealed record LlmChatRequest(IReadOnlyList<LlmChatMessage> Messages, double? Temperature = null);
public sealed record LlmResult(string Text, object? Usage = null);
```

### 8.4 AI 内容安全

- AI 生成内容默认进入待审核状态。
- 用户可见内容必须经过规则校验或人工审核。
- AI 对话需要进行敏感内容过滤。
- 管理端保留 AI 输出日志，便于问题追踪。

## 9. API 设计草案

### 9.1 认证

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | /api/auth/register | 注册 |
| POST | /api/auth/login | 登录 |
| POST | /api/auth/logout | 退出 |
| POST | /api/auth/refresh | 刷新令牌 |
| GET | /api/auth/me | 当前用户 |
| PUT | /api/auth/me | 更新当前用户昵称、水平和学习目标 |

### 9.2 学习首页

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/learning/dashboard | 获取学习首页数据 |
| POST | /api/learning/goals | 设置学习目标 |
| GET | /api/learning/tasks/today | 获取今日任务 |

### 9.3 语境听写

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/dictation/next | 获取下一题 |
| POST | /api/dictation/submit | 提交答案 |
| GET | /api/dictation/history | 获取练习历史 |
| POST | /api/dictation/{id}/hint | 使用提示 |

获取下一题响应示例：

```json
{
  "questionId": "q_001",
  "sentenceId": "sentence_001",
  "mode": "beginner",
  "audioUrl": "https://cdn.example.com/audio/sentence_001.mp3",
  "displayParts": [
    { "type": "text", "value": "I need to " },
    { "type": "blank", "blankId": "b1", "length": 8 },
    { "type": "text", "value": " a meeting with the marketing team." }
  ],
  "hints": {
    "firstLetter": "s",
    "meaningCn": "安排"
  }
}
```

提交答案请求示例：

```json
{
  "questionId": "q_001",
  "answers": [
    { "blankId": "b1", "value": "schedule" }
  ],
  "durationMs": 8300,
  "replayCount": 2,
  "hintTypes": []
}
```

### 9.4 单词复习

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/vocabulary/words | 获取用户词库 |
| POST | /api/vocabulary/words | 手动加入生词 |
| GET | /api/vocabulary/review/next | 获取复习题 |
| POST | /api/vocabulary/review/submit | 提交复习结果 |

### 9.5 AI 口语

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | /api/speaking/sessions | 创建口语会话 |
| POST | /api/speaking/sessions/{id}/messages | 发送用户消息 |
| POST | /api/speaking/sessions/{id}/audio | 上传用户录音 |
| POST | /api/speaking/sessions/{id}/end | 结束并生成报告 |
| GET | /api/speaking/sessions/{id} | 获取会话详情 |

### 9.6 管理端

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/admin/sentences | 句子列表 |
| POST | /api/admin/sentences | 新增句子 |
| PATCH | /api/admin/sentences/{id} | 编辑句子 |
| POST | /api/admin/sentences/import | 批量导入 |
| POST | /api/admin/sentences/{id}/publish | 发布句子 |
| GET | /api/admin/words | 单词列表 |
| POST | /api/admin/audio/tts | 生成音频 |

## 10. 前端页面设计范围

### 10.1 Web / H5 页面

- `/login`
- `/onboarding`
- `/dashboard`
- `/dictation`
- `/speaking`
- `/vocabulary`
- `/reports`
- `/profile`

### 10.2 Admin 页面

- `/admin/login`
- `/admin/dashboard`
- `/admin/sentences`
- `/admin/words`
- `/admin/scenes`
- `/admin/media`
- `/admin/users`
- `/admin/reviews`
- `/admin/settings`

## 11. 状态管理

前端建议拆分：

- Auth Store：登录状态、用户信息。
- Learning Store：今日任务、学习进度。
- Dictation Store：当前题目、答案、反馈。
- Speaking Store：当前会话、消息列表、录音状态。

服务端状态以数据库为准，前端状态只负责交互体验。

## 12. 文件与音频处理

### 12.1 音频来源

MVP 推荐使用 TTS 批量生成音频，降低内容生产成本。

后续可支持：

- 真人录音
- 多口音音频
- 慢速音频
- 用户录音回放

### 12.2 存储方案

本项目确认使用 MinIO 作为本地开发和 MVP 阶段的对象存储服务。

```text
开发 / MVP：
PostgreSQL + MinIO + ASP.NET Core

生产可选：
PostgreSQL + 阿里云 OSS / 腾讯云 COS / Cloudflare R2 + ASP.NET Core
```

MinIO 与 S3 API 兼容，适合在本地模拟云对象存储。后端通过统一文件存储接口访问 MinIO，后续切换到正式云 OSS 时尽量只改配置或 Provider 实现。

本地建议配置：

```text
MinIO API: http://localhost:9000
MinIO Console: http://localhost:9001
Bucket: english-study
AccessKey: minioadmin
SecretKey: minioadmin
UseSSL: false
```

建议 Bucket 规划：

```text
english-study
  audio/       # 平台句子音频
  images/      # 头像、封面图
  recordings/  # 用户口语录音
  generated/   # AI 生成音频或临时资源
```

### 12.3 存储策略

- 平台音频存储到 MinIO / 对象存储。
- 用户录音可设置生命周期，例如 30 天后删除。
- 关键学习报告只保存文本识别结果和评分，不长期保存原始录音，除非用户授权。
- 数据库只保存文件的 bucket、object key、URL、mime type、size 等元数据，不保存音频二进制内容。

### 12.4 后端抽象

后端定义统一文件存储接口，业务模块不直接依赖 MinIO SDK。

```csharp
public interface IFileStorageService
{
    Task<StoredFileResult> UploadAsync(
        Stream stream,
        string objectKey,
        string contentType,
        CancellationToken cancellationToken = default);

    Task<Stream> OpenReadAsync(
        string objectKey,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        string objectKey,
        CancellationToken cancellationToken = default);
}

public sealed record StoredFileResult(
    string Bucket,
    string ObjectKey,
    string Url,
    string ContentType,
    long Size);
```

## 13. 安全设计

### 13.1 认证与权限

- 用户端使用 JWT 或 Session。
- 管理端单独登录入口。
- 管理操作需要 RBAC 权限控制。
- 敏感操作记录审计日志。

### 13.2 数据安全

- 密码使用强哈希存储。
- 手机号、邮箱等敏感字段按需脱敏展示。
- 用户录音和学习数据需要按用户隔离。
- 管理端接口必须校验权限。

### 13.3 限流

需要限流的接口：

- 登录
- 验证码
- AI 对话
- 录音上传
- TTS 生成
- 批量导入

## 14. 日志与监控

### 14.1 业务日志

- 登录日志
- 答题提交日志
- AI 调用日志
- 支付日志，商业化阶段
- 管理端操作日志

### 14.2 技术监控

- API 响应时间
- 错误率
- AI 调用耗时
- ASR / TTS 成功率
- 音频加载失败率
- 数据库慢查询

## 15. 部署建议

### 15.1 MVP 部署

```text
Web / Admin: Vercel、Cloudflare Pages 或自建 Node 服务
API Server: ASP.NET Core Docker 容器，部署到云服务器 / 容器服务
Database: 云 PostgreSQL
Redis: 云 Redis
Storage: MinIO，本地 / 自托管；生产可切换 OSS / COS / R2
CDN: 音频与静态资源加速
```

### 15.2 环境划分

- local：本地开发
- dev：联调环境
- staging：预发布环境
- production：生产环境

### 15.3 配置管理

关键环境变量：

- ConnectionStrings__Default
- Redis__ConnectionString
- Jwt__Issuer
- Jwt__Audience
- Jwt__SigningKey
- Storage__Bucket
- Storage__AccessKey
- Storage__SecretKey
- Storage__Endpoint
- Storage__UseSSL
- Ai__Provider
- Ai__ApiKey
- Tts__Provider
- Asr__Provider

## 16. 开发阶段拆分

### 16.1 第一阶段：基础骨架

- 初始化前端与后端工程。
- 完成用户注册登录。
- 完成数据库模型与迁移。
- 完成基础管理端登录。

### 16.2 第二阶段：语境听写 MVP

- 完成句子与单词管理。
- 完成题目生成。
- 完成三种难度的前端交互。
- 完成答题判分和学习记录。
- 完成错词入库。

### 16.3 第三阶段：AI 口语 MVP

- 完成场景管理。
- 接入 ASR。
- 接入 LLM 对话。
- 保存会话记录。
- 生成基础复盘报告。

### 16.4 第四阶段：学习闭环

- 完成首页任务。
- 完成错词复习。
- 完成学习报告。
- 完成自适应难度推荐。

### 16.5 第五阶段：三端与商业化

- 接入小程序。
- 接入会员体系。
- 接入支付。
- 完善内容审核。
- 增加运营数据看板。

## 17. 技术风险

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| AI 口语延迟高 | 影响对话体验 | MVP 先用录音上传，后续再做实时语音 |
| 发音评测成本高 | 成本不可控 | 第一阶段只做基础跟读评分或延后 |
| 内容质量不稳定 | 影响学习效果 | AI 生成后人工审核，建立句子质量标准 |
| 三端重复开发 | 开发成本增加 | 先 Web + H5，共用接口和类型 |
| 音频加载慢 | 影响训练体验 | 使用 CDN 和预加载下一题音频 |

## 18. MVP 技术验收清单

- 前端可以完成登录、首页、语境听写、错词复习和个人学习设置。
- 后端提供稳定 REST API。
- 数据库可以保存用户、句子、单词、答题记录和错词状态。
- 管理端可以维护句子、单词、场景和音频。
- 语境听写三种难度均可正常判题。
- AI 口语暂不进入第一版，但后端保留 Provider 抽象，便于后续接入 ASR / LLM / TTS。
- 音频资源可以通过 CDN 或对象存储稳定访问。
- 核心接口有基础日志和错误处理。
