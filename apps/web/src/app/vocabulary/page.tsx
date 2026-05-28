"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { WrongWord, vocabularyApi } from "@/lib/api";
import { getToken } from "@/lib/session";

export default function VocabularyPage() {
  const router = useRouter();
  const [words, setWords] = useState<WrongWord[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const token = getToken();
    if (!token) {
      router.replace("/");
      return;
    }

    vocabularyApi
      .words(token)
      .then(setWords)
      .finally(() => setLoading(false));
  }, [router]);

  return (
    <main className="min-h-screen bg-[#f4f7f5] px-5 py-6 text-[#18211f] sm:px-8">
      <section className="mx-auto grid w-full max-w-5xl gap-5">
        <header className="border-b border-[#d9e1dc] pb-5">
          <Link className="text-sm font-medium text-[#35766f]" href="/dashboard">
            返回学习台
          </Link>
          <div className="mt-2 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h1 className="text-3xl font-semibold tracking-normal">词汇本</h1>
              <p className="mt-2 text-sm text-[#69736f]">
                手动加入的生词和答错的目标词都会按复习时间重新进入语境听写。
              </p>
            </div>
            <Link
              className="h-10 rounded-md bg-[#1f6f64] px-4 py-2.5 text-center text-sm font-semibold text-white transition hover:bg-[#18574f]"
              href="/dictation?mode=beginner&review=wrong"
            >
              开始复习
            </Link>
          </div>
        </header>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          {loading ? (
            <p className="text-sm text-[#69736f]">正在加载词汇...</p>
          ) : null}

          {!loading && words.length === 0 ? (
            <p className="text-sm text-[#69736f]">暂时没有生词或错词。</p>
          ) : null}

          <div className="grid gap-3">
            {words.map((word) => (
              <div
                className="grid gap-3 rounded-lg border border-[#e3e8e5] p-4 sm:grid-cols-[1fr_180px]"
                key={word.wordId}
              >
                <div>
                  <div className="flex flex-wrap items-baseline gap-2">
                    <h2 className="text-lg font-semibold">{word.lemma}</h2>
                    {word.phonetic ? (
                      <span className="text-sm text-[#69736f]">
                        {word.phonetic}
                      </span>
                    ) : null}
                    <span className="rounded-md bg-[#eef7f4] px-2 py-1 text-xs font-semibold text-[#1f6f64]">
                      {sourceLabel(word.source)}
                    </span>
                  </div>
                  <p className="mt-2 text-sm leading-6 text-[#69736f]">
                    {word.meaningCn}
                  </p>
                  {word.sourceSentenceText ? (
                    <div className="mt-3 rounded-md bg-[#fbfcfb] px-3 py-2 text-sm">
                      <p className="font-medium leading-6 text-[#40504b]">
                        {word.sourceSentenceText}
                      </p>
                      {word.sourceSentenceTranslation ? (
                        <p className="mt-1 leading-6 text-[#69736f]">
                          {word.sourceSentenceTranslation}
                        </p>
                      ) : null}
                    </div>
                  ) : null}
                  <p className="mt-2 text-xs text-[#87908c]">
                    {word.nextReviewAt
                      ? `下次复习：${formatDateTime(word.nextReviewAt)}`
                      : "现在可以复习"}
                  </p>
                  {word.lastMistakeAt ? (
                    <p className="mt-1 text-xs text-[#87908c]">
                      最近错误：{formatDateTime(word.lastMistakeAt)}
                    </p>
                  ) : null}
                  <p className="mt-1 text-xs text-[#87908c]">
                    加入时间：{formatDateTime(word.addedAt)}
                  </p>
                </div>
                <div className="grid content-start gap-2 sm:justify-items-end">
                  <div className="flex items-center gap-2">
                    {word.mistakeCount > 0 ? (
                      <span className="rounded-md bg-[#fff3df] px-2 py-1 text-xs font-semibold text-[#8a5a00]">
                        错 {word.mistakeCount}
                      </span>
                    ) : null}
                    <span className="rounded-md bg-[#eef7f4] px-2 py-1 text-xs font-semibold text-[#1f6f64]">
                      连对 {word.correctStreak}
                    </span>
                  </div>
                  <span className="text-xs text-[#69736f]">
                    {statusLabel(word.status)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </section>
      </section>
    </main>
  );
}

function statusLabel(status: string) {
  const labels: Record<string, string> = {
    New: "未学习",
    Learning: "学习中",
    Reviewing: "复习中",
    Mastered: "已掌握",
  };

  return labels[status] ?? status;
}

function sourceLabel(source: string) {
  const labels: Record<string, string> = {
    manual: "手动加入",
    dictation: "听写错词",
  };

  return labels[source] ?? source;
}

function formatDateTime(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return `${date.getMonth() + 1}/${date.getDate()} ${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}
