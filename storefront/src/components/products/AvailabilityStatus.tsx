"use client";

import { CircleCheckBig, CircleX, Clock, PackageCheck } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import type { AvailabilityState } from "@/lib/utils/variant-selection";

interface AvailabilityStatusProps {
  availability: AvailabilityState;
  /** Pre-order ship-by date (ISO); ignored outside the pre-order state. */
  preorderShipsAt?: string | null;
}

function formatShipsBy(iso: string, locale: string): string {
  try {
    return new Intl.DateTimeFormat(locale, {
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

/**
 * PDP availability line (PRD-20260915-catalog-pdp-state-correctness FR-002):
 * in stock / pre-order (with ship-by promise) / backorder / sold out.
 * Kept as its own component so ProductDetails' branching stays flat
 * (supervisor STD-CQ-001 decision-count budget).
 */
export function AvailabilityStatus({
  availability,
  preorderShipsAt,
}: AvailabilityStatusProps) {
  const t = useTranslations("products");
  const locale = useLocale();

  if (availability === "in_stock") {
    return (
      <span className="inline-flex items-center gap-1.5 text-green-600">
        <CircleCheckBig className="w-5 h-5" />
        {t("inStock")}
      </span>
    );
  }

  if (availability === "preorder") {
    return (
      <div className="flex flex-col gap-1">
        <span className="inline-flex items-center gap-1.5 text-blue-600">
          <Clock className="w-5 h-5" />
          {t("preorder")}
        </span>
        {preorderShipsAt ? (
          <span className="text-sm text-gray-500">
            {t("preorderShipsBy", {
              date: formatShipsBy(preorderShipsAt, locale),
            })}
          </span>
        ) : null}
      </div>
    );
  }

  if (availability === "backorder") {
    return (
      <div className="flex flex-col gap-1">
        <span className="inline-flex items-center gap-1.5 text-amber-600">
          <PackageCheck className="w-5 h-5" />
          {t("backorder")}
        </span>
        <span className="text-sm text-gray-500">{t("backorderNote")}</span>
      </div>
    );
  }

  return (
    <span className="inline-flex items-center gap-1.5 text-red-600">
      <CircleX className="w-5 h-5" />
      {t("outOfStock")}
    </span>
  );
}
