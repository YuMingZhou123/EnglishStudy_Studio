"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { authApi, getErrorMessage } from "@/lib/api";
import { clearSession, getToken, saveSession } from "@/lib/session";

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
        clearSession();
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
      setError(getErrorMessage(err, "登录失败"));
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="relative min-h-screen overflow-hidden bg-[#dfeee3] text-[#1c2a23]">
      <div
        className="absolute inset-0 bg-cover bg-center"
        style={{ backgroundImage: "url('/alpine-login-bg.png')" }}
      />
      <div className="absolute inset-0 bg-[linear-gradient(90deg,rgba(17,62,38,0.62),rgba(25,82,50,0.24)_48%,rgba(231,242,225,0.86)_72%,rgba(231,242,225,0.98))]" />

      <section className="relative mx-auto grid min-h-screen w-full max-w-6xl items-center gap-8 px-5 py-8 md:grid-cols-[1fr_430px] md:px-8">
        <div className="hidden text-white md:block">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-white/78">
            EnglishStudy Studio
          </p>
          <h1 className="mt-5 max-w-xl text-5xl font-semibold leading-tight">
            在真实场景里听懂英语
          </h1>
        </div>

        <section className="rounded-lg border border-white/64 bg-white/78 p-7 shadow-[0_24px_70px_rgba(30,73,41,0.22)] backdrop-blur-md">
          <div>
            <p className="text-sm font-semibold uppercase text-[#2f8a55]">
              Welcome back
            </p>
            <h2 className="mt-2 text-3xl font-semibold">
              {mode === "login" ? "进入学习" : "创建账号"}
            </h2>
          </div>

          <div className="mt-7 grid grid-cols-2 border-b border-[#d8e1dc] text-base font-semibold">
            <button
              className={`relative h-12 transition ${
                mode === "login"
                  ? "text-[#2f8a55] after:absolute after:bottom-[-1px] after:left-0 after:h-0.5 after:w-full after:bg-[#2f8a55]"
                  : "text-[#7d8a83] hover:text-[#426157]"
              }`}
              onClick={() => setMode("login")}
              type="button"
            >
              登录
            </button>
            <button
              className={`relative h-12 transition ${
                mode === "register"
                  ? "text-[#2f8a55] after:absolute after:bottom-[-1px] after:left-0 after:h-0.5 after:w-full after:bg-[#2f8a55]"
                  : "text-[#7d8a83] hover:text-[#426157]"
              }`}
              onClick={() => setMode("register")}
              type="button"
            >
              注册
            </button>
          </div>

          <form className="mt-6 grid gap-4" onSubmit={submit}>
            <label className="grid gap-2 text-sm font-medium text-[#293833]">
              邮箱
              <span className="grid h-11 grid-cols-[40px_1fr] items-center rounded-md border border-[#cbd8c8] bg-white/92 px-3 transition focus-within:border-[#2f8a55] focus-within:ring-2 focus-within:ring-[#2f8a55]/15">
                <span className="text-sm font-semibold text-[#89a091]">@</span>
                <input
                  className="h-full min-w-0 bg-transparent text-sm outline-none placeholder:text-[#9aa6a1]"
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="用户名 / 邮箱"
                  type="email"
                  value={email}
                />
              </span>
            </label>

            <label className="grid gap-2 text-sm font-medium text-[#293833]">
              密码
              <span className="grid h-11 grid-cols-[40px_1fr] items-center rounded-md border border-[#cbd8c8] bg-white/92 px-3 transition focus-within:border-[#2f8a55] focus-within:ring-2 focus-within:ring-[#2f8a55]/15">
                <span className="text-xs font-semibold text-[#89a091]">PW</span>
                <input
                  className="h-full min-w-0 bg-transparent text-sm outline-none placeholder:text-[#9aa6a1]"
                  onChange={(event) => setPassword(event.target.value)}
                  placeholder="密码"
                  type="password"
                  value={password}
                />
              </span>
            </label>

            {mode === "register" ? (
              <>
                <label className="grid gap-2 text-sm font-medium text-[#293833]">
                  昵称
                  <input
                    className="h-11 rounded-md border border-[#cbd8c8] bg-white/92 px-3 text-sm outline-none transition focus:border-[#2f8a55] focus:ring-2 focus:ring-[#2f8a55]/15"
                    onChange={(event) => setDisplayName(event.target.value)}
                    value={displayName}
                  />
                </label>

                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="grid gap-2 text-sm font-medium text-[#293833]">
                    当前水平
                    <select
                      className="h-11 rounded-md border border-[#cbd8c8] bg-white/92 px-3 text-sm outline-none transition focus:border-[#2f8a55] focus:ring-2 focus:ring-[#2f8a55]/15"
                      onChange={(event) => setCurrentLevel(event.target.value)}
                      value={currentLevel}
                    >
                      <option value="beginner">初级</option>
                      <option value="intermediate">中级</option>
                      <option value="advanced">高级</option>
                    </select>
                  </label>

                  <label className="grid gap-2 text-sm font-medium text-[#293833]">
                    学习目标
                    <select
                      className="h-11 rounded-md border border-[#cbd8c8] bg-white/92 px-3 text-sm outline-none transition focus:border-[#2f8a55] focus:ring-2 focus:ring-[#2f8a55]/15"
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

            <div className="flex items-center justify-between gap-4 text-sm text-[#6d7a73]">
              <label className="flex items-center gap-2">
                <input
                  className="h-4 w-4 accent-[#2f8a55]"
                  defaultChecked
                  type="checkbox"
                />
                记住我
              </label>
              <button
                className="font-medium text-[#2f8a55] transition hover:text-[#247244]"
                type="button"
              >
                忘记密码？
              </button>
            </div>

            {error ? (
              <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
                {error}
              </p>
            ) : null}

            <button
              className="mt-1 h-11 rounded-md bg-[#2f8a55] px-4 text-sm font-semibold text-white shadow-[0_14px_30px_rgba(47,138,85,0.24)] transition hover:bg-[#247244] disabled:cursor-not-allowed disabled:bg-[#a9cfb7]"
              disabled={loading}
              type="submit"
            >
              {loading ? "处理中..." : mode === "login" ? "进入学习" : "创建账号"}
            </button>

            <div className="grid grid-cols-[1fr_auto_1fr] items-center gap-4 py-1 text-xs font-medium text-[#9ca7a1]">
              <span className="h-px bg-[#d8e1dc]" />
              或
              <span className="h-px bg-[#d8e1dc]" />
            </div>

            <button
              className="h-10 rounded-md border border-[#b9d1bd] bg-[#eef7e8] px-3 text-sm font-semibold text-[#2f8a55] transition hover:bg-[#e2f0d8]"
              onClick={() => {
                setEmail("learner@example.com");
                setPassword("Pass123$");
              }}
              type="button"
            >
              使用本地演示账号
            </button>
          </form>

          <div className="mt-6 rounded-md border border-[#d9e8dd] bg-white/62 p-4">
            <p className="text-xs font-semibold uppercase text-[#2f8a55]">
              Today&apos;s practice
            </p>
            <p className="mt-2 text-base font-semibold leading-7">
              I booked a <span className="rounded bg-[#e7f3ed] px-3 py-1">____</span>{" "}
              near the station.
            </p>
          </div>
        </section>
      </section>
    </main>
  );
}
