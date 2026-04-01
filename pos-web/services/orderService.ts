import { doc, setDoc } from "firebase/firestore";
import { getFirebaseFirestore } from "../lib/firebase";
import { db, getOrCreateDeviceId } from "../lib/localDB";
import type { Order, OrderItem } from "../types";
import { syncPendingOrders } from "@/lib/syncEngine";

/** Create order offline-first: UUID id, save to IndexedDB, sync if online. Never block on network. */
export async function createOrder(params: {
  items: OrderItem[];
  subtotal: number;
  tax: number;
  total: number;
  customerId?: string | null;
  customerName?: string | null;
}): Promise<Order> {
  const id =
    typeof crypto !== "undefined" && crypto.randomUUID
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
  const now = Date.now();
  const deviceId = await getOrCreateDeviceId();

  const order: Order = {
    id,
    items: params.items,
    subtotal: params.subtotal,
    tax: params.tax,
    total: params.total,
    status: "draft",
    createdAt: now,
    updatedAt: now,
    syncStatus: "pending",
    deviceId,
    customerId: params.customerId ?? null,
    customerName: params.customerName ?? null,
  };

  await db.orders.add(order);

  if (typeof navigator !== "undefined" && navigator.onLine) {
    syncPendingOrders().catch(() => {});
  }

  return order;
}

/** Update order locally; set syncStatus pending. */
export async function updateOrder(
  orderId: string,
  updates: Partial<Pick<Order, "items" | "subtotal" | "tax" | "total" | "status" | "customerId" | "customerName">>
): Promise<void> {
  const now = Date.now();
  await db.orders.update(orderId, {
    ...updates,
    updatedAt: now,
    syncStatus: "pending",
  });
  if (typeof navigator !== "undefined" && navigator.onLine) {
    syncPendingOrders().catch(() => {});
  }
}

/** Get order by id from local DB. */
export async function getOrder(orderId: string): Promise<Order | undefined> {
  return db.orders.get(orderId);
}

/** List orders (e.g. pending first). */
export async function listOrders(): Promise<Order[]> {
  return db.orders.orderBy("createdAt").reverse().toArray();
}

/** Firestore: setDoc with order.id as doc id. Never use addDoc for orders. */
export async function pushOrderToFirestore(order: Order): Promise<void> {
  const ref = doc(getFirebaseFirestore(), "orders", order.id);
  await setDoc(ref, {
    id: order.id,
    items: order.items,
    subtotal: order.subtotal,
    tax: order.tax,
    total: order.total,
    status: order.status,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    deviceId: order.deviceId,
    orderNumber: order.orderNumber ?? null,
    customerId: order.customerId ?? null,
    customerName: order.customerName ?? null,
    paymentStatus: order.paymentStatus ?? null,
    paymentMethod: order.paymentMethod ?? null,
  });
}
