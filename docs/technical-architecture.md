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
        +-- 对象存储
        +-- AI / ASR / TTS / 发音评测服务
```

## 3. 技术选型建议

### 3.1 推荐 MVP 方案

| 层级 | 技术 | 说明 |
| --- | --- | --- |
| Web / H5 | Next.js + React + TypeScript | 快速构建 PC 和移动 H5，SEO 与服务端渲染可选 |
| 小程序 | Taro + React + TypeScript | 后续复用部分 React 思路接入微信小程序 |
| 后端 | NestJS + TypeScript | 与前端语言统一，适合模块化 API 服务 |
| 数据库 | PostgreSQL | 结构化业务数据、学习记录、内容库 |
| 缓存 | Redis | 验证码、会话、限流、排行榜、短期任务状态 |
| ORM | Prisma 或 TypeORM | 推荐 Prisma，类型安全和迁移体验较好 |
| 文件存储 | S3 兼容对象存储 | 保存音频、录音、图片 |
| AI 服务 | 可插拔 Provider | 支持后续替换 LLM、ASR、TTS、发音评测供应商 |

### 3.2 备选方案

如果团队更熟悉 Java：

- 后端可使用 Spring Boot + MyBatis Plus。
- 前端仍可使用 Next.js。
- AI 服务封装为独立 Provider 层。

如果希望最快覆盖小程序、H5 和 App：

- 可考虑 uni-app。
- 代价是复杂交互和大型 Web 管理端体验可能不如 React / Next.js 方案。

## 4. 应用划分

### 4.1 前端应用

建议目录：

```text
apps/
  web/        # PC Web + 移动 H5
  admin/      # 后台管理端
  miniapp/    # 微信小程序，v0.3 接入
packages/
  ui/         # 通用 UI 组件
  shared/     # 类型、工具函数、常量
  api-client/ # 接口请求封装
```

第一阶段也可以先使用单体仓库：

```text
web/
server/
docs/
```

待业务变复杂后再迁移到 monorepo。

### 4.2 后端服务模块

建议按业务模块组织：

```text
src/
  auth/
  users/
  content/
  dictation/
  vocabulary/
  speaking/
  learning-records/
  reports/
  membership/
  admin/
  ai/
  storage/
  common/
```

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
| TTS | 生成句子标准音频 | 高 |
| ASR | 识别用户口语录音 | 高 |
| LLM | AI 对话、纠错、解释 | 高 |
| 发音评测 | 跟读评分 | 中 |
| 语义相似度 | 高级听写评分辅助 | 中 |

### 8.2 Provider 抽象

后端应定义统一接口，避免业务代码绑定单一供应商。

```ts
interface TtsProvider {
  synthesize(input: {
    text: string;
    voice?: string;
    speed?: number;
  }): Promise<{ audioUrl: string; durationMs: number }>;
}

interface AsrProvider {
  transcribe(input: {
    audioUrl: string;
    language: "en";
  }): Promise<{ text: string; confidence?: number }>;
}

interface LlmProvider {
  chat(input: {
    messages: Array<{ role: "system" | "user" | "assistant"; content: string }>;
    temperature?: number;
  }): Promise<{ text: string; usage?: unknown }>;
}
```

### 8.3 AI 内容安全

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
| POST | /api/dictation/:id/hint | 使用提示 |

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
| POST | /api/speaking/sessions/:id/messages | 发送用户消息 |
| POST | /api/speaking/sessions/:id/audio | 上传用户录音 |
| POST | /api/speaking/sessions/:id/end | 结束并生成报告 |
| GET | /api/speaking/sessions/:id | 获取会话详情 |

### 9.6 管理端

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/admin/sentences | 句子列表 |
| POST | /api/admin/sentences | 新增句子 |
| PATCH | /api/admin/sentences/:id | 编辑句子 |
| POST | /api/admin/sentences/import | 批量导入 |
| POST | /api/admin/sentences/:id/publish | 发布句子 |
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

### 12.2 存储策略

- 平台音频存储到对象存储。
- 用户录音可设置生命周期，例如 30 天后删除。
- 关键学习报告只保存文本识别结果和评分，不长期保存原始录音，除非用户授权。

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
Web / Admin: Vercel 或自建 Node 服务
API Server: 云服务器 / 容器服务
Database: 云 PostgreSQL
Redis: 云 Redis
Storage: 对象存储
CDN: 音频与静态资源加速
```

### 15.2 环境划分

- local：本地开发
- dev：联调环境
- staging：预发布环境
- production：生产环境

### 15.3 配置管理

关键环境变量：

- DATABASE_URL
- REDIS_URL
- JWT_SECRET
- OBJECT_STORAGE_BUCKET
- OBJECT_STORAGE_ACCESS_KEY
- OBJECT_STORAGE_SECRET_KEY
- AI_PROVIDER
- AI_API_KEY
- TTS_PROVIDER
- ASR_PROVIDER

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

- 前端可以完成登录、首页、语境听写、错词复习、AI 口语基础流程。
- 后端提供稳定 REST API。
- 数据库可以保存用户、句子、单词、答题记录和口语会话。
- 管理端可以维护句子、单词、场景和音频。
- 语境听写三种难度均可正常判题。
- AI 口语至少支持录音上传、语音识别、AI 回复和复盘。
- 音频资源可以通过 CDN 或对象存储稳定访问。
- 核心接口有基础日志和错误处理。

