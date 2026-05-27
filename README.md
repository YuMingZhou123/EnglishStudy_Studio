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

新增 EF Core migration：

```powershell
dotnet tool run dotnet-ef migrations add <MigrationName> --project apps/api --startup-project apps/api --output-dir Data/Migrations
```

## 前端

```powershell
cd apps/web
npm install
npm run dev
```

默认地址：

- Web: `http://localhost:3000`

## 环境变量

参考根目录 `.env.example`。MVP 阶段优先使用本地 PostgreSQL 和 MinIO。
