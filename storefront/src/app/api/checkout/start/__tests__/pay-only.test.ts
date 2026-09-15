import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/checkout/start/route";

const updateMock = vi.fn();
const submitMock = vi.fn();
const createTransactionMock = vi.fn();

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => ({
    carts: { update: updateMock, submit: submitMock },
    orders: {
      transactions: { create: createTransactionMock },
      checkout: { get: vi.fn().mockRejectedValue(new Error("no view")) },
    },
  }),
  getCartOptions: vi.fn().mockResolvedValue({ headers: {} }),
  getCheckoutOptions: vi.fn().mockResolvedValue({ headers: {} }),
  setCartCookies: vi.fn(),
  clearCartCookies: vi.fn(),
  setCheckoutCookies: vi.fn(),
}));

function payRequest(body: Record<string, unknown>) {
  return new NextRequest("http://shop.test/api/checkout/start", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      host: "shop.test",
      origin: "http://shop.test",
    },
    body: JSON.stringify(body),
  });
}

/**
 * PRD-20260915-checkout-单页两段语义 AC-003/AC-005：
 * 带 `order_id` 的 Pay 请求**只启动交易**（不再 update/submit），
 * 且必须把页面确认过的报价版本带给后端。
 */
describe("checkout start BFF · pay-only mode (PRD-20260915 AC-003/AC-005)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    createTransactionMock.mockResolvedValue({
      id: "txn_1",
      state: "payment_pending",
      payment_execution: {
        id: "ps_1",
        status: "pending",
        external_data: { client_secret: "pi_secret" },
      },
    });
  });

  it("starts the transaction on the prepared order and forwards the quote version (AC-003)", async () => {
    const response = await POST(
      payRequest({
        order_id: "or_1",
        payment_method_id: "pm_card",
        session_required: true,
        payment_mode: "payment_intent",
        expected_checkout_version: 3,
        expected_price_version: "pv_3",
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    // Pay 阶段不得再提交购物车（防重复建单，AC-005）
    expect(updateMock).not.toHaveBeenCalled();
    expect(submitMock).not.toHaveBeenCalled();
    expect(createTransactionMock).toHaveBeenCalledWith(
      "or_1",
      expect.objectContaining({
        payment_method_id: "pm_card",
        expected_checkout_version: 3,
        expected_price_version: "pv_3",
      }),
      expect.any(Object),
    );
    expect(body.order.id).toBe("or_1");
    expect(body.transaction).toEqual({ id: "txn_1", state: "payment_pending" });
    expect(body.session.id).toBe("ps_1");
  });

  it("skips transaction start for methods that need no provider session", async () => {
    const response = await POST(
      payRequest({
        order_id: "or_2",
        payment_method_id: "pm_check",
        session_required: false,
      }),
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(createTransactionMock).not.toHaveBeenCalled();
    expect(body.transaction).toBeNull();
    expect(body.session).toBeNull();
    expect(body.order.id).toBe("or_2");
  });
});
