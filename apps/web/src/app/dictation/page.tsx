"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  DictationMode,
  DictationQuestion,
  DictationSubmitResult,
  dictationApi,
  getErrorMessage,
  isAuthError,
  vocabularyApi,
} from "@/lib/api";
import { AppHeader } from "@/app/_components/AppHeader";
import { clearSession, getToken } from "@/lib/session";

const flowSteps = ["听音", "作答", "复盘"];

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
  const [savedWordIds, setSavedWordIds] = useState<Set<string>>(() => new Set());
  const [savingWordId, setSavingWordId] = useState<string | null>(null);
  const [vocabularyMessage, setVocabularyMessage] = useState<string | null>(null);

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
      setSavedWordIds(new Set());
      setSavingWordId(null);
      setVocabularyMessage(null);

      try {
        const nextQuestion = isReviewMode
          ? await vocabularyApi.reviewNext(authToken, nextMode)
          : await dictationApi.next(authToken, nextMode);
        setQuestion(nextQuestion);
      } catch (err) {
        if (isAuthError(err)) {
          clearSession();
          router.replace("/");
          return;
        }

        setError(getErrorMessage(err, "题目加载失败"));
      } finally {
        setLoading(false);
      }
    },
    [isReviewMode, mode, router, token],
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
  const answeredCount =
    mode === "advanced"
      ? Number(fullAnswer.trim().length > 0)
      : blankParts.filter((part) => answers[part.blankId ?? ""]?.trim()).length;
  const answerTotal = mode === "advanced" ? 1 : Math.max(1, blankParts.length);
  const activeStep = result ? 2 : answeredCount > 0 ? 1 : 0;

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
      if (isAuthError(err)) {
        clearSession();
        router.replace("/");
        return;
      }

      setError(getErrorMessage(err, "提交失败"));
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

  async function addVocabularyWord(wordId: string) {
    if (!token) {
      return;
    }

    setSavingWordId(wordId);
    setVocabularyMessage(null);

    try {
      await vocabularyApi.addWord(token, wordId);
      setSavedWordIds((current) => new Set(current).add(wordId));
      setVocabularyMessage("已加入词汇本");
    } catch (err) {
      if (isAuthError(err)) {
        clearSession();
        router.replace("/");
        return;
      }

      setVocabularyMessage(getErrorMessage(err, "加入失败"));
    } finally {
      setSavingWordId(null);
    }
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

  function logout() {
    clearSession();
    router.replace("/");
  }

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f6f7f4] text-[#40504b]">
        正在准备题目...
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f6f7f4] text-[#17201d]">
      <AppHeader active={isReviewMode ? "review" : "dictation"} onLogout={logout} />

      <section className="mx-auto grid w-full max-w-6xl gap-5 px-5 py-6 sm:px-8">
        <header className="rounded-lg border border-[#d9e2dd] bg-white p-5 shadow-sm">
          <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <h1 className="mt-2 text-3xl font-semibold tracking-normal">
                {isReviewMode ? "词汇复习" : `${modeLabel(mode)}语境听写`}
              </h1>
              <p className="mt-2 text-sm leading-6 text-[#62706b]">
                {isReviewMode
                  ? "从词汇本里挑出到期单词，放回真实句子里复习。"
                  : modeDescription(mode)}
              </p>
            </div>
            <div className="grid grid-cols-3 rounded-lg bg-[#eef3f0] p-1 text-sm font-medium">
              {(["beginner", "intermediate", "advanced"] as DictationMode[]).map(
                (item) => (
                  <button
                    className={`h-10 rounded-md px-3 transition ${
                      item === mode
                        ? "bg-white text-[#17201d] shadow-sm"
                        : "text-[#62706b]"
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
          </div>
        </header>

        <section className="grid gap-5 lg:grid-cols-[1fr_300px]">
          <div className="grid gap-5">
            {error ? (
              <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
                {error}
              </p>
            ) : null}

            {question ? (
              <section className="rounded-lg border border-[#d9e2dd] bg-white p-5 shadow-sm">
                <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
                  <div>
                    <p className="text-sm font-semibold text-[#315b8c]">
                      {question.sceneName}
                    </p>
                    <h2 className="mt-2 text-2xl font-semibold">
                      先听，再填写答案
                    </h2>
                    <p className="mt-2 text-sm leading-6 text-[#62706b]">
                      已播放 {replayCount} 次，已填写 {answeredCount}/{answerTotal}。
                    </p>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    <button
                      className="h-11 rounded-md bg-[#1f6f64] px-4 text-sm font-semibold text-white transition hover:bg-[#164f49]"
                      onClick={() => playQuestionAudio(1)}
                      type="button"
                    >
                      原速朗读
                    </button>
                    <button
                      className="h-11 rounded-md border border-[#cfd8d3] px-4 text-sm font-medium text-[#40504b] transition hover:bg-[#f6f7f4]"
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

                <div className="mt-6 rounded-lg border border-[#e1e8e4] bg-[#fbfcfb] p-4">
                  {mode === "advanced" ? (
                    <textarea
                      className="min-h-36 w-full resize-y rounded-md border border-[#cfd8d3] bg-white p-3 text-base leading-7 outline-none transition focus:border-[#1f6f64] focus:ring-2 focus:ring-[#1f6f64]/15"
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
                            className="h-10 rounded-md border border-[#cfd8d3] bg-white px-2 text-center text-base outline-none transition focus:border-[#1f6f64] focus:ring-2 focus:ring-[#1f6f64]/15"
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
                        : "border border-[#cfd8d3] text-[#40504b] hover:bg-[#f6f7f4]"
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
                        : "border border-[#cfd8d3] text-[#40504b] hover:bg-[#f6f7f4]"
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
                        className="rounded-md border border-[#e1e8e4] bg-white px-3 py-2 text-sm"
                        key={word.blankId}
                      >
                        {showFirstLetters ? (
                          <span className="font-semibold text-[#315b8c]">
                            {word.firstLetter}
                          </span>
                        ) : null}
                        {showMeaning ? (
                          <span className="ml-2 text-[#62706b]">
                            {word.meaningCn}
                          </span>
                        ) : null}
                      </div>
                    ))}
                  </div>
                ) : null}

                <div className="mt-6 flex flex-wrap gap-3">
                  <button
                    className="h-11 rounded-md bg-[#1f6f64] px-5 text-sm font-semibold text-white transition hover:bg-[#164f49] disabled:cursor-not-allowed disabled:bg-[#9eb9b4]"
                    disabled={submitting}
                    onClick={submit}
                    type="button"
                  >
                    {submitting ? "提交中..." : "提交答案"}
                  </button>
                  <button
                    className="h-11 rounded-md border border-[#cfd8d3] px-4 text-sm font-medium text-[#40504b] transition hover:bg-[#f6f7f4]"
                    onClick={() => loadQuestion()}
                    type="button"
                  >
                    {isReviewMode ? "换一个词" : "换一题"}
                  </button>
                </div>
              </section>
            ) : null}

            {result ? (
              <section className="rounded-lg border border-[#d9e2dd] bg-white p-5 shadow-sm">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
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
                    <h2 className="mt-1 text-3xl font-semibold">
                      {result.score} 分
                    </h2>
                    <p className="mt-2 text-sm leading-6 text-[#62706b]">
                      复盘答案和目标词后，再进入下一题。
                    </p>
                  </div>
                  <button
                    className="h-10 rounded-md bg-[#1f6f64] px-4 text-sm font-semibold text-white transition hover:bg-[#164f49]"
                    onClick={() => loadQuestion()}
                    type="button"
                  >
                    {isReviewMode ? "继续复习" : "下一题"}
                  </button>
                </div>

                <div className="mt-5 rounded-lg bg-[#eef3f0] p-4">
                  <p className="text-lg font-semibold leading-8">
                    {result.sentenceText}
                  </p>
                  <p className="mt-2 text-sm leading-6 text-[#62706b]">
                    {result.translation}
                  </p>
                </div>

                <div className="mt-5 grid gap-2">
                  {result.blankResults.map((item) => (
                    <div
                      className="flex flex-col gap-1 rounded-md border border-[#e1e8e4] px-3 py-2 text-sm sm:flex-row sm:items-center sm:justify-between"
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
                    <div className="flex flex-wrap items-center justify-between gap-3">
                      <h3 className="text-base font-semibold">目标词</h3>
                      {vocabularyMessage ? (
                        <span className="text-sm font-medium text-[#1f6f64]">
                          {vocabularyMessage}
                        </span>
                      ) : null}
                    </div>
                    <div className="mt-3 grid gap-3 sm:grid-cols-2">
                      {result.targetWords.map((word) => (
                        <div
                          className="rounded-lg border border-[#e1e8e4] bg-[#fbfcfb] px-3 py-3 text-sm"
                          key={`${word.blankId}-${word.wordId}`}
                        >
                          <div className="flex flex-wrap items-baseline gap-2">
                            <span className="text-lg font-semibold text-[#17201d]">
                              {word.lemma}
                            </span>
                            {word.surfaceText !== word.lemma ? (
                              <span className="text-[#62706b]">
                                原句：{word.surfaceText}
                              </span>
                            ) : null}
                          </div>
                          <div className="mt-2 flex flex-wrap gap-2 text-xs text-[#62706b]">
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
                            <p className="mt-2 leading-6 text-[#62706b]">
                              常见搭配：{word.collocations}
                            </p>
                          ) : null}
                          <button
                            className="mt-3 h-9 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium text-[#40504b] transition hover:bg-white disabled:cursor-not-allowed disabled:bg-[#eef3f0] disabled:text-[#87908c]"
                            disabled={
                              savingWordId === word.wordId ||
                              savedWordIds.has(word.wordId)
                            }
                            onClick={() => addVocabularyWord(word.wordId)}
                            type="button"
                          >
                            {savedWordIds.has(word.wordId)
                              ? "已加入"
                              : savingWordId === word.wordId
                                ? "加入中..."
                                : "加入词汇本"}
                          </button>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}
              </section>
            ) : null}
          </div>

          <aside className="grid content-start gap-5">
            <section className="rounded-lg border border-[#d9e2dd] bg-white p-5 shadow-sm">
              <h2 className="text-base font-semibold">训练流程</h2>
              <div className="mt-4 grid gap-3">
                {flowSteps.map((step, index) => (
                  <div
                    className={`flex items-center gap-3 rounded-lg border px-3 py-2 ${
                      activeStep === index
                        ? "border-[#1f6f64] bg-[#eef7f4]"
                        : "border-[#e1e8e4] bg-white"
                    }`}
                    key={step}
                  >
                    <span
                      className={`flex h-7 w-7 items-center justify-center rounded-full text-xs font-semibold ${
                        activeStep === index
                          ? "bg-[#1f6f64] text-white"
                          : "bg-[#eef3f0] text-[#62706b]"
                      }`}
                    >
                      {index + 1}
                    </span>
                    <span className="text-sm font-medium">{step}</span>
                  </div>
                ))}
              </div>
            </section>

            <section className="rounded-lg border border-[#d9e2dd] bg-white p-5 shadow-sm">
              <h2 className="text-base font-semibold">当前题目</h2>
              <dl className="mt-4 grid gap-3 text-sm">
                <div className="flex justify-between gap-3">
                  <dt className="text-[#62706b]">难度</dt>
                  <dd className="font-medium">{modeLabel(mode)}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-[#62706b]">场景</dt>
                  <dd className="font-medium">{question?.sceneName ?? "-"}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-[#62706b]">目标词</dt>
                  <dd className="font-medium">{question?.targetWords.length ?? 0}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-[#62706b]">提示</dt>
                  <dd className="font-medium">
                    {Number(showFirstLetters) + Number(showMeaning)}
                  </dd>
                </div>
              </dl>
            </section>
          </aside>
        </section>
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
    beginner: "核心关键词留空，适合先建立听写信心。",
    intermediate: "多个关键词留空，训练在句子里捕捉关键信息。",
    advanced: "完整句子留空，训练整句听辨和拼写稳定性。",
  }[mode];
}
