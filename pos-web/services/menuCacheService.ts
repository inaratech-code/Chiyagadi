import { collection, getDocs, limit, query } from "firebase/firestore";
import { getFirebaseFirestore } from "../lib/firebase";
import { db } from "../lib/localDB";
import type { MenuRow } from "../types";

/**
 * Firestore collection for menu/products (override via env).
 * Default matches common POS naming; adjust to your Firebase schema.
 */
const MENU_COLLECTION =
  process.env.NEXT_PUBLIC_MENU_COLLECTION || "products";

/**
 * When online: pull all documents (up to `maxDocs`) and persist to IndexedDB.
 * Offline reads use `getMenuFromCache()`.
 */
export async function fetchMenuFromFirestoreAndCache(
  maxDocs = 500
): Promise<{ count: number; error?: string }> {
  try {
    const firestore = getFirebaseFirestore();
    const q = query(
      collection(firestore, MENU_COLLECTION),
      limit(maxDocs)
    );
    const snap = await getDocs(q);
    const now = Date.now();
    let count = 0;
    for (const d of snap.docs) {
      const row: MenuRow = {
        id: d.id,
        data: d.data() as Record<string, unknown>,
        updatedAt: now,
      };
      await db.menuItems.put(row);
      count++;
    }
    return { count };
  } catch (e) {
    return {
      count: 0,
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

export async function getMenuFromCache(): Promise<MenuRow[]> {
  return db.menuItems.orderBy("updatedAt").reverse().toArray();
}
