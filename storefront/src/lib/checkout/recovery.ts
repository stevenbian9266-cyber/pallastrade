/**
 * PRD-20260919-checkout-express-always-visible-and-pi-params FR-006 / AC-009：
 * **已转换购物车（Prepare 已建单）页面重访的恢复路由**。
 *
 * 背景（dev 事故路径）：统一结账页停留在 `cart_...` URL 时，Prepare 一建单就会
 * 把购物车 cookie 换成后继空车；随后任何一次服务端重渲染（刷新 / RSC 刷新）都会
 * 让 `getCheckoutOrder(cartId)` 解析出的对象与 URL 不符 —— 旧实现直接回落到
 * 购物车页（硬编码字符串目标），用户看到的是**空购物车**，明明订单已经建好（未支付）。
 *
 * 正确目标：`_pallastrade_checkout_order` cookie（Prepare/Start 由服务端写入）里
 * 记着真实订单 → 送到该订单的**纯支付页**（标准流程：`checkout/or_...` 支持补付）；
 * 只有确实没有待支付订单上下文时才回购物车页。
 */
export interface ConvertedCartRecoveryInput {
  country: string;
  locale: string;
  /** `_pallastrade_checkout_order` cookie 值（待支付订单 `or_...`；无则 null）。 */
  pendingOrderId: string | null;
}

/** 恢复路由（相对站点根，含 country/locale 前缀）。 */
export function recoveryRouteForConvertedCart({
  country,
  locale,
  pendingOrderId,
}: ConvertedCartRecoveryInput): string {
  const base = `/${country}/${locale}`;
  // 只接受订单前缀：cookie 异常（被篡改/旧格式）时不制造奇怪跳转。
  if (pendingOrderId?.startsWith("or_")) {
    return `${base}/checkout/${pendingOrderId}`;
  }
  return `${base}/cart`;
}
