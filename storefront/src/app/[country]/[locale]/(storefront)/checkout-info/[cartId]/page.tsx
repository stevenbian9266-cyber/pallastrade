import type { Country } from "@pallastrade/sdk";
import { redirect } from "next/navigation";
import { getCountries } from "@/lib/data/countries";
import { getShippingMethods, getShoppingCart } from "@/lib/data/shopping-cart";
import { CheckoutInfoContent } from "./CheckoutInfoContent";

interface CheckoutInfoPageProps {
  params: Promise<{
    cartId: string;
    country: string;
    locale: string;
  }>;
}

/**
 * 订单流程标准电商改造 P1（2026-08-30）：订单确认页（收件信息 + 物流方式 + 预览 + 提交订单）。
 * 提交后 → /checkout/[orderId]（Checkout 纯支付）。
 */
export default async function CheckoutInfoPage({
  params,
}: CheckoutInfoPageProps) {
  const { cartId, country, locale } = await params;

  const [cart, shippingMethods, countries] = await Promise.all([
    getShoppingCart(cartId),
    getShippingMethods(),
    getCountries(),
  ]);

  if (!cart || cart.items.length === 0) {
    redirect(`/${country}/${locale}/cart`);
  }

  return (
    <CheckoutInfoContent
      cart={cart}
      shippingMethods={shippingMethods}
      countries={countries?.data ?? []}
    />
  );
}
