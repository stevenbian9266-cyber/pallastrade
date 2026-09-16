"use client";

import { BadgeCheck, ImagePlus, Loader2, Star, X } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  createProductReview,
  getMoreProductReviews,
  uploadReviewImage,
} from "@/lib/data/reviews";

/** Photo types the API accepts (`PallasTrade::Review::ALLOWED_IMAGE_TYPES`). */
const ACCEPTED_IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];

/**
 * Client-side guards mirroring `PallasTrade::Review` (the API validates
 * again). They live here — not in `@/lib/data/reviews` — because a
 * `"use server"` module may only export async functions.
 */
const REVIEW_IMAGE_LIMIT = 3;
const REVIEW_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

export interface ReviewView {
  id: string;
  product_id?: string | null;
  user_name: string | null;
  rating: number;
  title: string | null;
  body: string | null;
  verified_purchase: boolean;
  created_at: string | null;
  /** F-1: photos of approved reviews only (absolute URLs). */
  image_urls?: string[];
}

export interface ReviewMeta {
  count: number;
  page: number;
  pages: number;
  next: number | null;
  rating_distribution: Record<string, number>;
  /** Catalog F-4: ordering the API applied to this page (optional so older
   *  payloads / fixtures without it still typecheck; the component then shows
   *  the default `newest`). */
  sort?: string;
}

interface ProductReviewsProps {
  productId: string;
  reviews: ReviewView[];
  averageRating: number | null;
  reviewCount: number;
  isAuthenticated: boolean;
  /** F-1: pagination + rating distribution from the Store API envelope. */
  meta?: ReviewMeta | null;
}

function Stars({
  rating,
  className = "size-4",
}: {
  rating: number;
  className?: string;
}) {
  return (
    <div
      className="flex items-center gap-0.5"
      role="img"
      aria-label={`${rating} / 5`}
    >
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          className={`${className} ${
            i <= Math.round(rating)
              ? "fill-amber-400 text-amber-400"
              : "fill-gray-200 text-gray-200"
          }`}
          aria-hidden="true"
        />
      ))}
    </div>
  );
}

function formatDate(iso: string | null, locale: string): string {
  if (!iso) return "";
  try {
    return new Intl.DateTimeFormat(locale === "zh-CN" ? "zh-CN" : "en", {
      year: "numeric",
      month: "short",
      day: "numeric",
    }).format(new Date(iso));
  } catch {
    return "";
  }
}

/**
 * Product reviews (P0-4) — rating summary + approved review list + a
 * submit form for signed-in customers. Reviews are approved by admins before
 * they become public, so a freshly submitted review won't appear immediately.
 */
