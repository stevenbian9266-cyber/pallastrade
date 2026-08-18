"use server";

import { getAccessToken, getClient, isJwtExpired } from "@/lib/pallastrade";
import { actionResult, withFallback } from "./utils";

/**
 * List approved reviews for a product (public Store API).
 */
export async function getProductReviews(productId: string): Promise<
  Array<{
    id: string;
    product_id: string | null;
    user_name: string | null;
    rating: number;
    title: string | null;
    body: string | null;
    verified_purchase: boolean;
    created_at: string | null;
  }>
> {
  return withFallback(
    async () => getClient().products.reviews.list(productId),
    [],
  );
}

/**
 * Submit a review as the signed-in customer. Requires a live JWT; the API
 * returns 401 otherwise.
 */
export async function createProductReview(
  productId: string,
  params: { rating: number; title?: string; body?: string },
): Promise<{ success: true } | { success: false; error: string }> {
  return actionResult(async () => {
    const token = await getAccessToken();
    if (!token || isJwtExpired(token, 30)) {
      throw new Error("authentication_required");
    }
    await getClient().products.reviews.create(productId, params, {
      token,
    });
    return {};
  }, "Failed to submit review. Please try again.");
}
