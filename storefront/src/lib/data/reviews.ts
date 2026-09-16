"use server";

import { createHash } from "node:crypto";
import { getAccessToken, getClient, isJwtExpired } from "@/lib/pallastrade";
import { actionResult, withFallback } from "./utils";

/**
 * Review shape handed to `ProductReviews`. `image_urls` carries only approved
 * reviews' photos — the API never exposes pending ones.
 */
export interface ProductReview {
  id: string;
  product_id: string | null;
  user_name: string | null;
  rating: number;
  title: string | null;
  body: string | null;
  verified_purchase: boolean;
  created_at: string | null;
  image_urls: string[];
}

export interface ProductReviewList {
  reviews: ProductReview[];
  /** `null` when the API call failed — the UI then renders the empty state. */
  meta: {
    count: number;
    page: number;
    pages: number;
    next: number | null;
    rating_distribution: Record<string, number>;
  } | null;
}

const EMPTY_REVIEW_LIST: ProductReviewList = { reviews: [], meta: null };

/** Mirrors `PallasTrade::Review::MAX_IMAGES` for a fast client-side guard. */
export const REVIEW_IMAGE_LIMIT = 3;

/** Mirrors `PallasTrade::Review::MAX_IMAGE_BYTES` (5 MB). */
export const REVIEW_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

/**
 * First page of approved reviews (F-1). The API answers with the v3 envelope,
 * so the rating distribution arrives on `meta.rating_distribution`.
 */
export async function getProductReviews(
  productId: string,
  params: { page?: number; limit?: number } = {},
): Promise<ProductReviewList> {
  return withFallback(async () => {
    const response = await getClient().products.reviews.list(productId, params);
    return { reviews: response.data, meta: response.meta };
  }, EMPTY_REVIEW_LIST);
}

/**
 * "Load more" (F-1): one more page of approved reviews for a product.
 * Returns `null` on failure so the caller keeps the reviews it already has
 * instead of collapsing the list to empty (AP-009b).
 */
export async function getMoreProductReviews(
  productId: string,
  page: number,
  limit?: number,
): Promise<{ reviews: ProductReview[]; next: number | null } | null> {
  try {
    const response = await getClient().products.reviews.list(productId, {
      page,
      limit,
    });
    return { reviews: response.data, next: response.meta.next };
  } catch (error) {
    console.error(error);
    return null;
  }
}

/**
 * Submit a review as the signed-in customer. Requires a live JWT; the API
 * returns 401 otherwise. `images` are signed ids from `uploadReviewImage`.
 */
export async function createProductReview(
  productId: string,
  params: { rating: number; title?: string; body?: string; images?: string[] },
): Promise<
  { success: true } | { success: false; error: string; code?: string }
> {
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

/**
 * Upload one review photo (F-1): presign through the Store API, PUT the bytes
 * to the storage service, hand the `signed_id` back to `createProductReview`.
 * Runs server-side, so the browser never talks to the storage service directly.
 */
export async function uploadReviewImage(
  file: File,
): Promise<
  | { success: true; signedId: string }
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const token = await getAccessToken();
    if (!token || isJwtExpired(token, 30)) {
      throw new Error("authentication_required");
    }
    if (file.size > REVIEW_IMAGE_MAX_BYTES) {
      throw new Error("review_image_too_large");
    }

    const bytes = await file.arrayBuffer();
    const checksum = createHash("md5")
      .update(Buffer.from(bytes))
      .digest("base64");

    const presign = await getClient().directUploads.create(
      {
        filename: file.name,
        byte_size: file.size,
        checksum,
        content_type: file.type || undefined,
      },
      { token },
    );

    const upload = await fetch(presign.direct_upload.url, {
      method: "PUT",
      headers: presign.direct_upload.headers,
      body: bytes,
    });
    if (!upload.ok) {
      throw new Error("review_image_upload_failed");
    }

    return { signedId: presign.signed_id };
  }, "Failed to upload photo. Please try again.");
}
