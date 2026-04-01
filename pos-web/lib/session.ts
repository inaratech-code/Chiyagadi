/**
 * Local session snapshot for offline UX and PWABuilder / audit tooling.
 * Firebase Auth still persists via its own IndexedDB; this mirrors uid/email/token
 * for prefill and "remember who logged in" when the network is down.
 */

export const SESSION_STORAGE_KEY = "chiyagadi_session";

export interface StoredSession {
  uid: string;
  email: string | null;
  token: string;
  loginTime: number;
}

export function saveSession(session: StoredSession): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(session));
  } catch {
    // Quota / private mode — ignore
  }
}

export function loadSession(): StoredSession | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = localStorage.getItem(SESSION_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredSession;
    if (!parsed.uid || !parsed.token) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function clearSession(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(SESSION_STORAGE_KEY);
  } catch {
    // ignore
  }
}
