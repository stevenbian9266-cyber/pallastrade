import { NextRequest } from "next/server";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/checkout/newsletter/route";

const createMock = vi.fn();

vi.mock("@/lib/pallastrade", () => ({
  getClient: () => ({
    newsletterSubscribers: { create: createMock },
  }),
}));

function newsletterRequest(
  body: unknown = { email: "buyer@example.com" },
  origin = "http://shop.test",
) {
  return new NextRequest("http://shop.test/api/checkout/newsletter", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      host: "shop.test",
      origin,
    },
    body: JSON.stringify(body),
  });
}

// PRD-20260914-checkout-placeholder-controls-governance：结算页 Marketing 订阅 BFF
describe("POST /api/checkout/newsletter", () => {
  beforeEach(() => {
    createMock.mockReset();
  });

  // AC-002：勾选 Marketing 后经服务端 SDK 真正订阅
  it("subscribes the email through the Store SDK", async () => {
    createMock.mockResolvedValue({ id: "nsub_1" });

    const response = await POST(newsletterRequest());

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toEqual({ ok: true });
    expect(createMock).toHaveBeenCalledWith({ email: "buyer@example.com" });
  });

  it("rejects cross-origin requests", async () => {
    const response = await POST(
      newsletterRequest({ email: "a@b.com" }, "http://evil.test"),
    );

    expect(response.status).toBe(403);
    expect(createMock).not.toHaveBeenCalled();
  });

  it("requires an email", async () => {
    const response = await POST(newsletterRequest({ email: "   " }));

    expect(response.status).toBe(422);
    expect(createMock).not.toHaveBeenCalled();
  });

  // AC-003：订阅失败不得向外抛错误状态（调用方 best-effort，不影响下单）
  it("never surfaces provider failures as an error status", async () => {
    createMock.mockRejectedValue(new Error("provider down"));

    const response = await POST(newsletterRequest());

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toEqual({ ok: false });
  });
});
