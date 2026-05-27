import type { AuthResponse } from "./api";

const TOKEN_KEY = "english-study-token";
const USER_KEY = "english-study-user";

export function saveSession(auth: AuthResponse) {
  window.localStorage.setItem(TOKEN_KEY, auth.accessToken);
  window.localStorage.setItem(USER_KEY, JSON.stringify(auth.user));
}

export function getToken() {
  return window.localStorage.getItem(TOKEN_KEY);
}

export function clearSession() {
  window.localStorage.removeItem(TOKEN_KEY);
  window.localStorage.removeItem(USER_KEY);
}
