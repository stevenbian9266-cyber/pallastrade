import { loadStripe, type Stripe } from "@stripe/stripe-js";

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
 * 解析 Stripe publishable key：API 下发值优先 → 回落 `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`。
 * @returns 非空字符串；两处都缺时返回 null。
 */
export function resolveStripePublishableKey(
  clientConfig?: PaymentClientConfig | null,
): string | null {
  const fromApi = clientConfig?.publishable?.publishable_key;
  if (typeof fromApi === "string" && fromApi.trim() !== "") {
    return fromApi.trim();
  }

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

  const created = loadStripe(publishableKey);
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
