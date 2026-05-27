"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { authApi } from "@/lib/api";
import { getToken, saveSession } from "@/lib/session";

type AuthMode = "login" | "register";

export default function Home() {
  const router = useRouter();
  const [mode, setMode] = useState<AuthMode>("login");
  const [email, setEmail] = useState("learner@example.com");
  const [password, setPassword] = useState("Pass123$");
  const [displayName, setDisplayName] = useState("Demo Learner");
  const [currentLevel, setCurrentLevel] = useState("beginner");
  const [learningGoal, setLearningGoal] = useState("daily");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      return;
    }

    authApi
      .me(token)
      .then(() => router.replace("/dashboard"))
      .catch(() => {
        window.localStorage.clear();
      });
  }, [router]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const auth =
        mode === "login"
          ? await authApi.login(email, password)
          : await authApi.register({
              email,
              password,
              displayName,
              currentLevel,
              learningGoal,
            });

      saveSession(auth);
      router.push("/dashboard");
    } catch (err) {
      setError(err instanceof Error ? err.message : "登录失败");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="min-h-screen bg-[#f4f7f5] text-[#18211f]">
      <section className="mx-auto grid min-h-screen w-full max-w-6xl gap-8 px-5 py-6 md:grid-cols-[1fr_390px] md:items-center md:px-8">
        <div className="flex flex-col gap-8">
          <header>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-[#35766f]">
              EnglishStudy Studio
            </p>
            <h1 className="mt-4 max-w-3xl text-4xl font-semibold leading-tight tracking-normal text-[#18211f] md:text-5xl">
              语境听写学习台
            </h1>
            <p className="mt-5 max-w-2xl text-base leading-7 text-[#5b6763]">
              听一句真实语境英语，在关键词空位里输入答案。初级练核心词，中级练多个关键词，高级练整句听写。
            </p>
          </header>

          <section className="grid gap-3 sm:grid-cols-3">
            {[
              ["初级", "核心关键词空位"],
              ["中级", "多个关键词空位"],
              ["高级", "整句听写输入"],
            ].map(([title, description]) => (
              <div
                className="rounded-lg border border-[#d9e1dc] bg-white p-4 shadow-sm"
                key={title}
              >
                <h2 className="text-sm font-semibold text-[#18211f]">
                  {title}
                </h2>
                <p className="mt-2 text-sm leading-6 text-[#69736f]">
                  {description}
                </p>
              </div>
            ))}
          </section>
        </div>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          <div className="grid grid-cols-2 rounded-md bg-[#edf2ef] p-1 text-sm font-medium">
            <button
              className={`h-10 rounded-md transition ${
                mode === "login"
                  ? "bg-white text-[#18211f] shadow-sm"
                  : "text-[#64706b]"
              }`}
              onClick={() => setMode("login")}
              type="button"
            >
              登录
            </button>
            <button
              className={`h-10 rounded-md transition ${
                mode === "register"
                  ? "bg-white text-[#18211f] shadow-sm"
                  : "text-[#64706b]"
              }`}
              onClick={() => setMode("register")}
              type="button"
            >
              注册
            </button>
          </div>

          <form className="mt-5 grid gap-4" onSubmit={submit}>
            <label className="grid gap-2 text-sm font-medium text-[#283330]">
              邮箱
              <input
                className="h-11 rounded-md border border-[#cfd8d3] px-3 text-sm outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                onChange={(event) => setEmail(event.target.value)}
                type="email"
                value={email}
              />
            </label>

            <label className="grid gap-2 text-sm font-medium text-[#283330]">
              密码
              <input
                className="h-11 rounded-md border border-[#cfd8d3] px-3 text-sm outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                onChange={(event) => setPassword(event.target.value)}
                type="password"
                value={password}
              />
            </label>

            {mode === "register" ? (
              <>
                <label className="grid gap-2 text-sm font-medium text-[#283330]">
                  昵称
                  <input
                    className="h-11 rounded-md border border-[#cfd8d3] px-3 text-sm outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                    onChange={(event) => setDisplayName(event.target.value)}
                    value={displayName}
                  />
                </label>

                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="grid gap-2 text-sm font-medium text-[#283330]">
                    当前水平
                    <select
                      className="h-11 rounded-md border border-[#cfd8d3] bg-white px-3 text-sm outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                      onChange={(event) => setCurrentLevel(event.target.value)}
                      value={currentLevel}
                    >
                      <option value="beginner">初级</option>
                      <option value="intermediate">中级</option>
                      <option value="advanced">高级</option>
                    </select>
                  </label>

                  <label className="grid gap-2 text-sm font-medium text-[#283330]">
                    学习目标
                    <select
                      className="h-11 rounded-md border border-[#cfd8d3] bg-white px-3 text-sm outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                      onChange={(event) => setLearningGoal(event.target.value)}
                      value={learningGoal}
                    >
                      <option value="daily">日常交流</option>
                      <option value="campus">校园学习</option>
                      <option value="workplace">职场沟通</option>
                    </select>
                  </label>
                </div>
              </>
            ) : null}

            {error ? (
              <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
                {error}
              </p>
            ) : null}

            <button
              className="h-11 rounded-md bg-[#1f6f64] px-4 text-sm font-semibold text-white transition hover:bg-[#18574f] disabled:cursor-not-allowed disabled:bg-[#9eb9b4]"
              disabled={loading}
              type="submit"
            >
              {loading ? "处理中..." : mode === "login" ? "进入学习" : "创建账号"}
            </button>

            <button
              className="h-10 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium text-[#40504b] transition hover:bg-[#f4f7f5]"
              onClick={() => {
                setEmail("learner@example.com");
                setPassword("Pass123$");
              }}
              type="button"
            >
              使用本地演示账号
            </button>
          </form>
        </section>
      </section>
    </main>
  );
}
