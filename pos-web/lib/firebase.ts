import { initializeApp, getApps, type FirebaseApp } from "firebase/app";
import { getAuth as firebaseGetAuth, type Auth } from "firebase/auth";
import {
  getFirestore,
  initializeFirestore,
  persistentLocalCache,
  type Firestore,
} from "firebase/firestore";

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

function getOrCreateApp(): FirebaseApp {
  if (getApps().length) return getApps()[0] as FirebaseApp;
  if (!firebaseConfig.apiKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_FIREBASE_API_KEY. Add it to .env.local or Vercel env."
    );
  }
  return initializeApp(firebaseConfig);
}

let _auth: Auth | null = null;

/** Lazy Auth — avoids initializing Firebase during SSR/static import when unused. */
export function getFirebaseAuth(): Auth {
  if (!_auth) {
    _auth = firebaseGetAuth(getOrCreateApp());
  }
  return _auth;
}

/**
 * Firestore with persistent local cache (IndexedDB) on the client.
 * Server uses plain getFirestore (no persistence API).
 */
let _firestore: Firestore | null = null;

export function getFirebaseFirestore(): Firestore {
  if (_firestore) return _firestore;
  const app = getOrCreateApp();
  if (typeof window === "undefined") {
    _firestore = getFirestore(app);
  } else {
    try {
      _firestore = initializeFirestore(app, {
        localCache: persistentLocalCache(),
      });
    } catch {
      _firestore = getFirestore(app);
    }
  }
  return _firestore;
}
