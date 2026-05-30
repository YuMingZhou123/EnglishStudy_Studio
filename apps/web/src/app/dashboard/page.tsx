"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useEffect, useState } from "react";
import {
  CurrentUser,
  DictationHistoryItem,
  LearningSummary,
  WrongWord,
  authApi,
  dictationApi,
  getErrorMessage,
  isAuthError,
  vocabularyApi,
} from "@/lib/api";
import { AppHeader } from "@/app/_components/AppHeader";
import { clearSession, getToken, saveCurrentUser } from "@/lib/session";

const practiceModes = [
  ["beginner", "初级听写", "听一句真实英语，补全核心词。", "适合热身"],
  ["intermediate", "场景关键词", "一次捕捉多个关键词和搭配。", "推荐进阶"],
  ["advanced", "整句听写", "完整输入句子，训练听辨和拼写。", "挑战模式"],
] as const;

export default function DashboardPage() {
  const router = useRouter();
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [history, setHistory] = useState<DictationHistoryItem[]>([]);
  const [vocabularyWords, setVocabularyWords] = useState<WrongWord[]>([]);
  const [summary, setSummary] = useState<LearningSummary | null>(null);
  const [profileForm, setProfileForm] = useState({
    displayName: "",
    currentLevel: "beginner",
    learningGoal: "daily",
  });
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMessage, setProfileMessage] = useState<{
    type: "success" | "error";
    text: string;
  } | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      router.replace("/");
      return;
    }
    const authToken = token;

    let cancelled = false;

    async function loadDashboard() {
      try {
        const currentUser = await authApi.me(authToken);
        if (cancelled) {
          return;
        }

        setUser(currentUser);
        setProfileForm({
          displayName: currentUser.displayName ?? "",
          currentLevel: currentUser.currentLevel ?? "beginner",
          learningGoal: currentUser.learningGoal ?? "daily",
        });

        const [historyItems, words, learningSummary] = await Promise.all([
          dictationApi.history(authToken, 6),
          vocabularyApi.words(authToken),
          dictationApi.summary(authToken),
        ]);

        if (cancelled) {
          return;
        }

        setHistory(historyItems);
        setVocabularyWords(words);
        setSummary(learningSummary);
      } catch (err) {
        if (isAuthError(err)) {
          clearSession();
          router.replace("/");
          return;
        }

        setLoadError(getErrorMessage(err, "学习首页加载失败"));
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadDashboard();

    return () => {
      cancelled = true;
    };
  }, [router]);

  function logout() {
    clearSession();
    router.replace("/");
  }

  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const token = getToken();
    if (!token) {
      router.replace("/");
      return;
    }

    setProfileSaving(true);
    setProfileMessage(null);

    try {
      const updatedUser = await authApi.updateMe(token, profileForm);
      setUser(updatedUser);
      setProfileForm({
        displayName: updatedUser.displayName ?? "",
        currentLevel: updatedUser.currentLevel ?? "beginner",
        learningGoal: updatedUser.learningGoal ?? "daily",
      });
      saveCurrentUser(updatedUser);
      setProfileMessage({ type: "success", text: "已保存" });
    } catch (err) {
      if (isAuthError(err)) {
        clearSession();
        router.replace("/");
        return;
      }

      setProfileMessage({
        type: "error",
        text: getErrorMessage(err, "保存失败"),
      });
    } finally {
      setProfileSaving(false);
    }
  }

  const dailyGoal = summary?.dailyDictationGoal ?? 10;
  const todayAttemptCount = summary?.todayAttemptCount ?? 0;
  const todayProgress = Math.min(
    100,
    Math.round((todayAttemptCount / Math.max(1, dailyGoal)) * 100),
  );
  const nextMode = user?.currentLevel ?? "beginner";
  const dueReviewCount = summary?.dueReviewCount ?? vocabularyWords.length;
  const displayName = user?.displayName ?? user?.email ?? "Learner";
  const canManageContent =
    user?.roles.some((role) => role === "Admin" || role === "ContentAdmin") ??
    false;

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f2f7ed] text-[#40504b]">
        正在加载学习首页...
      </main>
    );
  }

  if (loadError && !user) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f2f7ed] px-5 text-[#40504b]">
        <section className="w-full max-w-md rounded-lg border border-[#d8e4d7] bg-white p-5 shadow-sm">
          <p className="text-sm font-semibold text-[#b24b2a]">{loadError}</p>
          <button
            className="mt-4 h-10 rounded-md bg-[#2e8b45] px-4 text-sm font-semibold text-white transition hover:bg-[#237238]"
            onClick={() => window.location.reload()}
            type="button"
          >
            重新加载
          </button>
        </section>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f2f7ed] text-[#17201d]">
      <AppHeader active="home" onLogout={logout} showAdmin={canManageContent} />

      <section className="mx-auto grid w-full max-w-7xl gap-6 px-5 py-6 sm:px-8 lg:grid-cols-[1fr_340px]">
        <div className="grid gap-6">
          <section className="overflow-hidden rounded-lg border border-[#d8e4d7] bg-[#dff0d8] shadow-sm">
            <div className="grid gap-6 p-6 lg:grid-cols-[1fr_280px] lg:items-center lg:p-8">
              <div>
                <p className="text-sm font-semibold text-[#237238]">
                  Hi, {displayName}
                </p>
                <h1 className="mt-3 max-w-2xl text-4xl font-semibold leading-tight md:text-5xl">
                  继续今天的语境听写
                </h1>
                <p className="mt-4 max-w-xl text-base leading-7 text-[#4e665a]">
                  今天先完成一组短句训练，再把答错的词放回真实句子里复习。
                </p>
                <div className="mt-6 flex flex-wrap gap-3">
                  <Link
                    className="rounded-md bg-[#2e8b45] px-5 py-3 text-sm font-semibold text-white shadow-[0_14px_28px_rgba(46,139,69,0.22)] transition hover:bg-[#237238]"
                    href={`/dictation?mode=${nextMode}`}
                  >
                    开始下一课
                  </Link>
                  <Link
                    className="rounded-md border border-[#b9d1bd] bg-white/55 px-5 py-3 text-sm font-semibold text-[#2e7043] transition hover:bg-white"
                    href={`/dictation?mode=${nextMode}&review=wrong`}
                  >
                    复习 {dueReviewCount} 个词
                  </Link>
                </div>
              </div>

              <div className="rounded-lg border border-white/70 bg-white/62 p-4 shadow-sm">
                <p className="text-xs font-semibold uppercase text-[#237238]">
                  Today&apos;s lesson
                </p>
                <p className="mt-3 text-lg font-semibold leading-8">
                  I booked a <span className="rounded-md bg-[#e6f1e1] px-4 py-1">____</span> near the station.
                </p>
                <div className="mt-4 h-2 overflow-hidden rounded-full bg-white">
                  <div
                    className="h-full rounded-full bg-[#2e8b45]"
                    style={{ width: `${todayProgress}%` }}
                  />
                </div>
                <p className="mt-3 text-sm text-[#5d7068]">
                  今日 {todayAttemptCount}/{dailyGoal} 句 · {todayProgress}%
                </p>
              </div>
            </div>
          </section>

          {loadError ? (
            <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
              {loadError}
            </p>
          ) : null}

          <section>
            <div className="flex items-end justify-between gap-4">
              <div>
                <h2 className="text-2xl font-semibold">学习路径</h2>
                <p className="mt-2 text-sm text-[#62706b]">
                  像课程一样顺着走，先练听写，再回收错词。
                </p>
              </div>
              <span className="hidden rounded-full bg-[#e6f1e1] px-3 py-1 text-xs font-semibold text-[#237238] sm:inline">
                当前水平：{levelLabel(user?.currentLevel ?? "beginner")}
              </span>
            </div>

            <div className="mt-5 grid gap-3">
              <LessonRow
                href={`/dictation?mode=${nextMode}`}
                index="1"
                status="继续"
                title={`${levelLabel(nextMode)}语境听写`}
                description="听一句真实英语，补全空位后立即得到反馈。"
              />
              <LessonRow
                href={`/dictation?mode=${nextMode}&review=wrong`}
                index="2"
                status={dueReviewCount > 0 ? "待复习" : "可选"}
                title="错词回到句子里"
                description="不是孤立背词，而是在原来的语境里重新听、重新写。"
              />
              <LessonRow
                href="/reports"
                index="3"
                status="回顾"
                title="查看最近练习"
                description="看最近哪些句子丢分，决定下一次练初级、中级还是高级。"
              />
            </div>
          </section>

          <section>
            <div className="flex items-center justify-between gap-4">
              <h2 className="text-2xl font-semibold">选择一节短课</h2>
              <span className="text-sm text-[#62706b]">每节约 3-5 分钟</span>
            </div>
            <div className="mt-5 grid gap-3 md:grid-cols-3">
              {practiceModes.map(([mode, title, description, note]) => (
                <Link
                  className="rounded-lg border border-[#d8e4d7] bg-white p-4 shadow-sm transition hover:border-[#7db38b] hover:bg-[#fbfff8]"
                  href={`/dictation?mode=${mode}`}
                  key={mode}
                >
                  <div className="flex items-center justify-between gap-2">
                    <h3 className="text-lg font-semibold">{title}</h3>
                    {nextMode === mode ? (
                      <span className="rounded-md bg-[#e6f1e1] px-2 py-1 text-xs font-semibold text-[#237238]">
                        推荐
                      </span>
                    ) : null}
                  </div>
                  <p className="mt-3 text-sm font-medium text-[#315b8c]">
                    {description}
                  </p>
                  <p className="mt-3 text-sm leading-6 text-[#62706b]">{note}</p>
                </Link>
              ))}
            </div>
          </section>
        </div>

        <aside className="grid content-start gap-5">
          <section className="rounded-lg border border-[#d8e4d7] bg-white p-5 shadow-sm">
            <h2 className="text-xl font-semibold">复习队列</h2>
            <div className="mt-4 grid gap-3">
              {vocabularyWords.slice(0, 5).map((word) => (
                <div
                  className="border-b border-[#eef2ef] pb-3 last:border-b-0 last:pb-0"
                  key={word.wordId}
                >
                  <div className="flex items-center justify-between gap-3">
                    <p className="font-semibold">{word.lemma}</p>
                    <span
                      className={`rounded-md px-2 py-1 text-xs font-semibold ${
                        word.mistakeCount > 0
                          ? "bg-[#fff3df] text-[#8a5a00]"
                          : "bg-[#e6f1e1] text-[#237238]"
                      }`}
                    >
                      {word.mistakeCount > 0
                        ? `错 ${word.mistakeCount}`
                        : sourceLabel(word.source)}
                    </span>
                  </div>
                  <p className="mt-1 text-sm leading-6 text-[#62706b]">
                    {word.meaningCn}
                  </p>
                </div>
              ))}
              {vocabularyWords.length === 0 ? (
                <p className="text-sm text-[#62706b]">还没有词汇记录。</p>
              ) : null}
            </div>
            <Link
              className="mt-4 inline-flex text-sm font-semibold text-[#237238]"
              href="/vocabulary"
            >
              打开我的复习
            </Link>
          </section>

          <section className="rounded-lg border border-[#d8e4d7] bg-white p-5 shadow-sm">
            <h2 className="text-xl font-semibold">最近学过</h2>
            <div className="mt-4 grid gap-3">
              {history.slice(0, 4).map((item) => (
                <Link
                  className="block rounded-md bg-[#f6faf3] px-3 py-3 text-sm transition hover:bg-[#e6f1e1]"
                  href={`/dictation?mode=${item.mode}`}
                  key={item.attemptId}
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="font-semibold text-[#315b8c]">
                      {levelLabel(item.mode)}
                    </span>
                    <span
                      className={
                        item.isCorrect
                          ? "font-semibold text-[#237238]"
                          : "font-semibold text-[#b24b2a]"
                      }
                    >
                      {item.score} 分
                    </span>
                  </div>
                  <p className="mt-2 line-clamp-2 leading-6 text-[#4e665a]">
                    {item.sentenceText}
                  </p>
                </Link>
              ))}
              {history.length === 0 ? (
                <p className="text-sm text-[#62706b]">还没有练习记录。</p>
              ) : null}
            </div>
          </section>

          <section className="rounded-lg border border-[#d8e4d7] bg-[#fbfff8] p-5 shadow-sm">
            <details>
              <summary className="cursor-pointer text-sm font-semibold text-[#40504b]">
                调整学习资料
              </summary>
              <form className="mt-4 grid gap-3" onSubmit={saveProfile}>
                <label className="grid gap-2 text-sm font-medium text-[#283330]">
                  昵称
                  <input
                    className="h-10 rounded-md border border-[#cfd8d3] px-3 text-sm outline-none transition focus:border-[#2e8b45] focus:ring-2 focus:ring-[#2e8b45]/15"
                    onChange={(event) =>
                      setProfileForm((current) => ({
                        ...current,
                        displayName: event.target.value,
                      }))
                    }
                    value={profileForm.displayName}
                  />
                </label>

                <label className="grid gap-2 text-sm font-medium text-[#283330]">
                  当前水平
                  <select
                    className="h-10 rounded-md border border-[#cfd8d3] bg-white px-3 text-sm outline-none transition focus:border-[#2e8b45] focus:ring-2 focus:ring-[#2e8b45]/15"
                    onChange={(event) =>
                      setProfileForm((current) => ({
                        ...current,
                        currentLevel: event.target.value,
                      }))
                    }
                    value={profileForm.currentLevel}
                  >
                    <option value="beginner">初级</option>
                    <option value="intermediate">中级</option>
                    <option value="advanced">高级</option>
                  </select>
                </label>

                <label className="grid gap-2 text-sm font-medium text-[#283330]">
                  学习目标
                  <select
                    className="h-10 rounded-md border border-[#cfd8d3] bg-white px-3 text-sm outline-none transition focus:border-[#2e8b45] focus:ring-2 focus:ring-[#2e8b45]/15"
                    onChange={(event) =>
                      setProfileForm((current) => ({
                        ...current,
                        learningGoal: event.target.value,
                      }))
                    }
                    value={profileForm.learningGoal}
                  >
                    <option value="daily">日常交流</option>
                    <option value="campus">校园学习</option>
                    <option value="workplace">职场沟通</option>
                  </select>
                </label>

                <button
                  className="h-10 rounded-md bg-[#2e8b45] px-4 text-sm font-semibold text-white transition hover:bg-[#237238] disabled:cursor-not-allowed disabled:bg-[#8eb79a]"
                  disabled={profileSaving}
                  type="submit"
                >
                  {profileSaving ? "保存中..." : "保存"}
                </button>
                {profileMessage ? (
                  <span
                    className={`text-sm font-medium ${
                      profileMessage.type === "success"
                        ? "text-[#237238]"
                        : "text-[#b24b2a]"
                    }`}
                  >
                    {profileMessage.text}
                  </span>
                ) : null}
              </form>
            </details>
          </section>
        </aside>
      </section>
    </main>
  );
}

