import { CircleAlert } from "lucide-react";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";
import { getPendingCheckoutOrderId } from "@/lib/pallastrade";

interface OrdersRecentPageProps {
  params: Promise<{ country: string; locale: string }>;
}

/**
 * PRD-20260920-checkout-订单可见性补齐 FR-004（AC-008 / AC-009 / AC-010）。
 *
 * 无需登录的「最近一笔订单」恢复入口 —— 解决游客下单后**没有稳定入口回来**的问题
 * （`/account/orders` 按 `user_id` 作用域且要求登录，游客订单永不入列）。
 *
 * 授权**只**来自服务端写入的 HttpOnly checkout cookie
 * （`_pallastrade_checkout_order` + `_pallastrade_checkout_token`，见 `setCheckoutCookies`）。
 * 本页**绝不**读取任何请求参数来指定订单 id —— 否则就是一个订单号枚举接口。
 *
 * 已知限制（PRD §1.4 非目标 / 硬约束 C-4）：cookie 是**单值**，只能恢复**最近一笔**；
 * 也**不**引入 email 回溯关联。空态与「订单不存在」在此不可区分（不泄露存在性）。
 */
export default async function OrdersRecentPage({
  params,
}: OrdersRecentPageProps) {
  const { country, locale } = await params;
  const basePath = `/${country}/${locale}`;
  const orderId = await getPendingCheckoutOrderId();

  // 只接受本店订单前缀（`or_`）；其它任何形状（空 / 篡改 / 旧格式）一律按空态处理。
  if (orderId?.startsWith("or_")) {
    redirect(`${basePath}/payment-result/${orderId}`);
  }

  const t = await getTranslations({
    locale: locale as Locale,
    namespace: "orders",
  });

  return (
    <div className="mx-auto max-w-xl py-16 text-center">
      <CircleAlert className="mx-auto mb-4 h-14 w-14 text-gray-400" />
      <h1 className="mb-3 text-2xl font-bold text-gray-900">
        {t("noRecentOrderTitle")}
      </h1>
      <p className="mb-8 text-gray-500">{t("noRecentOrderDescription")}</p>
      <Button asChild>
        <Link
          href={`${basePath}/cart`}
          data-testid="orders-recent-back-to-cart"
        >
          {t("backToCart")}
        </Link>
      </Button>
    </div>
  );
}
