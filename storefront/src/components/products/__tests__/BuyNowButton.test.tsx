import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("next-intl", async () => {
  const actual = await vi.importActual("next-intl");
  return {
    ...actual,
    useTranslations: () => (key: string) => key,
  };
});

// # PRD-20260824-checkout-正向订单-逆向订单链路重构或优化 AC-011
// Buy Now 按钮：渲染、loading 态、点击回调（创建快捷订单 + 跳转由 ProductDetails 负责）
import { BuyNowButton } from "@/components/products/BuyNowButton";

describe("BuyNowButton", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("AC-011: 渲染 Buy Now 按钮并可点击触发 onBuyNow", () => {
    const onClick = vi.fn();
    render(<BuyNowButton onClick={onClick} />);

    const button = screen.getByTestId("buy-now-button");
    expect(button).toBeTruthy();
    fireEvent.click(button);
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it("AC-011: loading 时禁用按钮并显示进行中文案", () => {
    const onClick = vi.fn();
    render(<BuyNowButton onClick={onClick} loading />);

    const button = screen.getByTestId("buy-now-button") as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    fireEvent.click(button);
    expect(onClick).not.toHaveBeenCalled();
  });

  it("AC-011: disabled 时不可点击", () => {
    const onClick = vi.fn();
    render(<BuyNowButton onClick={onClick} disabled />);

    const button = screen.getByTestId("buy-now-button") as HTMLButtonElement;
    expect(button.disabled).toBe(true);
    fireEvent.click(button);
    expect(onClick).not.toHaveBeenCalled();
  });
});
