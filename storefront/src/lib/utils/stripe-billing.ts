import type { AddressFormData } from "@/lib/utils/address";

/**
 * PRD-20260919-checkout-billing-details-passthrough（第 4 项二期）：
 * 账单详情 → Stripe `billing_details` 的**唯一映射点**。
 *
 * 口径（与后端 `Carts::Update#validate_billing_address!` 一致）：
 * - 最小完整集 = `line1` + `city` + `postal_code` + `country`；
 * - 不完整 → 返回 `null`，调用方**整体不发**该字段（宁可不发，也不把半空
 *   地址送给 Stripe 触发 AVS 误判）；服务端 `BillingDetailsPresenter` 同口径。
 */

/** Stripe 地址形状（取自钱包事件 / 表单，字段可空）。 */
export interface StripeAddressLike {
  line1?: string | null;
  line2?: string | null;
  city?: string | null;
  state?: string | null;
  postal_code?: string | null;
  country?: string | null;
}

/** Stripe `billing_details`（PaymentMethod / PaymentIntent 通用）。 */
export interface StripeBillingDetails {
  name?: string;
  email?: string;
  phone?: string;
  address: {
    line1: string;
    line2?: string;
    city: string;
    state?: string;
    postal_code: string;
    country: string;
  };
}

function cleaned(value: string | null | undefined): string | undefined {
  const trimmed = (value ?? "").trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

/** 账单地址最小完整集判定（line1 + city + postal_code + country）。 */
export function isCompleteBillingAddress(
  address: StripeAddressLike | null | undefined,
): boolean {
  if (!address) return false;
  return Boolean(
    cleaned(address.line1) &&
      cleaned(address.city) &&
      cleaned(address.postal_code) &&
      cleaned(address.country),
  );
}

function stripeAddress(
  address: StripeAddressLike,
): StripeBillingDetails["address"] {
  return {
    line1: cleaned(address.line1) ?? "",
    city: cleaned(address.city) ?? "",
    postal_code: cleaned(address.postal_code) ?? "",
    country: cleaned(address.country) ?? "",
    ...(cleaned(address.line2) ? { line2: cleaned(address.line2) } : {}),
    ...(cleaned(address.state) ? { state: cleaned(address.state) } : {}),
  };
}

/** 结算页表单态（同配送 / 自定义）→ Stripe `billing_details`；不完整 → null。 */
export function billingDetailsFromFormData(
  form: AddressFormData,
): StripeBillingDetails | null {
  const address: StripeAddressLike = {
    line1: form.address1,
    line2: form.address2,
    city: form.city,
    state: form.state_abbr || form.state_name,
    postal_code: form.postal_code,
    country: form.country_iso,
  };
  if (!isCompleteBillingAddress(address)) return null;
  return { address: stripeAddress(address) };
}

/** 钱包（ExpressCheckoutElement）返回的 `billingDetails` → Stripe `billing_details`。 */
export function billingDetailsFromWallet(
  wallet:
    | {
        name?: string | null;
        email?: string | null;
        phone?: string | null;
        address?: StripeAddressLike | null;
      }
    | null
    | undefined,
): StripeBillingDetails | null {
  if (!wallet || !isCompleteBillingAddress(wallet.address)) return null;
  const name = cleaned(wallet.name);
  const email = cleaned(wallet.email);
  const phone = cleaned(wallet.phone);
  return {
    ...(name ? { name } : {}),
    ...(email ? { email } : {}),
    ...(phone ? { phone } : {}),
    address: stripeAddress(wallet.address ?? {}),
  };
}
