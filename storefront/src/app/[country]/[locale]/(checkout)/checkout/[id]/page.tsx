import type { Address, Cart, Country } from "@pallastrade/sdk";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { OrderPaymentContent } from "@/components/checkout/OrderPaymentContent";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";
import { getAddresses } from "@/lib/data/addresses";
import { getCheckoutOrder } from "@/lib/data/checkout";
import { isAuthenticated as checkAuth } from "@/lib/data/cookies";
import { getCountry } from "@/lib/data/countries";
import { getMarketCountries, resolveMarket } from "@/lib/data/markets";
import { getOrderForCheckout } from "@/lib/data/order-payment";
import { getShippingMethods } from "@/lib/data/shopping-cart";
import { setCartCookies } from "@/lib/pallastrade/cookies";

import { CheckoutPageContent } from "./CheckoutPageContent";

export interface CheckoutInitialData {
  cart: Cart;
  countries: Country[];
  savedAddresses: Address[];
  isAuthenticated: boolean;
}

interface CheckoutPageProps {
  params: Promise<{
    id: string;
    country: string;
    locale: string;
  }>;
  searchParams: Promise<{
    token?: string;
  }>;
}

async function CheckoutDataLoader({ params, searchParams }: CheckoutPageProps) {
  await connection();

  const { id: cartId, country: urlCountry, locale } = await params;
  const { token } = await searchParams;

  // P0-3 (2026-08-18): abandoned-cart recovery emails link here with ?token=…
  // so a returning visitor on a new device can re-attach to their cart.
  if (token) {
    await setCartCookies(cartId, token);
  }

  // 下单链路统一化（PRD-20260830-checkout）：新购物车（cart_ 前缀）→ 统一下单页
  // UnifiedCheckout（左右布局：地址/商品/物流/支付方式 + Pay Now 内联提交）。
  // 不再 redirect 到 checkout-info（独立确认页），也不再落入 legacy 一页式。
  if (cartId.startsWith("cart_")) {
    const [cartData, market, shippingMethods] = await Promise.all([
      getCheckoutOrder(cartId),
      resolveMarket(urlCountry).catch(() => null),
      getShippingMethods(),
    ]);
    if (!cartData || cartData.id !== cartId) {
      // 购物车不存在/已转换 → 回购物车页
      redirect(`/${urlCountry}/${locale}/cart`);
    }
    const countriesData = market
      ? await getMarketCountries(market.id).catch(() => ({
          data: [] as Country[],
        }))
      : { data: [] as Country[] };
    const defaultIso =
      cartData.shipping_address?.country_iso ?? countriesData.data[0]?.iso;
    if (defaultIso) {
      getCountry(defaultIso).catch(() => {});
    }
    return (
      <UnifiedCheckout
        cart={cartData as unknown as import("@pallastrade/sdk").ShoppingCart}
        shippingMethods={shippingMethods}
        countries={countriesData.data}
      />
    );
  }

  // Check auth first so we can skip address fetch for guests
  const authStatus = await checkAuth();

  // Fetch initial data in parallel during SSR
  const [cartData, market, addressesData] = await Promise.all([
    getCheckoutOrder(cartId),
    resolveMarket(urlCountry).catch(() => null),
    authStatus ? getAddresses() : Promise.resolve({ data: [] as Address[] }),
  ]);

  // 订单流程标准电商改造 P1（2026-08-30）：标准流程订单（or_ 前缀）→ 纯支付页。
  // 收货/物流已在 checkout-info 完成，这里只做支付。
  if (cartData?.id.startsWith("or_")) {
    const order = await getOrderForCheckout(cartId);
    if (order) {
      return <OrderPaymentContent order={order} />;
    }
    redirect(`/${urlCountry}/en`);
  }

  // Redirect to order-placed if already complete
  if (cartData?.current_step === "complete") {
    const basePath = `/${urlCountry}/en`;
    redirect(`${basePath}/order-placed/${cartId}`);
  }

  const countriesData = market
    ? await getMarketCountries(market.id).catch(() => ({
        data: [] as Country[],
      }))
    : { data: [] as Country[] };

  // Prefetch states for the default country (warms the server cache)
  const defaultIso =
    cartData?.shipping_address?.country_iso ?? countriesData.data[0]?.iso;
  if (defaultIso) {
    getCountry(defaultIso).catch(() => {});
  }

  const initialData: CheckoutInitialData | null = cartData
    ? {
        cart: cartData,
        countries: countriesData.data,
        savedAddresses: addressesData.data,
        isAuthenticated: authStatus,
      }
    : null;

  return (
    <CheckoutPageContent
      cartId={cartId}
      urlCountry={urlCountry}
      initialData={initialData}
    />
  );
}

export default function CheckoutPage({
  params,
  searchParams,
}: CheckoutPageProps) {
  return (
    <Suspense>
      <CheckoutDataLoader params={params} searchParams={searchParams} />
    </Suspense>
  );
}
