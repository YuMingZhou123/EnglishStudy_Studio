# 后端 DDD 架构约定

版本：v0.1
日期：2026-05-27
状态：第一版后端架构约定

## 1. 架构选择

本项目后端采用“DDD 风格的单体架构”。第一阶段不拆多个后端项目，也不拆微服务，先在 `apps/api` 一个 ASP.NET Core Web API 项目内按职责分层。

这样做的原因：

- 个人开发者更容易理解、运行和调试。
- 代码边界清晰，后续可以平滑拆分成多项目或微服务。
- 适合 AI 辅助开发，单次改动范围更明确。
- 不牺牲后续扩展能力，领域模型、应用服务、基础设施依赖从一开始就分开。

## 2. 当前目录结构

```text
apps/api/
  Domain/                 # 领域层：核心业务对象与业务规则
    Identity/             # 用户、角色、权限
    Content/              # 场景、句子、单词、关键词、媒体资源
    Learning/             # 听写记录、用户词汇状态
    Dictation/            # 听写模式、关键词选择、答案标准化、判分规则
  Application/            # 应用层：用例编排、DTO、接口抽象
    Common/Interfaces/    # 应用层依赖的抽象接口
    DependencyInjection.cs
  Infrastructure/         # 基础设施层：数据库、外部服务、存储、Provider 实现
    Options/              # 配置对象
    Persistence/          # EF Core DbContext 与 Migrations
    DependencyInjection.cs
  Controllers/            # API 入口层：HTTP 请求与响应
  Program.cs              # 应用启动与模块组合
```

## 3. 分层职责

### 3.1 Domain 领域层

领域层放业务概念本身，不直接处理 HTTP、数据库、MinIO、TTS Provider 等外部细节。

当前已启用的领域：

- `Identity`：`ApplicationUser`、`ApplicationRole`、`Permission`、`ApplicationUserRole`、`RolePermission`
- `Content`：`Scene`、`Word`、`Sentence`、`SentenceKeyword`、`MediaAsset`
- `Learning`：`DictationAttempt`、`UserWordState`
- `Dictation`：`DictationMode`、`DictationKeywordSelector`、`DictationGrader`、`DictationAnswerNormalizer`

听写规则、挖空策略、判分策略、错词状态流转，优先沉淀到领域层或领域服务中。应用层只负责调用这些规则并完成数据读取、保存和 DTO 转换。

### 3.2 Application 应用层

应用层负责“一个用户动作对应的一段业务流程”。

示例：

- 注册用户
- 登录并签发 Token
- 获取下一道听写题
- 提交听写答案
- 将错误关键词写入错词状态
- 查询学习首页数据

应用层可以依赖领域层，也可以依赖抽象接口，例如 `IAppDbContext`、`IFileStorageService`、`ITtsProvider`，但不直接依赖具体的 EF Core、MinIO SDK 或第三方 AI SDK 实现。

### 3.3 Infrastructure 基础设施层

基础设施层负责技术实现细节。

当前包含：

- `AppDbContext`
- EF Core migrations
- PostgreSQL 持久化配置
- ASP.NET Core Identity 持久化配置
- `StorageOptions`
- `JwtOptions`

后续会继续放：

- MinIO 文件存储实现
- Piper TTS 本地生成实现
- ASR / LLM / TTS Provider 实现
- 邮件、短信、缓存、队列、日志等基础设施

### 3.4 API 入口层

Controller 只负责 HTTP 入口，不直接写复杂业务规则。

Controller 应该做：

- 接收请求
- 做基础模型校验
- 调用 Application 用例
- 返回响应

Controller 不应该做：

- 直接拼复杂查询
- 直接操作多个聚合并写入业务规则
- 直接调用 MinIO、TTS、LLM 等外部服务

## 4. 边界上下文规划

第一版按以下边界推进：

| 边界上下文 | 主要职责 | MVP 状态 |
| --- | --- | --- |
| Identity & Access | 用户、角色、权限、登录认证 | 先建模型，逐步启用 |
| Content | 场景、句子、单词、关键词、音频资源 | MVP 核心 |
| Learning | 答题记录、错词状态、学习进度 | MVP 核心 |
| Dictation | 出题、挖空、判分、反馈 | MVP 核心 |
| Media | 文件元数据、音频存储、TTS 生成 | 第一版先接 MinIO 元数据 |
| AI | LLM、ASR、TTS Provider 抽象 | 后续扩展 |

## 5. 开发规则

- 新业务规则优先放在 `Domain` 或 `Application`，不要直接塞进 Controller。
- 新外部依赖优先定义接口，再由 `Infrastructure` 实现。
- 数据库表结构由 `Infrastructure/Persistence/AppDbContext.cs` 统一配置。
- EF migration 统一放在 `Infrastructure/Persistence/Migrations`。
- Controller 返回 DTO，不直接暴露 EF 实体。
- 第一阶段保持单体架构，等业务稳定后再考虑拆分多个 `.csproj`。

## 6. MVP 后端开发顺序

1. 用户注册、登录、JWT 鉴权。
2. 内容基础数据：场景、单词、句子、关键词、音频资源。
3. 听写出题：初级、中级、高级三种模式。
4. 听写提交与判分。
5. 答题记录保存。
6. 错词状态写入与错词本查询。
7. 管理端内容录入接口。
8. MinIO 文件上传与音频资源管理。
9. Piper TTS 生成音频。

## 7. 当前落地状态

已经完成：

- 后端代码按 DDD 单体结构重组。
- 权限模型进入 `Domain/Identity`。
- 听写核心模型进入 `Domain/Content` 与 `Domain/Learning`。
- EF Core 上下文进入 `Infrastructure/Persistence`。
- 配置对象进入 `Infrastructure/Options`。
- 应用层抽象 `IAppDbContext` 已建立。
- 听写核心数据表 migration 已生成。
- 听写模式、答案标准化、关键词选择和判分规则已沉淀到 `Domain/Dictation`。
- `UserWordState` 已承载“手动加入词汇本”“听写正确/错误后的复习状态流转”规则。
- `DictationService` 已调整为应用层编排：查询题目、调用领域规则、保存答题记录和词汇状态。

## 8. 后续 DDD 编码准则

新增后端功能时按以下顺序判断代码应该放在哪里：

1. 如果是业务概念、状态流转、判定规则，优先放到 `Domain`。
2. 如果是一个用户动作对应的流程编排，放到 `Application`。
3. 如果是数据库、MinIO、TTS、JWT、第三方服务，放到 `Infrastructure`。
4. 如果是 HTTP 路由、请求参数、鉴权入口、响应状态码，放到 `Controllers`。

第一版不强行引入完整 Repository、领域事件、CQRS 或微服务。等某个上下文变复杂后，再按实际压力逐步引入，避免为了架构而架构。
