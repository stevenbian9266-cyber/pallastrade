"use client";

import type { ShippingEstimate as ShippingEstimateData } from "@pallastrade/sdk";
import { Truck } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { estimatedArrivalRange, formatArrivalRange } from "@/lib/utils/arrival";

interface ShippingEstimateProps {
  estimate: ShippingEstimateData | null;
  /** Store timezone (`Store#preferred_timezone`) — arrival dates must match it. */
  timeZone?: string;
}

/**
 * Catalog F-2: the PDP shipping line, rendered directly under the price.
 *
 * Every state has its own wording — a digital good promises no window, a store
 * with no front-end delivery method says the cost is settled at checkout, and an
 * unknown estimate renders nothing at all rather than inventing numbers.
 */
export function ShippingEstimate({
  estimate,
  timeZone,
}: ShippingEstimateProps) {
  const t = useTranslations("products");
  const locale = useLocale();

  if (!estimate) return null;

  if (estimate.digital) {
    return (
      <p
        className="mt-2 flex items-center gap-2 text-sm text-gray-600"
        data-testid="shipping-estimate"
      >
        <Truck className="h-4 w-4 shrink-0" aria-hidden="true" />
        {t("instantDownload")}
      </p>
    );
  }

  if (!estimate.available) {
    return (
      <p
        className="mt-2 flex items-center gap-2 text-sm text-gray-600"
        data-testid="shipping-estimate"
      >
        <Truck className="h-4 w-4 shrink-0" aria-hidden="true" />
        {t("shippingAtCheckout")}
      </p>
    );
  }

  const range = estimatedArrivalRange(estimate.min_days, estimate.max_days);
  const daysLabel =
    estimate.min_days != null &&
    estimate.max_days != null &&
    estimate.max_days !== estimate.min_days
      ? t("transitDaysRange", {
          min: estimate.min_days,
          max: estimate.max_days,
        })
      : t("transitDaysSingle", {
          days: estimate.min_days ?? estimate.max_days ?? 0,
        });

  return (
    <div
      className="mt-2 space-y-1 text-sm text-gray-600"
      data-testid="shipping-estimate"
    >
      <p className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <Truck className="h-4 w-4 shrink-0" aria-hidden="true" />
        <span>{t("shippingEstimate")}</span>
        <span className="text-gray-900">{daysLabel}</span>
        {range && (
          <span>
            <span className="sr-only">{t("estimatedArrival")}: </span>
            {formatArrivalRange(range, locale, timeZone)}
          </span>
        )}
      </p>
      {estimate.free_shipping && (
        <p className="text-emerald-700">{t("freeShipping")}</p>
      )}
      {!estimate.free_shipping && estimate.free_shipping_threshold && (
        <p>
          {t("freeShippingOver", { amount: estimate.free_shipping_threshold })}
        </p>
      )}
    </div>
  );
}
