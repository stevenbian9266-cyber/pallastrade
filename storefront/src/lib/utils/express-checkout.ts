import type { Cart, Fulfillment } from "@pallastrade/sdk";

/**
 * Stripe zero-decimal currencies where the amount is already in the smallest unit.
 * @see https://docs.stripe.com/currencies#zero-decimal
 */
const STRIPE_ZERO_DECIMAL_CURRENCIES = new Set([
  "bif",
  "clp",
  "djf",
  "gnf",
  "jpy",
  "kmf",
  "krw",
  "mga",
  "pyg",
  "rwf",
  "ugx",
  "vnd",
  "vuv",
  "xaf",
  "xof",
  "xpf",
]);

/**
 * Convert a monetary amount to the smallest currency unit for Stripe.
 * For most currencies this means multiplying by 100 (e.g. $9.99 → 999).
 * For zero-decimal currencies (JPY, KRW, etc.) the amount is returned as-is.
 *
 * P0-4 (PRD FR-041): 本函数是「展示/单位换算」级别——**不是**权威金额来源。
 * 当 cart.express_payment 存在时，Stripe 金额必须用服务端 amount（见 expressAmount）。
 */
export function toCents(amount: string | number, currency?: string): number {
  const n = Number(amount);
  if (!Number.isFinite(n)) {
    throw new TypeError(
      `toCents: expected a finite number, got ${typeof amount} (${String(amount)})`,
    );
  }
  if (currency && STRIPE_ZERO_DECIMAL_CURRENCIES.has(currency.toLowerCase())) {
    return Math.round(n);
  }
  return Math.round(n * 100);
}

/** Generate a random 4-char suffix for Google Pay shipping rate ID workaround. */
export function randomSuffix(): string {
  return Math.random().toString(36).slice(2, 6);
}

/**
 * P0-4 (PRD FR-040): 服务端权威 Express 支付负载（CartSerializer#express_payment）。
 *   amount/currency = 资金权威（order.amount_due 子单位）
 *   display_total   = 展示
 *   line_items      = 仅供钱包/UI 展示（不得据此重算扣款金额）
 */
export interface ExpressPaymentPayload {
  amount: number;
  currency: string;
  display_total: string | null;
  line_items: Array<{ name: string; amount: number }>;
}

/** 服务端权威金额（子单位）；payload 缺失返回 null。 */
export function serverAmount(cart: Cart): number | null {
  return cart.express_payment?.amount ?? null;
}

/**
 * Express 展示行项目：优先服务端 line_items（子单位、展示级）；
 * payload 缺失（旧数据 / 无 express 支付能力的实体）退回 legacy buildLineItems。
 */
export function expressLineItems(
  cart: Cart,
): Array<{ name: string; amount: number }> {
  if (cart.express_payment) {
    return cart.express_payment.line_items;
  }
  return buildLineItems(cart);
}

/**
 * 喂给 Stripe Elements / 钱包的权威金额。
 * 优先服务端 express_payment.amount；缺失时退回 legacy 加总（保持兼容）。
 * FR-041：存在服务端负载时**禁止**用 sum(line_items) 决定金额。
 */
export function expressAmount(cart: Cart): number {
  if (cart.express_payment) {
    return cart.express_payment.amount;
  }
  return buildLineItems(cart).reduce((sum, item) => sum + item.amount, 0);
}

/**
 * Build the line items array for the Stripe payment sheet from a PallasTrade order.
 * NOTE: Shipping is excluded because the Express Checkout Element handles it
 * separately via shippingRates. Including it here would cause the line item
 * total to exceed the Elements amount, triggering an IntegrationError.
 *
 * P0-4 (PRD FR-041): 仅作 legacy/fallback 展示来源；有 express_payment 时请用
 * expressLineItems（服务端展示行）。不要用本函数的结果重算权威金额。
 */
export function buildLineItems(order: Cart) {
  const currency = order.currency;
  const items: Array<{ name: string; amount: number }> = [];

  const itemTotal =
    order.item_total != null ? toCents(order.item_total, currency) : 0;
  items.push({ name: "Subtotal", amount: itemTotal });

  const promoTotal =
    order.discount_total != null ? toCents(order.discount_total, currency) : 0;
  if (promoTotal < 0) {
    items.push({ name: "Discount", amount: promoTotal });
  }

  const additionalTaxTotal =
    order.additional_tax_total != null
      ? toCents(order.additional_tax_total, currency)
      : 0;
  if (additionalTaxTotal > 0) {
    items.push({ name: "Tax", amount: additionalTaxTotal });
  }

  return items;
}

/** Parse a Stripe name string (e.g. "John Doe") into first and last name. */
export function parseName(name: string): {
  firstname: string;
  lastname: string;
} {
  const parts = name.trim().split(/\s+/);
  if (parts.length <= 1) {
    return { firstname: parts[0] || "", lastname: "" };
  }
  return {
    firstname: parts.slice(0, -1).join(" "),
    lastname: parts[parts.length - 1],
  };
}

/** Build a PallasTrade-compatible address from Stripe address data. */
export function buildPallasTradeAddress(
  name: { firstname: string; lastname: string },
  address: {
    line1: string;
    line2: string | null;
    city: string;
    postal_code: string;
    country: string;
    state: string | null;
  },
  phone?: string,
) {
  return {
    first_name: name.firstname,
    last_name: name.lastname,
    address1: address.line1,
    address2: address.line2 || undefined,
    city: address.city,
    postal_code: address.postal_code,
    country_iso: address.country,
    state_name: address.state || undefined,
    phone: phone || undefined,
  };
}

interface ShippingRateMapping {
  /** Stripe-formatted rates for the payment sheet */
  shippingRates: Array<{ id: string; displayName: string; amount: number }>;
  /** Maps Stripe rate ID → [ { fulfillmentId, rateId } ] for selectDeliveryRate */
  selectionMap: Map<string, Array<{ fulfillmentId: string; rateId: string }>>;
}

/**
 * Build Stripe shipping rates and a selection map from PallasTrade fulfillments.
 * Deduplicates by delivery_method_id. For Google Pay, appends a random suffix
 * to each rate ID to work around its duplicate-ID rejection.
 */
export function buildShippingRateMap(
  shipments: Fulfillment[],
  isGooglePay: boolean,
  currency: string,
): ShippingRateMapping {
  const rateMap = new Map<
    string,
    { id: string; displayName: string; amount: number }
  >();
  const selectionMap = new Map<
    string,
    Array<{ fulfillmentId: string; rateId: string }>
  >();

  for (const shipment of shipments) {
    const rates = shipment.delivery_rates ?? [];

    for (const rate of rates) {
      const methodId = rate.delivery_method_id;

      if (!rateMap.has(methodId)) {
        const id = isGooglePay
          ? `${methodId}-${randomSuffix()}`
          : String(methodId);
        rateMap.set(methodId, {
          id,
          displayName: rate.name,
          amount: toCents(rate.cost, currency),
        });
        selectionMap.set(id, []);
      } else {
        // Accumulate shipping cost from additional fulfillments
        const existing = rateMap.get(methodId)!;
        existing.amount += toCents(rate.cost, currency);
      }
      const stripeId = rateMap.get(methodId)!.id;
      selectionMap.get(stripeId)!.push({
        fulfillmentId: shipment.id,
        rateId: rate.id,
      });
    }
  }

  return {
    shippingRates: Array.from(rateMap.values()),
    selectionMap,
  };
}
