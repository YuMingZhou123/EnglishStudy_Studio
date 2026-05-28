# EnglishStudy Studio

英语学习平台工程骨架。当前阶段目标是先跑通本地开发环境，再开发语境听写 MVP 核心链路。

## 技术栈

- 前端：Next.js + React + TypeScript + Tailwind CSS
- 后端：ASP.NET Core Web API + C#
- 数据库：PostgreSQL
- 文件存储：MinIO

## 目录结构

```text
apps/
  web/        # Next.js 前端
  api/        # ASP.NET Core Web API
infra/
  docker-compose.yml
docs/
```

## 本地基础设施

启动 PostgreSQL 和 MinIO：

```powershell
docker compose -f infra/docker-compose.yml up -d
```

服务地址：

- PostgreSQL: `localhost:55432`
- MinIO API: `http://localhost:9000`
- MinIO Console: `http://localhost:9001`

MinIO 登录：

```text
AccessKey: englishstudy
SecretKey: englishstudysecret
Bucket: english-study
```

## 后端

```powershell
dotnet tool restore
dotnet tool run dotnet-ef database update --project apps/api --startup-project apps/api
dotnet run --project apps/api
```

默认地址：

- API: `http://localhost:5180`
- Health: `http://localhost:5180/health`
- Ready: `http://localhost:5180/health/ready`
- Swagger: `http://localhost:5180/swagger`

开发环境会自动写入少量种子数据：

```text
Learner: learner@example.com / Pass123$
Admin: admin@example.com / Admin123$
```

TTS 默认配置为 `Tts__Provider=auto`。本地未安装 Piper 时会使用 Windows Speech 生成 WAV；安装 Piper 后配置 `Tts__PiperExecutablePath` 和 `Tts__PiperModelPath` 即可切换。

已跑通的 MVP 后端接口：

```text
POST /api/auth/register
POST /api/auth/login
GET  /api/auth/me
PUT  /api/auth/me
GET  /api/dictation/next?mode=beginner|intermediate|advanced
POST /api/dictation/submit
GET  /api/dictation/history
GET  /api/dictation/summary
GET  /api/vocabulary/words
POST /api/vocabulary/words
GET  /api/vocabulary/wrong-words
GET  /api/vocabulary/review/next?mode=beginner|intermediate|advanced
GET  /api/admin/scenes
POST /api/admin/scenes
PUT  /api/admin/scenes/{sceneId}
GET  /api/admin/words
POST /api/admin/words
PUT  /api/admin/words/{wordId}
GET  /api/admin/sentences
POST /api/admin/sentences
PUT  /api/admin/sentences/{sentenceId}
POST /api/admin/sentences/import
POST /api/admin/sentences/{sentenceId}/generate-audio
POST /api/admin/sentences/generate-missing-audio
POST /api/admin/media/upload
GET  /api/media/objects/{objectKey}
```

新增 EF Core migration：

```powershell
dotnet tool run dotnet-ef migrations add <MigrationName> --project apps/api --startup-project apps/api --output-dir Infrastructure/Persistence/Migrations
```

## 前端

```powershell
cd apps/web
npm install
npm run dev
```

默认地址：

- Web: `http://localhost:3000`
- Admin: `http://localhost:3000/admin`

## 环境变量

参考根目录 `.env.example`。MVP 阶段优先使用本地 PostgreSQL 和 MinIO。

## 第一版 smoke test

本地启动 PostgreSQL、MinIO、API 和 Web 后，可以运行一轮 MVP 主链路验收：

```powershell
.\scripts\smoke-test.ps1
```

如果只验证 API、数据库和 MinIO，不检查 Web 页面是否可访问：

```powershell
.\scripts\smoke-test.ps1 -SkipWeb
```

如果还要验证本地 TTS 生成并回读音频：

```powershell
.\scripts\smoke-test.ps1 -IncludeTts
```

脚本会检查健康状态、Swagger、登录、初级/中级/高级听写提交、错词复习、学习记录、后台内容创建/发布/下架、媒体上传和读取。`-IncludeTts` 会额外检查后台句子 TTS 生成、音频绑定和媒体回读。

页面级 smoke test：

```powershell
node .\scripts\ui-smoke-test.mjs
```

脚本会使用本机 Edge 或 Chrome 的 headless 模式检查登录、学习台、初级听写、词汇本、学习记录和内容后台页面。

汇总第一版自动化就绪状态：

```powershell
.\scripts\check-mvp-readiness.ps1
```

需要连同后端编译、前端 lint 和前端构建一起检查时：

```powershell
.\scripts\check-mvp-readiness.ps1 -IncludeBuild
```

## MVP 内容包

仓库内置一份原创 MVP 句子包：

```text
content/mvp-sentence-pack.json
```

内容规模：

- 120 条句子
- 5 个场景：日常、校园、职场、面试、旅行
- 三档难度：初级 / 中级 / 高级
- 335 个目标词配置项，324 个独立词形
- 每条句子至少 2 个目标词

API 启动后导入内容包：

```powershell
.\scripts\import-mvp-content.ps1
```

导入脚本会使用本地管理员账号调用后台批量导入接口，重复执行会按句子文本更新已有内容。

导入后为已发布句子生成缺失音频：

```powershell
.\scripts\generate-missing-audio.ps1
```

脚本会循环调用后台批量 TTS 接口，每轮最多生成 20 条，直到已发布句子没有缺失音频。

导入前也可以先做结构校验：

```powershell
.\scripts\validate-mvp-content.ps1
.\scripts\audit-mvp-content-quality.ps1
```

导出人工内容审核表：

```powershell
.\scripts\export-content-review-sheet.ps1
.\scripts\summarize-content-review.ps1
```

导出内测反馈表并汇总结果：

```powershell
.\scripts\export-beta-feedback-template.ps1
.\scripts\summarize-beta-feedback.ps1
```

## 第一版内测与审核

- 内测执行手册：`docs/internal-beta-playbook.md`
- 内容质量审核规范：`docs/content-quality-review.md`
- MVP 验收清单：`docs/mvp-acceptance-checklist.md`
