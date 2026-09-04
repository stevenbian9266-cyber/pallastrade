"use client";

import { useTranslations } from "next-intl";
import { useState } from "react";
import { CheckoutSectionTitle } from "@/components/checkout/CheckoutSectionTitle";

/**
 * Value-added service (Add-ons) section — UI placeholder only.
 *
 * Matches the checkout demo's "Worry-Free Purchase" single-select card.
 * The backend AddOn model + pricing pipeline is not integrated yet, so
 * selecting the card only toggles local state and shows the "not yet
 * integrated" hint; no order recalculation happens here.
 */
export function AddOnsSection() {
  const t = useTranslations("checkout");
  const [selected, setSelected] = useState(false);

  return (
    <section>
      <CheckoutSectionTitle step={4} title={t("addOns")} className="mb-3" />

      <label
        className={`flex w-full cursor-pointer items-start gap-3 rounded-lg border px-4 py-3.5 text-left transition-colors ${
          selected
            ? "border-primary bg-primary-50"
            : "border-gray-200 bg-white hover:border-gray-300"
        }`}
      >
        <input
          type="radio"
          name="add-on"
          checked={selected}
          onChange={() => setSelected((prev) => !prev)}
          className="mt-0.5 h-4 w-4 shrink-0 accent-primary"
        />
        <div>
          <p className="text-sm font-bold text-gray-900">
            {t("addOnsWorryFreeName")}
          </p>
          <p className="mt-1 text-xs text-gray-600 leading-relaxed">
            {t("addOnsWorryFreeDesc")}
          </p>
          <p className="mt-1.5 text-[11px] italic text-gray-400">
            {t("addOnsNotIntegrated")}
          </p>
        </div>
      </label>
    </section>
  );
}
