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

export type WrongWord = {
  wordId: string;
  lemma: string;
  meaningCn: string;
  phonetic?: string | null;
  status: string;
  mistakeCount: number;
  correctStreak: number;
  nextReviewAt?: string | null;
  lastReviewedAt?: string | null;
};

export type DictationMode = "beginner" | "intermediate" | "advanced";

type RequestOptions = RequestInit & {
  token?: string | null;
};

export async function apiRequest<T>(
  path: string,
  options: RequestOptions = {},
): Promise<T> {
  const headers = new Headers(options.headers);
  headers.set("Accept", "application/json");

  if (options.body && !headers.has("Content-Type")) {
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
};

export const vocabularyApi = {
  wrongWords(token: string) {
    return apiRequest<WrongWord[]>("/api/vocabulary/wrong-words", { token });
  },
};
