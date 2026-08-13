"use client";

import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { useCookieConsent } from "@/contexts/CookieConsentContext";
import {
  COOKIE_CATEGORIES,
  type CookieCategory,
} from "@/lib/constants/cookies";
import type { ToggleablePreferences } from "@/lib/cookie-consent";
import { cn } from "@/lib/utils";

interface CookieSettingsProps {
  /** Called after preferences are saved (e.g. to collapse the banner panel). */
  onSaved?: () => void;
}

/**
 * Cookie category toggles, shared by the banner's "customize" panel and the
 * standalone `/cookies` settings page.
 *
 * # PRD-20260812-storefront-商城前台新增cookie功能 FR-004
 */
export function CookieSettings({ onSaved }: CookieSettingsProps) {
  const t = useTranslations("cookie");
  const { consent, savePreferences } = useCookieConsent();
  const [prefs, setPrefs] = useState<ToggleablePreferences>({
    functional: consent?.functional ?? false,
    analytics: consent?.analytics ?? false,
    marketing: consent?.marketing ?? false,
  });
  const [saved, setSaved] = useState(false);

  // Sync local state whenever the persisted consent changes (first client
  // read, or a change made elsewhere, e.g. the banner "accept all").
  useEffect(() => {
    setPrefs({
      functional: consent?.functional ?? false,
      analytics: consent?.analytics ?? false,
      marketing: consent?.marketing ?? false,
    });
  }, [consent]);

  const handleSave = () => {
    savePreferences(prefs);
    setSaved(true);
    onSaved?.();
  };

  return (
    <div className="space-y-4">
      <p className="text-sm text-gray-600">{t("settingsDescription")}</p>
      <ul className="space-y-3">
        {COOKIE_CATEGORIES.map((category) => {
          const disabled = category.required === true;
          const checked = disabled
            ? true
            : prefs[category.key as keyof ToggleablePreferences];
          return (
            <li key={category.key} className="flex items-start gap-3">
              <Checkbox
                id={`cookie-category-${category.key}`}
                checked={checked}
                disabled={disabled}
                aria-label={t(`categories.${category.titleKey}`)}
                onCheckedChange={(value) => {
                  if (disabled) return;
                  setPrefs((prev) => ({
                    ...prev,
                    [category.key]: value === true,
                  }));
                  setSaved(false);
                }}
              />
              <label
                htmlFor={`cookie-category-${category.key}`}
                className={cn(
                  "text-sm",
                  disabled ? "text-gray-400" : "text-gray-900",
                )}
              >
                <span className="font-medium">
                  {t(`categories.${category.titleKey}`)}
                </span>
                <span className="block text-gray-500">
                  {t(`categories.${category.descriptionKey}`)}
                </span>
              </label>
            </li>
          );
        })}
      </ul>
      <div className="flex items-center gap-3">
        <Button type="button" size="sm" onClick={handleSave}>
          {t("savePreferences")}
        </Button>
        {saved && (
          <p role="status" className="text-sm text-green-600">
            {t("saved")}
          </p>
        )}
      </div>
    </div>
  );
}

// Keep the category type re-exported for callers that need it.
export type { CookieCategory };
