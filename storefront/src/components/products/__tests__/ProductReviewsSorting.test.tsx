import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ProductReviews, type ReviewView } from "../ProductReviews";

/**
 * PRD-20260916-catalog-batch-f4-review-sorting AC-007 / AC-010: the sorting
 * control exists, defaults to `newest`, and switching it refetches page 1 with
 * the new ordering while keeping the visible list when that refetch fails.
 */

const mockedLoadMore = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useLocale: () => "en",
}));

// F-5: the component reads the route to build its guest sign-in link.
vi.mock("next/navigation", () => ({
  useParams: () => ({ country: "us", locale: "en" }),
  usePathname: () => "/us/en/products/classic-t-shirt",
}));

vi.mock("@/lib/data/reviews", () => ({
  getMoreProductReviews: (...args: unknown[]) => mockedLoadMore(...args),
  createProductReview: vi.fn(),
  uploadReviewImage: vi.fn(),
  voteReviewHelpful: vi.fn(),
}));

function review(id: string): ReviewView {
  return {
    id,
    user_name: "Ada",
    rating: 5,
    title: "Great",
    body: "Loved it",
    verified_purchase: true,
    created_at: "2026-09-01T00:00:00Z",
    image_urls: [],
  };
}

const meta = {
  count: 2,
  page: 1,
  pages: 1,
  next: null,
  rating_distribution: { "5": 2, "4": 0, "3": 0, "2": 0, "1": 0 },
  sort: "newest",
};

function renderReviews() {
  return render(
    <ProductReviews
      productId="prod_1"
      reviews={[review("rev_1")]}
      meta={meta}
      averageRating={5}
      reviewCount={2}
      isAuthenticated={false}
    />,
  );
}

describe("ProductReviews sorting (F-4)", () => {
  beforeEach(() => {
    mockedLoadMore.mockReset();
  });

  it("renders the ordering control and defaults to newest (AC-010)", () => {
    renderReviews();

    const select = screen.getByLabelText("sortLabel");
    expect(select).toBeTruthy();
    expect((select as HTMLSelectElement).value).toBe("newest");
  });

  it("refetches page 1 with the selected ordering (AC-007)", async () => {
    mockedLoadMore.mockResolvedValue({
      reviews: [review("rev_9")],
      next: null,
    });
    renderReviews();

    fireEvent.change(screen.getByLabelText("sortLabel"), {
      target: { value: "lowest_rating" },
    });

    await waitFor(() =>
      expect(mockedLoadMore).toHaveBeenCalledWith(
        "prod_1",
        1,
        undefined,
        "lowest_rating",
      ),
    );
    expect(await screen.findByText("Great")).toBeTruthy();
  });

  it("keeps the current reviews when the refetch fails (AC-007)", async () => {
    mockedLoadMore.mockResolvedValue(null);
    renderReviews();

    fireEvent.change(screen.getByLabelText("sortLabel"), {
      target: { value: "highest_rating" },
    });

    await waitFor(() => expect(mockedLoadMore).toHaveBeenCalled());
    // The original review is still on screen — the list never collapses.
    expect(await screen.findByText("Great")).toBeTruthy();
  });
});
