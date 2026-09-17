"use server";

import { getClient } from "@/lib/pallastrade";

export interface CatalogEventPayload {
  event_id: string;
  event_name: "impression" | "click" | "product_added" | "product_searched";
  product_id?: string;
  variant_id?: string;
  list_id?: string;
  list_name?: string;
  position?: number;
  occurred_at?: string;
}

/**
 * Send a batch of storefront catalog events to the Store API
 * (`POST /api/v3/store/catalog_events`).
 *
 * Runs on the server because `PALLASTRADE_API_URL` / `PALLASTRADE_PUBLISHABLE_KEY`
 * are server-only env vars — a client component must call this action rather than
 * building an SDK client in the browser.
 *
 * ⚠️ **Returns `null` on failure, never `[]`** (AP-009b): analytics must never
 * break the storefront, and callers must be able to tell "the request failed"
 * apart from "there was nothing to send".
 *
 * The endpoint is idempotent per `event_id`, so a retried batch cannot double
 * count.
 */
export async function sendCatalogEvents(
  visitorId: string,
  events: CatalogEventPayload[],
): Promise<{ received: number } | null> {
  if (events.length === 0) {
    return { received: 0 };
  }

  try {
    return await getClient().catalogEvents.create({
      visitor_id: visitorId,
      events,
    });
  } catch {
    // Analytics is best-effort: swallow and let the caller drop the batch.
    return null;
  }
}
