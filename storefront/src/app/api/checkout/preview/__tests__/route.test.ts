import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/checkout/preview/route";

const previewQuoteMock = vi.fn();

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => ({ carts: { previewQuote: previewQuoteMock } }),
  getCartOptions: vi
    .fn()
    .mockResolvedValue({ guestToken: "guest-token", token: "jwt-token" }),
}));

function previewRequest(
  body: unknown = { cart_id: "cart_1", country: "US" },
  origin = "http://shop.test",
) {
  return new NextRequest("http://shop.test/api/checkout/preview", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      host: "shop.test",
      origin,
    },
    body: JSON.stringify(body),
  });
}

/**
 * PRD-20260919-shipping-checkout-quote-preview AC-007：
 * 结算页只读预览 BFF —— 同源校验、缺 cart_id 拒绝、透传 SDK 结果、
 * 失败时给**可降级**的 502（前端回落「提交时计算」，绝不阻断结算）。
 */
describe("checkout preview BFF (PRD-20260919 AC-007)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    previewQuoteMock.mockResolvedValue({
      cart_id: "cart_1",
      currency: "USD",
      display_delivery_total: "$5.00",
      display_tax_total: "$1.60",
      display_amount_due: "$26.58",
      selected_method_id: "dm_1",
      methods: [],
      estimated: true,
    });
  });

  it("forwards the preview body to the SDK and returns the payload", async () => {
    const response = await POST(previewRequest());
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.display_amount_due).toBe("$26.58");
    expect(previewQuoteMock).toHaveBeenCalledWith(
      "cart_1",
      {
        country: "US",
        shipping_method_id: undefined,
        shipping_address: undefined,
      },
      { guestToken: "guest-token", token: "jwt-token" },
    );
  });

  it("rejects cross-origin requests with 403", async () => {
    const response = await POST(previewRequest(undefined, "http://evil.test"));

    expect(response.status).toBe(403);
    expect(previewQuoteMock).not.toHaveBeenCalled();
  });

  it("rejects a missing cart_id with 400", async () => {
    const response = await POST(previewRequest({ country: "US" }));

    expect(response.status).toBe(400);
    expect(previewQuoteMock).not.toHaveBeenCalled();
  });

  it("degrades to 502 when the SDK call fails (never blocks checkout)", async () => {
    previewQuoteMock.mockRejectedValue(new Error("boom"));

    const response = await POST(previewRequest());
    const json = await response.json();

    expect(response.status).toBe(502);
    expect(json.error.code).toBe("preview_unavailable");
  });
});
