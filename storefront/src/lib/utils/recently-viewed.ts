import type { Product } from "@pallastrade/sdk";
import { isStoredEntry, parseStoredEntries } from "@/lib/utils/local-store";

/**
 * Recently viewed products, kept in the browser (PRD-20260915-catalog-batch-c1-discovery §8.2):
 * newest first, one entry per product, capped so the payload stays small.
 *
 * The pure helpers below never touch the browser — components own the storage
 * access (see `local-store.ts`), which keeps them SSR-safe and unit-testable.
 */
export const RECENTLY_VIEWED_KEY = "pt.recently_viewed";
export const RECENTLY_VIEWED_LIMIT = 12;
export const RECENTLY_VIEWED_EVENT = "pt:recently-viewed";

export interface RecentlyViewedEntry {
  /** Product id, stringified for stable comparisons. */
  id: string;
  slug: string;
  /** Epoch millis of the most recent visit. */
  viewedAt: number;
  product: Product;
}

function isEntry(value: unknown): value is RecentlyViewedEntry {
  return (
    isStoredEntry(value) &&
    typeof (value as { viewedAt?: unknown }).viewedAt === "number"
  );
}

/** Never throws: corrupt or foreign payloads degrade to "nothing viewed yet". */
export function parseRecentlyViewed(
  raw: string | null | undefined,
): RecentlyViewedEntry[] {
  return parseStoredEntries(raw, {
    isValid: isEntry,
    limit: RECENTLY_VIEWED_LIMIT,
  });
}

export function serializeRecentlyViewed(
  entries: RecentlyViewedEntry[],
): string {
  return JSON.stringify(entries);
}

/**
 * Records a visit: an already-seen product moves back to the front instead of
 * duplicating, and the list is trimmed to the cap.
 */
export function pushRecentlyViewed(
  entries: RecentlyViewedEntry[],
  product: Product,
  options: { now?: number; limit?: number } = {},
): RecentlyViewedEntry[] {
  const { now = Date.now(), limit = RECENTLY_VIEWED_LIMIT } = options;
  const id = String(product.id);

  const next: RecentlyViewedEntry[] = [
    { id, slug: product.slug, viewedAt: now, product },
    ...entries.filter((entry) => entry.id !== id),
  ];

  return next.slice(0, limit);
}
