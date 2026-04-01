# ChiyaGadi (inara_pos) — offline-first PWA notes

## What’s implemented

1. **Firestore offline persistence** — Configured in `lib/providers/firestore_database_provider.dart`: `Settings(persistenceEnabled: true, cacheSizeBytes: CACHE_SIZE_UNLIMITED)` on supported web/desktop/Android builds. **Web + iOS Safari** keeps persistence **disabled** for stability (same as before).

2. **Session snapshot** — `lib/services/offline_session_service.dart` stores `{ uid, email, token, loginTime }` in **SharedPreferences** (on web: `localStorage`) under key `chiyagadi_session`. Updated after **restoreSessionFromFirebaseUser** and when **Home** opens (web). Cleared on **logout**.

3. **Connectivity + UI** — `lib/providers/connectivity_notifier.dart` listens to **connectivity_plus**; `lib/widgets/offline_mode_banner.dart` shows **“Offline Mode Active”** at the top of **Home** when offline.

4. **Service worker + manifest** — See `web/service-worker.js`, `web/index.html`, `web/manifest.json`, `web/offline.html` (cache-first static assets, shell precache, `vercel.json` headers for `/service-worker.js`).

5. **SQLite sync** — `SyncProvider` remains for **mobile** offline queue. **Web** uses Firestore + SQLite is not used; no change required there.

## Deploy / test

1. `flutter build web` → deploy `build/web` (e.g. Vercel).
2. **HTTPS** required for PWA + service worker.
3. Log in online, open DevTools → Application → Service Workers → confirm `service-worker.js`.
4. Toggle offline; banner should appear; cached UI should still load.

## PWABuilder

1. Use your deployed HTTPS URL.
2. Confirm manifest + service worker are detected.
3. Package APK/TWA as documented by PWABuilder.

## Firebase

- Ensure **Firebase Auth** authorized domains include your **production** host and `localhost` for dev.
- **Firestore rules** must allow authenticated reads/writes for your collections.
