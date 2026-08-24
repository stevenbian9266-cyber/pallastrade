import { ShoppingBag } from "lucide-react";
import Link from "next/link";
import { connection } from "next/server";
import { getTranslations } from "next-intl/server";
import { CombinedPaymentPicker } from "@/components/account/CombinedPaymentPicker";
import { OrderList } from "@/components/account/OrderList";
import {
  type OrderStatusKey,
  OrderStatusTabs,
} from "@/components/account/OrderStatusTabs";
import { Button } from "@/components/ui/button";
import { getOrders, getUnpaidOrders } from "@/lib/data/orders";

interface OrdersPageProps {
  params: Promise<{ country: string; locale: string }>;
  searchParams: Promise<{ status?: string }>;
}

export const ORDER_STATUS_TABS: Array<{
  key: OrderStatusKey;
  scope: string;
  i18nKey: string;
}> = [
  { key: "all", scope: "all", i18nKey: "tabAll" },
  { key: "unpaid", scope: "unpaid", i18nKey: "tabUnpaid" },
  { key: "processing", scope: "processing", i18nKey: "tabProcessing" },
  { key: "shipped", scope: "shipped", i18nKey: "tabShipped" },
  { key: "completed", scope: "complete", i18nKey: "tabCompleted" },
  { key: "canceled", scope: "canceled", i18nKey: "tabCanceled" },
];

export default async function OrdersPage({
  params,
  searchParams,
}: OrdersPageProps) {
  await connection();
  const { country, locale } = await params;
  const { status } = await searchParams;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "orders",
  });
  const basePath = `/${country}/${locale}`;

  const activeTab =
    ORDER_STATUS_TABS.find((s) => s.key === status) ?? ORDER_STATUS_TABS[0];

  // PALLAS-CUSTOM: 状态选项卡（PRD-20260824-checkout-订单列表状态选项卡）—
  // 按 scope 拉取对应状态订单；待支付订单始终用于合并支付区块。
  const [response, unpaidResponse] = await Promise.all([
    getOrders({ limit: 50, scope: activeTab.scope }),
    getUnpaidOrders(50),
  ]);
  const orders = response.data;
  const unpaidOrders = unpaidResponse.data;

  const showCombinedPicker =
    activeTab.key === "all" || activeTab.key === "unpaid";

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">
        {t("orderHistory")}
      </h1>

      <OrderStatusTabs
        tabs={ORDER_STATUS_TABS.map((s) => ({
          key: s.key,
          label: t(s.i18nKey),
        }))}
        activeKey={activeTab.key}
        basePath={basePath}
      />

      {/* PALLAS-CUSTOM: 待支付订单合并/单独支付入口 */}
      {showCombinedPicker && (
        <CombinedPaymentPicker orders={unpaidOrders} basePath={basePath} />
      )}

      {orders.length === 0 ? (
        <div className="bg-white rounded-xl border border-gray-200 p-12 text-center">
          <ShoppingBag className="w-12 h-12 text-gray-400 mx-auto mb-4" />
          <h3 className="text-lg font-medium text-gray-900 mb-2">
            {t("noOrders")}
          </h3>
          <p className="text-gray-500 mb-6">{t("noOrdersDescription")}</p>
          <Button asChild>
            <Link href={`${basePath}/products`}>{t("startShopping")}</Link>
          </Button>
        </div>
      ) : (
        <OrderList orders={orders} basePath={basePath} locale={locale} />
      )}
    </div>
  );
}
