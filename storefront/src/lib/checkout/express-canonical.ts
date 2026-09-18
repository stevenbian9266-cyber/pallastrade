/**
 * 钱包（Express / Apple Pay / Google Pay）canonical 编排
 * （PRD-20260915-checkout-…-b4-… FR-001/003/005）。
 *
 * 方案 §29：Express **不得**成为第二条 Checkout Flow —— 必须与结账页走同一条链：
 *
 *   POST /api/checkout/start
 *     └─ carts.update（email/地址/账单语义）
 *        → carts.submit（幂等提交 → or_ 订单）
 *        → orders.transactions.create
 *            （Transactions::Start → StockReserve → PaymentSessions::Start）
 *   Stripe confirmPayment(client_secret)
 *   PATCH /api/checkout/start
 *     └─ orders.paymentSessions.complete（best-effort；webhook/OnPaymentSuccess 兜底）
 *   → /{country}/{locale}/payment-result/{orderId}?session=…
 *
 * 这里**不再**出现 `carts.paymentSessions.*`（legacy 会话）：创建与完成都走
 * Order 域同名端点，从而不再产生 `payment.legacy_flow.used` 流量。
 *
 * 本模块为「客户端安全」的纯编排（不 import SDK / 服务端依赖），便于单测断言
 * 「调用 canonical、不调用 legacy、错误如何分流」。
 */

/** 与服务端 BFF 对齐的最小响应形状（仅取本模块需要的字段）。 */
export interface ExpressStartResponse {
  order: { id: string; shipping_method_id?: string | null };
  transaction: { id: string; state: string } | null;
  session: {
    id: string;
    /** 支付执行体（ps_）——Stripe 等会话类的 client_secret 在 external_data 中。 */
    external_data?: Record<string, unknown> | null;
  } | null;
}

export interface ExpressStartError {
  status: number;
  code?: string;
  message: string;
}

export type ExpressStartResult =
  | { ok: true; data: ExpressStartResponse }
  | { ok: false; error: ExpressStartError };

/** 需要走「结果页 · 已收款待恢复」分支的错误码（禁止二次支付，§33）。 */
const RECOVERY_NOTICE_CODES = new Set([
  "INVENTORY_RECOVERY_REQUIRED",
  "transaction_not_payable",
]);

/**
 * D7 补口 2b（2026-09-18）：钱包元素**初始化上限**（毫秒）。
 *
 * Stripe 的 `ExpressCheckoutElement` 通过 `onReady` 上报本设备能力；但元素 iframe 被中断
 * （实测 Windows/Electron 上 `elements-inner-easel` 请求 `net::ERR_ABORTED`，元素高度停在 2px）
 * 或浏览器完全没有钱包时，该回调**可能永不触发** —— 只等回调会留下**无限加载态**，
 * 用户视角同样等于「组件没渲染出来」。超过此上限仍未上报 → 按「本设备不可用」走显式降级。
 */
export const WALLET_READY_TIMEOUT_MS = 5000;

/**
 * 错误落点（PRD FR-005）：
 * - `recovery` → 结果页 `?notice=recovery|processing`（已收款/处理中，绝不能重付）
 * - `inline`   → 抽屉内提示（无 PSP 扣款：库存/报价/未就绪/支付方式不可用等）
 */
export function expressErrorRoute(code?: string | null): "recovery" | "inline" {
  if (!code) return "inline";
  return RECOVERY_NOTICE_CODES.has(code) ? "recovery" : "inline";
}

/** 结果页 notice 参数（仅 recovery 落点使用）。 */
export function expressNoticeFor(
  code?: string | null,
): "recovery" | "processing" | null {
  if (code === "INVENTORY_RECOVERY_REQUIRED") return "recovery";
  if (code === "transaction_not_payable") return "processing";
  return null;
}

interface ErrorEnvelope {
  error?: { code?: unknown; message?: unknown };
  order_id?: unknown;
}

function readError(body: unknown, status: number): ExpressStartError {
  const envelope = (body ?? {}) as ErrorEnvelope;
  const code = envelope.error?.code;
  const message = envelope.error?.message;
  return {
    status,
    ...(typeof code === "string" && code.length > 0 ? { code } : {}),
    message:
      typeof message === "string" && message.length > 0
        ? message
        : "Checkout could not be completed",
  };
}

/** `POST /api/checkout/start`：cart update → 幂等 submit → Transaction（含会话）。 */
export async function startExpressCheckout(
  body: Record<string, unknown>,
): Promise<ExpressStartResult> {
  try {
    const response = await fetch("/api/checkout/start", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    const payload = (await response.json().catch(() => null)) as unknown;

    if (!response.ok) {
      return { ok: false, error: readError(payload, response.status) };
    }
    return { ok: true, data: payload as ExpressStartResponse };
  } catch (error) {
    return {
      ok: false,
      error: {
        status: 0,
        message:
          error instanceof Error ? error.message : "Network request failed",
      },
    };
  }
}

/**
 * `PATCH /api/checkout/start`：驱动 `orders.paymentSessions.complete`。
 * best-effort —— 失败不抛（后端 webhook / `Transactions::OnPaymentSuccess` 会收尾，
 * 结果页以服务端状态为准）。
 */
export async function completeExpressCheckout(
  orderId: string,
  sessionId: string,
): Promise<boolean> {
  try {
    const response = await fetch("/api/checkout/start", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ order_id: orderId, session_id: sessionId }),
    });
    return response.ok;
  } catch {
    return false;
  }
}

/** 钱包会话的 client_secret（缺失 → 不得调用 provider confirm）。 */
export function expressClientSecret(
  session: ExpressStartResponse["session"],
): string | null {
  const raw = session?.external_data?.client_secret;
  if (typeof raw !== "string" || raw.length === 0) return null;
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

/** 钱包支付结果页 URL（canonical 落点 + provider return_url 共用）。 */
export function expressResultUrl(
  origin: string,
  basePath: string,
  orderId: string,
  sessionId?: string | null,
): string {
  const query = sessionId ? `?session=${encodeURIComponent(sessionId)}` : "";
  return `${origin}${basePath}/payment-result/${orderId}${query}`;
}
