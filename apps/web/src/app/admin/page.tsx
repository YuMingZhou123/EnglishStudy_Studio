"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  DictationMode,
  GenerateMissingAudioResult,
  ImportSentencesInput,
  ImportSentencesResult,
  MediaAsset,
  Scene,
  Sentence,
  SentenceKeywordInput,
  Word,
  adminApi,
  authApi,
} from "@/lib/api";
import { clearSession, getToken } from "@/lib/session";

type KeywordDraft = SentenceKeywordInput & { key: string };

const importSample = `{
  "defaultStatus": "published",
  "updateExisting": true,
  "items": [
    {
      "text": "I need to schedule a meeting with the marketing team.",
      "translation": "我需要和市场团队安排一次会议。",
      "level": "beginner",
      "sceneCode": "workplace",
      "sceneName": "职场沟通",
      "keywords": [
        {
          "lemma": "schedule",
          "meaningCn": "安排",
          "surfaceText": "schedule",
          "priority": 100,
          "partOfSpeech": "verb"
        }
      ]
    }
  ]
}`;

export default function AdminPage() {
  const router = useRouter();
  const [token, setToken] = useState<string | null>(null);
  const [scenes, setScenes] = useState<Scene[]>([]);
  const [words, setWords] = useState<Word[]>([]);
  const [sentences, setSentences] = useState<Sentence[]>([]);
  const [mediaAssets, setMediaAssets] = useState<MediaAsset[]>([]);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [editingSceneId, setEditingSceneId] = useState<string | null>(null);
  const [editingWordId, setEditingWordId] = useState<string | null>(null);
  const [editingSentenceId, setEditingSentenceId] = useState<string | null>(null);
  const [importText, setImportText] = useState(importSample);
  const [importResult, setImportResult] = useState<ImportSentencesResult | null>(null);
  const [audioBatchResult, setAudioBatchResult] =
    useState<GenerateMissingAudioResult | null>(null);
  const [audioBatchForm, setAudioBatchForm] = useState({
    limit: "5",
    level: "all",
    status: "published",
    speed: "1",
    includeExternalAudio: false,
  });

  const [sceneForm, setSceneForm] = useState({
    code: "",
    name: "",
    description: "",
    isEnabled: true,
  });
  const [wordForm, setWordForm] = useState({
    lemma: "",
    phonetic: "",
    partOfSpeech: "",
    meaningCn: "",
    cefrLevel: "A2",
  });
  const [sentenceForm, setSentenceForm] = useState({
    text: "",
    translation: "",
    level: "beginner" as DictationMode,
    sceneId: "",
    audioAssetId: "",
    audioUrl: "",
    status: "draft",
  });
  const [keywordDrafts, setKeywordDrafts] = useState<KeywordDraft[]>([
    { key: crypto.randomUUID(), wordId: "", surfaceText: "", priority: 100 },
  ]);

  const refreshData = useCallback(
    async (authToken: string) => {
      if (!authToken) {
        return;
      }

      const [sceneItems, wordItems, sentenceItems] = await Promise.all([
        adminApi.scenes(authToken),
        adminApi.words(authToken),
        adminApi.sentences(authToken),
      ]);

      setScenes(sceneItems);
      setWords(wordItems);
      setSentences(sentenceItems);

      setSentenceForm((current) =>
        current.sceneId || sceneItems.length === 0
          ? current
          : { ...current, sceneId: sceneItems[0].id },
      );
    },
    [],
  );

  useEffect(() => {
    const savedToken = getToken();
    if (!savedToken) {
      router.replace("/");
      return;
    }

    authApi
      .me(savedToken)
      .then((user) => {
        if (!user.roles.some((role) => role === "Admin" || role === "ContentAdmin")) {
          router.replace("/dashboard");
          return;
        }

        setToken(savedToken);
        return refreshData(savedToken);
      })
      .catch(() => {
        clearSession();
        router.replace("/");
      })
      .finally(() => setLoading(false));
  }, [refreshData, router]);

  async function createScene(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) {
      return;
    }

    await runAction(async () => {
      if (editingSceneId) {
        await adminApi.updateScene(token, editingSceneId, sceneForm);
      } else {
        await adminApi.createScene(token, sceneForm);
      }

      setSceneForm({ code: "", name: "", description: "", isEnabled: true });
      setEditingSceneId(null);
      await refreshData(token);
      setMessage(editingSceneId ? "场景已更新" : "场景已创建");
    });
  }

  async function createWord(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) {
      return;
    }

    await runAction(async () => {
      const word = editingWordId
        ? await adminApi.updateWord(token, editingWordId, wordForm)
        : await adminApi.createWord(token, wordForm);
      setWordForm({
        lemma: "",
        phonetic: "",
        partOfSpeech: "",
        meaningCn: "",
        cefrLevel: "A2",
      });
      setEditingWordId(null);
      setWords((current) =>
        editingWordId
          ? current.map((item) => (item.id === editingWordId ? word : item))
          : [word, ...current],
      );
      setMessage(editingWordId ? "单词已更新" : "单词已创建");
    });
  }

  async function uploadMedia(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) {
      return;
    }

    const input = event.currentTarget.elements.namedItem("file") as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) {
      setError("请选择音频文件");
      return;
    }

    await runAction(async () => {
      const media = await adminApi.uploadMedia(token, file, "audio");
      setMediaAssets((current) => [media, ...current]);
      setSentenceForm((current) => ({ ...current, audioAssetId: media.id }));
      input.value = "";
      setMessage("音频已上传到 MinIO");
    });
  }

  async function createSentence(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) {
      return;
    }

    const keywords = keywordDrafts
      .filter((keyword) => keyword.wordId && keyword.surfaceText.trim())
      .map((keyword) => ({
        wordId: keyword.wordId,
        surfaceText: keyword.surfaceText,
        priority: keyword.priority,
        blankGroup: keyword.blankGroup,
      }));

    await runAction(async () => {
      const payload = {
        ...sentenceForm,
        audioAssetId: sentenceForm.audioAssetId || null,
        audioUrl: sentenceForm.audioUrl || null,
        keywords,
      };

      if (editingSentenceId) {
        await adminApi.updateSentence(token, editingSentenceId, payload);
      } else {
        await adminApi.createSentence(token, payload);
      }

      setSentenceForm((current) => ({
        ...current,
        text: "",
        translation: "",
        audioUrl: "",
        audioAssetId: "",
        status: "draft",
      }));
      setEditingSentenceId(null);
      setKeywordDrafts([
        { key: crypto.randomUUID(), wordId: "", surfaceText: "", priority: 100 },
      ]);
      await refreshData(token);
      setMessage(editingSentenceId ? "句子已更新" : "句子已创建");
    });
  }

  async function setSentenceStatus(sentenceId: string, status: "published" | "offline") {
    if (!token) {
      return;
    }

    await runAction(async () => {
      const sentence =
        status === "published"
          ? await adminApi.publishSentence(token, sentenceId)
          : await adminApi.offlineSentence(token, sentenceId);

      setSentences((current) =>
        current.map((item) => (item.id === sentenceId ? sentence : item)),
      );
      setMessage(status === "published" ? "句子已发布" : "句子已下架");
    });
  }

  async function generateAudio(sentenceId: string) {
    if (!token) {
      return;
    }

    await runAction(async () => {
      const sentence = await adminApi.generateSentenceAudio(token, sentenceId, {
        speed: 1,
      });

      setSentences((current) =>
        current.map((item) => (item.id === sentenceId ? sentence : item)),
      );
      setMessage("音频已生成");
    });
  }

  async function generateMissingAudio(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) {
      return;
    }

    const limit = Number(audioBatchForm.limit);
    const speed = Number(audioBatchForm.speed);
    if (!Number.isFinite(limit) || limit <= 0) {
      setError("批量数量必须大于 0");
      return;
    }

    if (!Number.isFinite(speed) || speed <= 0) {
      setError("语速必须大于 0");
      return;
    }

    await runAction(async () => {
      const result = await adminApi.generateMissingAudio(token, {
        limit,
        speed,
        level: audioBatchForm.level,
        status: audioBatchForm.status,
        includeExternalAudio: audioBatchForm.includeExternalAudio,
      });

      setAudioBatchResult(result);
      await refreshData(token);
      setMessage(`批量音频完成：成功 ${result.generatedCount}，失败 ${result.failedCount}`);
    });
  }

  async function importSentences(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token) {
      return;
    }

    let payload: ImportSentencesInput;
    try {
      payload = JSON.parse(importText) as ImportSentencesInput;
    } catch {
      setError("JSON 格式不正确");
      return;
    }

    await runAction(async () => {
      const result = await adminApi.importSentences(token, payload);
      setImportResult(result);
      await refreshData(token);
      setMessage(
        `导入完成：新增句子 ${result.createdSentences}，更新句子 ${result.updatedSentences}`,
      );
    });
  }

  function editScene(scene: Scene) {
    setEditingSceneId(scene.id);
    setSceneForm({
      code: scene.code,
      name: scene.name,
      description: scene.description ?? "",
      isEnabled: scene.isEnabled,
    });
    setMessage("正在编辑场景");
  }

  function editWord(word: Word) {
    setEditingWordId(word.id);
    setWordForm({
      lemma: word.lemma,
      phonetic: word.phonetic ?? "",
      partOfSpeech: word.partOfSpeech ?? "",
      meaningCn: word.meaningCn,
      cefrLevel: word.cefrLevel ?? "A2",
    });
    setMessage("正在编辑单词");
  }

  function editSentence(sentence: Sentence) {
    setEditingSentenceId(sentence.id);
    setSentenceForm({
      text: sentence.text,
      translation: sentence.translation,
      level: sentence.level,
      sceneId: sentence.sceneId,
      audioAssetId: sentence.audioAssetId ?? "",
      audioUrl: sentence.audioAssetId ? "" : sentence.audioUrl ?? "",
      status: sentence.status,
    });
    setKeywordDrafts(
      sentence.keywords.length === 0
        ? [{ key: crypto.randomUUID(), wordId: "", surfaceText: "", priority: 100 }]
        : sentence.keywords.map((keyword) => ({
            key: crypto.randomUUID(),
            wordId: keyword.wordId,
            surfaceText: keyword.surfaceText,
            priority: keyword.priority,
            blankGroup: keyword.blankGroup,
          })),
    );
    setMessage("正在编辑句子");
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function runAction(action: () => Promise<void>) {
    setError(null);
    setMessage(null);
    try {
      await action();
    } catch (err) {
      setError(err instanceof Error ? err.message : "操作失败");
    }
  }

  const audioOptions = [
    ["", "暂不绑定"],
    ...mediaAssets.map((media) => [media.id, media.objectKey]),
  ];
  if (
    sentenceForm.audioAssetId &&
    !audioOptions.some(([value]) => value === sentenceForm.audioAssetId)
  ) {
    audioOptions.push([sentenceForm.audioAssetId, "当前已绑定音频"]);
  }

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-[#f4f7f5] text-[#40504b]">
        正在进入内容后台...
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f4f7f5] px-5 py-6 text-[#18211f] sm:px-8">
      <section className="mx-auto grid w-full max-w-7xl gap-5">
        <header className="flex flex-col gap-4 border-b border-[#d9e1dc] pb-5 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <Link className="text-sm font-medium text-[#35766f]" href="/dashboard">
              返回学习台
            </Link>
            <h1 className="mt-2 text-3xl font-semibold tracking-normal">
              内容管理
            </h1>
          </div>
          <button
            className="h-10 rounded-md border border-[#cfd8d3] px-4 text-sm font-medium text-[#40504b] transition hover:bg-white"
            onClick={() => {
              if (token) {
                refreshData(token);
              }
            }}
            disabled={!token}
            type="button"
          >
            刷新
          </button>
        </header>

        {message ? (
          <p className="rounded-md border border-[#bfe2d5] bg-[#eef9f4] px-3 py-2 text-sm text-[#1f6f64]">
            {message}
          </p>
        ) : null}
        {error ? (
          <p className="rounded-md border border-[#f0c6b5] bg-[#fff5ef] px-3 py-2 text-sm text-[#9a4727]">
            {error}
          </p>
        ) : null}

        <section className="grid gap-5 xl:grid-cols-[360px_1fr]">
          <div className="grid gap-5">
            <AdminPanel title="新增场景">
              <form className="grid gap-3" onSubmit={createScene}>
                <AdminInput
                  label="编码"
                  onChange={(value) => setSceneForm((current) => ({ ...current, code: value }))}
                  placeholder="daily"
                  value={sceneForm.code}
                />
                <AdminInput
                  label="名称"
                  onChange={(value) => setSceneForm((current) => ({ ...current, name: value }))}
                  placeholder="Daily English"
                  value={sceneForm.name}
                />
                <AdminInput
                  label="描述"
                  onChange={(value) =>
                    setSceneForm((current) => ({ ...current, description: value }))
                  }
                  value={sceneForm.description}
                />
                <label className="flex items-center gap-2 text-sm font-medium">
                  <input
                    checked={sceneForm.isEnabled}
                    onChange={(event) =>
                      setSceneForm((current) => ({
                        ...current,
                        isEnabled: event.target.checked,
                      }))
                    }
                    type="checkbox"
                  />
                  启用
                </label>
                <SubmitButton label={editingSceneId ? "保存场景" : "创建场景"} />
              </form>
              <div className="mt-4 grid gap-2">
                {scenes.slice(0, 8).map((scene) => (
                  <button
                    className="rounded-md border border-[#d9e1dc] px-3 py-2 text-left text-sm hover:bg-[#f4f7f5]"
                    key={scene.id}
                    onClick={() => editScene(scene)}
                    type="button"
                  >
                    <span className="font-medium">{scene.name}</span>
                    <span className="ml-2 text-xs text-[#69736f]">{scene.code}</span>
                  </button>
                ))}
              </div>
            </AdminPanel>

            <AdminPanel title="新增单词">
              <form className="grid gap-3" onSubmit={createWord}>
                <AdminInput
                  label="单词"
                  onChange={(value) => setWordForm((current) => ({ ...current, lemma: value }))}
                  placeholder="schedule"
                  value={wordForm.lemma}
                />
                <AdminInput
                  label="释义"
                  onChange={(value) =>
                    setWordForm((current) => ({ ...current, meaningCn: value }))
                  }
                  placeholder="安排"
                  value={wordForm.meaningCn}
                />
                <div className="grid gap-3 sm:grid-cols-2">
                  <AdminInput
                    label="音标"
                    onChange={(value) =>
                      setWordForm((current) => ({ ...current, phonetic: value }))
                    }
                    value={wordForm.phonetic}
                  />
                  <AdminInput
                    label="词性"
                    onChange={(value) =>
                      setWordForm((current) => ({ ...current, partOfSpeech: value }))
                    }
                    value={wordForm.partOfSpeech}
                  />
                </div>
                <SubmitButton label={editingWordId ? "保存单词" : "创建单词"} />
              </form>
              <div className="mt-4 grid max-h-72 gap-2 overflow-y-auto pr-1">
                {words.slice(0, 30).map((word) => (
                  <button
                    className="rounded-md border border-[#d9e1dc] px-3 py-2 text-left text-sm hover:bg-[#f4f7f5]"
                    key={word.id}
                    onClick={() => editWord(word)}
                    type="button"
                  >
                    <span className="font-medium">{word.lemma}</span>
                    <span className="ml-2 text-xs text-[#69736f]">{word.meaningCn}</span>
                  </button>
                ))}
              </div>
            </AdminPanel>

            <AdminPanel title="上传音频">
              <form className="grid gap-3" onSubmit={uploadMedia}>
                <input
                  accept="audio/*"
                  className="rounded-md border border-[#cfd8d3] bg-white p-2 text-sm"
                  name="file"
                  type="file"
                />
                <SubmitButton label="上传到 MinIO" />
              </form>
              {mediaAssets.length > 0 ? (
                <div className="mt-3 grid gap-2">
                  {mediaAssets.map((media) => (
                    <button
                      className="truncate rounded-md border border-[#d9e1dc] px-3 py-2 text-left text-xs text-[#40504b] hover:bg-[#f4f7f5]"
                      key={media.id}
                      onClick={() =>
                        setSentenceForm((current) => ({
                          ...current,
                          audioAssetId: media.id,
                        }))
                      }
                      type="button"
                    >
                      {media.objectKey}
                    </button>
                  ))}
                </div>
              ) : null}
            </AdminPanel>

            <AdminPanel title="批量生成音频">
              <form className="grid gap-3" onSubmit={generateMissingAudio}>
                <div className="grid gap-3 sm:grid-cols-2">
                  <AdminInput
                    label="数量"
                    onChange={(value) =>
                      setAudioBatchForm((current) => ({ ...current, limit: value }))
                    }
                    type="number"
                    value={audioBatchForm.limit}
                  />
                  <AdminInput
                    label="语速"
                    onChange={(value) =>
                      setAudioBatchForm((current) => ({ ...current, speed: value }))
                    }
                    type="number"
                    value={audioBatchForm.speed}
                  />
                </div>
                <div className="grid gap-3 sm:grid-cols-2">
                  <AdminSelect
                    label="难度"
                    onChange={(value) =>
                      setAudioBatchForm((current) => ({ ...current, level: value }))
                    }
                    options={[
                      ["all", "全部"],
                      ["beginner", "初级"],
                      ["intermediate", "中级"],
                      ["advanced", "高级"],
                    ]}
                    value={audioBatchForm.level}
                  />
                  <AdminSelect
                    label="状态"
                    onChange={(value) =>
                      setAudioBatchForm((current) => ({ ...current, status: value }))
                    }
                    options={[
                      ["published", "已发布"],
                      ["draft", "草稿"],
                      ["offline", "已下架"],
                      ["all", "全部"],
                    ]}
                    value={audioBatchForm.status}
                  />
                </div>
                <label className="flex items-center gap-2 text-sm font-medium">
                  <input
                    checked={audioBatchForm.includeExternalAudio}
                    onChange={(event) =>
                      setAudioBatchForm((current) => ({
                        ...current,
                        includeExternalAudio: event.target.checked,
                      }))
                    }
                    type="checkbox"
                  />
                  覆盖仅绑定外部 URL 的句子
                </label>
                <SubmitButton label="生成缺失音频" />
              </form>

              {audioBatchResult ? (
                <div className="mt-4 grid gap-2 text-sm text-[#40504b]">
                  <p>
                    候选 {audioBatchResult.totalCandidates} 条，成功{" "}
                    {audioBatchResult.generatedCount}，失败{" "}
                    {audioBatchResult.failedCount}
                  </p>
                  {audioBatchResult.items.slice(0, 5).map((item) => (
                    <p
                      className={item.succeeded ? "text-[#1f6f64]" : "text-[#9a4727]"}
                      key={item.sentenceId}
                    >
                      {item.succeeded ? "已生成" : "失败"}：{item.text}
                    </p>
                  ))}
                </div>
              ) : null}
            </AdminPanel>

            <AdminPanel title="批量导入">
              <form className="grid gap-3" onSubmit={importSentences}>
                <label className="grid gap-2 text-sm font-medium">
                  JSON 内容
                  <textarea
                    className="min-h-80 rounded-md border border-[#cfd8d3] bg-white p-3 font-mono text-xs leading-5 outline-none focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                    onChange={(event) => setImportText(event.target.value)}
                    value={importText}
                  />
                </label>
                <SubmitButton label="导入题库" />
              </form>

              {importResult ? (
                <div className="mt-4 grid gap-2 text-sm text-[#40504b]">
                  <p>
                    共 {importResult.totalCount} 条，新增场景 {importResult.createdScenes}
                    ，新增单词 {importResult.createdWords}
                  </p>
                  <p>
                    新增句子 {importResult.createdSentences}，更新句子{" "}
                    {importResult.updatedSentences}，跳过 {importResult.skippedCount}
                  </p>
                  {importResult.failures.length > 0 ? (
                    <div className="grid gap-2">
                      {importResult.failures.slice(0, 5).map((failure) => (
                        <p className="text-xs text-[#9a4727]" key={failure.rowNumber}>
                          第 {failure.rowNumber} 条：{failure.errors.join("；")}
                        </p>
                      ))}
                    </div>
                  ) : null}
                </div>
              ) : null}
            </AdminPanel>
          </div>

          <div className="grid gap-5">
            <AdminPanel title={editingSentenceId ? "编辑句子" : "新增句子"}>
              <form className="grid gap-4" onSubmit={createSentence}>
                <label className="grid gap-2 text-sm font-medium">
                  英文句子
                  <textarea
                    className="min-h-24 rounded-md border border-[#cfd8d3] p-3 text-sm outline-none focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
                    onChange={(event) =>
                      setSentenceForm((current) => ({ ...current, text: event.target.value }))
                    }
                    value={sentenceForm.text}
                  />
                </label>
                <AdminInput
                  label="中文翻译"
                  onChange={(value) =>
                    setSentenceForm((current) => ({ ...current, translation: value }))
                  }
                  value={sentenceForm.translation}
                />

                <div className="grid gap-3 sm:grid-cols-4">
                  <AdminSelect
                    label="难度"
                    onChange={(value) =>
                      setSentenceForm((current) => ({
                        ...current,
                        level: value as DictationMode,
                      }))
                    }
                    options={[
                      ["beginner", "初级"],
                      ["intermediate", "中级"],
                      ["advanced", "高级"],
                    ]}
                    value={sentenceForm.level}
                  />
                  <AdminSelect
                    label="场景"
                    onChange={(value) =>
                      setSentenceForm((current) => ({ ...current, sceneId: value }))
                    }
                    options={scenes.map((scene) => [scene.id, scene.name])}
                    value={sentenceForm.sceneId}
                  />
                  <AdminSelect
                    label="状态"
                    onChange={(value) =>
                      setSentenceForm((current) => ({ ...current, status: value }))
                    }
                    options={[
                      ["draft", "草稿"],
                      ["published", "发布"],
                    ]}
                    value={sentenceForm.status}
                  />
                  <AdminSelect
                    label="音频"
                    onChange={(value) =>
                      setSentenceForm((current) => ({ ...current, audioAssetId: value }))
                    }
                    options={audioOptions}
                    value={sentenceForm.audioAssetId}
                  />
                </div>

                <AdminInput
                  label="外部音频 URL"
                  onChange={(value) =>
                    setSentenceForm((current) => ({ ...current, audioUrl: value }))
                  }
                  placeholder="可选"
                  value={sentenceForm.audioUrl}
                />

                <div className="grid gap-3">
                  <div className="flex items-center justify-between gap-3">
                    <h3 className="text-sm font-semibold">目标关键词</h3>
                    <button
                      className="h-9 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium text-[#40504b]"
                      onClick={() =>
                        setKeywordDrafts((current) => [
                          ...current,
                          {
                            key: crypto.randomUUID(),
                            wordId: "",
                            surfaceText: "",
                            priority: 80,
                          },
                        ])
                      }
                      type="button"
                    >
                      添加关键词
                    </button>
                  </div>

                  {keywordDrafts.map((keyword, index) => (
                    <div className="grid gap-3 sm:grid-cols-[1fr_1fr_90px_70px]" key={keyword.key}>
                      <AdminSelect
                        label="词条"
                        onChange={(value) => updateKeyword(index, { wordId: value })}
                        options={words.map((word) => [
                          word.id,
                          `${word.lemma} - ${word.meaningCn}`,
                        ])}
                        value={keyword.wordId}
                      />
                      <AdminInput
                        label="句中原文"
                        onChange={(value) => updateKeyword(index, { surfaceText: value })}
                        value={keyword.surfaceText}
                      />
                      <AdminInput
                        label="优先级"
                        onChange={(value) =>
                          updateKeyword(index, { priority: Number(value) || 0 })
                        }
                        type="number"
                        value={String(keyword.priority)}
                      />
                      <button
                        className="mt-6 h-10 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium text-[#9a4727]"
                        onClick={() =>
                          setKeywordDrafts((current) =>
                            current.filter((item) => item.key !== keyword.key),
                          )
                        }
                        type="button"
                      >
                        删除
                      </button>
                    </div>
                  ))}
                </div>

                <div className="flex flex-wrap gap-2">
                  <SubmitButton label={editingSentenceId ? "更新句子" : "保存句子"} />
                  {editingSentenceId ? (
                    <button
                      className="h-10 rounded-md border border-[#cfd8d3] px-4 text-sm font-medium text-[#40504b]"
                      onClick={() => {
                        setEditingSentenceId(null);
                        setSentenceForm((current) => ({
                          ...current,
                          text: "",
                          translation: "",
                          audioUrl: "",
                          audioAssetId: "",
                          status: "draft",
                        }));
                        setKeywordDrafts([
                          {
                            key: crypto.randomUUID(),
                            wordId: "",
                            surfaceText: "",
                            priority: 100,
                          },
                        ]);
                      }}
                      type="button"
                    >
                      取消编辑
                    </button>
                  ) : null}
                </div>
              </form>
            </AdminPanel>

            <AdminPanel title="句子列表">
              <div className="grid gap-3">
                {sentences.map((sentence) => (
                  <div
                    className="rounded-lg border border-[#e3e8e5] p-4"
                    key={sentence.id}
                  >
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div>
                        <p className="font-semibold">{sentence.text}</p>
                        <p className="mt-1 text-sm text-[#69736f]">
                          {sentence.translation}
                        </p>
                        <p className="mt-2 text-xs text-[#69736f]">
                          {sentence.sceneName} / {sentence.level} / {sentence.status}
                        </p>
                      </div>
                      <div className="flex gap-2">
                        <button
                          className="h-9 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium"
                          onClick={() => editSentence(sentence)}
                          type="button"
                        >
                          编辑
                        </button>
                        <button
                          className="h-9 rounded-md border border-[#1f6f64] px-3 text-sm font-medium text-[#1f6f64]"
                          onClick={() => generateAudio(sentence.id)}
                          type="button"
                        >
                          TTS
                        </button>
                        <button
                          className="h-9 rounded-md bg-[#1f6f64] px-3 text-sm font-semibold text-white"
                          onClick={() => setSentenceStatus(sentence.id, "published")}
                          type="button"
                        >
                          发布
                        </button>
                        <button
                          className="h-9 rounded-md border border-[#cfd8d3] px-3 text-sm font-medium"
                          onClick={() => setSentenceStatus(sentence.id, "offline")}
                          type="button"
                        >
                          下架
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </AdminPanel>
          </div>
        </section>
      </section>
    </main>
  );

  function updateKeyword(index: number, patch: Partial<KeywordDraft>) {
    setKeywordDrafts((current) =>
      current.map((keyword, itemIndex) =>
        itemIndex === index ? { ...keyword, ...patch } : keyword,
      ),
    );
  }
}

function AdminPanel({
  children,
  title,
}: {
  children: React.ReactNode;
  title: string;
}) {
  return (
    <section className="rounded-lg border border-[#d9e1dc] bg-white p-5 shadow-sm">
      <h2 className="text-lg font-semibold">{title}</h2>
      <div className="mt-4">{children}</div>
    </section>
  );
}

function AdminInput({
  label,
  onChange,
  placeholder,
  type = "text",
  value,
}: {
  label: string;
  onChange: (value: string) => void;
  placeholder?: string;
  type?: string;
  value: string;
}) {
  return (
    <label className="grid gap-2 text-sm font-medium">
      {label}
      <input
        className="h-10 rounded-md border border-[#cfd8d3] px-3 text-sm outline-none focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        type={type}
        value={value}
      />
    </label>
  );
}

function AdminSelect({
  label,
  onChange,
  options,
  value,
}: {
  label: string;
  onChange: (value: string) => void;
  options: string[][];
  value: string;
}) {
  return (
    <label className="grid gap-2 text-sm font-medium">
      {label}
      <select
        className="h-10 min-w-0 rounded-md border border-[#cfd8d3] bg-white px-3 text-sm outline-none focus:border-[#35766f] focus:ring-2 focus:ring-[#35766f]/15"
        onChange={(event) => onChange(event.target.value)}
        value={value}
      >
        {options.map(([optionValue, labelText]) => (
          <option key={optionValue} value={optionValue}>
            {labelText}
          </option>
        ))}
      </select>
    </label>
  );
}

function SubmitButton({ label }: { label: string }) {
  return (
    <button
      className="h-10 rounded-md bg-[#1f6f64] px-4 text-sm font-semibold text-white transition hover:bg-[#18574f]"
      type="submit"
    >
      {label}
    </button>
  );
}
