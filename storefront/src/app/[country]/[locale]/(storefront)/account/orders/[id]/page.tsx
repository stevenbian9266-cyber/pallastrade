import Link from "next/link";
import { connection } from "next/server";
import { getTranslations } from "next-intl/server";
import { OrderDetail } from "@/components/account/OrderDetail";
import { getOrder } from "@/lib/data/orders";

interface OrderDetailPageProps {
  params: Promise<{
    country: string;
    locale: string;
    id: string;
  }>;
}

export default async function OrderDetailPage({
  params,
}: OrderDetailPageProps) {
  await connection();
  const { country, locale, id } = await params;
  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "orders",
  });
  const basePath = `/${country}/${locale}`;
  const order = await getOrder(id);

  // PRD-20260919-checkout-express-always-visible-and-pi-params FR-004 / AC-005：
  // 「未支付」不是「不存在」。旧条件把 `completed_at === null`（待支付订单 —— 列表里
  // 明明有、点进去却 404）当成找不到；只有**真取不到订单**才是 not found。
  // 未支付订单照常渲染详情（含 `OrderDetail` 内的 Pay Now 补付入口）。
  if (!order) {
    return (
      <div className="text-center py-12">
        <h2 className="text-xl font-medium text-gray-900 mb-2">
          {t("orderNotFound")}
        </h2>
        <p className="text-gray-500 mb-6">{t("orderNotFoundDescription")}</p>
        <Link
          href={`${basePath}/account/orders`}
          className="text-primary hover:text-primary font-medium"
        >
          {t("backToOrders")}
        </Link>
      </div>
    );
  }

  return <OrderDetail order={order} basePath={basePath} locale={locale} />;
}
