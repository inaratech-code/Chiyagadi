# POS Offline-First (Next.js)

- **Offline login** after first online login; re-auth every 24h.
- **Offline order creation** with UUID; stored in IndexedDB (Dexie); sync when online.
- **Sync engine**: setDoc(orders, order.id) — no addDoc; last-write-wins by updatedAt.
- **NetworkContext**: isOnline, isSyncing, pendingOrderCount, triggerSync.
- **PWA**: `/public/service-worker.js` (cache shell + static; network-first for API/Firebase), `/public/manifest.json`.

## Setup

1. `npm install`
2. Copy `.env.example` to `.env.local` and set Firebase config.
3. `npm run dev`

## Structure

- `lib/localDB.ts` — Dexie schema (users, orders, meta); getOrCreateDeviceId().
- `lib/syncEngine.ts` — syncPendingOrders(); setDoc only.
- `services/offlineAuthService.ts` — persistSessionForOffline, offlineLogin.
- `services/orderService.ts` — createOrder (UUID, IndexedDB, then sync if online).
- `context/NetworkContext.tsx` — online/offline, sync on "online", pending count.
- `public/service-worker.js` — service worker; `public/manifest.json` — PWA manifest.
