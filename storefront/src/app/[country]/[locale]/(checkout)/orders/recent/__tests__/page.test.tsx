import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

// PRD-20260920-checkout-订单可见性补齐 AC-008 / AC-009 / AC-010：
// /orders/recent 是游客订单的**唯一**稳定找回入口 —— 授权必须只来自服务端 HttpOnly
// checkout cookie，绝不接受外部参数指定订单 id（否则即为订单号枚举接口）。

const redirectMock = vi.fn((url: string) => {
  // 模拟 next/navigation 的 redirect：抛控制流异常，由框架捕获。
  throw new Error(`NEXT_REDIRECT:${url}`);
});
vi.mock("next/navigation", () => ({
  redirect: (url: string) => redirectMock(url),
}));

const pendingOrderIdMock = vi.fn();
vi.mock("@/lib/pallastrade", () => ({
  getPendingCheckoutOrderId: () => pendingOrderIdMock(),
}));

vi.mock("next-intl/server", () => ({
  getTranslations: async () => (key: string) => `t:${key}`,
}));

// biome-ignore lint/style/useImportType: 组件默认导出需真实模块
import OrdersRecentPage from "../page";

const params = Promise.resolve({ country: "us", locale: "en" });

async function renderPage(extra: Record<string, unknown> = {}) {
  const ui = await OrdersRecentPage({ params, ...extra } as never);
  return render(ui);
}

describe("/orders/recent (guest order recovery)", () => {
  beforeEach(() => {
    redirectMock.mockClear();
    pendingOrderIdMock.mockReset();
  });

  // PRD-20260920-checkout-订单可见性补齐 AC-008
  it("redirects to the payment-result page when the checkout cookie holds an order", async () => {
    pendingOrderIdMock.mockResolvedValue("or_123");

    await expect(renderPage()).rejects.toThrow("NEXT_REDIRECT");

    expect(redirectMock).toHaveBeenCalledTimes(1);
    expect(redirectMock).toHaveBeenCalledWith("/us/en/payment-result/or_123");
  });

  // PRD-20260920-checkout-订单可见性补齐 AC-009
  it("renders an empty state (not a 500) when there is no checkout cookie", async () => {
    pendingOrderIdMock.mockResolvedValue(null);

    await renderPage();

    expect(redirectMock).not.toHaveBeenCalled();
    expect(screen.getByText("t:noRecentOrderTitle")).toBeTruthy();
    expect(screen.getByTestId("orders-recent-back-to-cart")).toHaveAttribute(
      "href",
      "/us/en/cart",
    );
  });

  // PRD-20260920-checkout-订单可见性补齐 AC-009（前缀守卫）
  it("treats a malformed cookie value as empty state", async () => {
    pendingOrderIdMock.mockResolvedValue("not-an-order-id");

    await renderPage();

    expect(redirectMock).not.toHaveBeenCalled();
    expect(screen.getByText("t:noRecentOrderTitle")).toBeTruthy();
  });

  // PRD-20260920-checkout-订单可见性补齐 AC-010
  it("ignores an externally supplied ?order_id= parameter", async () => {
    pendingOrderIdMock.mockResolvedValue(null);

    await renderPage({
      searchParams: Promise.resolve({ order_id: "or_attacker_supplied" }),
    });

    expect(redirectMock).not.toHaveBeenCalled();
    expect(screen.getByText("t:noRecentOrderTitle")).toBeTruthy();
  });
});
