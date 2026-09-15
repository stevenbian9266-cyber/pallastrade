/**
 * Browser-storage access for the local-first discovery features
 * (PRD-20260915-catalog-batch-c1-discovery FR-005/FR-006).
 *
 * Every helper swallows failures on purpose: Safari private mode and exhausted
 * quotas both throw on `localStorage`, and a storefront must degrade silently
 * instead of breaking the page or the render.
 */

export function readLocalValue(key: string): string | null {
  if (typeof window === "undefined") return null;

  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

export function writeLocalValue(key: string, value: string): void {
  if (typeof window === "undefined") return;

  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Storage unavailable (private mode / quota) — the feature degrades to
    // "not persisted" rather than surfacing an error to the shopper.
  }
}

/** Notifies same-page listeners; the `storage` event only fires cross-tab. */
export function dispatchLocalEvent(name: string): void {
  if (typeof window === "undefined") return;

  try {
    window.dispatchEvent(new Event(name));
  } catch {
    // Event dispatch is best-effort.
  }
}

/**
 * Shared reader for the list-shaped local features (recently viewed, wishlist):
 * JSON → validated entries → capped, and "nothing usable" for anything corrupt
 * or foreign instead of an exception.
 */
export function parseStoredEntries<T>(
  raw: string | null | undefined,
  options: { isValid: (value: unknown) => value is T; limit: number },
): T[] {
  if (!raw) return [];

  try {
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];

    return parsed.filter(options.isValid).slice(0, options.limit);
  } catch {
    return [];
  }
}

/** Shape every list-shaped local feature stores: a product reference + slug. */
export interface StoredEntryShape {
  id: string;
  slug: string;
  product: unknown;
}

/** Guards the shared shape; each feature narrows its own timestamp on top. */
export function isStoredEntry(value: unknown): value is StoredEntryShape {
  if (typeof value !== "object" || value === null) return false;

  const candidate = value as Partial<StoredEntryShape>;
  return (
    candidate.id != null &&
    typeof candidate.slug === "string" &&
    typeof candidate.product === "object" &&
    candidate.product !== null
  );
}
