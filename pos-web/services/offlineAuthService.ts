import {
  signInWithEmailAndPassword,
  type User as FirebaseUser,
} from "firebase/auth";
import { getFirebaseAuth } from "../lib/firebase";
import { db } from "../lib/localDB";
import { saveSession, clearSession } from "../lib/session";
import type { LocalUser } from "../types";

const REAUTH_INTERVAL_MS = 24 * 60 * 60 * 1000;

function getTokenExpiryMs(token: string): number {
  try {
    const payload = JSON.parse(atob(token.split(".")[1]));
    const exp = payload.exp as number | undefined;
    return exp ? exp * 1000 : 0;
  } catch {
    return 0;
  }
}

export async function persistSessionForOffline(
  firebaseUser: FirebaseUser
): Promise<void> {
  const token = await firebaseUser.getIdToken();
  const tokenExpiry = getTokenExpiryMs(token);
  const now = Date.now();
  const local: LocalUser = {
    id: firebaseUser.uid,
    email: firebaseUser.email ?? "",
    token,
    tokenExpiry,
    lastLoginAt: now,
  };
  await db.users.put(local);
  // Mirror for offline-first UX + audits (see lib/session.ts).
  saveSession({
    uid: firebaseUser.uid,
    email: firebaseUser.email,
    token,
    loginTime: now,
  });
}

export async function offlineLogin(
  email: string
): Promise<LocalUser | null> {
  const user = await db.users.where("email").equals(email).first();
  if (!user) return null;
  const now = Date.now();
  if (user.tokenExpiry <= now) return null;
  if (now - user.lastLoginAt > REAUTH_INTERVAL_MS) return null;
  return user;
}

export async function getStoredUserByEmail(
  email: string
): Promise<LocalUser | null> {
  const u = await db.users.where("email").equals(email).first();
  return u ?? null;
}

export async function getStoredEmails(): Promise<string[]> {
  const users = await db.users.toArray();
  return users.map((u) => u.email).filter(Boolean);
}

export async function clearStoredUser(userId: string): Promise<void> {
  await db.users.delete(userId);
  clearSession();
}
