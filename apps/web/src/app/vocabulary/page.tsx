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
      .wrongWords(token)
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
          <h1 className="mt-2 text-3xl font-semibold tracking-normal">
            错词本
          </h1>
        </header>

        <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
          {loading ? (
            <p className="text-sm text-[#69736f]">正在加载错词...</p>
          ) : null}

          {!loading && words.length === 0 ? (
            <p className="text-sm text-[#69736f]">暂时没有错词。</p>
          ) : null}

          <div className="grid gap-3">
            {words.map((word) => (
              <div
                className="grid gap-2 rounded-lg border border-[#e3e8e5] p-4 sm:grid-cols-[1fr_120px]"
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
                  </div>
                  <p className="mt-2 text-sm leading-6 text-[#69736f]">
                    {word.meaningCn}
                  </p>
                </div>
                <div className="flex items-center gap-2 sm:justify-end">
                  <span className="rounded-md bg-[#fff3df] px-2 py-1 text-xs font-semibold text-[#8a5a00]">
                    错 {word.mistakeCount}
                  </span>
                  <span className="rounded-md bg-[#eef7f4] px-2 py-1 text-xs font-semibold text-[#1f6f64]">
                    连对 {word.correctStreak}
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
