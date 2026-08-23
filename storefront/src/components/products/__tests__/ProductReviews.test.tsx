import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  ProductReviews,
  type ReviewView,
} from "@/components/products/ProductReviews";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
  useLocale: () => "en",
}));

vi.mock("@/lib/data/reviews", () => ({
  createProductReview: vi.fn(),
}));

import { createProductReview } from "@/lib/data/reviews";

const mockedCreate = vi.mocked(createProductReview);

const reviews: ReviewView[] = [
  {
    id: "rev_1",
    user_name: "Alice",
    rating: 5,
    title: "Love it",
    body: "Works great",
    verified_purchase: true,
    created_at: "2026-08-18T08:00:00Z",
  },
  {
    id: "rev_2",
    user_name: null,
    rating: 3,
    title: null,
    body: "Okay",
    verified_purchase: false,
    created_at: "2026-08-17T08:00:00Z",
  },
];

// # PRD-20260818-catalog-p0-4-产品评论
// AC-005：评分摘要 + 列表 + 表单；已购客户带 verified 徽标
describe("ProductReviews", () => {
  beforeEach(() => {
    mockedCreate.mockReset();
  });

  it("renders the rating summary and review list", () => {
    render(
      <ProductReviews
        productId="prod_1"
        reviews={reviews}
        averageRating={4}
        reviewCount={2}
        isAuthenticated={false}
      />,
    );
    expect(screen.getByText("4.0")).toBeTruthy();
    expect(screen.getByText("Alice")).toBeTruthy();
    expect(screen.getByText("Love it")).toBeTruthy();
    expect(screen.getByText("verifiedPurchase")).toBeTruthy();
    expect(screen.getByText("anonymous")).toBeTruthy();
    expect(screen.getByText("signInToReview")).toBeTruthy();
  });

  it("shows empty state when there are no reviews", () => {
    render(
      <ProductReviews
        productId="prod_1"
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={false}
      />,
    );
    expect(screen.getByText("empty")).toBeTruthy();
  });

  it("requires a star rating before submitting", async () => {
    const user = userEvent.setup();
    render(
      <ProductReviews
        productId="prod_1"
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={true}
      />,
    );
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(screen.getByText("selectRating")).toBeTruthy();
    expect(mockedCreate).not.toHaveBeenCalled();
  });

  it("submits a review and shows the success message", async () => {
    mockedCreate.mockResolvedValue({
      success: true,
      review: {
        id: "rev_new",
        product_id: "prod_1",
        user_name: null,
        rating: 5,
        title: "Great",
        body: "Really good",
        verified_purchase: false,
        created_at: "2026-08-23T08:00:00Z",
      },
    });
    const user = userEvent.setup();
    render(
      <ProductReviews
        productId="prod_1"
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={true}
      />,
    );
    await user.click(screen.getByRole("button", { name: "5 stars" }));
    await user.type(screen.getByPlaceholderText("titlePlaceholder"), "Great");
    await user.type(
      screen.getByPlaceholderText("bodyPlaceholder"),
      "Really good",
    );
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(mockedCreate).toHaveBeenCalledWith("prod_1", {
      rating: 5,
      title: "Great",
      body: "Really good",
    });
    expect(screen.getByText("success")).toBeTruthy();
    // AC-005: the freshly submitted review is echoed back with a pending badge
    expect(screen.getByText("Great")).toBeTruthy();
    expect(screen.getByText("Really good")).toBeTruthy();
    expect(screen.getByText("pending")).toBeTruthy();
  });

  it("echoes a freshly submitted review to the top of the list with a pending badge", async () => {
    mockedCreate.mockResolvedValue({
      success: true,
      review: {
        id: "rev_new",
        product_id: "prod_1",
        user_name: "Bob",
        rating: 4,
        title: "Nice",
        body: null,
        verified_purchase: false,
        created_at: "2026-08-23T09:00:00Z",
      },
    });
    const user = userEvent.setup();
    render(
      <ProductReviews
        productId="prod_1"
        reviews={reviews}
        averageRating={4}
        reviewCount={2}
        isAuthenticated={true}
      />,
    );
    await user.click(screen.getByRole("button", { name: "4 stars" }));
    await user.type(screen.getByPlaceholderText("titlePlaceholder"), "Nice");
    await user.click(screen.getByRole("button", { name: "submit" }));

    // New review (with pending badge) appears alongside approved ones
    expect(screen.getByText("Bob")).toBeTruthy();
    expect(screen.getByText("Nice")).toBeTruthy();
    expect(screen.getByText("pending")).toBeTruthy();
    expect(screen.getByText("Alice")).toBeTruthy();
  });

  it("shows an error when submission fails", async () => {
    mockedCreate.mockResolvedValue({ success: false, error: "submitError" });
    const user = userEvent.setup();
    render(
      <ProductReviews
        productId="prod_1"
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={true}
      />,
    );
    await user.click(screen.getByRole("button", { name: "3 stars" }));
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(screen.getByText("submitError")).toBeTruthy();
  });
});
