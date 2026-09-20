import {
  loadStripe,
  type Stripe,
  type StripeConstructorOptions,
} from "@stripe/stripe-js";

/**
 * PRD-20260918-payments-隐藏-stripe-elements-开发者工具入口（2026-09-18）——
 * 关闭 Stripe.js 在**测试模式**下注入的开发者工具浮层（右下角黑色按钮 + 面板）。
 *
 * 为什么必须关：dev / staging / 预发均使用测试密钥（`pk_test_…`），Stripe.js 会注入
 * "Stripe developer tools"（iframe 标题 `Stripe developer tools frame`，按钮 aria-label
 * `Open Stripe Developer Tools`）。Stripe 自述「仅开发环境显示，客户不会看到」，但演示、
 * 录屏、验收时会被误认为产品缺陷；且团队对页面右下角冒出未知控件有安全/合规疑虑。
 *
 * 为什么用这个选项而不是 CSS 隐藏：该浮层属于 Stripe 的 Easel UI 体系
 * （`<hash>__Easel-contentWrapper`），类名 hash 随 Stripe.js 版本漂移，且同一体系还承载
 * **真实支付面**（卡表单 / 钱包 / 弹层）—— 盲屏蔽会把支付 UI 一并弄挂。
 * `developerTools` 是 `@stripe/stripe-js` 的 `StripeConstructorOptions` 公开字段；
 * Stripe.js 内部逻辑为 `undefined !== e.assistant.enabled ? 采用用户值（上报
 * easel.user_set_easel_option） : 默认值`，因此显式传 `false` 会被尊重。
 *
 * 需要临时恢复调试能力：把 `enabled` 改回 `true`（或移除该选项）即可，仅影响本机。
 */
export const STRIPE_DEVELOPER_TOOLS_DISABLED: StripeConstructorOptions = {
  developerTools: { assistant: { enabled: false } },
};

/**
 * PALLAS-CUSTOM: D10（PRD-20260915-payments-d10-client-config）——
 * 前台密钥下发（业务方案 §68.4 / §76.1）：服务端在 `payment_methods[].client_config`
 * 下发 **publishable 级**凭据；前端**先读 API、回落构建期环境变量**（双读迁移）。
 * 目标：换支付商 / 换环境 = 后台改配置即生效，不再重建镜像。
 */
export interface PaymentClientConfig {
  provider?: string | null;
  environment?: string | null;
  publishable?: Record<string, string> | null;
  session_token?: string | null;
}

/** 按 publishable key 缓存 `loadStripe` 结果（同 key 复用，换 key 重新初始化）。 */
const stripePromises = new Map<string, Promise<Stripe | null>>();

/**
 * PRD-20260919-payments-checkout-top-express-pay-locale（2026-09-19）——
 * Stripe 渲染面跟随**站点语种**。此前所有 `Elements`/`loadStripe` 均未传 `locale`，
 * Stripe 按**浏览器语言**自动检测 → 中文浏览器上钱包按钮/卡表单渲染中文，
 * 与商城前台语种（messages/{de,en,es,fr,pl}.json 五语言）不符。
 *
 * 站点五语种均映射为 Stripe 同码 locale；未知/缺省回落 `auto`（= 维持旧的
 * 浏览器语言行为，不劣于现状）。
 */
export type StorefrontStripeLocale = "auto" | "de" | "en" | "es" | "fr" | "pl";

const SITE_LOCALE_TO_STRIPE: Record<string, StorefrontStripeLocale> = {
  de: "de",
  en: "en",
  es: "es",
  fr: "fr",
  pl: "pl",
};

/** 站点 locale（如 `en` / `en-US`）→ Stripe `Elements` 的 `locale` 选项值。 */
export function stripeLocaleFor(
  siteLocale?: string | null,
): StorefrontStripeLocale {
  const base = (siteLocale ?? "").toLowerCase().split("-")[0] ?? "";
  return SITE_LOCALE_TO_STRIPE[base] ?? "auto";
}

/**
 * 仅解析**首屏 payload**（`payment_methods[].client_config`）里的 publishable key，
 * **不做环境变量回落**。
 *
 * 用途：预连接 / 预加载这类「必须发生在服务端渲染时」的预热决策 —— 只有服务端
 * 明确下发了凭据，本页才真的会加载 Stripe.js（不猜、不白付连接与流量成本）。
 * 运行时初始化仍走 `resolveStripePublishableKey`（payload 优先 + env 回落，D10 双读）。
 */
export function payloadStripePublishableKey(
  clientConfig?: PaymentClientConfig | null,
): string | null {
  const fromApi = clientConfig?.publishable?.publishable_key;
  return typeof fromApi === "string" && fromApi.trim() !== ""
    ? fromApi.trim()
    : null;
}

/**
 * 解析 Stripe publishable key：API 下发值优先 → 回落 `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`。
 * @returns 非空字符串；两处都缺时返回 null。
 */
export function resolveStripePublishableKey(
  clientConfig?: PaymentClientConfig | null,
): string | null {
  const fromApi = payloadStripePublishableKey(clientConfig);
  if (fromApi) return fromApi;

  const fromEnv = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;
  return typeof fromEnv === "string" && fromEnv.trim() !== ""
    ? fromEnv.trim()
    : null;
}

/** Whether Stripe is usable (service-provided key, or env fallback). */
export function isStripeConfigured(
  clientConfig?: PaymentClientConfig | null,
): boolean {
  return resolveStripePublishableKey(clientConfig) !== null;
}

/**
 * Stripe.js 懒加载单例（按 key 维度）。未配置时返回已 resolve 的 null
 * （与旧 `stripePromise` 行为一致：调用方无需 try/catch）。
 */
export function getStripePromise(
  clientConfig?: PaymentClientConfig | null,
): Promise<Stripe | null> {
  const publishableKey = resolveStripePublishableKey(clientConfig);
  if (!publishableKey) return Promise.resolve(null);

  const cached = stripePromises.get(publishableKey);
  if (cached) return cached;

  const created = loadStripe(publishableKey, STRIPE_DEVELOPER_TOOLS_DISABLED);
  stripePromises.set(publishableKey, created);
  return created;
}

/**
 * PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): Checkout Session
 * client_secrets returned by Stripe may carry URL-encoded characters (e.g.
 * `%2F` in the secret segment), which `elements({ clientSecret })` rejects.
 * Normalize before passing to Stripe.js. Idempotent — safe for already-clean
 * secrets (including PaymentIntent `pi_..._secret_...`).
 */
export function normalizeClientSecret(clientSecret: string): string {
  if (!clientSecret.includes("%")) return clientSecret;
  try {
    return decodeURIComponent(clientSecret);
  } catch {
    return clientSecret;
  }
}

/** 支付会话的类型（含后端透传的 external_data）。 */
export interface PaymentSessionLike {
  id: string;
  external_data?: Record<string, unknown> | null;
}

/**
 * PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 * 从支付会话提取 client_secret（位于 external_data 且 URL 编码 %2F → 解码）。
 * 纯函数放非 server 文件（Next.js server action 文件禁止导出非 async 函数），
 * UnifiedCheckout / OrderPaymentContent / PaymentCheckoutModal 三处共用。
 */
export function extractSessionClientSecret(
  session: PaymentSessionLike | null | undefined,
): string | null {
  if (!session) return null;
  const raw = session.external_data?.client_secret as string | undefined;
  if (!raw) return null;
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}
