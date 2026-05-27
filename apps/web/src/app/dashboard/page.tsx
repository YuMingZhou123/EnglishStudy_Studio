export default function DashboardPage() {
  return (
    <main className="min-h-screen bg-[#f7f8fb] px-5 py-8 text-[#172033] sm:px-8">
      <section className="mx-auto w-full max-w-5xl">
        <a className="text-sm font-medium text-[#537188]" href="/">
          返回首页
        </a>
        <header className="mt-6 border-b border-[#d8dde8] pb-6">
          <p className="text-sm font-medium text-[#537188]">
            MVP Placeholder
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-normal">
            学习首页
          </h1>
          <p className="mt-3 max-w-2xl text-sm leading-6 text-[#5b6472]">
            这里会承载今日任务、语境听写入口、错词复习和学习进度。当前页面用于工程骨架验证。
          </p>
        </header>

        <section className="mt-6 grid gap-4 md:grid-cols-3">
          {[
            ["今日任务", "语境听写 10 句"],
            ["错词复习", "待复习 0 个"],
            ["当前阶段", "工程骨架搭建"],
          ].map(([title, value]) => (
            <div
              className="rounded-lg border border-[#d8dde8] bg-white p-5 shadow-sm"
              key={title}
            >
              <h2 className="text-sm font-medium text-[#537188]">{title}</h2>
              <p className="mt-3 text-lg font-semibold text-[#172033]">
                {value}
              </p>
            </div>
          ))}
        </section>
      </section>
    </main>
  );
}

