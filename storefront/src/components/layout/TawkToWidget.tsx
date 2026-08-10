"use client";

import Script from "next/script";

/**
 * Tawk.to live-chat widget (客服挂件).
 *
 * Enabled only when BOTH `NEXT_PUBLIC_TAWK_TO_PROPERTY_ID` and
 * `NEXT_PUBLIC_TAWK_TO_WIDGET_ID` are set (they identify a public tawk.to
 * property/widget — like a publishable key, not a secret). When either is
 * missing the component renders nothing and no third-party script is loaded.
 *
 * The embed script loads asynchronously via `next/script` with the
 * `afterInteractive` strategy so it never blocks first paint.
 *
 * # PRD-20260810-storefront-商城前台接入tawk-to作为客服工具 AC-001/AC-002/AC-004
 */
export function TawkToWidget() {
  const propertyId = process.env.NEXT_PUBLIC_TAWK_TO_PROPERTY_ID;
  const widgetId = process.env.NEXT_PUBLIC_TAWK_TO_WIDGET_ID;

  if (!propertyId || !widgetId) {
    return null;
  }

  return (
    <Script
      id="tawk-to"
      strategy="afterInteractive"
      src={`https://embed.tawk.to/${propertyId}/${widgetId}`}
    />
  );
}
