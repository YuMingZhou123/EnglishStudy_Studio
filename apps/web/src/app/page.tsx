export default function Home() {
  return (
    <main className="min-h-screen bg-[#f7f8fb] text-[#172033]">
      <section className="mx-auto flex w-full max-w-6xl flex-col gap-8 px-5 py-8 sm:px-8 lg:px-10">
        <header className="flex flex-col gap-4 border-b border-[#d8dde8] pb-6 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-medium text-[#537188]">
              EnglishStudy Studio
            </p>
            <h1 className="mt-2 text-3xl font-semibold tracking-normal text-[#172033]">
              语境听写学习工作台
            </h1>
          </div>
          <a
            className="inline-flex h-11 items-center justify-center rounded-md bg-[#172033] px-4 text-sm font-medium text-white transition hover:bg-[#2d3a4f]"
            href="/dashboard"
          >
            进入学习
          </a>
        </header>

        <section className="grid gap-4 md:grid-cols-3">
          {[
            ["核心链路", "播放音频、填空判题、错词入库"],
            ["本地服务", "ASP.NET Core + PostgreSQL + MinIO"],
            ["下一步", "先跑通第一条语境听写题目"],
          ].map(([title, description]) => (
            <div
              className="rounded-lg border border-[#d8dde8] bg-white p-5 shadow-sm"
              key={title}
            >
              <h2 className="text-base font-semibold text-[#172033]">
                {title}
              </h2>
              <p className="mt-3 text-sm leading-6 text-[#5b6472]">
                {description}
              </p>
            </div>
          ))}
        </section>

        <section className="grid gap-5 lg:grid-cols-[1.3fr_0.7fr]">
          <div className="rounded-lg border border-[#d8dde8] bg-white p-5 shadow-sm">
            <h2 className="text-lg font-semibold text-[#172033]">
              MVP 第一条核心链路
            </h2>
            <ol className="mt-4 grid gap-3 text-sm text-[#4a5566]">
              {[
                "管理员录入英文句子",
                "Piper TTS 生成音频并上传 MinIO",
                "用户获取题目并播放音频",
                "用户按难度完成填空或听写",
                "后端判题、保存记录、错词入库",
              ].map((item, index) => (
                <li className="flex gap-3" key={item}>
                  <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-md bg-[#e8f0ee] text-xs font-semibold text-[#20615b]">
                    {index + 1}
                  </span>
                  <span className="leading-6">{item}</span>
                </li>
              ))}
            </ol>
          </div>

          <div className="rounded-lg border border-[#d8dde8] bg-white p-5 shadow-sm">
            <h2 className="text-lg font-semibold text-[#172033]">
              API 连接
            </h2>
            <dl className="mt-4 space-y-3 text-sm">
              <div>
                <dt className="font-medium text-[#172033]">Base URL</dt>
                <dd className="mt-1 break-all text-[#5b6472]">
                  {process.env.NEXT_PUBLIC_API_BASE_URL ??
                    "http://localhost:5180"}
                </dd>
              </div>
              <div>
                <dt className="font-medium text-[#172033]">Health</dt>
                <dd className="mt-1 text-[#5b6472]">/health</dd>
              </div>
            </dl>
          </div>
        </section>
      </section>
    </main>
  );
}

