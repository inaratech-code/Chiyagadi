"use client";

import { useCallback, useEffect, useState } from "react";
import { useNetwork } from "../../context/NetworkContext";
import { createOrder, listOrders } from "../../services/orderService";
import type { Order, OrderItem } from "../../types";

export default function OrdersPage() {
  const net = useNetwork();
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setOrders(await listOrders());
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const onDemo = async () => {
    await createOrder({
      items: [{ productId: "p1", name: "Item A", quantity: 2, unitPrice: 100, totalPrice: 200 }],
      subtotal: 200,
      tax: 0,
      total: 200,
    });
    await load();
    await net.triggerSync();
  };

  return (
    <div style={{ padding: 24 }}>
      {!net.isOnline && <span style={{ marginRight: 12 }}>Offline</span>}
      {net.isSyncing && <span>Syncing...</span>}
      {net.pendingOrderCount > 0 && <span>Pending: {net.pendingOrderCount}</span>}
      <button onClick={() => net.triggerSync()} disabled={!net.isOnline || net.isSyncing}>Sync</button>
      <h1>Orders</h1>
      <button onClick={onDemo} disabled={net.isSyncing}>Create demo order</button>
      {loading ? <p>Loading...</p> : (
        <ul style={{ listStyle: "none", padding: 0 }}>
          {orders.map((o) => (
            <li key={o.id} style={{ border: "1px solid #eee", padding: 12, marginBottom: 8 }}>
              {o.id.slice(0, 8)}... NPR {o.total} ({o.syncStatus})
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
