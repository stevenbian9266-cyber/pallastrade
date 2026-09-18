/**
 * PALLAS-CUSTOM: D7 补口 3（PRD-20260918-payments-d7-payment-section-express AC-013~AC-015）
 *
 * 钱包入口的**设备能力**读数模型 —— 服务端可用性（D8/D11/D15c）之外的第二个轴，
 * 也是**只有客户端知道**的那个轴。
 *
 * 三条口径（缺一不可）：
 *   1. **点谁显示谁**：`expressPaymentMethodsFor(entry.method_key)` 把未选中的钱包设为
 *      `never`，选中项设 `auto` —— 点 Apple Pay 只出现 Apple Pay 按钮（此前会同时出现
 *      该设备所有可用钱包）。
 *   2. **未知 ≠ 不可用**：`onReady` 未给出 `availablePaymentMethods` 时是 `unknown`
 *      （保持加载），只有明确 false 才是 `unavailable(device)`；超时是 `unavailable(timeout)`
 *      且**可重试**（移动网络慢不能判死）。
 *   3. **只标注不删除**：本模块只输出状态给父级做置灰/回落，**不**决定入口集合
 *      （集合仍由服务端 `Availability::Resolver` 决定，D15c 红线）。
 */

/** 前台 express 组件（Stripe `ExpressCheckoutElement`）真正能渲染的钱包 kind。 */
export const EXPRESS_WALLET_KINDS = [
  "apple_pay",
  "google_pay",
  "link",
] as const;

/** Stripe `ExpressCheckoutElement.paymentMethods` 的键。 */
export type StripeWalletKey = "applePay" | "googlePay" | "link";

/**
 * 逐键精确的类型（与 `@stripe/stripe-js` 的 `express-checkout.d.ts` 对齐）：
 * `applePay` / `googlePay` 支持 `always`；**`link` 只支持 `auto` | `never`**。
 */
export interface ExpressPaymentMethodsConfig {
  applePay: "always" | "auto" | "never";
  googlePay: "always" | "auto" | "never";
  link: "auto" | "never";
}

/** 设备能力三态。 */
export type WalletState = "unknown" | "available" | "unavailable";

/**
 * 不可用原因（决定文案 + 是否可重试）：
 * - `device`       支付商明确报告本设备无该钱包（Apple Pay 非 Safari、Google Pay 未登录等）
 * - `timeout`      元素在 `WALLET_READY_TIMEOUT_MS` 内未上报（网络慢/iframe 被中断）→ **可重试**
 * - `unsupported`  该 kind 前台无法渲染（如 paypal / shop_pay / amazon_pay）
 * - `unconfigured` 前台拿不到支付商 publishable key
 */
export type WalletUnavailableReason =
  | "device"
  | "timeout"
  | "unsupported"
  | "unconfigured";

export interface WalletAvailability {
  state: WalletState;
  reason?: WalletUnavailableReason;
}

/**
 * 钱包元素**初始化上限**（毫秒）。
 *
 * Stripe 的 `ExpressCheckoutElement` 通过 `onReady` 上报本设备能力；元素 iframe 被中断
 * （实测 Windows/Electron 上 `elements-inner-easel` 请求 `net::ERR_ABORTED`，元素高度停在
 * 2px）或浏览器完全没有钱包时，该回调**可能永不触发**。移动网络明显更慢，因此上限取 10s，
 * 超时后给出**可重试**的降级（而不是无限加载，也不是永久判死）。
 */
export const WALLET_READY_TIMEOUT_MS = 10000;

/** entry 的 `method_key` → Stripe 钱包键；非前台支持的钱包返回 null。 */
export function stripeWalletKeyFor(
  methodKey?: string | null,
): StripeWalletKey | null {
  switch ((methodKey ?? "").toLowerCase()) {
    case "apple_pay":
      return "applePay";
    case "google_pay":
      return "googlePay";
    case "link":
      return "link";
    default:
      return null;
  }
}

/** 该入口 kind 是否由前台 express 组件渲染（否则走说明行）。 */
export function isExpressWalletKind(methodKey?: string | null): boolean {
  return stripeWalletKeyFor(methodKey) !== null;
}

