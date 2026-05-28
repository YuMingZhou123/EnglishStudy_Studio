export const API_BASE_URL =
  process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:5180";

export type CurrentUser = {
  id: string;
  email: string;
  displayName?: string | null;
  currentLevel?: string | null;
  learningGoal?: string | null;
  membershipStatus: string;
  roles: string[];
};

export type AuthResponse = {
  accessToken: string;
  expiresAt: string;
  user: CurrentUser;
};

export type DisplayPart = {
  type: "text" | "blank";
  value?: string | null;
  blankId?: string | null;
  length?: number | null;
};

export type TargetWord = {
  blankId: string;
  wordId: string;
  surfaceText: string;
  lemma: string;
  meaningCn: string;
  phonetic?: string | null;
  partOfSpeech?: string | null;
  collocations?: string | null;
  firstLetter?: string | null;
};

export type DictationQuestion = {
  questionId: string;
  sentenceId: string;
  mode: DictationMode;
  sceneCode: string;
  sceneName: string;
  level: string;
  speechText: string;
  audioUrl?: string | null;
  slowAudioUrl?: string | null;
  displayParts: DisplayPart[];
  targetWords: TargetWord[];
  reviewWordId?: string | null;
};

export type BlankAnswer = {
  blankId: string;
  value: string;
};

export type BlankResult = {
  blankId: string;
  expected: string;
  answer?: string | null;
  isCorrect: boolean;
};

export type DictationSubmitResult = {
  attemptId: string;
  sentenceId: string;
  mode: DictationMode;
  isCorrect: boolean;
  score: number;
  sentenceText: string;
  translation: string;
  blankResults: BlankResult[];
  targetWords: TargetWord[];
};

export type DictationHistoryItem = {
  attemptId: string;
  sentenceId: string;
  mode: DictationMode;
  score: number;
  isCorrect: boolean;
  sentenceText: string;
  translation: string;
  createdAt: string;
};

export type DailyLearningStat = {
  date: string;
  attemptCount: number;
  correctCount: number;
  accuracy: number;
};

export type LearningSummary = {
  dailyDictationGoal: number;
  todayAttemptCount: number;
  todayCorrectCount: number;
  todayAccuracy: number;
  wrongWordCount: number;
  dueReviewCount: number;
  totalAttemptCount: number;
  learningDayCount: number;
  currentStreakDays: number;
  recentAccuracy: number;
  recentDays: DailyLearningStat[];
};

export type WrongWord = {
  wordId: string;
  lemma: string;
  meaningCn: string;
  phonetic?: string | null;
  status: string;
  source: string;
  mistakeCount: number;
  correctStreak: number;
  nextReviewAt?: string | null;
  lastReviewedAt?: string | null;
  lastMistakeAt?: string | null;
  addedAt: string;
  sourceSentenceText?: string | null;
  sourceSentenceTranslation?: string | null;
};

export type DictationMode = "beginner" | "intermediate" | "advanced";

export type Scene = {
  id: string;
  code: string;
  name: string;
  description?: string | null;
  isEnabled: boolean;
};

export type Word = {
  id: string;
  lemma: string;
  phonetic?: string | null;
  partOfSpeech?: string | null;
  meaningCn: string;
  cefrLevel?: string | null;
  examTags?: string | null;
  collocations?: string | null;
};

export type MediaAsset = {
  id: string;
  bucket: string;
  objectKey: string;
  url: string;
  contentType: string;
  size: number;
  source: string;
};

export type SentenceKeywordInput = {
  wordId: string;
  surfaceText: string;
  priority: number;
  blankGroup?: string | null;
};

export type Sentence = {
  id: string;
  text: string;
  translation: string;
  level: DictationMode;
  sceneId: string;
  sceneName: string;
  audioUrl?: string | null;
  slowAudioUrl?: string | null;
  audioAssetId?: string | null;
  source: string;
  status: string;
  keywords: Array<{
    id: string;
    wordId: string;
    surfaceText: string;
    startIndex: number;
    endIndex: number;
    blankGroup?: string | null;
    priority: number;
    word: Word;
  }>;
};

export type ImportSentenceKeywordInput = {
  lemma: string;
  meaningCn: string;
  surfaceText: string;
  priority?: number;
  phonetic?: string | null;
  partOfSpeech?: string | null;
  cefrLevel?: string | null;
  examTags?: string | null;
  collocations?: string | null;
  blankGroup?: string | null;
};

