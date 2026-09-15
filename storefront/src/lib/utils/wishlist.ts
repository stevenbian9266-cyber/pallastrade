import type { Product } from "@pallastrade/sdk";
import { isStoredEntry, parseStoredEntries } from "@/lib/utils/local-store";

/**
 * Wishlist V1 — browser-local (PRD-20260915-catalog-batch-c1-discovery §8.3).
 *
 * The plan keeps V1 free of a server-side domain model: signed-in cloud sync is
 * a later slice, so this module only owns the list arithmetic while components
 * own the storage access (`local-store.ts`).
 */
export const WISHLIST_KEY = "pt.wishlist";
export const WISHLIST_LIMIT = 100;
export const WISHLIST_EVENT = "pt:wishlist";

export interface WishlistEntry {
  /** Product id, stringified for stable comparisons. */
  id: string;
  slug: string;
  /** Epoch millis when the product was saved. */
  addedAt: number;
  product: Product;
}

function isEntry(value: unknown): value is WishlistEntry {
  return (
    isStoredEntry(value) &&
    typeof (value as { addedAt?: unknown }).addedAt === "number"
  );
}

/** Never throws: corrupt payloads degrade to an empty wishlist. */
export function parseWishlist(raw: string | null | undefined): WishlistEntry[] {
  return parseStoredEntries(raw, { isValid: isEntry, limit: WISHLIST_LIMIT });
}

export function serializeWishlist(entries: WishlistEntry[]): string {
  return JSON.stringify(entries);
}

export function isWishlisted(
  entries: WishlistEntry[],
  productId: string | number | null | undefined,
): boolean {
  if (productId == null) return false;
  const id = String(productId);
  return entries.some((entry) => entry.id === id);
}

/** Adds when missing, removes when present — returns the new list. */
export function toggleWishlistEntry(
  entries: WishlistEntry[],
  product: Product,
  options: { now?: number; limit?: number } = {},
): WishlistEntry[] {
  const { now = Date.now(), limit = WISHLIST_LIMIT } = options;
  const id = String(product.id);

  if (entries.some((entry) => entry.id === id)) {
    return entries.filter((entry) => entry.id !== id);
  }

  return [{ id, slug: product.slug, addedAt: now, product }, ...entries].slice(
    0,
    limit,
  );
}

export function removeWishlistEntry(
  entries: WishlistEntry[],
  productId: string | number | null | undefined,
): WishlistEntry[] {
  if (productId == null) return entries;
  const id = String(productId);
  return entries.filter((entry) => entry.id !== id);
}
