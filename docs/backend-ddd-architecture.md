# 后端 DDD 架构约定

版本：v0.2
日期：2026-05-28
状态：第一版后端架构基线

## 1. 架构定位

本项目后端采用 DDD 风格的模块化单体架构。

第一版不拆微服务，也不拆多个后端项目，先在 `apps/api` 一个 ASP.NET Core Web API 项目内保持清晰分层：

```text
apps/api/
  Domain/          # 领域层：业务对象、领域规则、状态流转
  Application/     # 应用层：用例编排、DTO、抽象接口
  Infrastructure/  # 基础设施层：数据库、存储、TTS、JWT 等技术实现
  Controllers/     # API 层：HTTP 路由、鉴权入口、请求响应
  Program.cs       # 应用启动和依赖注入组合
```

这样做的原因：

- 适合个人开发者和 AI 辅助开发，运行、调试、定位问题更直接。
- 业务边界先清晰起来，后续可以平滑拆成多个项目或服务。
- 避免第一版为了架构而架构，把时间花在接口、仓储、事件总线等过早复杂度上。
- 仍然保留 DDD 的核心价值：领域规则不散落在 Controller 或数据库访问代码里。

## 2. 依赖方向

目标依赖方向：

```text
Controllers -> Application -> Domain
Infrastructure -> Application / Domain
Program.cs 负责组合依赖注入
```

具体约束：

- `Domain` 不主动依赖数据库、MinIO、TTS、JWT、HTTP 等外部技术。
- `Application` 可以依赖 `Domain`，负责一次用户动作对应的业务流程。
- `Application/Common/Interfaces` 定义外部能力抽象，例如数据库上下文、文件存储、TTS。
- `Infrastructure` 实现这些抽象，例如 EF Core、MinIO、本地 TTS、JWT。
- `Controllers` 只接收请求、做基础校验、调用应用服务、返回响应。

当前 MVP 为了开发效率，`Application` 允许通过 `IAppDbContext` 使用 EF Core 查询能力；当某个领域变复杂后，再逐步引入 Repository、Specification、领域事件或 CQRS。

## 3. 边界上下文

第一版按以下边界上下文组织：

| 上下文 | 目录 | 主要职责 | MVP 状态 |
| --- | --- | --- | --- |
| Identity & Access | `Domain/Identity` | 用户、角色、权限、用户角色、角色权限 | 已建立模型 |
| Content | `Domain/Content` | 场景、单词、句子、关键词、媒体资源 | MVP 核心 |
| Dictation | `Domain/Dictation` | 听写模式、挖空策略、答案标准化、判分规则 | MVP 核心 |
| Learning | `Domain/Learning` | 听写记录、错词状态、复习状态流转 | MVP 核心 |
| Media / TTS | `Application + Infrastructure` | 文件存储、TTS 生成、音频绑定 | MVP 核心 |

后续机构端、班级、会员、订单、支付、内容审核、AI 口语可以继续按新的边界上下文扩展。

## 4. 分层职责

### 4.1 Domain

领域层放“业务本身”。

当前包含：

- `Identity`
  - `ApplicationUser`
  - `ApplicationRole`
  - `Permission`
  - `ApplicationUserRole`
  - `RolePermission`
- `Content`
  - `Scene`
  - `Word`
  - `Sentence`
  - `SentenceKeyword`
  - `MediaAsset`
- `Dictation`
  - `DictationMode`
  - `DictationBlankId`
  - `DictationAnswerNormalizer`
  - `DictationKeywordSelector`
  - `DictationGrader`
- `Learning`
  - `DictationAttempt`
  - `UserWordState`

适合放在 Domain 的代码：

- 关键词如何选择。
- 初级、中级、高级如何挖空。
- 用户答案如何标准化。
- 听写如何判分。
- 错词状态如何从 `New`、`Reviewing` 流转到 `Mastered`。
- 用户答错后下一次复习时间如何计算。

### 4.2 Application

应用层放“用例编排”。

示例：

- 注册用户。
- 登录并签发 Token。
- 获取下一道听写题。
- 提交听写答案。
- 更新错词状态。
- 查询学习报告。
- 管理员创建、发布、下架句子。
- 管理员生成句子音频。

应用层可以：

- 调用领域对象和领域服务。
- 通过抽象接口访问数据库、文件存储、TTS。
- 组装请求和响应 DTO。

应用层不应该：

- 把复杂领域规则写成大量散落的 `if/else`。
- 直接依赖 MinIO SDK、Piper 命令、第三方 AI SDK。

### 4.3 Infrastructure

基础设施层放技术实现。

当前包含：

- `Persistence/AppDbContext.cs`
- EF Core migrations
- PostgreSQL 持久化配置
- ASP.NET Core Identity 持久化配置
- `Storage/MinioFileStorageService.cs`
- `Tts/LocalTtsProvider.cs`
- `Auth/JwtTokenService.cs`
- `Options/*`

