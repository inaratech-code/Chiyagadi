# Offline-First POS — Folder Structure

```
pos-web/
├── app/
│   ├── layout.tsx          # Root layout; NetworkProvider, RegisterSW, manifest link
│   ├── page.tsx            # Home: offline badge, syncing, pending count, nav
│   ├── globals.css
│   ├── login/
│   │   └── page.tsx        # Online login + persistSessionForOffline; offline login (24h policy)
│   └── orders/
│       └── page.tsx        # Example: list orders, create demo order, Sync button, badges
├── components/
│   └── RegisterSW.tsx       # Client: register /sw.js on mount
├── context/
│   └── NetworkContext.tsx  # isOnline, isSyncing, pendingOrderCount, lastSyncError, triggerSync; online → sync
├── lib/
│   ├── firebase.ts         # Firebase app, auth, firestore (env-based config)
│   ├── localDB.ts          # Dexie: users, orders, meta; getOrCreateDeviceId()
│   └── syncEngine.ts       # syncPendingOrders(): setDoc(orders, order.id) only; last-write-wins
├── services/
│   ├── offlineAuthService.ts  # persistSessionForOffline, offlineLogin, getStoredEmails, clearStoredUser
│   └── orderService.ts     # createOrder (UUID, IndexedDB, sync if online), updateOrder, getOrder, listOrders
├── types/
│   └── index.ts            # Order, OrderItem, LocalUser, MetaRow, SyncStatus
├── public/
│   ├── manifest.json       # PWA manifest
│   ├── sw.js               # Service worker: shell/static cache; navigate → network first, fallback offline
│   └── offline.html        # Offline fallback page
├── package.json
├── tsconfig.json
├── next.config.js
├── .env.example
├── README.md
└── STRUCTURE.md
```

## Critical Implementation Notes

- **Orders**: ID is `crypto.randomUUID()`. Firestore document ID = `order.id`; always `setDoc(doc(db, "orders", order.id), data)`, never `addDoc`.
- **Conflict resolution**: Compare `updatedAt`; last write wins.
- **Auth**: Only ID token + expiry stored in IndexedDB; force online re-auth every 24 hours.
- **Sync**: On `online` event, run `syncPendingOrders()`; on failure leave orders pending and retry next time.
