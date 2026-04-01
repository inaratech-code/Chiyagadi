/** Local + Firestore order shape. id is UUID; Firestore doc id must equal order.id (never use addDoc). */
export interface Order {
  id: string;
  items: OrderItem[];
  subtotal: number;
  tax: number;
  total: number;
  status: OrderStatus;
  createdAt: number;
  updatedAt: number;
  syncStatus: SyncStatus;
  deviceId: string;
  /** Optional: set when synced to Firestore */
  orderNumber?: string;
  customerId?: string | null;
  customerName?: string | null;
  paymentStatus?: string;
  paymentMethod?: string;
}

export interface OrderItem {
  productId: string;
  name: string;
  quantity: number;
  unitPrice: number;
  totalPrice: number;
  notes?: string;
}

export type OrderStatus = "draft" | "confirmed" | "cancelled";
export type SyncStatus = "pending" | "synced";

/** Stored in IndexedDB users table. No passwords. */
export interface LocalUser {
  id: string;
  email: string;
  role?: string;
  token: string;
  tokenExpiry: number;
  lastLoginAt: number;
}

/** Meta key-value for deviceId etc. */
export interface MetaRow {
  key: string;
  value: string | number | boolean;
}

/** Cached Firestore menu/product document (IndexedDB). */
export interface MenuRow {
  id: string;
  data: Record<string, unknown>;
  updatedAt: number;
}
