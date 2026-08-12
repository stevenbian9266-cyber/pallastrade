"use client";

import Script from "next/script";
import { useCallback, useEffect, useRef, useState } from "react";

interface TurnstileApi {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string;
  reset: (widgetId?: string) => void;
}

type WidgetStatus = "loading" | "ready" | "error";

const SCRIPT_SRC = "https://challenges.cloudflare.com/turnstile/api.js";
const LOAD_TIMEOUT_MS = 8000;

/**
 * Cloudflare Turnstile human-verification widget.
 *
 * Renders a VISIBLE wrapper (border + status area) so the component is always
 * present on the registration form. The Turnstile challenge iframe is rendered
 * inside once the Cloudflare script loads; if the script fails to load (e.g.
 * network/region blocking), an error message + retry button is shown instead —
 * the component never disappears silently.
 *
 * Enabled only when `NEXT_PUBLIC_TURNSTILE_SITE_KEY` is set (the site key is
 * public — it is NOT a secret). When it is missing the component renders
 * nothing and no third-party script is loaded.
 *
 * Retries reload the script with a native <script> tag so next/script's
 * dedup logic can't swallow a re-load after a failure.
 *
 * # PRD-20260812-storefront-商城前台注册面板接入-turnstile-真人验证 AC-001
 * # 修复：组件必须可见渲染（占位/加载/错误+重试），脚本加载失败不静默消失
 */
export function TurnstileWidget({
  onTokenChange,
  labels = {},
}: {
  onTokenChange?: (token: string | null) => void;
  labels?: {
    loading?: string;
    loadFailed?: string;
    retry?: string;
  };
}) {
  const siteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  const containerRef = useRef<HTMLDivElement>(null);
  const widgetIdRef = useRef<string | undefined>(undefined);
  const [status, setStatus] = useState<WidgetStatus>("loading");
  const [retryKey, setRetryKey] = useState(0);

  const renderWidget = useCallback(() => {
    const turnstile = (window as unknown as { turnstile?: TurnstileApi })
      .turnstile;
    if (!turnstile || !containerRef.current || !siteKey) return;

    try {
      if (widgetIdRef.current) {
        turnstile.reset(widgetIdRef.current);
      } else {
        widgetIdRef.current = turnstile.render(containerRef.current, {
          sitekey: siteKey,
          callback: (token: string) => onTokenChange?.(token),
          "expired-callback": () => onTokenChange?.(null),
          "error-callback": () => onTokenChange?.(null),
        });
      }
      setStatus("ready");
    } catch {
      setStatus("error");
    }
  }, [siteKey, onTokenChange]);

  // Watchdog: if the script never becomes available within the timeout,
  // surface the visible error state (with retry) instead of staying blank.
  useEffect(() => {
    if (status === "ready") return;
    const timer = setTimeout(() => {
      if (!(window as unknown as { turnstile?: TurnstileApi }).turnstile) {
        setStatus("error");
      }
    }, LOAD_TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, [status, retryKey]);

  const handleRetry = () => {
    setStatus("loading");
    setRetryKey((key) => key + 1);
    widgetIdRef.current = undefined;

    document.getElementById("cf-turnstile-script")?.remove();
    const script = document.createElement("script");
    script.id = "cf-turnstile-script";
    script.src = SCRIPT_SRC;
    script.async = true;
    script.defer = true;
    script.onload = renderWidget;
    script.onerror = () => setStatus("error");
    document.head.appendChild(script);
  };

  if (!siteKey) {
    return null;
  }

  return (
    <div
      className="rounded-md border border-input bg-muted/50 p-3"
      data-testid="turnstile-wrapper"
    >
      {/* next/script is only rendered on first mount; retries use a native
          <script> so the reload isn't deduped by next/script. */}
      {retryKey === 0 && (
        <Script
          id="cf-turnstile"
          strategy="afterInteractive"
          src={SCRIPT_SRC}
          onReady={renderWidget}
          onError={() => setStatus("error")}
        />
      )}
      <div ref={containerRef} data-testid="turnstile-widget" />

      {status === "loading" && labels.loading && (
        <p className="mt-2 text-sm text-muted-foreground">{labels.loading}</p>
      )}

      {status === "error" && (
        <div
          className="mt-2 flex items-center justify-between gap-3"
          data-testid="turnstile-error"
        >
          <p className="text-sm text-destructive">
            {labels.loadFailed ?? "Human verification failed to load."}
          </p>
          <button
            type="button"
            onClick={handleRetry}
            className="rounded-md border border-input px-3 py-1.5 text-sm font-medium text-foreground transition-colors hover:bg-accent"
          >
            {labels.retry ?? "Retry"}
          </button>
        </div>
      )}
    </div>
  );
}
