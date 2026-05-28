# 英语学习平台技术架构设计文档

版本：v0.2
日期：2026-05-28
状态：第一版技术基线

## 1. 技术目标

本项目目标是做一个可逐步商业化的英语学习平台，第一版聚焦“语境听写 + 单词记忆 + 学习记录 + 内容管理”。

长期希望支持：

- PC Web。
- 移动 H5。
- 微信小程序。
- 语境听写。
- 错词复习。
- 学习报告。
- 后台内容管理。
- TTS 音频生成。
- 后续 AI 口语、ASR、发音评测、会员付费、机构端。

第一版技术目标：

- 快速交付 MVP。
- 前后端边界清晰。
- 后端采用 C# / ASP.NET Core，按 DDD 风格模块化单体实现。
- 本地开发可完整跑通 PostgreSQL、MinIO、API、Web。
- 文件存储先用 MinIO，本地体验接近阿里云 OSS / S3 类对象存储。
- TTS 先支持本地生成，后续可切换云服务。
- 小程序不进入第一版，但接口和业务模型为后续接入保留空间。

## 2. 已确认技术栈

| 层级 | 技术 | 说明 |
| --- | --- | --- |
| Web / H5 | Next.js + React + TypeScript | 承载 PC Web、移动 H5、管理后台页面 |
| 样式 | Tailwind CSS | 快速构建响应式界面 |
| 后端 | ASP.NET Core Web API + C# | 独立后端服务，承载核心业务 |
| 后端架构 | DDD 风格模块化单体 | 先单体，按领域边界组织代码 |
| 数据库 | PostgreSQL | 用户、内容、学习记录、权限、媒体元数据 |
| ORM | Entity Framework Core | C# 生态成熟，支持迁移和 LINQ 查询 |
| 文件存储 | MinIO | 本地和 MVP 阶段使用，生产可切换 OSS / COS / R2 |
| 接口文档 | Swagger / OpenAPI | 便于调试、联调和 AI 辅助开发 |
| 认证 | ASP.NET Core Identity + JWT | 登录、密码哈希、角色基础能力 |
| TTS | 本地 TTS Provider | 优先 Piper，可回退 Windows Speech |
| 小程序 | Taro + React + TypeScript | 后续独立轻量端，不进入第一版 |

Next.js 只作为前端，不作为核心业务后端。核心业务、数据库访问、判题、学习记录、权限、TTS、文件存储都放在 ASP.NET Core 后端。

## 3. 总体架构

```text
PC Web / Mobile H5 / Future Miniapp
        |
        | HTTPS / REST API
        v
ASP.NET Core Web API
        |
        +-- Identity & Access
        +-- Content
        +-- Dictation
        +-- Learning
        +-- Media / TTS
        |
        +-- PostgreSQL
        +-- MinIO
        +-- Local / Cloud TTS Provider
```

第一版以 REST API 为主。后续如果 AI 口语需要实时语音能力，再评估 WebSocket、WebRTC 或流式接口。

## 4. 后端 DDD 分层

后端目录：

```text
apps/api/
  Domain/
    Identity/
    Content/
    Dictation/
    Learning/
  Application/
    Auth/
    Content/
    Dictation/
    Common/Interfaces/
  Infrastructure/
    Persistence/
    Storage/
    Tts/
    Auth/
    Options/
  Controllers/
  Program.cs
```

依赖方向：

```text
Controllers -> Application -> Domain
Infrastructure -> Application / Domain
Program.cs 组合依赖注入
```

分层职责：

- `Domain`：业务模型、业务规则、状态流转。
- `Application`：用例编排、DTO、接口抽象。
- `Infrastructure`：EF Core、PostgreSQL、MinIO、TTS、JWT 等技术实现。
- `Controllers`：HTTP API 入口。

详细约定见：[后端 DDD 架构约定](backend-ddd-architecture.md)。

## 5. 边界上下文

| 上下文 | 核心模型 | 说明 |
| --- | --- | --- |
| Identity & Access | User、Role、Permission、UserRole、RolePermission | 登录、角色、权限 |
| Content | Scene、Word、Sentence、SentenceKeyword、MediaAsset | 场景、单词、句子、关键词、音频 |
| Dictation | DictationMode、KeywordSelector、Grader、Normalizer | 出题、挖空、判分 |
| Learning | DictationAttempt、UserWordState | 学习记录、错词状态 |
| Media / TTS | FileStorage、TtsProvider | 文件上传、音频生成 |

## 6. 核心数据模型

### 6.1 权限模型

第一版先设计完整基础模型，只启用必要能力：

```text
User
Role
Permission
UserRole
RolePermission
```

后续机构端再扩展：

- Organization。
- Department。
- Class。
- DataScope。
- MenuPermission。
- ButtonPermission。
- AuditLog。

### 6.2 内容模型

```text
Scene
- id
- code
- name
- description
- isEnabled

Word
- id
- lemma
- phonetic
- partOfSpeech
- meaningCn
- cefrLevel
- examTags
- collocations

Sentence
- id
- text
- translation
- level
- sceneId
- audioAssetId
- audioUrl
- slowAudioUrl
- source
- status

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

### 6.3 学习模型

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
- lastMistakeAt
- lastMistakeSentenceId
```

## 7. 语境听写设计

用户听一句英语音频，然后根据难度填写空缺内容。

