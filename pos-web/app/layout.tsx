import type { Metadata, Viewport } from "next";
import "./globals.css";
import { NetworkProvider } from "../context/NetworkContext";
import { RegisterSW } from "../components/RegisterSW";
import { OfflineBanner } from "../components/OfflineBanner";
import { AuthBootstrap } from "../components/AuthBootstrap";

export const metadata: Metadata = {
  title: "ChiyaGadi",
  description: "ChiyaGadi — offline-first POS (PWA)",
  manifest: "/manifest.json",
  appleWebApp: { capable: true, title: "ChiyaGadi" },
};

export const viewport: Viewport = {
  themeColor: "#ffc107",
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
        <meta name="theme-color" content="#ffc107" />
        <meta name="mobile-web-app-capable" content="yes" />
      </head>
      <body>
        <NetworkProvider>
          <AuthBootstrap />
          <OfflineBanner />
          <RegisterSW />
          {children}
        </NetworkProvider>
      </body>
    </html>
  );
}
