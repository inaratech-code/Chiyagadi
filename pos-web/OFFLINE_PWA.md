# ChiyaGadi — offline-first PWA integration

## What was implemented

1. **Firestore** — `getFirebaseFirestore()` uses `initializeFirestore` + `persistentLocalCache()` in the browser so reads can be served from IndexedDB after data was fetched online.
2. **Firebase Auth** — `getFirebaseAuth()` is lazy (no init during SSR). `AuthBootstrap` refreshes Dexie + `localStorage` session when a user is signed in.
3. **Session** — `lib/session.ts` mirrors `{ uid, email, token, loginTime }` to `localStorage` after login; login page pre-fills email from this snapshot.
4. **IndexedDB** — Dexie (`lib/localDB.ts`): `users`, `orders`, `meta`, `menuItems` (v2). Orders queue with `syncStatus: pending`; `lib/syncEngine.ts` pushes to Firestore with `setDoc` (doc id = order id).
5. **Network** — `context/NetworkContext.tsx`: `online` / `offline`, auto-sync when back online, pending order count.
6. **UI** — `components/OfflineBanner.tsx`: sticky “Offline Mode Active” / syncing / pending counts.
7. **Service worker** — `public/sw.js` precaches `/`, `/login`, `/menu`, `/cart`, `/orders`, `/offline.html`; cache-first for static assets; navigations network-first with offline fallback.
8. **Manifest** — `public/manifest.json` (ChiyaGadi / Chiya); linked from `app/layout.tsx`.
9. **APK** — HTTPS on Vercel + SW + manifest satisfy PWABuilder prerequisites.

## Environment

Copy `.env.example` to `.env.local` and set all `NEXT_PUBLIC_FIREBASE_*` values. Builds **require** a valid `NEXT_PUBLIC_FIREBASE_API_KEY` for runtime auth/Firestore calls (static prerender no longer initializes Firebase at import time).

Optional: `NEXT_PUBLIC_MENU_COLLECTION` (default `products`) for menu cache in `services/menuCacheService.ts`.

## Deploy (Vercel)

1. Add the same env vars in Project → Settings → Environment Variables.
2. Build command: `npm run build` (from `pos-web` root if this is the app root, or set Root Directory to `pos-web`).
3. Ensure `public/sw.js` is served (Next `public/` maps to `/sw.js`).

## Test offline

1. Login once online (tokens + Dexie + `localStorage` updated).
2. Open DevTools → Application → Service Workers → verify `sw.js` active.
3. DevTools → Network → Offline; reload — shell and cached routes should load.
4. Create orders; go online — pending orders sync via `NetworkContext` / `syncPendingOrders`.

## PWABuilder

1. Open [PWABuilder](https://www.pwabuilder.com/) and enter your production URL.
2. Confirm manifest + service worker are detected.
3. Package for Android (TWA/APK) and follow the signing flow.

## Notes

- **Dexie** is used instead of raw `idb` for IndexedDB (same storage layer, better ergonomics).
- `syncEngine` uses `setDoc` with deterministic `order.id` to match your Flutter/Firestore conventions; adjust `toFirestoreOrder` if your schema differs.