export type ImportSentenceItemInput = {
  text: string;
  translation: string;
  level: DictationMode;
  sceneCode: string;
  sceneName: string;
  keywords: ImportSentenceKeywordInput[];
  sceneDescription?: string | null;
  audioUrl?: string | null;
  status?: string | null;
};

export type ImportSentencesInput = {
  items: ImportSentenceItemInput[];
  defaultStatus?: string;
  updateExisting?: boolean;
};

export type ImportSentencesResult = {
  totalCount: number;
  createdScenes: number;
  createdWords: number;
  createdSentences: number;
  updatedSentences: number;
  skippedCount: number;
  failures: Array<{
    rowNumber: number;
    text: string;
    errors: string[];
  }>;
};

export type GenerateMissingAudioInput = {
  limit?: number;
  level?: string | null;
  status?: string;
  voice?: string | null;
  speed?: number;
  includeExternalAudio?: boolean;
};

export type GenerateMissingAudioResult = {
  totalCandidates: number;
  generatedCount: number;
  failedCount: number;
  items: Array<{
    sentenceId: string;
    text: string;
    succeeded: boolean;
    audioUrl?: string | null;
    error?: string | null;
  }>;
};

type RequestOptions = RequestInit & {
  token?: string | null;
};

export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set("Accept", "application/json");

  if (
    options.body &&
    !(options.body instanceof FormData) &&
    !headers.has("Content-Type")
  ) {
    headers.set("Content-Type", "application/json");
  }

  if (options.token) {
    headers.set("Authorization", `Bearer ${options.token}`);
  }

  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers,
  });

  if (!response.ok) {
    let message = `Request failed with ${response.status}`;
    try {
      const payload = await response.json();
      if (Array.isArray(payload?.errors)) {
        message = payload.errors.join(" ");
      }
    } catch {
      const text = await response.text();
      message = text || message;
    }

    throw new Error(message);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return response.json() as Promise<T>;
}

export const authApi = {
  login(email: string, password: string) {
    return apiRequest<AuthResponse>("/api/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password }),
    });
  },

  register(input: {
    email: string;
    password: string;
    displayName?: string;
    currentLevel?: string;
    learningGoal?: string;
  }) {
    return apiRequest<AuthResponse>("/api/auth/register", {
      method: "POST",
      body: JSON.stringify(input),
    });
  },

  me(token: string) {
    return apiRequest<CurrentUser>("/api/auth/me", { token });
  },

  updateMe(
    token: string,
    input: {
      displayName?: string;
      currentLevel?: string;
      learningGoal?: string;
    },
  ) {
    return apiRequest<CurrentUser>("/api/auth/me", {
      method: "PUT",
      token,
      body: JSON.stringify(input),
    });
  },
};

export const dictationApi = {
  next(token: string, mode: DictationMode) {
    return apiRequest<DictationQuestion>(
      `/api/dictation/next?mode=${mode}`,
      { token },
    );
  },

  submit(
    token: string,
    input: {
      sentenceId: string;
      mode: DictationMode;
      answers: BlankAnswer[];
      userAnswer?: string | null;
      durationMs: number;
      replayCount: number;
      hintCount: number;
      reviewWordId?: string | null;
    },
  ) {
    return apiRequest<DictationSubmitResult>("/api/dictation/submit", {
      method: "POST",
      token,
      body: JSON.stringify(input),
    });
  },

  history(token: string, limit = 10) {
    return apiRequest<DictationHistoryItem[]>(
      `/api/dictation/history?limit=${limit}`,
      { token },
    );
  },

  summary(token: string) {
    return apiRequest<LearningSummary>("/api/dictation/summary", { token });
  },
};

export const vocabularyApi = {
  words(token: string) {
    return apiRequest<WrongWord[]>("/api/vocabulary/words", { token });
  },

  wrongWords(token: string) {
    return apiRequest<WrongWord[]>("/api/vocabulary/wrong-words", { token });
  },

  addWord(token: string, wordId: string) {
    return apiRequest<WrongWord>("/api/vocabulary/words", {
      method: "POST",
      token,
      body: JSON.stringify({ wordId }),
    });
  },

  reviewNext(token: string, mode: DictationMode) {
    return apiRequest<DictationQuestion>(
      `/api/vocabulary/review/next?mode=${mode}`,
      { token },
    );
  },
};

