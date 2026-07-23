import { GoogleTagManager } from "@next/third-parties/google";
import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import type { Metadata } from "next";
import { Geist } from "next/font/google";
import "./globals.css";
import { Suspense } from "react";
import { getStoreDescription, getStoreName } from "@/lib/store";

const gtmId = process.env.GTM_ID;
const pallastradeApiOrigin = (() => {
  try {
    return process.env.PALLASTRADE_API_URL
      ? new URL(process.env.PALLASTRADE_API_URL).origin
      : undefined;
  } catch {
    return undefined;
  }
})();

const geist = Geist({
  variable: "--font-geist",
  subsets: ["latin"],
  display: "swap",
});

const rootStoreName = getStoreName();

export const metadata: Metadata = {
  title: {
    template: `%s | ${rootStoreName}`,
    default: rootStoreName,
  },
  description: getStoreDescription(),
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        {pallastradeApiOrigin && (
          <>
            <link rel="preconnect" href={pallastradeApiOrigin} />
            <link rel="dns-prefetch" href={pallastradeApiOrigin} />
          </>
        )}
      </head>
      {gtmId && <GoogleTagManager gtmId={gtmId} />}
      <body
        className={`${geist.variable} antialiased min-h-screen flex flex-col`}
      >
        <Suspense fallback={null}>{children}</Suspense>
        {process.env.NODE_ENV === "production" && (
          <>
            <Analytics />
            <SpeedInsights />
          </>
        )}
      </body>
    </html>
  );
}
