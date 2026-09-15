import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  completeExpressCheckout,
  expressClientSecret,
  expressErrorRoute,
  expressNoticeFor,
  expressResultUrl,
  startExpressCheckout,
} from "@/lib/checkout/express-canonical";

const fetchMock = vi.fn();
vi.stubGlobal("fetch", fetchMock);

function jsonResponse(status: number, body: unknown) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  };
}

const startBody = {
  cart_id: "cart_1",
  payment_method_id: "pm_1",
  payment_mode: "payment_intent",
  checkout: { email: "ada@example.com" },
};

/**
 * 钱包 canonical 编排（PRD-20260915-checkout B4）。
 * 关键点：创建/完成只走同源 BFF（`/api/checkout/start`，后端为
 * `orders.transactions.create` / `orders.paymentSessions.complete`），
 * **不再**触碰 legacy `carts.paymentSessions.*`。
 */
describe("express canonical orchestration", () => {
  beforeEach(() => {
    fetchMock.mockReset();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-001
  it("starts the canonical checkout through the same-origin BFF", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(200, {
        order: { id: "or_1" },
        transaction: { id: "txn_1", state: "payment_pending" },
        session: { id: "ps_1", external_data: { client_secret: "cs_1" } },
      }),
    );

    const result = await startExpressCheckout(startBody);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("/api/checkout/start");
    expect(init.method).toBe("POST");
    expect(JSON.parse(String(init.body))).toEqual(startBody);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data.order.id).toBe("or_1");
      expect(result.data.session?.id).toBe("ps_1");
      expect(result.data.transaction?.state).toBe("payment_pending");
    }
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-006
  it("surfaces the canonical error code for stock failures", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(422, {
        error: { code: "INSUFFICIENT_STOCK", message: "Product A is sold out" },
      }),
    );

    const result = await startExpressCheckout(startBody);

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("INSUFFICIENT_STOCK");
      expect(result.error.status).toBe(422);
    }
    expect(expressErrorRoute("INSUFFICIENT_STOCK")).toBe("inline");
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-005
  it("routes paid-but-recovering failures to the result page (no second payment)", async () => {
    fetchMock.mockResolvedValue(
      jsonResponse(409, {
        error: {
          code: "INVENTORY_RECOVERY_REQUIRED",
          message: "Order confirming",
        },
      }),
    );

    const result = await startExpressCheckout(startBody);

    expect(result.ok).toBe(false);
    expect(expressErrorRoute("INVENTORY_RECOVERY_REQUIRED")).toBe("recovery");
    expect(expressNoticeFor("INVENTORY_RECOVERY_REQUIRED")).toBe("recovery");
    expect(expressNoticeFor("transaction_not_payable")).toBe("processing");
    expect(expressNoticeFor("INSUFFICIENT_STOCK")).toBeNull();
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-003 AC-004
  it("builds the unified result page URL (provider return_url included)", () => {
    expect(
      expressResultUrl("https://shop.test", "/us/en", "or_1", "ps_1"),
    ).toBe("https://shop.test/us/en/payment-result/or_1?session=ps_1");
    expect(expressResultUrl("https://shop.test", "/us/en", "or_1")).toBe(
      "https://shop.test/us/en/payment-result/or_1",
    );
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-007
  it("only exposes a provider secret when the server returned one", () => {
    expect(expressClientSecret(null)).toBeNull();
    expect(expressClientSecret({ id: "ps_1", external_data: {} })).toBeNull();
    expect(
      expressClientSecret({
        id: "ps_1",
        external_data: { client_secret: "cs_test%5F1" },
      }),
    ).toBe("cs_test_1");
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-008
  it("never throws when the completion call fails", async () => {
    fetchMock.mockResolvedValue(jsonResponse(500, { error: "boom" }));

    await expect(completeExpressCheckout("or_1", "ps_1")).resolves.toBe(false);

    fetchMock.mockRejectedValue(new Error("network down"));
    await expect(completeExpressCheckout("or_1", "ps_1")).resolves.toBe(false);
  });
});
