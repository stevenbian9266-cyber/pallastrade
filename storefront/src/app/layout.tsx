import type { Metadata } from "next";
import { Geist } from "next/font/google";
import "./globals.css";
import { Suspense } from "react";
import { GatedScripts } from "@/components/cookie/GatedScripts";
import { CookieConsentProvider } from "@/contexts/CookieConsentContext";
import { getStoreDescription, getStoreName } from "@/lib/store";

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
      <body
        className={`${geist.variable} antialiased min-h-screen flex flex-col`}
      >
        <CookieConsentProvider>
          <Suspense fallback={null}>{children}</Suspense>
          {/* GTM / Vercel Analytics / Speed Insights / Tawk.to — gated by
              the visitor's cookie consent (# PRD-20260812-storefront-cookie). */}
          <GatedScripts />
        </CookieConsentProvider>
      </body>
    </html>
  );
}