export const adminApi = {
  scenes(token: string) {
    return apiRequest<Scene[]>("/api/admin/scenes", { token });
  },

  createScene(
    token: string,
    input: { code: string; name: string; description?: string; isEnabled: boolean },
  ) {
    return apiRequest<Scene>("/api/admin/scenes", {
      method: "POST",
      token,
      body: JSON.stringify(input),
    });
  },

  updateScene(
    token: string,
    sceneId: string,
    input: { code: string; name: string; description?: string; isEnabled: boolean },
  ) {
    return apiRequest<Scene>(`/api/admin/scenes/${sceneId}`, {
      method: "PUT",
      token,
      body: JSON.stringify(input),
    });
  },

  words(token: string, keyword = "") {
    const query = keyword ? `?keyword=${encodeURIComponent(keyword)}` : "";
    return apiRequest<Word[]>(`/api/admin/words${query}`, { token });
  },

  createWord(
    token: string,
    input: {
      lemma: string;
      phonetic?: string;
      partOfSpeech?: string;
      meaningCn: string;
      cefrLevel?: string;
      examTags?: string;
      collocations?: string;
    },
  ) {
    return apiRequest<Word>("/api/admin/words", {
      method: "POST",
      token,
      body: JSON.stringify(input),
    });
  },

  updateWord(
    token: string,
    wordId: string,
    input: {
      lemma: string;
      phonetic?: string;
      partOfSpeech?: string;
      meaningCn: string;
      cefrLevel?: string;
      examTags?: string;
      collocations?: string;
    },
  ) {
    return apiRequest<Word>(`/api/admin/words/${wordId}`, {
      method: "PUT",
      token,
      body: JSON.stringify(input),
    });
  },

  sentences(token: string) {
    return apiRequest<Sentence[]>("/api/admin/sentences", { token });
  },

  createSentence(
    token: string,
    input: {
      text: string;
      translation: string;
      level: DictationMode;
      sceneId: string;
      audioAssetId?: string | null;
      audioUrl?: string | null;
      keywords: SentenceKeywordInput[];
      status: string;
    },
  ) {
    return apiRequest<Sentence>("/api/admin/sentences", {
      method: "POST",
      token,
      body: JSON.stringify(input),
    });
  },

  importSentences(token: string, input: ImportSentencesInput) {
    return apiRequest<ImportSentencesResult>("/api/admin/sentences/import", {
      method: "POST",
      token,
      body: JSON.stringify(input),
    });
  },

  updateSentence(
    token: string,
    sentenceId: string,
    input: {
      text: string;
      translation: string;
      level: DictationMode;
      sceneId: string;
      audioAssetId?: string | null;
      audioUrl?: string | null;
      keywords: SentenceKeywordInput[];
      status: string;
    },
  ) {
    return apiRequest<Sentence>(`/api/admin/sentences/${sentenceId}`, {
      method: "PUT",
      token,
      body: JSON.stringify(input),
    });
  },

  publishSentence(token: string, sentenceId: string) {
    return apiRequest<Sentence>(`/api/admin/sentences/${sentenceId}/publish`, {
      method: "POST",
      token,
    });
  },

  offlineSentence(token: string, sentenceId: string) {
    return apiRequest<Sentence>(`/api/admin/sentences/${sentenceId}/offline`, {
      method: "POST",
      token,
    });
  },

  generateSentenceAudio(
    token: string,
    sentenceId: string,
    input: { voice?: string | null; speed?: number } = {},
  ) {
    return apiRequest<Sentence>(
      `/api/admin/sentences/${sentenceId}/generate-audio`,
      {
        method: "POST",
        token,
        body: JSON.stringify(input),
      },
    );
  },

  generateMissingAudio(
    token: string,
    input: GenerateMissingAudioInput = {},
  ) {
    return apiRequest<GenerateMissingAudioResult>(
      "/api/admin/sentences/generate-missing-audio",
      {
        method: "POST",
        token,
        body: JSON.stringify(input),
      },
    );
  },

  uploadMedia(token: string, file: File, folder = "audio") {
    const formData = new FormData();
    formData.append("file", file);
    formData.append("folder", folder);

    return apiRequest<MediaAsset>("/api/admin/media/upload", {
      method: "POST",
      token,
      body: formData,
    });
  },
};
