import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { BackInStockNotify } from "@/components/products/BackInStockNotify";

/**
 * PRD-20260916-shipping-catalog-observability-scope AC-010/AC-011: subscribing used to be
 * invisible to analytics (no way to answer "did 缺货订阅 bring sales"), and
 * tracking must never be able to break the flow.
 */

const sendGTMEvent = vi.fn();
const createBackInStockSubscription = vi.fn();

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

vi.mock("@next/third-parties/google", () => ({
  sendGTMEvent: (...args: unknown[]) => sendGTMEvent(...args),
}));

vi.mock("@/lib/data/backInStock", () => ({
  createBackInStockSubscription: (...args: unknown[]) =>
    createBackInStockSubscription(...args),
}));

function subscribe(email = "shopper@example.com") {
  render(<BackInStockNotify productId="prod_1" variantId="variant_1" />);
  fireEvent.change(screen.getByLabelText("backInStockPlaceholder"), {
    target: { value: email },
  });
  fireEvent.click(screen.getByText("backInStockSubmit"));
}

describe("BackInStockNotify observability (AC-010/AC-011)", () => {
  beforeEach(() => {
    sendGTMEvent.mockReset();
    createBackInStockSubscription.mockReset();
  });

  it("reports a successful subscription with the subscribed SKU", async () => {
    createBackInStockSubscription.mockResolvedValue({ success: true });

    subscribe();

    await waitFor(() => expect(sendGTMEvent).toHaveBeenCalled());
    expect(sendGTMEvent).toHaveBeenCalledWith({
      event: "back_in_stock_subscribe",
      product_id: "prod_1",
      variant_id: "variant_1",
      success: true,
    });
  });

  it("reports a failed subscription without flipping the button state", async () => {
    createBackInStockSubscription.mockResolvedValue({
      success: false,
      error: "boom",
    });

    subscribe();

    await waitFor(() => expect(sendGTMEvent).toHaveBeenCalled());
    expect(sendGTMEvent).toHaveBeenCalledWith(
      expect.objectContaining({ success: false }),
    );
    expect(screen.getByText("backInStockError")).toBeTruthy();
    expect(screen.queryByText("backInStockSuccess")).toBeNull();
  });

  it("still completes the subscription when analytics throws (AC-011)", async () => {
    createBackInStockSubscription.mockResolvedValue({ success: true });
    sendGTMEvent.mockImplementation(() => {
      throw new Error("analytics down");
    });

    subscribe();

    await waitFor(() =>
      expect(screen.getByText("backInStockSuccess")).toBeTruthy(),
    );
  });
});
