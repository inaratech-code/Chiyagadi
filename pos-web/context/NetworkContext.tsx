"use client";

import React, { createContext, useCallback, useContext, useEffect, useState } from "react";
import { db } from "../lib/localDB";
import { syncPendingOrders } from "../lib/syncEngine";

interface NetworkState {
  isOnline: boolean;
  isSyncing: boolean;
  pendingOrderCount: number;
  lastSyncError: string | null;
  triggerSync: () => Promise<void>;
}

const NetworkContext = createContext<NetworkState | null>(null);

export function NetworkProvider({ children }: { children: React.ReactNode }) {
  const [isOnline, setIsOnline] = useState(typeof navigator !== "undefined" ? navigator.onLine : true);
  const [isSyncing, setIsSyncing] = useState(false);
  const [pendingOrderCount, setPendingOrderCount] = useState(0);
  const [lastSyncError, setLastSyncError] = useState<string | null>(null);

  const refreshPendingCount = useCallback(async () => {
    try {
      const count = await db.orders.where("syncStatus").equals("pending").count();
      setPendingOrderCount(count);
    } catch {
      setPendingOrderCount(0);
    }
  }, []);

  const runSync = useCallback(async () => {
    if (!isOnline) return;
    setIsSyncing(true);
    setLastSyncError(null);
    try {
      const result = await syncPendingOrders();
      await refreshPendingCount();
      if (result.errors.length) setLastSyncError(result.errors.join("; "));
    } catch (e) {
      setLastSyncError(e instanceof Error ? e.message : String(e));
    } finally {
      setIsSyncing(false);
    }
  }, [isOnline, refreshPendingCount]);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      runSync();
    };
    const handleOffline = () => setIsOnline(false);
    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);
    refreshPendingCount();
    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
    };
  }, [runSync, refreshPendingCount]);

  const triggerSync = useCallback(() => runSync(), [runSync]);

  const value: NetworkState = {
    isOnline,
    isSyncing,
    pendingOrderCount,
    lastSyncError,
    triggerSync,
  };

  return (
    <NetworkContext.Provider value={value}>
      {children}
    </NetworkContext.Provider>
  );
}

export function useNetwork(): NetworkState {
  const ctx = useContext(NetworkContext);
  if (!ctx) throw new Error("useNetwork must be used within NetworkProvider");
  return ctx;
}
