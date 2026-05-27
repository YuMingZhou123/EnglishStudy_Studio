"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  DictationMode,
  DictationQuestion,
  DictationSubmitResult,
  dictationApi,
  vocabularyApi,
} from "@/lib/api";
import { getToken } from "@/lib/session";

export default function DictationPage() {
  const router = useRouter();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [token] = useState<string | null>(() =>
    typeof window === "undefined" ? null : getToken(),
  );
  const [mode, setMode] = useState<DictationMode>(() =>
    typeof window === "undefined"
      ? "beginner"
      : normalizeMode(new URLSearchParams(window.location.search).get("mode")),
  );
  const [isReviewMode] = useState(() =>
    typeof window === "undefined"
      ? false
      : new URLSearchParams(window.location.search).get("review") === "wrong",
  );
  const [question, setQuestion] = useState<DictationQuestion | null>(null);
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [fullAnswer, setFullAnswer] = useState("");
  const [result, setResult] = useState<DictationSubmitResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [showFirstLetters, setShowFirstLetters] = useState(false);
  const [showMeaning, setShowMeaning] = useState(false);
  const [replayCount, setReplayCount] = useState(0);
  const [startedAt, setStartedAt] = useState(() => Date.now());

  const loadQuestion = useCallback(
    async (authToken = token, nextMode = mode) => {
      if (!authToken) {
        return;
      }

      setLoading(true);
      setError(null);
      setResult(null);
      setAnswers({});
      setFullAnswer("");
      setShowFirstLetters(false);
      setShowMeaning(false);
      setReplayCount(0);
      setStartedAt(Date.now());

      try {
        const nextQuestion = isReviewMode
          ? await vocabularyApi.reviewNext(authToken, nextMode)
          : await dictationApi.next(authToken, nextMode);
        setQuestion(nextQuestion);
      } catch (err) {
        setError(err instanceof Error ? err.message : "题目加载失败");
      } finally {
        setLoading(false);
      }
    },
    [isReviewMode, mode, token],
  );

  useEffect(() => {
    if (!token) {
      router.replace("/");
      return;
    }

    const timer = window.setTimeout(() => {
      loadQuestion(token, mode);
    }, 0);

    return () => window.clearTimeout(timer);
  }, [loadQuestion, mode, router, token]);

  const blankParts = useMemo(
    () => question?.displayParts.filter((part) => part.type === "blank") ?? [],
    [question],
  );

  async function submit() {
    if (!token || !question) {
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      const submitResult = await dictationApi.submit(token, {
        sentenceId: question.sentenceId,
        mode,
        answers:
          mode === "advanced"
            ? []
            : blankParts.map((part) => ({
                blankId: part.blankId ?? "",
                value: answers[part.blankId ?? ""] ?? "",
              })),
        userAnswer: mode === "advanced" ? fullAnswer : null,
        durationMs: Date.now() - startedAt,
        replayCount,
        hintCount: Number(showFirstLetters) + Number(showMeaning),
        reviewWordId: question.reviewWordId ?? null,
      });

      setResult(submitResult);
    } catch (err) {
      setError(err instanceof Error ? err.message : "提交失败");
    } finally {
      setSubmitting(false);
    }
  }

  async function playQuestionAudio(rate = 1) {
    if (!question) {
      return;
    }

    const audio = audioRef.current;
    const audioSource =
      rate < 1 && question.slowAudioUrl ? question.slowAudioUrl : question.audioUrl;

    if (audio && audioSource) {
      window.speechSynthesis?.cancel();
      audio.pause();
      audio.src = audioSource;
      audio.currentTime = 0;
      audio.playbackRate = rate < 1 && question.slowAudioUrl ? 1 : rate;

      try {
        await audio.play();
        setReplayCount((count) => count + 1);
        return;
      } catch {
        // Fall through to browser TTS when autoplay policies or media loading fail.
      }
    }

    speakWithBrowserVoice(rate);
  }

  function speakWithBrowserVoice(rate = 1) {
    if (!question || !("speechSynthesis" in window)) {
      return;
    }

    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(question.speechText);
    utterance.lang = "en-US";
    utterance.rate = rate;
    window.speechSynthesis.speak(utterance);
    setReplayCount((count) => count + 1);
  }

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f4f7f5] text-[#40504b]">
        正在准备题目...
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f4f7f5] px-5 py-6 text-[#18211f] sm:px-8">
      <section className="mx-auto grid w-full max-w-5xl gap-5">
        <header className="flex flex-col gap-4 border-b border-[#d9e1dc] pb-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <Link className="text-sm font-medium text-[#35766f]" href="/dashboard">
              返回学习台
            </Link>
            <h1 className="mt-2 text-3xl font-semibold tracking-normal">
              {isReviewMode ? "错词复习" : `${modeLabel(mode)}语境听写`}
            </h1>
          </div>
          <div className="flex gap-2">
            {(["beginner", "intermediate", "advanced"] as DictationMode[]).map(
              (item) => (
                <button
                  className={`h-10 rounded-md px-3 text-sm font-medium transition ${
                    item === mode
                      ? "bg-[#1f6f64] text-white"
                      : "border border-[#cfd8d3] bg-white text-[#40504b]"
                  }`}
                  key={item}
                  onClick={() => {
                    setMode(item);
                    window.history.replaceState(
                      null,
                      "",
                      `/dictation?mode=${item}${isReviewMode ? "&review=wrong" : ""}`,
                    );
                  }}
                  type="button"
                >
                  {modeLabel(item)}
                </button>
              ),
            )}
          </div>
        </header>

        {error ? (
          <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
            {error}
          </p>
        ) : null}

        {question ? (
          <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p className="text-sm font-semibold text-[#35766f]">
                  {question.sceneName}
                </p>
                <p className="mt-1 text-sm text-[#69736f]">
                  {isReviewMode ? "优先复习错词本里的到期单词" : modeDescription(mode)}
                </p>
              </div>

              <div className="flex flex-wrap gap-2">
                <button
                  className="h-10 rounded-md bg-[#1f6f64] px-3 text-sm font-semibold text-white transition hover:bg-[#18574f]"
                  onClick={() => playQuestionAudio(1)}
                  type="button"
                >
                  原速朗读
                </button>
                <button
                  className="h-10 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium text-[#40504b] transition hover:bg-[#f4f7f5]"
                  onClick={() => playQuestionAudio(0.75)}
                  type="button"
                >
                  慢速朗读
                </button>
              </div>
            </div>

            {question.audioUrl || question.slowAudioUrl ? (
              <audio
                className="mt-4 w-full"
                controls
                ref={audioRef}
                src={question.audioUrl ?? question.slowAudioUrl ?? undefined}
              >
                <track kind="captions" />
              </audio>
            ) : null}

            <div className="mt-6 rounded-lg border border-[#e3e8e5] bg-[#fbfcfb] p-4">
              {mode === "advanced" ? (
                <textarea
                  className="min-h-32 w-full resize-y rounded-md border border-[#cfd8d3] bg-white p-3 text-base leading-7 outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                  onChange={(event) => setFullAnswer(event.target.value)}
                  placeholder="听完后输入完整英文句子"
                  value={fullAnswer}
                />
              ) : (
                <div className="flex flex-wrap items-center gap-x-2 gap-y-3 text-lg leading-10">
                  {question.displayParts.map((part, index) =>
                    part.type === "text" ? (
                      <span key={`${part.value}-${index}`}>{part.value}</span>
                    ) : (
                      <input
                        aria-label="blank answer"
                        className="h-10 rounded-md border border-[#cfd8d3] bg-white px-2 text-center text-base outline-none transition focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                        key={part.blankId}
                        onChange={(event) =>
                          setAnswers((current) => ({
                            ...current,
                            [part.blankId ?? ""]: event.target.value,
                          }))
                        }
                        style={{
                          width: `${Math.max(part.length ?? 6, 6) + 2}ch`,
                        }}
                        value={answers[part.blankId ?? ""] ?? ""}
                      />
                    ),
                  )}
                </div>
              )}
            </div>

            <div className="mt-4 flex flex-wrap gap-2">
              <button
                className={`h-10 rounded-md px-3 text-sm font-medium transition ${
                  showFirstLetters
                    ? "bg-[#fff3df] text-[#8a5a00]"
                    : "border border-[#cfd8d3] text-[#40504b]"
                }`}
                onClick={() => setShowFirstLetters((value) => !value)}
                type="button"
              >
                首字母
              </button>
              <button
                className={`h-10 rounded-md px-3 text-sm font-medium transition ${
                  showMeaning
                    ? "bg-[#fff3df] text-[#8a5a00]"
                    : "border border-[#cfd8d3] text-[#40504b]"
                }`}
                onClick={() => setShowMeaning((value) => !value)}
                type="button"
              >
                中文提示
              </button>
            </div>

            {showFirstLetters || showMeaning ? (
              <div className="mt-4 grid gap-2 sm:grid-cols-2">
                {question.targetWords.map((word) => (
                  <div
                    className="rounded-md border border-[#e3e8e5] bg-white px-3 py-2 text-sm"
                    key={word.blankId}
                  >
                    {showFirstLetters ? (
                      <span className="font-semibold text-[#35766f]">
                        {word.firstLetter}
                      </span>
                    ) : null}
                    {showMeaning ? (
                      <span className="ml-2 text-[#69736f]">{word.meaningCn}</span>
                    ) : null}
                  </div>
                ))}
              </div>
            ) : null}

            <div className="mt-6 flex flex-wrap gap-3">
              <button
                className="h-11 rounded-md bg-[#1f6f64] px-5 text-sm font-semibold text-white transition hover:bg-[#18574f] disabled:cursor-not-allowed disabled:bg-[#9eb9b4]"
                disabled={submitting}
                onClick={submit}
                type="button"
              >
                {submitting ? "提交中..." : "提交答案"}
              </button>
              <button
                className="h-11 rounded-md border border-[#cfd8d3] px-4 text-sm font-medium text-[#40504b] transition hover:bg-[#f4f7f5]"
                onClick={() => loadQuestion()}
                type="button"
              >
                {isReviewMode ? "换一个错词" : "换一题"}
              </button>
            </div>
          </section>
        ) : null}

        {result ? (
          <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <p
                  className={
                    result.isCorrect
                      ? "text-sm font-semibold text-[#1f6f64]"
                      : "text-sm font-semibold text-[#b24b2a]"
                  }
                >
                  {result.isCorrect ? "回答正确" : "继续加油"}
                </p>
                <h2 className="mt-1 text-2xl font-semibold">
                  {result.score} 分
                </h2>
              </div>
              <button
                className="h-10 rounded-md bg-[#1f6f64] px-4 text-sm font-semibold text-white transition hover:bg-[#18574f]"
                onClick={() => loadQuestion()}
                type="button"
              >
                {isReviewMode ? "继续复习" : "下一题"}
              </button>
            </div>

            <div className="mt-5 grid gap-3">
              <p className="text-lg font-semibold">{result.sentenceText}</p>
              <p className="text-sm leading-6 text-[#69736f]">
                {result.translation}
              </p>
            </div>

            <div className="mt-5 grid gap-2">
              {result.blankResults.map((item) => (
                <div
                  className="flex flex-col gap-1 rounded-md border border-[#e3e8e5] px-3 py-2 text-sm sm:flex-row sm:items-center sm:justify-between"
                  key={item.blankId}
                >
                  <span className="font-medium">{item.expected}</span>
                  <span
                    className={
                      item.isCorrect ? "text-[#1f6f64]" : "text-[#b24b2a]"
                    }
                  >
                    {item.isCorrect ? "正确" : `你的答案：${item.answer || "空"}`}
                  </span>
                </div>
              ))}
            </div>

            {result.targetWords.length > 0 ? (
              <div className="mt-5 border-t border-[#eef2ef] pt-5">
                <h3 className="text-base font-semibold">目标词</h3>
                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  {result.targetWords.map((word) => (
                    <div
                      className="rounded-md border border-[#e3e8e5] bg-[#fbfcfb] px-3 py-3 text-sm"
                      key={`${word.blankId}-${word.wordId}`}
                    >
                      <div className="flex flex-wrap items-baseline gap-2">
                        <span className="text-lg font-semibold text-[#18211f]">
                          {word.lemma}
                        </span>
                        {word.surfaceText !== word.lemma ? (
                          <span className="text-[#69736f]">
                            原句：{word.surfaceText}
                          </span>
                        ) : null}
                      </div>
                      <div className="mt-2 flex flex-wrap gap-2 text-xs text-[#69736f]">
                        {word.phonetic ? (
                          <span className="rounded bg-white px-2 py-1">
                            {word.phonetic}
                          </span>
                        ) : null}
                        {word.partOfSpeech ? (
                          <span className="rounded bg-white px-2 py-1">
                            {word.partOfSpeech}
                          </span>
                        ) : null}
                      </div>
                      <p className="mt-2 leading-6 text-[#40504b]">
                        {word.meaningCn}
                      </p>
                      {word.collocations ? (
                        <p className="mt-2 leading-6 text-[#69736f]">
                          常见搭配：{word.collocations}
                        </p>
                      ) : null}
                    </div>
                  ))}
                </div>
              </div>
            ) : null}
          </section>
        ) : null}
      </section>
    </main>
  );
}

function normalizeMode(value: string | null): DictationMode {
  return value === "intermediate" || value === "advanced" ? value : "beginner";
}

function modeLabel(mode: DictationMode) {
  return {
    beginner: "初级",
    intermediate: "中级",
    advanced: "高级",
  }[mode];
}

function modeDescription(mode: DictationMode) {
  return {
    beginner: "核心关键词留空",
    intermediate: "多个关键词留空",
    advanced: "完整句子留空",
  }[mode];
}
