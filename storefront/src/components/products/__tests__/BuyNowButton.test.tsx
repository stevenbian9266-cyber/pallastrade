import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { BuyNowButton } from "@/components/products/BuyNowButton";

const pushMock = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock }),
  usePathname: () => "/us/en/products/my-product",
}));

vi.mock("@/lib/data/buy-now", () => ({
  createBuyNowCart: vi.fn(),
}));

import { createBuyNowCart } from "@/lib/data/buy-now";

const mockedBuyNow = vi.mocked(createBuyNowCart);

describe("BuyNowButton", () => {
  beforeEach(() => {
    pushMock.mockReset();
    mockedBuyNow.mockReset();
  });

  it("renders and starts a buy-now checkout on click (P5 AC-008)", async () => {
    const user = userEvent.setup();
    mockedBuyNow.mockResolvedValue({ cart: { id: "cart_1" } } as never);

    render(<BuyNowButton variantId="variant_1" quantity={1} />);

    await user.click(screen.getByRole("button", { name: "buyNow" }));

    expect(mockedBuyNow).toHaveBeenCalledWith("variant_1", 1);
    // 下单链路统一化（PRD-20260830-checkout）：Buy Now → 统一下单页
    expect(pushMock).toHaveBeenCalledWith("/us/en/checkout/cart_1");
  });

  it("is disabled without a variant (P5 AC-008)", () => {
    render(<BuyNowButton variantId="" quantity={1} />);
    expect(screen.getByRole("button", { name: "buyNow" })).toBeDisabled();
  });
});
