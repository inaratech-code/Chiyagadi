"use client";

import { useEffect } from "react";
import { onAuthStateChanged } from "firebase/auth";
import { getFirebaseAuth } from "../lib/firebase";
import { persistSessionForOffline } from "../services/offlineAuthService";

/**
 * Keeps IndexedDB + localStorage session in sync with Firebase Auth when online.
 * Does not clear session on sign-out here (avoid wiping offline session during
 * transient auth states); call clearSession() from your sign-out handler.
 */
export function AuthBootstrap() {
  useEffect(() => {
    const unsub = onAuthStateChanged(getFirebaseAuth(), (user) => {
      if (user) {
        persistSessionForOffline(user).catch(() => {});
      }
    });
    return () => unsub();
  }, []);
  return null;
}
