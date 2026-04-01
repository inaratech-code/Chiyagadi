"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useNetwork } from "../../context/NetworkContext";
import {
  fetchMenuFromFirestoreAndCache,
  getMenuFromCache,
} from "../../services/menuCacheService";
import type { MenuRow } from "../../types";

/**
 * Menu: loads from IndexedDB when offline; when online, refreshes cache from Firestore.
 * Set NEXT_PUBLIC_MENU_COLLECTION to match your collection id (default: products).
 */
export default function MenuPage() {
  const { isOnline } = useNetwork();
  const [rows, setRows] = useState<MenuRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshError, setRefreshError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setRefreshError(null);
      const cached = await getMenuFromCache();
      if (!cancelled) setRows(cached);
      if (typeof navigator !== "undefined" && navigator.onLine) {
        const r = await fetchMenuFromFirestoreAndCache();
        if (r.error) setRefreshError(r.error);
        const fresh = await getMenuFromCache();
        if (!cancelled) setRows(fresh);
      }
      if (!cancelled) setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [isOnline]);

  return (
    <div style={{ padding: 24, maxWidth: 720 }}>
      <nav style={{ marginBottom: 16 }}>
        <Link href="/" style={{ marginRight: 16 }}>
          Home
        </Link>
        <Link href="/cart">Cart</Link>
      </nav>
      <h1>Menu</h1>
      {refreshError && (
        <p style={{ color: "#c62828", fontSize: 14 }}>
          Could not refresh from server: {refreshError}. Showing cached items if
          any.
        </p>
      )}
      {loading ? (
        <p>Loading…</p>
      ) : rows.length === 0 ? (
        <p style={{ color: "#666" }}>
          No menu items cached yet. Connect once online to sync from Firestore (
          <code>NEXT_PUBLIC_MENU_COLLECTION</code>, default{" "}
          <code>products</code>).
        </p>
      ) : (
        <ul style={{ listStyle: "none", padding: 0 }}>
          {rows.map((row) => (
            <li
              key={row.id}
              style={{
                border: "1px solid #eee",
                borderRadius: 8,
                padding: 12,
                marginBottom: 8,
              }}
            >
              <strong>{String(row.data.name ?? row.data.title ?? row.id)}</strong>
              {row.data.price != null && (
                <span style={{ marginLeft: 8, color: "#555" }}>
                  NPR {String(row.data.price)}
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
