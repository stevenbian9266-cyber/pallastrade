/**
 * PRD-20260914-checkout-quote-confirmation-loop：
 * `cart_` 页报价快照（sessionStorage）与差异计算。
 *
 * 用途：Pay Now 时把「客户端所见报价版本」带回后端（`expected_checkout_version` /
 * `expected_price_version`）；后端判定漂移 → 409 → 页内展示逐步差异并要求重新点击。
 *
 * Money 契约：差异判断只看 raw 字段（`delivery_total` / `discount_total` / `amount_due`），
 * 展示一律用 `display_*`（禁止 `parseFloat(display_*)`）。
 */

export interface CheckoutQuote {
  checkout_version: number;
  price_version: string | null;
  delivery_total: string | null;
  display_delivery_total: string | null;
  discount_total: string | null;
  display_discount_total: string | null;
  /** PRD-20260919-checkout-order-summary-fee-read-model FR-007：权威税费。 */
  tax_total: string | null;
  display_tax_total: string | null;
  amount_due: string | null;
  display_amount_due: string | null;
}

export type QuoteDiffKey = "shipping" | "promotion" | "amountDue";

export interface QuoteDiffRow {
  key: QuoteDiffKey;
  /** 旧值（display_*；缺失则 null） */
  before: string | null;
  /** 新值（display_*；缺失则 null） */
  after: string | null;
  changed: boolean;
}

const STORAGE_PREFIX = "pallastrade:quote:";

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/** 把任意来源（BFF 响应）归一为快照；形状不合法 → null（降级：不带 expected_* 也能支付）。 */
export function normalizeQuote(input: unknown): CheckoutQuote | null {
  if (!input || typeof input !== "object") return null;
  const raw = input as Record<string, unknown>;
  const version = raw.checkout_version;
  if (typeof version !== "number" || Number.isNaN(version)) return null;

  return {
    checkout_version: version,
    price_version: str(raw.price_version),
    delivery_total: str(raw.delivery_total),
    display_delivery_total: str(raw.display_delivery_total),
    discount_total: str(raw.discount_total),
    display_discount_total: str(raw.display_discount_total),
    tax_total: str(raw.tax_total),
    display_tax_total: str(raw.display_tax_total),
    amount_due: str(raw.amount_due),
    display_amount_due: str(raw.display_amount_due),
  };
}

function storage(): Storage | null {
  try {
    if (typeof window === "undefined") return null;
    return window.sessionStorage;
  } catch {
    return null;
  }
}

export function readQuoteSnapshot(cartId: string): CheckoutQuote | null {
  const store = storage();
  if (!store) return null;

  try {
    return normalizeQuote(
      JSON.parse(store.getItem(`${STORAGE_PREFIX}${cartId}`) ?? "null"),
    );
  } catch {
    return null;
  }
}

export function writeQuoteSnapshot(cartId: string, quote: unknown): void {
  const normalized = normalizeQuote(quote);
  const store = storage();
  if (!store || !normalized) return;

  try {
    store.setItem(`${STORAGE_PREFIX}${cartId}`, JSON.stringify(normalized));
  } catch {
    // 快照仅用于多一层报价确认；写入失败不得影响支付
  }
}

/** Pay Now 载荷片段：有快照才带 expected_*（无快照 = 首次点击，后端自行判定）。 */
export function expectedVersions(quote: CheckoutQuote | null): {
  expected_checkout_version?: number;
  expected_price_version?: string;
} {
  if (!quote) return {};
  return {
    expected_checkout_version: quote.checkout_version,
    ...(quote.price_version
      ? { expected_price_version: quote.price_version }
      : {}),
  };
}

function row(
  key: QuoteDiffKey,
  beforeRaw: string | null,
  beforeDisplay: string | null,
  afterRaw: string | null,
  afterDisplay: string | null,
): QuoteDiffRow {
  return {
    key,
    before: beforeDisplay,
    after: afterDisplay,
    changed: (beforeRaw ?? "") !== (afterRaw ?? ""),
  };
}

/** 三行差异（Shipping / Promotion / Amount due）；无旧快照时全部标记为 changed。 */
export function diffQuotes(
  before: CheckoutQuote | null,
  after: CheckoutQuote | null,
): QuoteDiffRow[] {
  if (!after) return [];

  const rows = [
    row(
      "shipping",
      before?.delivery_total ?? null,
      before?.display_delivery_total ?? null,
      after.delivery_total,
      after.display_delivery_total,
    ),
    row(
      "promotion",
      before?.discount_total ?? null,
      before?.display_discount_total ?? null,
      after.discount_total,
      after.display_discount_total,
    ),
    row(
      "amountDue",
      before?.amount_due ?? null,
      before?.display_amount_due ?? null,
      after.amount_due,
      after.display_amount_due,
    ),
  ];

  return before ? rows : rows.map((item) => ({ ...item, changed: true }));
}
