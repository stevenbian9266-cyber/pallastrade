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
  /** F-5: public vote count (counter cache on the API side). */
  helpful_votes_count?: number;
  /**
   * F-5: the caller's own vote. `true`/`false` for a signed-in customer,
   * `null` for guests (the API answers "not asked" instead of guessing).
   */
  helpful_voted?: boolean | null;
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
    /** Catalog F-4: the ordering the API actually applied. */
    sort: string;
  } | null;
}

const EMPTY_REVIEW_LIST: ProductReviewList = { reviews: [], meta: null };

// NOTE: a "use server" module may only export async functions, so the
// client-side image guards (limit / max bytes) live in `ProductReviews.tsx`.
/** Mirrors `PallasTrade::Review::MAX_IMAGE_BYTES` (5 MB) for the pre-flight. */
const REVIEW_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

/**
 * First page of approved reviews (F-1). The API answers with the v3 envelope,
 * so the rating distribution arrives on `meta.rating_distribution`.
 */
export async function getProductReviews(
  productId: string,
  params: { page?: number; limit?: number; sort?: string } = {},
): Promise<ProductReviewList> {
  // Explicit type argument: the SDK types `meta` as always-present, while this
  // module models a failed call as `meta: null` (the UI then renders the empty
  // state) — without it the fallback would not typecheck against the value.
  return withFallback<ProductReviewList>(async () => {
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
  sort?: string,
): Promise<{ reviews: ProductReview[]; next: number | null } | null> {
  try {
    const response = await getClient().products.reviews.list(productId, {
      page,
      limit,
      sort,
    });
    return { reviews: response.data, next: response.meta.next };
  } catch (error) {
    console.error(error);
    return null;
  }
}

/**
 * Vote (or take the vote back) on an approved review as the signed-in customer
 * (F-5). Requires a live JWT; the API answers with the **authoritative state**
 * (count + this caller's own vote), so the button never has to guess whether
 * the click landed. Voting is refused on your own review (`own_review_vote_
 * forbidden`) and reviews the caller cannot see answer 404.
 */
export async function voteReviewHelpful(
  reviewId: string,
  voted: boolean,
): Promise<
  | { success: true; helpfulVotesCount: number; helpfulVoted: boolean }
  | { success: false; error: string; code?: string }
> {
  return actionResult(async () => {
    const token = await getAccessToken();
    if (!token || isJwtExpired(token, 30)) {
      throw new Error("authentication_required");
    }

    const client = getClient();
    const response = voted
      ? await client.reviewHelpfulVotes.destroy(reviewId, { token })
      : await client.reviewHelpfulVotes.create(reviewId, { token });

    return {
      helpfulVotesCount: response.data.attributes.helpful_votes_count,
      helpfulVoted: response.data.attributes.helpful_voted,
    };
  }, "Failed to record your vote. Please try again.");
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
