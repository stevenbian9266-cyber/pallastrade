"use client";

import { Check } from "lucide-react";
import { useTranslations } from "next-intl";
import { useState } from "react";

interface SaveInfoSectionProps {
  isAuthenticated: boolean;
}

type SaveInfoStatus = "idle" | "saved" | "declined";

/**
 * "Save my information for a faster checkout" module — UI placeholder only.
 *
 * Matches the checkout demo: a light-gray box with Save / Not now buttons.
 * Save only works for signed-in users (guests are prompted to sign in);
 * the buttons update local state and do not persist anything yet.
 */
export function SaveInfoSection({ isAuthenticated }: SaveInfoSectionProps) {
  const t = useTranslations("checkout");
  const [status, setStatus] = useState<SaveInfoStatus>("idle");

  const handleSave = () => {
    if (!isAuthenticated) {
      // Guests are prompted to sign in — the demo shows the same gate.
      // Sign-in flows already exist via the account page; this remains a
      // placeholder until backend persistence is implemented.
      return;
    }
    setStatus("saved");
  };

  if (status === "declined") {
    return (
      <div
        data-testid="save-info-section"
        className="flex items-center justify-between rounded-lg bg-gray-100 px-4 py-3.5 opacity-50 pointer-events-none"
      >
        <span className="text-[13px] text-gray-500">{t("saveInfoText")}</span>
      </div>
    );
  }

  if (status === "saved") {
    return (
      <div
        data-testid="save-info-section"
        className="flex items-center justify-between rounded-lg bg-gray-100 px-4 py-3.5"
      >
        <span className="flex items-center gap-2 text-[13px] font-semibold text-green-700">
          <Check className="h-4 w-4" aria-hidden="true" />
          {t("saveInfoSaved")}
        </span>
      </div>
    );
  }

  return (
    <div
      data-testid="save-info-section"
      className="flex items-center justify-between gap-3 rounded-lg bg-gray-100 px-4 py-3.5"
    >
      <span className="text-[13px] text-gray-600">{t("saveInfoText")}</span>
      <div className="flex shrink-0 gap-2">
        <button
          type="button"
          onClick={handleSave}
          className="rounded-md bg-primary px-4 py-1.5 text-[13px] font-semibold text-white transition-colors hover:bg-primary-600"
        >
          {t("saveInfoSave")}
        </button>
        <button
          type="button"
          onClick={() => setStatus("declined")}
          className="rounded-md border border-gray-300 bg-transparent px-3.5 py-1.5 text-[13px] text-gray-600 transition-colors hover:border-gray-400 hover:text-gray-800"
        >
          {t("saveInfoNotNow")}
        </button>
      </div>
    </div>
  );
}
