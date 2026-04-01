"use client";

import Link from "next/link";
import { useNetwork } from "../context/NetworkContext";

export default function HomePage() {
  const { isSyncing, pendingOrderCount } = useNetwork();

  return (
    <div style={{ padding: 24 }}>
      <h1>ChiyaGadi</h1>
      <p style={{ color: "#666", marginBottom: 16 }}>
        Offline-first PWA — use the banner above for connection status.
      </p>
      {isSyncing && <div style={{ marginBottom: 16 }}>Syncing…</div>}
      {pendingOrderCount > 0 && (
        <div style={{ marginBottom: 16 }}>
          Pending sync: {pendingOrderCount} order(s)
        </div>
      )}
      <nav>
        <Link href="/orders" style={{ marginRight: 16 }}>
          Orders
        </Link>
        <Link href="/menu" style={{ marginRight: 16 }}>
          Menu
        </Link>
        <Link href="/cart" style={{ marginRight: 16 }}>
          Cart
        </Link>
        <Link href="/login">Login</Link>
      </nav>
    </div>
  );
}
