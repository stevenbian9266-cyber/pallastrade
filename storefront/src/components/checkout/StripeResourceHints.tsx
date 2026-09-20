import {
  type PaymentClientConfig,
  payloadStripePublishableKey,
} from "@/lib/utils/stripe";

/** Stripe.js 的源与脚本 URL（`@stripe/stripe-js#loadStripe` 注入的即为后者）。 */
export const STRIPE_JS_ORIGIN = "https://js.stripe.com";
export const STRIPE_JS_SCRIPT_URL = `${STRIPE_JS_ORIGIN}/v3/`;

/**
 * P1-a（PRD-20260920-checkout 支付核心统一 FR-011）—— `js.stripe.com` 预连接 + 预加载。
 *
 * 为什么需要：钱包/卡支付控件要等 `loadStripe()` 注入的 `https://js.stripe.com/v3/`
 * 下载并初始化后才可用（此前只在组件挂载时才发起 → 首屏多出一整段 RTT）。
 *
 * 口径（三条都不许省）：
 * 1. **只认首屏 payload**：`payment_methods[].client_config`（与 `PaymentMethods::ClientConfig`
 *    同源的 publishable 凭据）。无凭据 = 本页不会加载 Stripe.js → **一个 link 都不发**
 *    （预连接/预加载不是免费操作，不在无支付页面上白付成本）。
 * 2. **脚本 URL 与 `loadStripe` 一致**（`https://js.stripe.com/v3/`）—— 否则浏览器会
 *    预加载一个永远不会被复用的资源（等于白下载一次 Stripe.js）。
 * 3. **不传 `crossOrigin`**：Stripe.js 以经典 `<script>` 加载（非 CORS 请求），
 *    带上 `crossorigin` 会落到另一条连接池，预连接就白做了。
 *
 * 由页面装配（`UnifiedCheckout` / `OrderPaymentContent`）在确有 Stripe 支付方式时渲染；
 * React 19 会把这些 `<link>` 提升进 `<head>`（SSR 亦然）。
 */
export function StripeResourceHints({
  clientConfig,
}: {
  clientConfig?: PaymentClientConfig | null;
}) {
  if (!payloadStripePublishableKey(clientConfig)) return null;

  return (
    <>
      <link rel="preconnect" href={STRIPE_JS_ORIGIN} />
      <link rel="dns-prefetch" href={STRIPE_JS_ORIGIN} />
      <link rel="preload" as="script" href={STRIPE_JS_SCRIPT_URL} />
    </>
  );
}
