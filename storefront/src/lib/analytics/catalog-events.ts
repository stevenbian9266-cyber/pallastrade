import { sendCatalogEvents } from "@/lib/data/catalog-events";

/**
 * Side-channel product analytics (PRD-20260917-catalog-product-events).
 *
 * Mirrors the existing GA4 calls in `gtm.ts` into the store's **own** database so
 * `Related Product CTR` can be computed from first-party data. The GA4/GTM path
 * is untouched — this is an additional sink, not a replacement.
 *
 * ## Why batching is mandatory, not an optimisation
 *
 * `PallasTrade::Api::V3::BaseController` declares a global `rate_limit` of
 * **300 requests / 60s** and its counter is keyed by **API key**. A storefront
 * serves every visitor with a single publishable key, so that budget is shared by
 * the whole store — and the limit cannot be skipped by a subclass (the Rails
 * callback is an anonymous lambda). Therefore the request count must scale with
 * **page navigations**, not with events:
 *
 * - events accumulate in a queue for the lifetime of a page view;
 * - the queue is flushed **once** when the page is hidden or unloaded
 *   (`visibilitychange` → `hidden`, `pagehide`);
 * - an overflow flush kicks in only if a single page view somehow produces more
 *   than `CATALOG_EVENT_MAX_BATCH` events.
 *
 * A failed flush is dropped — never retried — because analytics must not compete
 * with real user traffic for the rate-limit budget.
 */

export type CatalogEventName =
  | "impression"
  | "click"
  | "product_added"
  | "product_searched";

export interface CatalogEventInput {
  event_id: string;
  event_name: CatalogEventName;
  product_id?: string;
  variant_id?: string;
  list_id?: string;
  list_name?: string;
  position?: number;
  occurred_at?: string;
}

/** Must match `PallasTrade::CatalogEvent::MAX_BATCH_SIZE` on the backend. */
export const CATALOG_EVENT_MAX_BATCH = 100;

/** Storage key holding the random, non-identifying visitor id. */
export const CATALOG_VISITOR_STORAGE_KEY = "pallastrade_visitor_id";

export interface CatalogEventQueue {
  /** Queue one event; may trigger an overflow flush. */
  track: (event: CatalogEventInput) => void;
  /** Send everything queued so far as a single request. Safe to call repeatedly. */
  flush: () => Promise<void>;
  /** Number of events still queued. */
  pending: () => number;
}

export interface CatalogEventQueueOptions {
  send: (
    visitorId: string,
    events: CatalogEventInput[],
  ) => Promise<{ received: number } | null>;
  visitorId: string;
  maxBatch?: number;
}

/**
 * Build a queue that drains itself in as few requests as possible: each flush
 * takes the whole backlog and sends it as one batch.
 */
export function createCatalogEventQueue(
  options: CatalogEventQueueOptions,
): CatalogEventQueue {
  const { send, visitorId, maxBatch = CATALOG_EVENT_MAX_BATCH } = options;

  let queue: CatalogEventInput[] = [];
  let inFlight = false;

  const flush = async (): Promise<void> => {
    if (inFlight || queue.length === 0) return;

    const batch = queue;
    queue = [];
    inFlight = true;

    try {
      await send(visitorId, batch);
    } catch {
      // Best-effort: a dropped batch is preferable to retrying into a shared
      // rate-limit budget.
    } finally {
      inFlight = false;
    }

    // Anything queued while the request was in flight goes out immediately.
    if (queue.length > 0) {
      await flush();
    }
  };

  const track = (event: CatalogEventInput): void => {
    queue.push(event);

    if (queue.length >= maxBatch) {
      void flush();
    }
  };

  const pending = (): number => queue.length;

  return { track, flush, pending };
}

/** A random, non-identifying event id (the backend's idempotency key). */
export function createCatalogEventId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  }
}

/** A random, non-identifying visitor id — never derived from the user. */
export function getOrCreateVisitorId(): string {
  try {
    const existing = window.localStorage.getItem(CATALOG_VISITOR_STORAGE_KEY);
    if (existing) return existing;

    const created = createCatalogEventId();
    window.localStorage.setItem(CATALOG_VISITOR_STORAGE_KEY, created);
    return created;
  } catch {
    // Private mode / storage disabled: still report, just without continuity.
    return createCatalogEventId();
  }
}

let sharedQueue: CatalogEventQueue | null = null;

/**
 * The browser-wide queue. Created lazily and wired to the page-lifecycle events
 * so a page view results in at most one report.
 */
export function getCatalogEventQueue(): CatalogEventQueue {
  if (sharedQueue) return sharedQueue;

  sharedQueue = createCatalogEventQueue({
    send: sendCatalogEvents,
    visitorId: getOrCreateVisitorId(),
  });

  if (typeof document !== "undefined") {
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") {
        void sharedQueue?.flush();
      }
    });
  }

  if (typeof window !== "undefined") {
    window.addEventListener("pagehide", () => {
      void sharedQueue?.flush();
    });
  }

  return sharedQueue;
}

function track(
  event: Omit<CatalogEventInput, "event_id" | "occurred_at">,
): void {
  getCatalogEventQueue().track({
    ...event,
    event_id: createCatalogEventId(),
    occurred_at: new Date().toISOString(),
  });
}

/** One product shown inside a recommendation surface (the CTR denominator). */
export function trackCatalogImpression(
  productId: string,
  listId: string,
  listName: string,
  position: number,
  variantId?: string,
): void {
  track({
    event_name: "impression",
    product_id: productId,
    variant_id: variantId,
    list_id: listId,
    list_name: listName,
    position,
  });
}

/** A product clicked from a recommendation surface (the CTR numerator). */
export function trackCatalogClick(
  productId: string,
  listId: string,
  listName: string,
  position: number,
  variantId?: string,
): void {
  track({
    event_name: "click",
    product_id: productId,
    variant_id: variantId,
    list_id: listId,
    list_name: listName,
    position,
  });
}

/** A product added to the cart. */
export function trackCatalogProductAdded(
  productId: string,
  variantId?: string,
): void {
  track({
    event_name: "product_added",
    product_id: productId,
    variant_id: variantId,
  });
}

/** A search performed from the storefront. No search term is stored (zero PII). */
export function trackCatalogProductSearched(productId?: string): void {
  track({ event_name: "product_searched", product_id: productId });
}