function LessonRow({
  href,
  index,
  status,
  title,
  description,
}: {
  href: string;
  index: string;
  status: string;
  title: string;
  description: string;
}) {
  return (
    <Link
      className="grid gap-4 rounded-lg border border-[#d8e4d7] bg-white p-4 shadow-sm transition hover:border-[#7db38b] hover:bg-[#fbfff8] sm:grid-cols-[52px_1fr_auto] sm:items-center"
      href={href}
    >
      <span className="flex h-12 w-12 items-center justify-center rounded-full bg-[#e6f1e1] text-base font-semibold text-[#237238]">
        {index}
      </span>
      <span>
        <span className="block text-lg font-semibold">{title}</span>
        <span className="mt-1 block text-sm leading-6 text-[#62706b]">
          {description}
        </span>
      </span>
      <span className="w-fit rounded-full bg-[#f4f8ef] px-3 py-1 text-xs font-semibold text-[#4e665a]">
        {status}
      </span>
    </Link>
  );
}

function levelLabel(level: string) {
  const labels: Record<string, string> = {
    beginner: "初级",
    intermediate: "中级",
    advanced: "高级",
  };
  return labels[level] ?? "初级";
}

function sourceLabel(source: string) {
  const labels: Record<string, string> = {
    manual: "生词",
    dictation: "听写",
  };

  return labels[source] ?? source;
}
