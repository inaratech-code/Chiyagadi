"use client";

import Link from "next/link";
import { useNetwork } from "../context/NetworkContext";

export default function HomePage() {
  const { isOnline, isSyncing, pendingOrderCount } = useNetwork();

  return (
    <div style={{ padding: 24 }}>
      <h1>POS Offline First</h1>
      {!isOnline && (
        <div style={{ background: "#fff3cd", padding: 12, borderRadius: 8, marginBottom: 16 }}>
          Offline Mode — Orders saved locally
        </div>
      )}
      {isSyncing && (
        <div style={{ marginBottom: 16 }}>Syncing...</div>
      )}
      {pendingOrderCount > 0 && (
        <div style={{ marginBottom: 16 }}>
          Pending sync: {pendingOrderCount} order(s)
        </div>
      )}
      <nav>
        <Link href="/orders" style={{ marginRight: 16 }}>Orders</Link>
        <Link href="/login">Login</Link>
      </nav>
    </div>
  );
}
