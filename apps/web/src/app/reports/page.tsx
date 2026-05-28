"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import {
  DictationHistoryItem,
  LearningSummary,
  dictationApi,
  getErrorMessage,
  isAuthError,
} from "@/lib/api";
import { clearSession, getToken } from "@/lib/session";

export default function ReportsPage() {
  const router = useRouter();
  const [history, setHistory] = useState<DictationHistoryItem[]>([]);
  const [summary, setSummary] = useState<LearningSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      router.replace("/");
      return;
    }

    Promise.all([
      dictationApi.summary(token),
      dictationApi.history(token, 50),
    ])
      .then(([learningSummary, historyItems]) => {
        setSummary(learningSummary);
        setHistory(historyItems);
      })
      .catch((err) => {
        if (isAuthError(err)) {
          clearSession();
          router.replace("/");
          return;
        }

        setError(getErrorMessage(err, "学习记录加载失败"));
      })
      .finally(() => setLoading(false));
  }, [router]);

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f4f7f5] text-[#40504b]">
        正在加载学习记录...
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f4f7f5] px-5 py-6 text-[#18211f] sm:px-8">
      <section className="mx-auto grid w-full max-w-6xl gap-5">
        <header className="border-b border-[#d9e1dc] pb-5">
          <Link className="text-sm font-medium text-[#35766f]" href="/dashboard">
            返回学习台
          </Link>
          <h1 className="mt-2 text-3xl font-semibold tracking-normal">
            学习记录
          </h1>
        </header>

        {error ? (
          <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
            {error}
          </p>
        ) : null}

        <section className="grid gap-4 md:grid-cols-4">
          <MetricCard
            label="累计练习"
            value={`${summary?.totalAttemptCount ?? 0} 次`}
          />
          <MetricCard
            label="学习天数"
            value={`${summary?.learningDayCount ?? 0} 天`}
          />
          <MetricCard
            label="连续学习"
            value={`${summary?.currentStreakDays ?? 0} 天`}
          />
          <MetricCard
            label="近 7 日正确率"
            value={`${summary?.recentAccuracy ?? 0}%`}
          />
        </section>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 className="text-lg font-semibold">近 7 日趋势</h2>
              <p className="mt-1 text-sm text-[#69736f]">
                按每天的听写正确率和练习次数汇总。
              </p>
            </div>
            <span className="text-sm font-medium text-[#40504b]">
              今日 {summary?.todayAttemptCount ?? 0}/{summary?.dailyDictationGoal ?? 10}
            </span>
          </div>

          <div className="mt-5 grid grid-cols-7 items-end gap-2">
            {(summary?.recentDays ?? []).map((day) => (
              <div className="grid gap-2 text-center text-xs" key={day.date}>
                <div className="flex h-24 items-end justify-center rounded-md bg-[#f4f7f5] px-1">
                  <div
                    className="w-full rounded-t bg-[#8fb9ad]"
                    style={{
                      height: `${Math.max(8, Math.min(100, day.accuracy || 0))}%`,
                    }}
                  />
                </div>
                <span className="font-medium text-[#40504b]">
                  {day.accuracy}%
                </span>
                <span className="text-[#69736f]">
                  {formatDay(day.date)} / {day.attemptCount}
                </span>
              </div>
            ))}
          </div>
        </section>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          <h2 className="text-lg font-semibold">练习明细</h2>
          <div className="mt-4 grid gap-3">
            {history.map((item) => (
              <div
                className="grid gap-2 border-b border-[#eef2ef] pb-3 text-sm last:border-b-0 last:pb-0 lg:grid-cols-[86px_1fr_120px_76px]"
                key={item.attemptId}
              >
                <span className="font-medium text-[#35766f]">
                  {modeLabel(item.mode)}
                </span>
                <div>
                  <p className="font-medium text-[#40504b]">
                    {item.sentenceText}
                  </p>
                  <p className="mt-1 text-[#69736f]">{item.translation}</p>
                </div>
                <span className="text-[#69736f]">
                  {formatDateTime(item.createdAt)}
                </span>
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

function MetricCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
      <p className="text-sm font-medium text-[#69736f]">{label}</p>
      <p className="mt-3 text-2xl font-semibold">{value}</p>
    </div>
  );
}

function modeLabel(mode: string) {
  const labels: Record<string, string> = {
    beginner: "初级",
    intermediate: "中级",
    advanced: "高级",
  };

  return labels[mode] ?? mode;
}

function formatDay(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value.slice(5);
  }

  return `${date.getMonth() + 1}/${date.getDate()}`;
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return `${date.getMonth() + 1}/${date.getDate()} ${String(
    date.getHours(),
  ).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}
