"use server";

import { getClient } from "@/lib/pallastrade";
import { actionResult } from "./utils";

/**
 * Subscribe an email to be notified when an out-of-stock product is back in
 * stock. Guest-accessible Store API endpoint; idempotent per (product, email).
 *
 * Runs on the server (env vars are server-only), so client components must call
 * this action instead of building an SDK client in the browser.
 */
export async function createBackInStockSubscription(
  productId: string,
  email: string,
): Promise<{ success: true } | { success: false; error: string }> {
  return actionResult(async () => {
    await getClient().backInStockSubscriptions.create(productId, { email });
    return {};
  }, "Failed to subscribe. Please try again.");
}
