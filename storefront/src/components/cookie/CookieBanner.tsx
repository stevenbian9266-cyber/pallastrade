"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { useCookieConsent } from "@/contexts/CookieConsentContext";
import { CookieSettings } from "./CookieSettings";

/**
 * Cookie consent banner shown on first visit (no consent cookie yet).
 * Rendered only after this component has mounted on the client and while
 * undecided, so returning visitors never see a flash of the banner.
 *
 * `mounted` is local state in THIS component (same segment that conditionally
 * renders) so the post-hydration re-render never crosses a streaming
 * boundary — which would otherwise trigger a React hydration mismatch.
 *
 * Actions: Accept all / Necessary only / Customize (inline category panel).
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-002 / FR-003
 */
export function CookieBanner() {
  const t = useTranslations("cookie");
  const { consent, acceptAll, rejectAll } = useCookieConsent();
  const [customizing, setCustomizing] = useState(false);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted || consent !== null) return null;

  return (
    <div
      role="dialog"
      aria-label={t("bannerTitle")}
      aria-live="polite"
      className="fixed inset-x-4 bottom-4 z-50 mx-auto max-w-xl rounded-lg border border-gray-200 bg-white p-5 shadow-lg"
    >
      <h2 className="text-sm font-semibold text-gray-900">
        {t("bannerTitle")}
      </h2>
      <p className="mt-2 text-sm leading-relaxed text-gray-600">
        {t("bannerDescription")}
      </p>

      {customizing ? (
        <div className="mt-4">
          <CookieSettings onSaved={() => setCustomizing(false)} />
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="mt-3"
            onClick={() => setCustomizing(false)}
          >
            {t("back")}
          </Button>
        </div>
      ) : (
        <div className="mt-4 flex flex-wrap gap-2">
          <Button type="button" size="sm" onClick={acceptAll}>
            {t("acceptAll")}
          </Button>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={rejectAll}
          >
            {t("necessaryOnly")}
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => setCustomizing(true)}
          >
            {t("customize")}
          </Button>
        </div>
      )}
    </div>
  );
}
