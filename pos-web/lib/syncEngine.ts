import { doc, getDoc, setDoc } from "firebase/firestore";
import { getFirebaseFirestore } from "./firebase";
import { db } from "./localDB";
import type { Order } from "../types";

/**
 * Sync pending orders to Firestore. Firestore doc id MUST equal order.id (setDoc, never addDoc).
 *
 * Orders are queued in IndexedDB (Dexie) with syncStatus "pending" — the canonical offline queue.
 * If you previously used localStorage "pendingOrders", migrate those rows into Dexie before sync.
 */
export async function syncPendingOrders(): Promise<{
  synced: number;
  failed: number;
  errors: string[];
}> {
  const pending = await db.orders.where("syncStatus").equals("pending").toArray();
  const errors: string[] = [];
  let synced = 0;
  let failed = 0;

  const firestore = getFirebaseFirestore();
  for (const order of pending) {
    try {
      const ref = doc(firestore, "orders", order.id);
      const snap = await getDoc(ref);

      if (!snap.exists()) {
        await setDoc(ref, toFirestoreOrder(order));
        await db.orders.update(order.id, { syncStatus: "synced" as const });
        synced++;
        continue;
      }

      const remote = snap.data();
      const remoteUpdated = (remote?.updatedAt as number) ?? 0;
      if (order.updatedAt >= remoteUpdated) {
        await setDoc(ref, toFirestoreOrder(order));
        await db.orders.update(order.id, { syncStatus: "synced" as const });
        synced++;
      } else {
        await db.orders.update(order.id, { syncStatus: "synced" as const });
        synced++;
      }
    } catch (e) {
      failed++;
      errors.push(`${order.id}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  return { synced, failed, errors };
}

function toFirestoreOrder(order: Order): Record<string, unknown> {
  return {
    id: order.id,
    items: order.items,
    subtotal: order.subtotal,
    tax: order.tax,
    total: order.total,
    status: order.status,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    deviceId: order.deviceId,
    orderNumber: order.orderNumber,
    customerId: order.customerId ?? null,
    customerName: order.customerName ?? null,
    paymentStatus: order.paymentStatus ?? null,
    paymentMethod: order.paymentMethod ?? null,
  };
}
