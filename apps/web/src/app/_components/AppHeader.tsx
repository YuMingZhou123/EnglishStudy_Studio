"use client";

import Link from "next/link";

type AppHeaderProps = {
  active: "home" | "review" | "dictation" | "reports" | "admin";
  showAdmin?: boolean;
  onLogout?: () => void;
};

const navItems = [
  { key: "home", label: "首页", href: "/dashboard" },
  { key: "review", label: "我的复习", href: "/vocabulary" },
  { key: "dictation", label: "听写练习", href: "/dictation" },
  { key: "reports", label: "学习记录", href: "/reports" },
] as const;

export function AppHeader({ active, onLogout, showAdmin = false }: AppHeaderProps) {
  return (
    <header className="border-b-4 border-[#2f8a55] bg-[#242625] text-white">
      <nav className="mx-auto flex min-h-16 max-w-7xl flex-col lg:flex-row lg:items-stretch">
        <Link
          className="flex h-16 shrink-0 items-center gap-3 px-5 sm:px-6"
          href="/dashboard"
        >
          <span className="grid h-9 w-9 place-items-center rounded-full bg-[#2f8a55] text-lg font-semibold text-white">
            E
          </span>
          <span className="text-xl font-semibold">EnglishStudy</span>
        </Link>

        <div className="flex min-w-0 flex-1 flex-col lg:flex-row lg:items-stretch lg:justify-between">
          <div className="flex min-w-0 overflow-x-auto">
            {navItems.map((item) => (
              <Link
                className={`relative flex h-16 shrink-0 items-center px-5 text-base font-medium transition ${
                  active === item.key
                    ? "bg-[#111312] text-white"
                    : "text-[#d7ddd9] hover:bg-[#1b1d1c] hover:text-white"
                }`}
                href={item.href}
                key={item.key}
              >
                {item.label}
                {active === item.key ? (
                  <span className="absolute bottom-[-4px] left-1/2 h-0 w-0 -translate-x-1/2 border-x-8 border-t-8 border-x-transparent border-t-[#2f8a55]" />
                ) : null}
              </Link>
            ))}
          </div>

          <div className="flex h-16 shrink-0 items-center gap-4 px-5">
            <label className="hidden h-10 w-60 items-center gap-2 rounded-full bg-white px-4 text-sm text-[#7b8580] xl:flex">
              <span className="text-lg leading-none text-[#8b9690]">⌕</span>
              <input
                className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-[#8b9690]"
                placeholder="搜索课程/单词/句子"
                type="search"
              />
            </label>

            {showAdmin ? (
              <Link
                className={`hidden h-10 items-center rounded-full border px-5 text-sm font-medium transition sm:flex ${
                  active === "admin"
                    ? "border-[#6ba77a] bg-[#111312] text-white"
                    : "border-[#59605c] text-[#d7ddd9] hover:border-[#8b9690] hover:text-white"
                }`}
                href="/admin"
              >
                内容管理
              </Link>
            ) : null}

            {onLogout ? (
              <button
                className="h-10 shrink-0 text-sm font-medium text-[#c4cbc7] transition hover:text-white"
                onClick={onLogout}
                type="button"
              >
                退出
              </button>
            ) : null}
          </div>
        </div>
      </nav>
    </header>
  );
}
