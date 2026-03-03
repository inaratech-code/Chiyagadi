import Dexie, { type Table } from "dexie";
import type { LocalUser, Order, MetaRow } from "../types";

const DB_NAME = "pos-offline-db";
const VERSION = 1;

export class LocalDB extends Dexie {
  users!: Table<LocalUser, string>;
  orders!: Table<Order, string>;
  meta!: Table<MetaRow, string>;

  constructor() {
    super(DB_NAME);
    this.version(VERSION).stores({
      users: "id, email, tokenExpiry",
      orders: "id, syncStatus, createdAt, updatedAt, deviceId",
      meta: "key",
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