export function ProductReviews({
  productId,
  reviews,
  averageRating,
  reviewCount,
  isAuthenticated,
  meta = null,
}: ProductReviewsProps) {
  const t = useTranslations("reviews");
  const locale = useLocale();

  const [rating, setRating] = useState(0);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [state, setState] = useState<"idle" | "loading" | "done">("idle");

  // F-1: photos upload before the review is submitted, so what the customer
  // sees is exactly what the API attaches (up to REVIEW_IMAGE_LIMIT).
  const [photos, setPhotos] = useState<{ signedId: string; name: string }[]>(
    [],
  );
  const [uploading, setUploading] = useState(false);

  // F-1: "load more" appends pages; the API drives the next page number.
  const [appended, setAppended] = useState<ReviewView[] | null>(null);
  const [nextPage, setNextPage] = useState<number | null>(meta?.next ?? null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreError, setMoreError] = useState(false);
  // Catalog F-4: ordering of the list. Switching it refetches the first page
  // so the new order is never merged with the pages already appended; a failed
  // refetch keeps what the customer is looking at (FR-006).
  const [sort, setSort] = useState<string>(meta?.sort ?? "newest");

  const changeSort = async (next: string) => {
    if (next === sort) return;

    setSort(next);
    setMoreError(false);

    const first = await getMoreProductReviews(productId, 1, undefined, next);
    if (!first) {
      setMoreError(true);
      return;
    }

    setAppended(first.reviews);
    setNextPage(first.next);
  };

  const visibleReviews = appended ?? reviews;
  const distribution = meta?.rating_distribution ?? null;
  const totalCount = meta?.count ?? reviewCount;
  const maxBucket = distribution
    ? Math.max(1, ...Object.values(distribution))
    : 1;

  const mapSubmitError = (code: string | undefined) =>
    code === "review_image_limit_exceeded"
      ? t("photoLimitReached", { count: REVIEW_IMAGE_LIMIT })
      : code === "review_image_not_owned" || code === "review_image_invalid"
        ? t("photoUploadFailed")
        : t("submitError");

  const handlePhotoPick = async (files: FileList | null) => {
    if (!files || files.length === 0) return;

    const remaining = REVIEW_IMAGE_LIMIT - photos.length;
    if (remaining <= 0) {
      setError(t("photoLimitReached", { count: REVIEW_IMAGE_LIMIT }));
      return;
    }

    const chosen = Array.from(files).slice(0, remaining);
    setError(
      files.length > remaining
        ? t("photoLimitReached", { count: REVIEW_IMAGE_LIMIT })
        : null,
    );

    setUploading(true);
    for (const file of chosen) {
      if (!ACCEPTED_IMAGE_TYPES.includes(file.type)) {
        setError(t("photoTypeInvalid"));
        continue;
      }
      if (file.size > REVIEW_IMAGE_MAX_BYTES) {
        setError(t("photoTooLarge"));
        continue;
      }
      const result = await uploadReviewImage(file);
      if (result.success) {
        setPhotos((current) => [
          ...current,
          { signedId: result.signedId, name: file.name },
        ]);
      } else {
        setError(mapSubmitError(result.code ?? result.error));
      }
    }
    setUploading(false);
  };

  const handleLoadMore = async () => {
    if (nextPage == null || loadingMore) return;
    setLoadingMore(true);
    setMoreError(false);
    const page = await getMoreProductReviews(
      productId,
      nextPage,
      undefined,
      sort,
    );
    if (page) {
      setAppended((current) => [...(current ?? reviews), ...page.reviews]);
      setNextPage(page.next);
    } else {
      // Keep what we already show; the button stays for a retry (AP-009b).
      setMoreError(true);
    }
    setLoadingMore(false);
  };

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (rating < 1) {
      setError(t("selectRating"));
      return;
    }
    setError(null);
    setState("loading");
    const result = await createProductReview(productId, {
      rating,
      title: title.trim() || undefined,
      body: body.trim() || undefined,
      images:
        photos.length > 0 ? photos.map((photo) => photo.signedId) : undefined,
    });
    if (result.success) {
      setState("done");
      setRating(0);
      setTitle("");
      setBody("");
      setPhotos([]);
    } else {
      setError(
        result.error === "authentication_required"
          ? t("signInRequired")
          : mapSubmitError(result.code),
      );
      setState("idle");
    }
  };

  const showSummary = averageRating != null && reviewCount > 0;

  return (
    <div className="mt-10 border-t pt-8">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-medium text-gray-900">{t("title")}</h2>
        {showSummary && (
          <div className="flex items-center gap-2">
            <span className="text-lg font-bold text-gray-900">
              {Number(averageRating).toFixed(1)}
            </span>
            <Stars rating={averageRating ?? 0} />
            <span className="text-sm text-gray-500">
              ({totalCount} {t("count")})
            </span>
          </div>
        )}
      </div>

      {/* Catalog F-4: ordering control — switching it refetches page 1. */}
      <div className="mt-4 flex items-center gap-2">
        <label htmlFor="review-sort" className="text-sm text-gray-600">
          {t("sortLabel")}
        </label>
        <select
          id="review-sort"
          value={sort}
          onChange={(event) => void changeSort(event.target.value)}
          className="rounded-md border border-gray-300 px-2 py-1 text-sm outline-none focus:border-gray-500"
          data-testid="review-sort"
        >
          <option value="newest">{t("sortNewest")}</option>
          <option value="highest_rating">{t("sortHighest")}</option>
          <option value="lowest_rating">{t("sortLowest")}</option>
        </select>
      </div>

      {/* F-1: rating distribution — same population as the average above */}
      {showSummary && distribution && (
        <ul
          className="mt-4 max-w-sm space-y-1"
          data-testid="rating-distribution"
          aria-label={t("ratingBreakdown")}
        >
          {[5, 4, 3, 2, 1].map((star) => {
            const count = distribution[String(star)] ?? 0;
            return (
              <li
                key={star}
                className="flex items-center gap-3 text-xs text-gray-600"
              >
                <span className="w-8 shrink-0 tabular-nums">{`${star} ★`}</span>
                <span
                  className="h-2 flex-1 overflow-hidden rounded-full bg-gray-100"
                  aria-hidden="true"
                >
                  <span
                    className="block h-full rounded-full bg-amber-400"
                    style={{
                      width: `${Math.round((count / maxBucket) * 100)}%`,
                    }}
                  />
                </span>
                <span className="w-6 shrink-0 text-right tabular-nums">
                  {count}
                </span>
              </li>
            );
          })}
        </ul>
      )}

      {visibleReviews.length > 0 ? (
        <ul className="mt-6 space-y-6">
          {visibleReviews.map((review) => (
            <li key={review.id} className="border-b pb-6 last:border-b-0">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-gray-900">
                    {review.user_name || t("anonymous")}
                  </span>
                  {review.verified_purchase && (
                    <span className="inline-flex items-center gap-1 text-xs text-green-600">
                      <BadgeCheck className="size-3.5" aria-hidden="true" />
                      {t("verifiedPurchase")}
                    </span>
                  )}
                </div>
                <span className="text-xs text-gray-400">
                  {formatDate(review.created_at, locale)}
                </span>
              </div>
              <div className="mt-1">
                <Stars rating={review.rating} className="size-3.5" />
              </div>
              {review.title && (
                <p className="mt-2 text-sm font-semibold text-gray-900">
                  {review.title}
                </p>
              )}
              {review.body && (
                <p className="mt-1 text-sm text-gray-600">{review.body}</p>
              )}
              {review.image_urls && review.image_urls.length > 0 && (
                <ul className="mt-3 flex flex-wrap gap-2">
                  {review.image_urls.map((url, index) => (
                    <li key={url}>
                      {/* biome-ignore lint/performance/noImgElement: remote storage URLs (same dynamic host as product media) */}
                      <img
                        src={url}
                        alt={`${t("reviewPhoto")} ${index + 1}`}
                        className="size-20 rounded-md border object-cover"
                        loading="lazy"
                      />
                    </li>
                  ))}
                </ul>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-4 text-sm text-gray-500">{t("empty")}</p>
      )}

      {/* F-1: "load more" appends the next page of approved reviews */}
      {nextPage != null && (
        <div className="mt-6">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={handleLoadMore}
            disabled={loadingMore}
          >
            {loadingMore ? (
              <>
                <Loader2 className="size-4 animate-spin" aria-hidden="true" />
                {t("loadingMore")}
              </>
            ) : (
              t("loadMore")
            )}
          </Button>
          {moreError && (
            <p role="alert" className="mt-2 text-sm text-red-600">
              {t("loadMoreError")}
            </p>
          )}
        </div>
      )}

      {/* Review form — signed-in customers only */}
      {isAuthenticated ? (
        <form
          onSubmit={handleSubmit}
          className="mt-8 rounded-lg border border-gray-200 p-4"
        >
          <h3 className="text-sm font-medium text-gray-900">
            {t("writeReview")}
          </h3>

          <div
            className="mt-3 flex items-center gap-1"
            role="radiogroup"
            aria-label={t("rating")}
          >
            {[1, 2, 3, 4, 5].map((i) => (
              <button
                key={i}
                type="button"
                onClick={() => setRating(i)}
                className="p-0.5"
                aria-label={`${i} ${t("stars")}`}
              >
                <Star
                  className={`size-6 ${
                    i <= rating
                      ? "fill-amber-400 text-amber-400"
                      : "fill-gray-200 text-gray-200"
                  }`}
                />
              </button>
            ))}
          </div>

          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={t("titlePlaceholder")}
            className="mt-3 w-full rounded-md border border-gray-300 px-3 py-2 text-sm outline-none focus:border-gray-500"
          />
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder={t("bodyPlaceholder")}
            rows={4}
            className="mt-3 w-full rounded-md border border-gray-300 px-3 py-2 text-sm outline-none focus:border-gray-500"
          />

          {/* F-1: up to REVIEW_IMAGE_LIMIT photos, uploaded before submit */}
          <div className="mt-3">
            <div className="flex items-center gap-2">
              <label
                htmlFor="review-photos"
                className="inline-flex cursor-pointer items-center gap-1 rounded-md border border-gray-300 px-3 py-1.5 text-xs text-gray-700 hover:bg-gray-50"
              >
                <ImagePlus className="size-3.5" aria-hidden="true" />
                {t("addPhotos")}
              </label>
              <input
                id="review-photos"
                type="file"
                accept={ACCEPTED_IMAGE_TYPES.join(",")}
                multiple
                className="sr-only"
                disabled={uploading || photos.length >= REVIEW_IMAGE_LIMIT}
                onChange={(event) => {
                  void handlePhotoPick(event.target.files);
                  event.target.value = "";
                }}
              />
              <span className="text-xs text-gray-500">
                {t("photoLimit", { count: REVIEW_IMAGE_LIMIT })}
              </span>
              {uploading && (
                <Loader2
                  className="size-4 animate-spin text-gray-400"
                  aria-hidden="true"
                />
              )}
            </div>

            {photos.length > 0 && (
              <ul className="mt-2 flex flex-wrap gap-2">
                {photos.map((photo) => (
                  <li
                    key={photo.signedId}
                    className="inline-flex items-center gap-1 rounded-md bg-gray-100 px-2 py-1 text-xs text-gray-700"
                  >
                    <span className="max-w-40 truncate">{photo.name}</span>
                    <button
                      type="button"
                      onClick={() =>
                        setPhotos((current) =>
                          current.filter(
                            (item) => item.signedId !== photo.signedId,
                          ),
                        )
                      }
                      aria-label={t("removePhoto")}
                      className="text-gray-500 hover:text-gray-700"
                    >
                      <X className="size-3.5" aria-hidden="true" />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {error && <p className="mt-2 text-sm text-red-600">{error}</p>}

          {state === "done" ? (
            <p role="status" className="mt-3 text-sm text-green-600">
              {t("success")}
            </p>
          ) : (
            <Button
              type="submit"
              size="sm"
              className="mt-4"
              disabled={state === "loading"}
            >
              {state === "loading" ? (
                <>
                  <Loader2 className="size-4 animate-spin" aria-hidden="true" />
                  {t("submitting")}
                </>
              ) : (
                t("submit")
              )}
            </Button>
          )}
        </form>
      ) : (
        <p className="mt-6 text-sm text-gray-500">{t("signInToReview")}</p>
      )}
    </div>
  );
}
