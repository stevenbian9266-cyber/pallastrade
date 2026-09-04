import type { Country } from "@pallastrade/sdk";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { Suspense } from "react";
import { OrderPaymentContent } from "@/components/checkout/OrderPaymentContent";
import { UnifiedCheckout } from "@/components/checkout/UnifiedCheckout";
import { getCheckoutOrder } from "@/lib/data/checkout";
import { isAuthenticated as checkAuth } from "@/lib/data/cookies";
import { getCountry } from "@/lib/data/countries";
import { getMarketCountries, resolveMarket } from "@/lib/data/markets";
import { getOrderCheckout } from "@/lib/data/order-checkout";
import { getOrderForCheckout } from "@/lib/data/order-payment";
import { getShippingMethods } from "@/lib/data/shopping-cart";

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

  // E 场景（邮件订单回流补付，P0-3 2026-08-18）：弃单/待支付邮件链接携带
  // ?token= 让新设备重新绑定购物车。token 写入 HttpOnly cookie 由 src/proxy.ts
  // 处理（Server Component 渲染期间不允许写 cookie，Next.js 16 限制）；
  // proxy 会从 URL 移除 token 后再进入本页，因此这里不再读取 searchParams。
  void searchParams;

  // 下单链路统一化（PRD-20260830-checkout）：新购物车（cart_ 前缀）→ 统一下单页
  // UnifiedCheckout（左右布局：地址/商品/物流/支付方式 + Pay Now 内联提交）。
  // 不再 redirect 到 checkout-info（独立确认页），也不再落入 legacy 一页式。
  if (cartId.startsWith("cart_")) {
    const [cartData, market, shippingMethods, authStatus] = await Promise.all([
      getCheckoutOrder(cartId),
      resolveMarket(urlCountry).catch(() => null),
      getShippingMethods(),
      checkAuth(),
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
        isAuthenticated={authStatus}
      />
    );
  }

  // 订单流程标准电商改造 P1（2026-08-30）：标准流程订单（or_ 前缀）→ 纯支付页。
  // 收货/物流已在 checkout-info 完成，这里只做支付。
  // CHK-P1-4：并行取服务端 CheckoutView（只读投影）——支付页金额/商品/就绪态
  // 以投影为准；view 缺失时回退 Order 快照（投影是增强，不阻塞支付页）。
  // CHK-P1-4B：同时解析市场国家列表供 or_ 页内联地址编辑。
  const cartData = await getCheckoutOrder(cartId);
  if (cartData?.id.startsWith("or_")) {
    const [order, view, market] = await Promise.all([
      getOrderForCheckout(cartId),
      getOrderCheckout(cartId),
      resolveMarket(urlCountry).catch(() => null),
    ]);
    const countriesData = market
      ? await getMarketCountries(market.id).catch(() => ({
          data: [] as Country[],
        }))
      : { data: [] as Country[] };
    if (order) {
      return (
        <OrderPaymentContent
          order={order}
          view={view}
          countries={countriesData.data}
        />
      );
    }
  }

  // CHK-P1-4C4 (2026-09-04)：legacy 一页式支付页已退役。
  // cart_（UnifiedCheckout）与 or_（OrderPaymentContent）覆盖全部有效 id——
  // 后端对存量整数 id 兼容解析且序列化恒 or_ 前缀，故无前缀/不可解析 id
  // 一律回首页（不再落入 legacy 一页式兜底）。
  redirect(`/${urlCountry}/${locale}`);
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
