"use client";

import { useState, useEffect } from "react";
import { signInWithEmailAndPassword } from "firebase/auth";
import { getFirebaseAuth } from "../../lib/firebase";
import { persistSessionForOffline, offlineLogin, getStoredEmails } from "../../services/offlineAuthService";
import { loadSession } from "../../lib/session";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [storedEmails, setStoredEmails] = useState<string[]>([]);

  useEffect(() => {
    const s = loadSession();
    if (s?.email) setEmail(s.email);
    getStoredEmails().then(setStoredEmails);
  }, []);

  const handleOnlineLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    try {
      const cred = await signInWithEmailAndPassword(
        getFirebaseAuth(),
        email,
        password
      );
      await persistSessionForOffline(cred.user);
      window.location.href = "/";
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  const handleOfflineLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    const user = await offlineLogin(email);
    if (user) {
      window.location.href = "/";
    } else {
      setError("Offline login failed. Token expired or need to re-auth online (every 24h).");
    }
  };

  const canOffline = storedEmails.includes(email);

  return (
    <div style={{ padding: 24, maxWidth: 400 }}>
      <h1>Login</h1>
      <form onSubmit={handleOnlineLogin}>
        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          style={{ display: "block", marginBottom: 8, width: "100%" }}
        />
        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          style={{ display: "block", marginBottom: 8, width: "100%" }}
        />
        {error && <p style={{ color: "red" }}>{error}</p>}
        <button type="submit">Sign in (online)</button>
        {canOffline && (
          <button type="button" onClick={handleOfflineLogin} style={{ marginLeft: 8 }}>
            Use offline
          </button>
        )}
      </form>
    </div>
  );
}