后续可以继续放：

- Redis。
- 邮件、短信。
- 队列。
- 付费 TTS / ASR / LLM Provider。
- 监控、日志、审计实现。

### 4.4 Controllers

Controller 是 HTTP 入口，不写核心业务规则。

Controller 应该做：

- 接收请求参数。
- 读取当前用户身份。
- 做基础模型校验。
- 调用 Application service。
- 返回 HTTP 响应。

Controller 不应该做：

- 直接操作多个聚合并写业务规则。
- 直接访问 MinIO、TTS、LLM。
- 直接拼复杂查询并承载业务判断。

## 5. Identity 的实现取舍

当前用户、角色、用户角色继承了 ASP.NET Core Identity 类型，这是第一版为了快速获得成熟登录、密码哈希、角色能力做出的工程取舍。

这意味着 `Domain/Identity` 对 `Microsoft.AspNetCore.Identity` 有少量依赖。它不是最纯粹的 DDD，但对当前阶段是合理的：

- 可以快速获得可靠的密码安全能力。
- 能减少个人开发者维护认证细节的成本。
- RBAC 模型仍然保持清晰：`User`、`Role`、`Permission`、`UserRole`、`RolePermission`。

如果后续要追求更严格的领域隔离，可以演进为：

```text
Domain/Identity/User        # 自定义纯领域模型
Infrastructure/Identity/*   # 适配 ASP.NET Core Identity
Application/Auth/*          # 只依赖领域模型和认证抽象
```

第一版暂不做这一步，避免过度设计。

## 6. 当前落地状态

已经完成：

- 后端代码按 DDD 风格模块化单体组织。
- 权限模型进入 `Domain/Identity`。
- 内容模型进入 `Domain/Content`。
- 听写模型和听写规则进入 `Domain/Dictation`。
- 学习记录和错词状态进入 `Domain/Learning`。
- EF Core 上下文进入 `Infrastructure/Persistence`。
- MinIO 文件存储进入 `Infrastructure/Storage`。
- 本地 TTS Provider 进入 `Infrastructure/Tts`。
- JWT 签发进入 `Infrastructure/Auth`。
- Controller 通过 Application service 承载用例入口。

当前自动检查结果：

- API smoke test 已覆盖登录、三种听写模式、错词复习、后台内容、媒体上传、TTS 音频绑定。
- UI smoke test 已覆盖桌面和移动端核心页面。
- MVP readiness 自动化项已可运行，但最终产品就绪仍需要真实内容审核和 5-10 位用户反馈。

## 7. 新功能开发流程

新增后端功能时按这个顺序判断代码放哪里：

1. 如果是业务概念、状态、规则、判定，优先放 `Domain`。
2. 如果是一个用户动作对应的流程编排，放 `Application`。
3. 如果是数据库、MinIO、TTS、JWT、第三方服务，放 `Infrastructure`。
4. 如果是 HTTP 路由、请求参数、鉴权入口、响应状态码，放 `Controllers`。
5. 如果一个类同时做了两层以上的事情，优先拆开，而不是继续塞进去。

## 8. 第一版暂不引入的复杂度

第一版先不强制引入：

- 完整 Repository 层。
- 领域事件总线。
- CQRS。
- Event Sourcing。
- 微服务。
- 多数据库拆分。
- 复杂组织权限、菜单权限、按钮权限、数据权限。

这些不是不要，而是等机构端、内容审核、支付、运营后台真正变复杂后再引入。

## 9. 自动化边界检查

为了避免后续 AI 辅助开发时把代码写错层，仓库提供 DDD 边界检查脚本：

```powershell
.\scripts\check-ddd-boundaries.ps1
```

该脚本会检查：

- `Domain` 不依赖 Application、Infrastructure、Controller、EF Core、MinIO、HTTP。
- `Application` 不依赖 Infrastructure、Controller、MinIO、HTTP Controller 关注点。
- `Infrastructure` 不依赖 Controller。
- `Controllers` 不直接依赖 Infrastructure、EF Core、MinIO。

当前第一版允许两个工程取舍：

- `Domain/Identity` 可以使用 ASP.NET Core Identity。
- `Application` 可以通过 `IAppDbContext` 使用 EF Core 查询扩展。

`check-mvp-readiness.ps1` 已经把该脚本纳入自动化就绪检查。

## 10. 后续演进方向

当业务增长后，优先按以下顺序演进：

1. 将 `Application` 中重复查询抽为 Query service 或 Repository。
2. 将复杂状态流转沉淀为领域服务。
3. 为内容发布、TTS 生成、审核流程引入领域事件。
4. 为后台管理和学习端拆分更清晰的应用服务。
5. 当单体边界稳定后，再考虑把 Identity、Content、Learning、AI 独立成多个项目或服务。
