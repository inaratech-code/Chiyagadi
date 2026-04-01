"use client";

import { useNetwork } from "../context/NetworkContext";

/**
 * Global "Offline Mode Active" indicator — does not change layout width;
 * keeps existing pages readable while making offline state obvious.
 */
export function OfflineBanner() {
  const { isOnline, isSyncing, pendingOrderCount } = useNetwork();

  if (isOnline && !isSyncing && pendingOrderCount === 0) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      style={{
        position: "sticky",
        top: 0,
        zIndex: 1000,
        padding: "10px 16px",
        fontSize: 14,
        fontWeight: 600,
        color: isOnline ? "#0d47a1" : "#5d4037",
        background: isOnline ? "#e3f2fd" : "#fff8e1",
        borderBottom: `1px solid ${isOnline ? "#90caf9" : "#ffe082"}`,
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        flexWrap: "wrap",
        gap: 8,
      }}
    >
      <span>
        {!isOnline
          ? "Offline Mode Active — app and cached data are available"
          : isSyncing
            ? "Syncing with server…"
            : pendingOrderCount > 0
              ? `${pendingOrderCount} order(s) pending sync`
              : ""}
      </span>
    </div>
  );
}
