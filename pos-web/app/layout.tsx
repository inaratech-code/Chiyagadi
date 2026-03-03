import type { Metadata } from "next";
import "./globals.css";
import { NetworkProvider } from "../context/NetworkContext";
import { RegisterSW } from "../components/RegisterSW";

export const metadata: Metadata = {
  title: "POS Offline First",
  description: "Offline-first Point of Sale",
  manifest: "/manifest.json",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="manifest" href="/manifest.json" />
      </head>
      <body>
        <NetworkProvider>
          <RegisterSW />
          {children}
        </NetworkProvider>
      </body>
    </html>
  );
}
