import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * PRD-20260916-catalog-batch-f1-reviews AC-005 / AC-006: rating distribution,
 * Load-more paging and the photo picker (limit, removal, error mapping).
 */
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
  getMoreProductReviews: vi.fn(),
  uploadReviewImage: vi.fn(),
  REVIEW_IMAGE_LIMIT: 3,
  REVIEW_IMAGE_MAX_BYTES: 5 * 1024 * 1024,
}));

import {
  createProductReview,
  getMoreProductReviews,
  uploadReviewImage,
} from "@/lib/data/reviews";

const mockedCreate = vi.mocked(createProductReview);
const mockedLoadMore = vi.mocked(getMoreProductReviews);
const mockedUpload = vi.mocked(uploadReviewImage);

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
    mockedCreate.mockResolvedValue({ success: true });
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
    await user.click(screen.getByRole("button", { name: "submit" }));
    expect(mockedCreate).toHaveBeenCalledWith("prod_1", {
      rating: 5,
      title: "Great",
      body: undefined,
      images: undefined,
    });
    expect(screen.getByText("success")).toBeTruthy();
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

// # PRD-20260916-catalog-batch-f1-reviews
// AC-005：评分分布（与评分同源）＋列表；AC-006：评论图片展示；AC-009：分页 Load more
describe("ProductReviews — F-1", () => {
  const meta = {
    count: 14,
    page: 1,
    pages: 2,
    next: 2,
    rating_distribution: { "5": 8, "4": 3, "3": 2, "2": 1, "1": 0 },
  };

  const baseProps = {
    productId: "prod_1",
    averageRating: 4,
    reviewCount: 14,
    isAuthenticated: false,
  };

  beforeEach(() => {
    mockedCreate.mockReset();
    mockedLoadMore.mockReset();
    mockedUpload.mockReset();
  });

  it("renders the rating distribution from meta", () => {
    render(<ProductReviews {...baseProps} reviews={reviews} meta={meta} />);
    const list = screen.getByTestId("rating-distribution");
    // 5★ bucket reads the same numbers the API reported.
    expect(list.textContent).toContain("8");
    expect(list.textContent).toContain("1 ★");
  });

  it("omits the distribution when meta is missing", () => {
    render(<ProductReviews {...baseProps} reviews={reviews} />);
    expect(screen.queryByTestId("rating-distribution")).toBeNull();
  });

  it("updates the header count from meta", () => {
    render(<ProductReviews {...baseProps} reviews={reviews} meta={meta} />);
    expect(screen.getByText(/14 count/)).toBeTruthy();
  });

  it("appends the next page and hides the button on the last page", async () => {
    const user = userEvent.setup();
    mockedLoadMore.mockResolvedValue({
      reviews: [
        {
          id: "rev_3",
          product_id: "prod_1",
          user_name: "Bob",
          rating: 4,
          title: null,
          body: "Solid",
          verified_purchase: false,
          created_at: "2026-08-16T08:00:00Z",
          image_urls: [],
        },
      ],
      next: null,
    });

    render(<ProductReviews {...baseProps} reviews={reviews} meta={meta} />);
    await user.click(screen.getByRole("button", { name: "loadMore" }));

    expect(mockedLoadMore).toHaveBeenCalledWith(
      "prod_1",
      2,
      undefined,
      "newest",
    );
    expect(await screen.findByText("Bob")).toBeTruthy();
    // Existing reviews stay, and the last page no longer offers "load more".
    expect(screen.getByText("Alice")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "loadMore" })).toBeNull();
  });

  it("keeps the loaded reviews and stays retryable when a page fails", async () => {
    const user = userEvent.setup();
    mockedLoadMore.mockResolvedValue(null);

    render(<ProductReviews {...baseProps} reviews={reviews} meta={meta} />);
    await user.click(screen.getByRole("button", { name: "loadMore" }));

    expect(screen.getByText("loadMoreError")).toBeTruthy();
    expect(screen.getByText("Alice")).toBeTruthy();
    expect(screen.getByRole("button", { name: "loadMore" })).toBeTruthy();
  });

  it("renders review photos with accessible alt text", () => {
    const withPhotos = [
      {
        ...reviews[0],
        image_urls: [
          "https://cdn.test/a.jpg",
          "https://cdn.test/b.jpg",
          "https://cdn.test/c.jpg",
        ],
      },
    ];
    render(
      <ProductReviews
        {...baseProps}
        reviews={withPhotos}
        averageRating={5}
        reviewCount={1}
      />,
    );
    expect(screen.getAllByRole("img", { name: /reviewPhoto/ })).toHaveLength(3);
  });

  it("submits the signed ids of uploaded photos", async () => {
    mockedUpload.mockResolvedValue({ success: true, signedId: "signed_1" });
    mockedCreate.mockResolvedValue({ success: true });
    const user = userEvent.setup();

    render(
      <ProductReviews
        {...baseProps}
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={true}
      />,
    );
    await user.click(screen.getByRole("button", { name: "5 stars" }));
    await user.upload(
      screen.getByLabelText("addPhotos"),
      new File(["x"], "photo.jpg", { type: "image/jpeg" }),
    );
    await user.click(screen.getByRole("button", { name: "submit" }));

    expect(mockedUpload).toHaveBeenCalledTimes(1);
    expect(mockedCreate).toHaveBeenCalledWith("prod_1", {
      rating: 5,
      title: undefined,
      body: undefined,
      images: ["signed_1"],
    });
  });

  it("rejects unsupported photo types before uploading", async () => {
    render(
      <ProductReviews
        {...baseProps}
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={true}
      />,
    );
    // `fireEvent.change` bypasses the `accept` filter user-event applies.
    fireEvent.change(screen.getByLabelText("addPhotos"), {
      target: { files: [new File(["x"], "photo.gif", { type: "image/gif" })] },
    });

    expect(await screen.findByText("photoTypeInvalid")).toBeTruthy();
    expect(mockedUpload).not.toHaveBeenCalled();
  });

  it("maps the API photo-limit error to the localized message", async () => {
    mockedCreate.mockResolvedValue({
      success: false,
      error: "review photos rejected",
      code: "review_image_limit_exceeded",
    });
    const user = userEvent.setup();
    render(
      <ProductReviews
        {...baseProps}
        reviews={[]}
        averageRating={null}
        reviewCount={0}
        isAuthenticated={true}
      />,
    );
    await user.click(screen.getByRole("button", { name: "4 stars" }));
    await user.click(screen.getByRole("button", { name: "submit" }));

    expect(screen.getByText("photoLimitReached")).toBeTruthy();
  });
});
