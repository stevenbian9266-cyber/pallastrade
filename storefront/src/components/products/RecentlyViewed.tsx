"use client";

import type { Product } from "@pallastrade/sdk";
import { useTranslations } from "next-intl";
import { useEffect, useMemo, useState } from "react";
import { ProductCarousel } from "@/components/products/ProductCarousel";
import { readLocalValue } from "@/lib/utils/local-store";
import {
  parseRecentlyViewed,
  RECENTLY_VIEWED_EVENT,
  RECENTLY_VIEWED_KEY,
  type RecentlyViewedEntry,
} from "@/lib/utils/recently-viewed";

interface RecentlyViewedProps {
  basePath: string;
  /** The product on screen — never suggested back to the shopper. */
  currentProductId?: string | number;
  currency?: string;
}

/**
 * "Recently viewed" rail (PRD-20260915-catalog-batch-c1-discovery FR-002).
 *
 * Browser-local and mounted-only: the first render is empty by design so server
 * and client markup agree, then the list syncs on same-page events (new visit)
 * and cross-tab `storage` events.
 */
export function RecentlyViewed({
  basePath,
  currentProductId,
  currency,
}: RecentlyViewedProps) {
  const t = useTranslations("products");
  const [entries, setEntries] = useState<RecentlyViewedEntry[] | null>(null);

  useEffect(() => {
    const sync = () =>
      setEntries(parseRecentlyViewed(readLocalValue(RECENTLY_VIEWED_KEY)));

    sync();
    window.addEventListener(RECENTLY_VIEWED_EVENT, sync);
    window.addEventListener("storage", sync);

    return () => {
      window.removeEventListener(RECENTLY_VIEWED_EVENT, sync);
      window.removeEventListener("storage", sync);
    };
  }, []);

  const products = useMemo<Product[]>(() => {
    const current = currentProductId == null ? null : String(currentProductId);
    return (entries ?? [])
      .filter((entry) => entry.id !== current)
      .map((entry) => entry.product);
  }, [entries, currentProductId]);

  if (products.length === 0) return null;

  return (
    <section
      aria-labelledby="recently-viewed-heading"
      className="container mx-auto px-4 sm:px-6 lg:px-8 py-10"
    >
      <h2
        id="recently-viewed-heading"
        className="text-lg font-medium text-gray-900 mb-6"
      >
        {t("recentlyViewedTitle")}
      </h2>
      <ProductCarousel
        products={products}
        basePath={basePath}
        currency={currency}
      />
    </section>
  );
}
