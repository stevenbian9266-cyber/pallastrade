"use client";

import { useEffect, useState } from "react";
import { GoogleTagManager } from "@next/third-parties/google";
import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import { TawkToWidget } from "@/components/layout/TawkToWidget";
import { useCookieConsent } from "@/contexts/CookieConsentContext";

/**
 * Client-side gate for all third-party scripts.
 *
 * Nothing is loaded until this component has mounted on the client
 * (`mounted`, local state in the same segment that conditionally renders) and
 * each script only mounts when its category is consented:
 * - GTM / Vercel Analytics / Speed Insights → `analytics`
 * - Tawk.to live chat → `marketing`
 *
 * Before consent is known (SSR / first paint) this renders nothing, which is
 * the privacy-safe default: no third-party script loads until the visitor
 * decides.
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-007
 */
export function GatedScripts() {
  const { consent } = useCookieConsent();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const gtmId = process.env.NEXT_PUBLIC_GTM_ID;
  const vercelAnalyticsEnabled =
    process.env.NODE_ENV === "production" &&
    process.env.NEXT_PUBLIC_VERCEL_ANALYTICS === "true";

  if (!mounted || !consent) return null;

  return (
    <>
      {gtmId && consent.analytics && <GoogleTagManager gtmId={gtmId} />}
      {vercelAnalyticsEnabled && consent.analytics && (
        <>
          <Analytics />
          <SpeedInsights />
        </>
      )}
      {consent.marketing && <TawkToWidget />}
    </>
  );
}