/**
 * 按选中入口构造 `paymentMethods`。
 *
 * **为什么用 `always` 而不是 `auto`**（Stripe 官方文档 *Express Checkout Element* → 支持的浏览器）：
 *   - 脚注 3：**非 Safari 桌面端浏览器仅在 `paymentMethods.applePay = 'always'` 时才支持 Apple Pay**
 *     （`auto` 时 Chrome/Edge 桌面端不初始化 Apple Pay → 前台表现为一直加载/无按钮）；
 *   - 脚注 4：**Firefox / Safari / iOS 浏览器仅在 `paymentMethods.googlePay = 'always'` 时支持 Google Pay**；
 *   - 同名章节：「若要允许 Apple Pay 或 Google Pay 在**未设置时显示**，请设置为 `always`。但是，
 *     如果平台不支持或付款时使用不受支持的货币，它们仍然不会被迫出现」。
 * 即 `always` 只解除「未设置/浏览器未命中就不显示」的限制，**不会**在平台或币种不支持时强行渲染。
 *
 * - `methodKey` 为 `undefined` / `null` / `''` → **无入口上下文**（购物车抽屉：多钱包并排）→ 两个钱包 `always`。
 * - 有入口但 kind 前台不支持 → 返回 null（调用方不渲染钱包元素，走说明行）。
 */
export function expressPaymentMethodsFor(
  methodKey?: string | null,
): ExpressPaymentMethodsConfig | null {
  if (methodKey === undefined || methodKey === null || methodKey === "") {
    return { applePay: "always", googlePay: "always", link: "auto" };
  }
  const selected = stripeWalletKeyFor(methodKey);
  if (!selected) return null;
  return {
    applePay: selected === "applePay" ? "always" : "never",
    googlePay: selected === "googlePay" ? "always" : "never",
    // Link 的类型只允许 'auto' | 'never'（@stripe/stripe-js express-checkout.d.ts）
    link: selected === "link" ? "auto" : "never",
  };
}

/**
 * 读取本设备可用性（`onReady` 事件的 `availablePaymentMethods`）。
 *
 * ⚠️ **`undefined` 是确定性结论，不是「未知」**（Stripe 官方类型定义原文，
 * `@stripe/stripe-js` → `ExpressCheckoutElementReadyEvent`）：
 *
 * ```
 * availablePaymentMethods: undefined | AvailablePaymentMethods;
 *   // "The list of payment methods that could possibly show in the element,
 *   //  or undefined if no payment methods can show."
 * ```
 *
 * 即：`onReady` 一旦触发，`undefined` = **该环境没有任何钱包可显示** → `unavailable(device)`。
 * 旧实现把它当「未知」→ 界面一直停在加载态，10s 后才报「加载失败」，把确定性结论说成了网络问题
 * （实测：VS Code 内嵌 Electron 浏览器 / Windows 无 `ApplePaySession` → 两个钱包都必然
 * `undefined`，而用户看到的就是「一直加载」）。
 *
 * 真正的「未知」只存在于 **`onReady` 尚未触发**时（初始态），由看门狗兜底。
 *
 * - 无入口上下文 → 任一钱包可用即 `available`（抽屉语义）。
 * - 有入口 → **只认选中钱包那一个键**（点谁显示谁）。
 */
export function selectedWalletAvailability(
  methodKey: string | null | undefined,
  availablePaymentMethods?: Record<string, boolean> | null,
): WalletAvailability {
  const hasEntryContext = Boolean(methodKey);
  const key = hasEntryContext ? stripeWalletKeyFor(methodKey) : null;
  if (hasEntryContext && !key) {
    return { state: "unavailable", reason: "unsupported" };
  }
  // onReady 已触发但**没有任何**可显示的钱包 → 本环境确定性不可用
  if (
    availablePaymentMethods === undefined ||
    availablePaymentMethods === null
  ) {
    return { state: "unavailable", reason: "device" };
  }
  const usable = key
    ? availablePaymentMethods[key] === true
    : Boolean(
        availablePaymentMethods.applePay ||
          availablePaymentMethods.googlePay ||
          availablePaymentMethods.link,
      );
  return usable
    ? { state: "available" }
    : { state: "unavailable", reason: "device" };
}

/** 未上报兜底（看门狗）：保持 unknown 直到超时。 */
export function walletTimeoutAvailability(): WalletAvailability {
  return { state: "unavailable", reason: "timeout" };
}
