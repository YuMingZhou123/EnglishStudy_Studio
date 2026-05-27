"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  CurrentUser,
  DictationHistoryItem,
  LearningSummary,
  WrongWord,
  authApi,
  dictationApi,
  vocabularyApi,
} from "@/lib/api";
import { clearSession, getToken } from "@/lib/session";

export default function DashboardPage() {
  const router = useRouter();
  const [user, setUser] = useState<CurrentUser | null>(null);
  const [history, setHistory] = useState<DictationHistoryItem[]>([]);
  const [wrongWords, setWrongWords] = useState<WrongWord[]>([]);
  const [summary, setSummary] = useState<LearningSummary | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      router.replace("/");
      return;
    }

    Promise.all([
      authApi.me(token),
      dictationApi.history(token, 6),
      vocabularyApi.wrongWords(token),
      dictationApi.summary(token),
    ])
      .then(([currentUser, historyItems, words, learningSummary]) => {
        setUser(currentUser);
        setHistory(historyItems);
        setWrongWords(words);
        setSummary(learningSummary);
      })
      .catch(() => {
        clearSession();
        router.replace("/");
      })
      .finally(() => setLoading(false));
  }, [router]);

  function logout() {
    clearSession();
    router.replace("/");
  }

  const dailyGoal = summary?.dailyDictationGoal ?? 10;
  const todayAttemptCount = summary?.todayAttemptCount ?? 0;
  const todayProgress = Math.min(
    100,
    Math.round((todayAttemptCount / Math.max(1, dailyGoal)) * 100),
  );
  const nextMode = user?.currentLevel ?? "beginner";

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f4f7f5] text-[#40504b]">
        正在加载学习台...
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f4f7f5] px-5 py-6 text-[#18211f] sm:px-8">
      <section className="mx-auto grid w-full max-w-6xl gap-6">
        <header className="flex flex-col gap-4 border-b border-[#d9e1dc] pb-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-[#35766f]">
              Learning Desk
            </p>
            <h1 className="mt-2 text-3xl font-semibold tracking-normal">
              {user?.displayName ?? user?.email}，开始今天的语境听写
            </h1>
          </div>
          <button
            className="h-10 rounded-md border border-[#cfd8d3] px-4 text-sm font-medium text-[#40504b] transition hover:bg-white"
            onClick={logout}
            type="button"
          >
            退出
          </button>
          {user?.roles.some((role) => role === "Admin" || role === "ContentAdmin") ? (
            <Link
              className="h-10 rounded-md bg-[#1f6f64] px-4 py-2.5 text-center text-sm font-semibold text-white transition hover:bg-[#18574f]"
              href="/admin"
            >
              内容后台
            </Link>
          ) : null}
        </header>

        <section className="grid gap-4 md:grid-cols-4">
          <SummaryCard label="今日进度" value={`${todayAttemptCount}/${dailyGoal}`} />
          <SummaryCard
            label="今日正确率"
            value={`${summary?.todayAccuracy ?? 0}%`}
          />
          <SummaryCard
            label="待复习错词"
            value={`${summary?.dueReviewCount ?? wrongWords.length} 个`}
          />
          <SummaryCard
            label="当前水平"
            value={levelLabel(user?.currentLevel ?? "beginner")}
          />
        </section>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <h2 className="text-lg font-semibold">今日任务</h2>
              <p className="mt-1 text-sm leading-6 text-[#69736f]">
                完成 {dailyGoal} 句语境听写，优先保持连续学习节奏。
              </p>
            </div>
            <div className="flex flex-wrap gap-2">
              <Link
                className="h-10 rounded-md bg-[#1f6f64] px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-[#18574f]"
                href={`/dictation?mode=${nextMode}`}
              >
                继续训练
              </Link>
              <Link
                className="h-10 rounded-md border border-[#cfd8d3] px-4 py-2.5 text-sm font-medium text-[#40504b] transition hover:bg-[#f4f7f5]"
                href="/vocabulary"
              >
                复习错词
              </Link>
            </div>
          </div>

          <div className="mt-5">
            <div className="flex items-center justify-between text-sm">
              <span className="font-medium text-[#40504b]">
                已完成 {todayAttemptCount} 句
              </span>
              <span className="text-[#69736f]">{todayProgress}%</span>
            </div>
            <div className="mt-2 h-3 overflow-hidden rounded-full bg-[#edf2ef]">
              <div
                className="h-full rounded-full bg-[#1f6f64] transition-all"
                style={{ width: `${todayProgress}%` }}
              />
            </div>
          </div>

          <div className="mt-5 grid gap-3 sm:grid-cols-[160px_1fr]">
            <div className="rounded-md bg-[#f4f7f5] px-3 py-2 text-sm">
              <p className="font-semibold text-[#18211f]">
                连续 {summary?.currentStreakDays ?? 0} 天
              </p>
              <p className="mt-1 text-[#69736f]">
                累计练习 {summary?.totalAttemptCount ?? 0} 次
              </p>
            </div>
            <div className="grid grid-cols-7 items-end gap-2">
              {(summary?.recentDays ?? []).map((day) => (
                <div className="grid gap-1 text-center text-xs" key={day.date}>
                  <div className="flex h-16 items-end justify-center rounded-md bg-[#f4f7f5] px-1">
                    <div
                      className="w-full rounded-t bg-[#8fb9ad]"
                      style={{
                        height: `${Math.max(8, Math.min(100, day.accuracy || 0))}%`,
                      }}
                    />
                  </div>
                  <span className="text-[#69736f]">{formatDay(day.date)}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="grid gap-4 lg:grid-cols-[1fr_0.8fr]">
          <div className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
            <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 className="text-lg font-semibold">语境听写</h2>
                <p className="mt-1 text-sm leading-6 text-[#69736f]">
                  选择难度后进入题目，播放句子并提交答案。
                </p>
              </div>
            </div>

            <div className="mt-5 grid gap-3 sm:grid-cols-3">
              {[
                ["beginner", "初级", "核心词空位"],
                ["intermediate", "中级", "多个词空位"],
                ["advanced", "高级", "整句听写"],
              ].map(([mode, title, description]) => (
                <Link
                  className="rounded-lg border border-[#d9e1dc] p-4 transition hover:border-[#1f6f64] hover:bg-[#f6fbf9]"
                  href={`/dictation?mode=${mode}`}
                  key={mode}
                >
                  <h3 className="text-base font-semibold">{title}</h3>
                  <p className="mt-2 text-sm text-[#69736f]">{description}</p>
                </Link>
              ))}
            </div>
          </div>

          <div className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
            <div className="flex items-center justify-between gap-3">
              <h2 className="text-lg font-semibold">错词本</h2>
              <Link
                className="text-sm font-medium text-[#1f6f64]"
                href="/vocabulary"
              >
                查看全部
              </Link>
            </div>
            <div className="mt-4 grid gap-3">
              {wrongWords.slice(0, 5).map((word) => (
                <div
                  className="flex items-center justify-between gap-3 border-b border-[#eef2ef] pb-3 last:border-b-0 last:pb-0"
                  key={word.wordId}
                >
                  <div>
                    <p className="font-semibold">{word.lemma}</p>
                    <p className="mt-1 text-sm text-[#69736f]">
                      {word.meaningCn}
                    </p>
                  </div>
                  <span className="rounded-md bg-[#fff3df] px-2 py-1 text-xs font-semibold text-[#8a5a00]">
                    错 {word.mistakeCount}
                  </span>
                </div>
              ))}
              {wrongWords.length === 0 ? (
                <p className="text-sm text-[#69736f]">还没有错词记录。</p>
              ) : null}
            </div>
          </div>
        </section>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          <h2 className="text-lg font-semibold">最近练习</h2>
          <div className="mt-4 grid gap-3">
            {history.map((item) => (
              <div
                className="grid gap-2 border-b border-[#eef2ef] pb-3 text-sm last:border-b-0 last:pb-0 sm:grid-cols-[90px_1fr_80px]"
                key={item.attemptId}
              >
                <span className="font-medium text-[#35766f]">
                  {levelLabel(item.mode)}
                </span>
                <span className="text-[#40504b]">{item.sentenceText}</span>
                <span
                  className={
                    item.isCorrect
                      ? "font-semibold text-[#1f6f64]"
                      : "font-semibold text-[#b24b2a]"
                  }
                >
                  {item.score} 分
                </span>
              </div>
            ))}
            {history.length === 0 ? (
              <p className="text-sm text-[#69736f]">还没有练习记录。</p>
            ) : null}
          </div>
        </section>
      </section>
    </main>
  );
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
      <p className="text-sm font-medium text-[#69736f]">{label}</p>
      <p className="mt-3 text-2xl font-semibold">{value}</p>
    </div>
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

function formatDay(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value.slice(5);
  }

  return `${date.getMonth() + 1}/${date.getDate()}`;
}
