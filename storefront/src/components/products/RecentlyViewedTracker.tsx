"use client";

import type { Product } from "@pallastrade/sdk";
import { useEffect } from "react";
import {
  dispatchLocalEvent,
  readLocalValue,
  writeLocalValue,
} from "@/lib/utils/local-store";
import {
  parseRecentlyViewed,
  pushRecentlyViewed,
  RECENTLY_VIEWED_EVENT,
  RECENTLY_VIEWED_KEY,
  serializeRecentlyViewed,
} from "@/lib/utils/recently-viewed";

/**
 * Records a product view in `localStorage` (PRD-20260915-catalog-batch-c1-discovery
 * FR-002). Renders nothing — mounted on the product page so the rail below can
 * pick the visit up on the same page.
 */
export function RecentlyViewedTracker({ product }: { product: Product }) {
  useEffect(() => {
    const entries = parseRecentlyViewed(readLocalValue(RECENTLY_VIEWED_KEY));
    const next = pushRecentlyViewed(entries, product);

    writeLocalValue(RECENTLY_VIEWED_KEY, serializeRecentlyViewed(next));
    dispatchLocalEvent(RECENTLY_VIEWED_EVENT);
  }, [product]);

  return null;
}
