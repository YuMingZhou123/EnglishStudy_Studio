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
