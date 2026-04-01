"use client";

import Link from "next/link";

/** Shell route for SW precache + future cart UI; keeps offline navigation working. */
export default function CartPage() {
  return (
    <div style={{ padding: 24 }}>
      <nav style={{ marginBottom: 16 }}>
        <Link href="/" style={{ marginRight: 16 }}>
          Home
        </Link>
        <Link href="/menu">Menu</Link>
      </nav>
      <h1>Cart</h1>
      <p style={{ color: "#666" }}>
        Cart UI can be wired to local IndexedDB here; shell is cached for offline
        use.
      </p>
    </div>
  );
}
