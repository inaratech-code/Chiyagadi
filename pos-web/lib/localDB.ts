import Dexie, { type Table } from "dexie";
import type { LocalUser, Order, MetaRow, MenuRow } from "../types";

const DB_NAME = "pos-offline-db";
const VERSION = 2;

export class LocalDB extends Dexie {
  users!: Table<LocalUser, string>;
  orders!: Table<Order, string>;
  meta!: Table<MetaRow, string>;
  /** Cached menu/products from Firestore for offline reads */
  menuItems!: Table<MenuRow, string>;

  constructor() {
    super(DB_NAME);
    this.version(1).stores({
      users: "id, email, tokenExpiry",
      orders: "id, syncStatus, createdAt, updatedAt, deviceId",
      meta: "key",
    });
    this.version(2).stores({
      users: "id, email, tokenExpiry",
      orders: "id, syncStatus, createdAt, updatedAt, deviceId",
      meta: "key",
      menuItems: "id, updatedAt",
    });
  }
}

export const db = new LocalDB();

const META_DEVICE_ID = "deviceId";
export async function getOrCreateDeviceId(): Promise<string> {
  const row = await db.meta.get(META_DEVICE_ID);
  if (row?.value && typeof row.value === "string") return row.value;
  const id =
    typeof crypto !== "undefined" && crypto.randomUUID
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
  await db.meta.put({ key: META_DEVICE_ID, value: id });
  return id;
}
