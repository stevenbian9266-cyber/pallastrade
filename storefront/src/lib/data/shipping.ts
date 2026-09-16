"use server";

import type { ShippingEstimate } from "@pallastrade/sdk";
import { getClient } from "@/lib/pallastrade";

/**
 * Catalog F-2 (PRD-20260916-catalog-batch-f2-stock-shipping): the PDP shipping
 * block's data.
 *
 * Advisory only — the authoritative delivery cost is computed when the order is
 * submitted. Returns `null` (not an empty estimate) when the call fails, so the
 * PDP can tell "unknown" apart from "no delivery options" and simply omit the
 * block instead of claiming shipping is unavailable.
 */
export async function getShippingEstimate(
  productId: string,
  country?: string,
): Promise<ShippingEstimate | null> {
  try {
    return await getClient().shippingEstimate.get({
      product_id: productId,
      country,
    });
  } catch {
    return null;
  }
}
