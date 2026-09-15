import type { ShoppingCart } from "@pallastrade/sdk";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { CartCreditsPanel } from "@/components/cart/CartCreditsPanel";
import { CartCreditsSummary } from "@/components/cart/CartCreditsSummary";

const applyDiscountCodeMock = vi.fn();
const applyGiftCardMock = vi.fn();
const applyStoreCreditMock = vi.fn();
const removeDiscountCodeMock = vi.fn();
const removeGiftCardMock = vi.fn();
const removeStoreCreditMock = vi.fn();

vi.mock("@/lib/data/shopping-cart", () => ({
  applyDiscountCode: (...args: unknown[]) => applyDiscountCodeMock(...args),
  applyGiftCard: (...args: unknown[]) => applyGiftCardMock(...args),
  applyStoreCredit: (...args: unknown[]) => applyStoreCreditMock(...args),
  removeDiscountCode: (...args: unknown[]) => removeDiscountCodeMock(...args),
  removeGiftCard: (...args: unknown[]) => removeGiftCardMock(...args),
  removeStoreCredit: (...args: unknown[]) => removeStoreCreditMock(...args),
}));

vi.mock("next-intl", () => ({
  // 与既有组件测试同口径：断言 key 而不是文案。
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${JSON.stringify(values)}` : key,
}));

const updatedCart = {
  id: "cart_1",
  status: "active",
} as unknown as ShoppingCart;

function buildCart(overrides: Partial<ShoppingCart> = {}): ShoppingCart {
  return {
    id: "cart_1",
    token: "guest-token",
    status: "active",
    email: null,
    customer_note: null,
    currency: "USD",
    locale: "en",
    item_count: 1,
    item_total: "10.0",
    display_item_total: "$10.00",
    converted_at: null,
    shipping_method_id: null,
    items: [],
    billing_address: null,
    shipping_address: null,
    ...overrides,
  } as ShoppingCart;
}

function renderSummary(cart: ShoppingCart) {
  return render(<CartCreditsSummary cart={cart} />);
}

function renderPanel(options: {
  cart: ShoppingCart;
  isLoggedIn?: boolean;
  onCartUpdated?: (cart: ShoppingCart) => void;
}) {
  return render(
    <CartCreditsPanel
      cart={options.cart}
      isLoggedIn={options.isLoggedIn ?? true}
      loginHref="/us/en/account?redirect=%2Fus%2Fen%2Fcart"
      onCartUpdated={options.onCartUpdated ?? vi.fn()}
    />,
  );
}

/**
 * 购物车页「优惠与抵扣」（PRD-20260914-checkout B2）。
 * 车阶段三种抵扣都只是**意图**：UI 只展示服务端快照 + 记住/忘掉意图，
 * 不做金额计算（money 契约：raw 判逻辑、display 仅渲染）。
 */
describe("CartCreditsSummary", () => {
  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-001
  it("renders the store credit row from the server snapshot", () => {
    renderSummary(
      buildCart({
        store_credit: { amount: "7.5", display_amount: "$7.50" },
      }),
    );

    const row = screen.getByTestId("store-credit-row");
    expect(row.textContent).toContain("storeCredit");
    expect(row.textContent).toContain("-$7.50");
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-002
  it("hides the store credit row when there is no credit or the amount is zero", () => {
    const { unmount } = renderSummary(buildCart({ store_credit: null }));
    expect(screen.queryByTestId("store-credit-row")).toBeNull();
    unmount();

    renderSummary(
      buildCart({ store_credit: { amount: "0.0", display_amount: "$0.00" } }),
    );
    expect(screen.queryByTestId("store-credit-row")).toBeNull();
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-003
  it("renders the applied discount code and gift card rows", () => {
    renderSummary(
      buildCart({
        discount_code: "save10",
        gift_card: { code: "GC-123", display_amount_remaining: "$25.00" },
      }),
    );

    const discountRow = screen.getByTestId("discount-code-row");
    expect(discountRow.textContent).toContain("save10");
    // 车阶段折扣金额要到提交时才计算 → 行内必须标注，避免"应用成功但无金额"的困惑
    expect(discountRow.textContent).toContain("discountCalculatedAtSubmit");

    const giftRow = screen.getByTestId("gift-card-row");
    expect(giftRow.textContent).toContain("GC-123");
    expect(screen.queryByTestId("store-credit-row")).toBeNull();
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-011
  it("renders nothing when no credit intent is present", () => {
    renderSummary(buildCart());
    expect(screen.queryByTestId("cart-credits-summary")).toBeNull();
  });
});

describe("CartCreditsPanel", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-004
  it("applies store credit and forwards the refreshed snapshot", async () => {
    const user = userEvent.setup();
    const onCartUpdated = vi.fn();
    applyStoreCreditMock.mockResolvedValue({
      success: true,
      cart: updatedCart,
    });

    renderPanel({ cart: buildCart(), onCartUpdated });

    await user.click(screen.getByTestId("use-store-credit"));

    expect(applyStoreCreditMock).toHaveBeenCalledWith("cart_1");
    expect(onCartUpdated).toHaveBeenCalledWith(updatedCart);
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-005
  it("removes an applied store credit", async () => {
    const user = userEvent.setup();
    const onCartUpdated = vi.fn();
    removeStoreCreditMock.mockResolvedValue({
      success: true,
      cart: updatedCart,
    });

    renderPanel({
      cart: buildCart({
        store_credit: { amount: "7.5", display_amount: "$7.50" },
      }),
      onCartUpdated,
    });

    await user.click(screen.getByLabelText("removeStoreCredit"));

    expect(removeStoreCreditMock).toHaveBeenCalledWith("cart_1");
    expect(onCartUpdated).toHaveBeenCalledWith(updatedCart);
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-006
  it("keeps guests offline: disabled control, login link, no request", async () => {
    const user = userEvent.setup();
    renderPanel({ cart: buildCart(), isLoggedIn: false });

    const button = screen.getByTestId("use-store-credit");
    expect(button).toBeDisabled();
    expect(screen.getByText("storeCreditLoginRequired")).toBeTruthy();
    expect(screen.getByRole("link").getAttribute("href")).toBe(
      "/us/en/account?redirect=%2Fus%2Fen%2Fcart",
    );

    await user.click(button);
    expect(applyStoreCreditMock).not.toHaveBeenCalled();
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-007
  it("blocks store credit while a gift card is applied", async () => {
    const user = userEvent.setup();
    renderPanel({
      cart: buildCart({
        gift_card: { code: "GC-123", display_amount_remaining: "$25.00" },
      }),
    });

    const button = screen.getByTestId("use-store-credit");
    expect(button).toBeDisabled();
    expect(screen.getByText("storeCreditGiftCardConflict")).toBeTruthy();

    await user.click(button);
    expect(applyStoreCreditMock).not.toHaveBeenCalled();
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-008
  it("maps store credit server error codes to copy", async () => {
    const user = userEvent.setup();
    applyStoreCreditMock.mockResolvedValue({
      success: false,
      error: "server said store_credit_not_available",
      code: "store_credit_not_available",
    });

    renderPanel({ cart: buildCart() });
    await user.click(screen.getByTestId("use-store-credit"));

    expect(screen.getByTestId("cart-credits-error").textContent).toContain(
      "storeCreditNotAvailable",
    );
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-011
  it("falls back to a gift card when the code is not a discount code", async () => {
    const user = userEvent.setup();
    applyDiscountCodeMock.mockResolvedValue({
      success: false,
      error: "invalid code",
      code: "coupon_code_not_found",
    });
    applyGiftCardMock.mockResolvedValue({
      success: true,
      cart: updatedCart,
    });

    renderPanel({ cart: buildCart() });

    await user.type(screen.getByLabelText("placeholder"), "GC-123");
    await user.click(screen.getByRole("button", { name: "apply" }));

    expect(applyDiscountCodeMock).toHaveBeenCalledWith("cart_1", "GC-123");
    expect(applyGiftCardMock).toHaveBeenCalledWith("cart_1", "GC-123");
  });

  // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-011
  it("removes an applied discount code and a gift card by code", async () => {
    const user = userEvent.setup();
    removeDiscountCodeMock.mockResolvedValue({
      success: true,
      cart: updatedCart,
    });
    removeGiftCardMock.mockResolvedValue({ success: true, cart: updatedCart });

    renderPanel({
      cart: buildCart({
        discount_code: "save10",
        gift_card: { code: "GC-123", display_amount_remaining: "$25.00" },
      }),
    });

    await user.click(screen.getByLabelText('removeCoupon:{"code":"save10"}'));
    expect(removeDiscountCodeMock).toHaveBeenCalledWith("cart_1", "save10");

    await user.click(screen.getByLabelText("removeGiftCard"));
    expect(removeGiftCardMock).toHaveBeenCalledWith("cart_1", "GC-123");
  });
});
