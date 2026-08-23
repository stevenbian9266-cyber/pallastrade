"use client";

import { BadgeCheck, Loader2, Star } from "lucide-react";
import { useLocale, useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { createProductReview } from "@/lib/data/reviews";

export interface ReviewView {
  id: string;
  user_name: string | null;
  rating: number;
  title: string | null;
  body: string | null;
  verified_purchase: boolean;
  created_at: string | null;
  /** Freshly submitted review awaiting admin approval — echoed back to the list. */
  is_pending?: boolean;
}

interface ProductReviewsProps {
  productId: string;
  reviews: ReviewView[];
  averageRating: number | null;
  reviewCount: number;
  isAuthenticated: boolean;
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
}: ProductReviewsProps) {
  const t = useTranslations("reviews");
  const locale = useLocale();

  const [rating, setRating] = useState(0);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [state, setState] = useState<"idle" | "loading" | "done">("idle");
  // Freshly submitted reviews (status=pending) echoed at the top of the list
  // until an admin approves them and they start returning from the Store API.
  const [pendingReviews, setPendingReviews] = useState<ReviewView[]>([]);

  const allReviews = [...pendingReviews, ...reviews];

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
    });
    if (result.success) {
      setState("done");
      setRating(0);
      setTitle("");
      setBody("");
      setPendingReviews((prev) => [
        {
          id: result.review.id,
          user_name: result.review.user_name,
          rating: result.review.rating,
          title: result.review.title,
          body: result.review.body,
          verified_purchase: result.review.verified_purchase,
          created_at: result.review.created_at,
          is_pending: true,
        },
        ...prev,
      ]);
    } else {
      setError(
        result.error === "authentication_required"
          ? t("signInRequired")
          : t("submitError"),
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
              {averageRating?.toFixed(1)}
            </span>
            <Stars rating={averageRating ?? 0} />
            <span className="text-sm text-gray-500">
              ({reviewCount} {t("count")})
            </span>
          </div>
        )}
      </div>

      {allReviews.length > 0 ? (
        <ul className="mt-6 space-y-6">
          {allReviews.map((review) => (
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
                  {review.is_pending && (
                    <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-xs text-amber-700">
                      {t("pending")}
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
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-4 text-sm text-gray-500">{t("empty")}</p>
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
