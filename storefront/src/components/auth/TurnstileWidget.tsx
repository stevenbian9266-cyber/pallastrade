"use client";

import Script from "next/script";
import { useCallback, useRef } from "react";

interface TurnstileApi {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string;
  reset: (widgetId?: string) => void;
}

/**
 * Cloudflare Turnstile human-verification widget.
 *
 * Renders the Turnstile challenge and reports the `cf-turnstile-response` token
 * via `onTokenChange`. Enabled only when `NEXT_PUBLIC_TURNSTILE_SITE_KEY` is set
 * (the site key is public — it is NOT a secret). When it is missing the
 * component renders nothing and no third-party script is loaded — matching the
 * TawkToWidget pattern for optional third-party integrations.
 *
 * # PRD-20260812-storefront-商城前台注册面板接入-turnstile-真人验证 AC-001
 */
export function TurnstileWidget({
  onTokenChange,
}: {
  onTokenChange?: (token: string | null) => void;
}) {
  const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  const containerRef = useRef<HTMLDivElement>(null);
  const widgetIdRef = useRef<string | undefined>(undefined);

  const renderWidget = useCallback(() => {
    const turnstile = (window as unknown as { turnstile?: TurnstileApi })
      .turnstile;
    if (!turnstile || !containerRef.current || !siteKey) return;

    if (widgetIdRef.current) {
      turnstile.reset(widgetIdRef.current);
      return;
    }

    widgetIdRef.current = turnstile.render(containerRef.current, {
      sitekey: siteKey,
      callback: (token: string) => onTokenChange?.(token),
      "expired-callback": () => onTokenChange?.(null),
      "error-callback": () => onTokenChange?.(null),
    });
  }, [siteKey, onTokenChange]);

  if (!siteKey) {
    return null;
  }

  return (
    <>
      <Script
        id="cf-turnstile"
        strategy="afterInteractive"
        src="https://challenges.cloudflare.com/turnstile/api.js"
        onReady={renderWidget}
      />
      <div ref={containerRef} data-testid="turnstile-widget" />
    </>
  );
}
