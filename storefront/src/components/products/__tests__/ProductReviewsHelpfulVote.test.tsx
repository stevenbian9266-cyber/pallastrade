import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ProductReviews, type ReviewView } from "../ProductReviews";

/**
 * PRD-20260916-catalog-batch-f5-helpful-vote AC-011: the vote control shows the
 * public count, reflects the caller's own vote, takes it back on a second
 * click, sends guests to sign-in, and keeps the previous state when the API
 * call fails (AP-009b — a failed vote must never look like a state change).
 */

const mockedVote = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useLocale: () => "en",
}));

vi.mock("next/navigation", () => ({
  useParams: () => ({ country: "us", locale: "en" }),
  usePathname: () => "/us/en/products/classic-t-shirt",
}));

vi.mock("@/lib/data/reviews", () => ({
  getMoreProductReviews: vi.fn(),
  createProductReview: vi.fn(),
  uploadReviewImage: vi.fn(),
  voteReviewHelpful: (...args: unknown[]) => mockedVote(...args),
}));

function review(overrides: Partial<ReviewView> = {}): ReviewView {
  return {
    id: "rev_1",
    user_name: "Ada",
    rating: 5,
    title: "Great",
    body: "Loved it",
    verified_purchase: true,
    created_at: "2026-09-01T00:00:00Z",
    image_urls: [],
    helpful_votes_count: 0,
    helpful_voted: false,
    ...overrides,
  };
}

const meta = {
  count: 1,
  page: 1,
  pages: 1,
  next: null,
  rating_distribution: { "5": 1, "4": 0, "3": 0, "2": 0, "1": 0 },
  sort: "newest",
};

function renderReviews({
  item = review(),
  isAuthenticated = true,
}: { item?: ReviewView; isAuthenticated?: boolean } = {}) {
  return render(
    <ProductReviews
      productId="prod_1"
      reviews={[item]}
      meta={meta}
      averageRating={5}
      reviewCount={1}
      isAuthenticated={isAuthenticated}
    />,
  );
}

describe("ProductReviews helpful vote (F-5)", () => {
  beforeEach(() => {
    mockedVote.mockReset();
  });

  it("shows the public count that came with the list", () => {
    renderReviews({ item: review({ helpful_votes_count: 4 }) });

    expect(
      screen.getByTestId("review-helpful-count-rev_1").getAttribute("data-count"),
    ).toBe("4");
  });

  it("records a vote and switches to the caller's own state", async () => {
    mockedVote.mockResolvedValue({
      success: true,
      helpfulVotesCount: 5,
      helpfulVoted: true,
    });
    renderReviews({ item: review({ helpful_votes_count: 4 }) });

    fireEvent.click(screen.getByTestId("review-helpful-rev_1"));

    // `voted: false` leaving the button means "cast a vote".
    await waitFor(() => expect(mockedVote).toHaveBeenCalledWith("rev_1", false));
    await waitFor(() =>
      expect(
        screen.getByTestId("review-helpful-rev_1").textContent,
      ).toContain("helpfulVoted"),
    );
    expect(
      screen.getByTestId("review-helpful-count-rev_1").getAttribute("data-count"),
    ).toBe("5");
  });

  it("takes the vote back when the caller had already voted", async () => {
    mockedVote.mockResolvedValue({
      success: true,
      helpfulVotesCount: 0,
      helpfulVoted: false,
    });
    renderReviews({
      item: review({ helpful_votes_count: 1, helpful_voted: true }),
    });

    fireEvent.click(screen.getByTestId("review-helpful-rev_1"));

    await waitFor(() => expect(mockedVote).toHaveBeenCalledWith("rev_1", true));
    await waitFor(() =>
      expect(
        screen.getByTestId("review-helpful-rev_1").textContent,
      ).toContain("helpful"),
    );
  });

  it("keeps the previous state when the vote fails", async () => {
    mockedVote.mockResolvedValue({ success: false, error: "boom" });
    renderReviews({ item: review({ helpful_votes_count: 3 }) });

    fireEvent.click(screen.getByTestId("review-helpful-rev_1"));

    await waitFor(() => expect(screen.getByText("helpfulFailed")).toBeTruthy());
    expect(
      screen.getByTestId("review-helpful-count-rev_1").getAttribute("data-count"),
    ).toBe("3");
    expect(
      screen.getByTestId("review-helpful-rev_1").textContent,
    ).not.toContain("helpfulVoted");
  });

  it("explains the refusal when the review is the caller's own", async () => {
    mockedVote.mockResolvedValue({
      success: false,
      error: "own",
      code: "own_review_vote_forbidden",
    });
    renderReviews();

    fireEvent.click(screen.getByTestId("review-helpful-rev_1"));

    await waitFor(() => expect(screen.getByText("helpfulOwnReview")).toBeTruthy());
  });

  it("sends guests to sign-in instead of offering a vote button", () => {
    renderReviews({ isAuthenticated: false });

    expect(screen.queryByTestId("review-helpful-rev_1")).toBeNull();
    const link = screen.getByTestId("review-helpful-signin-rev_1");
    // Back to this PDP after signing in.
    expect(link.getAttribute("href")).toContain("us/en");
    expect(link.getAttribute("href")).toContain("redirect");
  });
});