难度规则：

- 初级：核心关键词留空，通常 1 个。
- 中级：多个关键词留空，通常 2-4 个。
- 高级：整句留空，用户输入完整句子。

后端职责：

- 根据模式选择关键词。
- 生成展示文本和空位。
- 标准化用户答案。
- 判分。
- 保存听写记录。
- 更新错词和复习状态。

前端职责：

- 播放音频。
- 展示文本、空位、输入框。
- 提交答案。
- 展示判分反馈和目标词。

## 8. TTS 设计

TTS 可以“给文本直接生成语音”，但平台里分两种使用方式。

### 8.1 语境听写：提前生成

语境听写使用固定或半固定题库，同一句话会被很多用户反复练习，所以第一版推荐提前生成音频：

```text
后台录入英文句子
-> TTS 生成音频
-> 上传到 MinIO
-> 数据库保存 audioAssetId / audioUrl
-> 用户练习时直接播放
```

优点：

- 播放更快。
- 同一句话只生成一次，节省成本。
- 发布前可以人工检查音频质量。
- 适合 100-300 条 MVP 题库。

### 8.2 AI 口语：实时生成

后续 AI 口语的回复是动态生成的，适合实时 TTS：

```text
用户语音
-> ASR 转文本
-> LLM 生成回复
-> TTS 实时生成回复音频
-> 前端播放
```

第一版先保留 Provider 抽象，不做完整 AI 口语闭环。

### 8.3 音色策略

第一版后台生成音频时支持传入 `voice` 和 `speed`，前端用户端先只提供：

- 原速播放。
- 慢速播放。

推荐默认音色：

- 美式女声。
- 美式男声。
- 英式女声。
- 英式男声。

本地优先接 Piper；没有 Piper 时可回退 Windows Speech，后续可替换云 TTS。

## 9. 文件存储设计

本项目本地开发和 MVP 阶段使用 MinIO。

MinIO 可以理解为“专门存文件的服务”，体验上类似阿里云 OSS、腾讯云 COS、S3：

- 数据库保存文件元数据。
- 文件二进制内容保存在对象存储。
- 后端通过统一接口访问。
- 生产环境可切换到云对象存储。

本地默认：

```text
MinIO API: http://localhost:9000
MinIO Console: http://localhost:9001
Bucket: english-study
```

推荐对象路径：

```text
audio/        # 句子音频
recordings/   # 用户录音
images/       # 图片资源
generated/    # AI 生成资源
```

数据库只保存：

- bucket。
- object key。
- url。
- mime type。
- size。
- source。

不把音频二进制直接塞进 PostgreSQL。

## 10. API 范围

第一版核心 API：

| 模块 | API |
| --- | --- |
| 认证 | `POST /api/auth/register`、`POST /api/auth/login`、`GET /api/auth/me`、`PUT /api/auth/me` |
| 听写 | `GET /api/dictation/next`、`POST /api/dictation/submit`、`GET /api/dictation/history`、`GET /api/dictation/summary` |
| 词汇 | `GET /api/vocabulary/words`、`POST /api/vocabulary/words`、`GET /api/vocabulary/review/next`、`POST /api/vocabulary/review/submit` |
| 后台内容 | 场景、单词、句子、发布、下架、批量导入 |
| 媒体 | 上传、读取、TTS 生成、缺失音频批量生成 |

## 11. 前端范围

第一版页面：

- `/` 登录和入口。
- `/dashboard` 学习首页。
- `/dictation` 语境听写。
- `/vocabulary` 词汇和错词复习。
- `/reports` 学习报告。
- `/admin` 内容管理后台。

第一版前端覆盖 PC Web 和移动 H5。微信小程序后续使用独立 Taro 项目接入同一套后端 API。

## 12. 本地开发环境

本地开发组合：

```text
PostgreSQL + MinIO + ASP.NET Core API + Next.js Web
```

推荐启动顺序：

1. 启动 Docker 基础设施。
2. 启动 ASP.NET Core API。
3. 启动 Next.js Web。
4. 运行 smoke test。
5. 运行 UI smoke test。

关键地址：

```text
API: http://localhost:5180
Swagger: http://localhost:5180/swagger
Web: http://localhost:3000
PostgreSQL: localhost:55432
MinIO API: http://localhost:9000
MinIO Console: http://localhost:9001
```

## 13. 验收与质量

自动化检查：

- API health。
- Ready check。
- Swagger 可访问。
- 登录、注册、用户信息。
- 初级、中级、高级听写。
- 错词复习。
- 学习报告。
- 后台内容管理。
- 媒体上传和读取。
- TTS 生成和音频绑定。
- 桌面端和移动端页面 smoke test。
- MVP 内容包结构和质量检查。

产品侧检查：

- 内容人工审核。
- 音频人工抽检。
- 5-10 位真实用户内测反馈。
- 修复高优先级问题后再进入对外发布。

## 14. 后续演进

技术演进顺序：

1. 完善内容审核流。
2. 接入 Redis 做限流、缓存、任务状态。
3. 引入后台操作审计。
4. 接入 ASR / LLM / 发音评测 Provider。
5. 增加微信小程序端。
6. 增加会员、订单、支付。
7. 增加机构、班级、老师、学生管理。
8. 视复杂度拆分后端项目或服务。
