import { render } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { StripeResourceHints } from "@/components/checkout/StripeResourceHints";

/**
 * P1-a（PRD-20260920-checkout 支付核心统一 FR-011）—— `js.stripe.com` 预热。
 *
 * 口径：**只认首屏 payload**（`payment_methods[].client_config`，与
 * `PaymentMethods::ClientConfig` 同源）里下发的 publishable 凭据；
 * 无凭据 = 本页不会加载 Stripe.js → 一个 link 都不发（不白付连接/流量）。
 * 脚本 URL 必须与 `@stripe/stripe-js#loadStripe` 注入的一致（否则预加载不会被复用）。
 */
describe("StripeResourceHints (P1-a FR-011)", () => {
  it("preconnects and preloads Stripe.js when the payload ships a publishable key", () => {
    render(
      <StripeResourceHints
        clientConfig={{ publishable: { publishable_key: "pk_test_payload" } }}
      />,
    );

    expect(
      document.querySelector(
        'link[rel="preconnect"][href="https://js.stripe.com"]',
      ),
    ).not.toBeNull();
    expect(
      document.querySelector(
        'link[rel="dns-prefetch"][href="https://js.stripe.com"]',
      ),
    ).not.toBeNull();
    expect(
      document.querySelector(
        'link[rel="preload"][as="script"][href="https://js.stripe.com/v3/"]',
      ),
    ).not.toBeNull();
  });

  it("renders nothing without payload credentials", () => {
    render(<StripeResourceHints clientConfig={null} />);
    expect(
      document.querySelector('link[href^="https://js.stripe.com"]'),
    ).toBeNull();
  });

  it("ignores an empty publishable key (blank string is not a credential)", () => {
    render(
      <StripeResourceHints
        clientConfig={{ publishable: { publishable_key: "  " } }}
      />,
    );
    expect(
      document.querySelector('link[href^="https://js.stripe.com"]'),
    ).toBeNull();
  });
});
