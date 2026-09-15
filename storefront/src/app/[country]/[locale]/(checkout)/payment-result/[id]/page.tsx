import type {
  Order,
  PaymentCombination,
  PaymentSession,
} from "@pallastrade/sdk";
import { CircleAlert, CircleCheckBig, Clock3, XCircle } from "lucide-react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { AddressBlock } from "@/components/order/AddressBlock";
import { ShippingGroups } from "@/components/order/ShippingGroups";
import { Button } from "@/components/ui/button";
import { isAuthenticated } from "@/lib/data/cookies";
import {
  getOrderForCheckout,
  getOrderPaymentSession,
} from "@/lib/data/order-payment";
import { getPaymentCombination } from "@/lib/data/payment-combination";
import { safeParseFloat } from "@/lib/utils/format";

type ResultStatus = "success" | "failed" | "canceled" | "pending";

interface PaymentResultPageProps {
  params: Promise<{
    id: string;
    country: string;
    locale: string;
  }>;
  searchParams: Promise<{ session?: string; notice?: string }>;
}

function statusFromSession(session: PaymentSession | null): ResultStatus {
  if (!session) return "pending";
  if (session.status === "failed" || session.status === "expired") {
    return "failed";
  }
  if (session.status === "canceled") return "canceled";
  return "pending";
}

function statusFromCombination(combination: PaymentCombination): ResultStatus {
  if (combination.status === "succeeded") return "success";
  if (combination.status === "failed" || combination.status === "expired") {
    return "failed";
  }
  if (combination.status === "canceled") return "canceled";
  return "pending";
}

function statusFromOrder(
  order: Order,
  session: PaymentSession | null,
): ResultStatus {
  if (
    order.payment_status === "paid" ||
    order.state === "paid" ||
    order.state === "complete" ||
    order.state === "completed"
  ) {
    return "success";
  }
  return statusFromSession(session);
}

export default async function PaymentResultPage({
  params,
  searchParams,
}: PaymentResultPageProps) {
  const { id, country, locale } = await params;
  const { session: sessionId, notice } = await searchParams;
  const t = await getTranslations("paymentResult");
  const basePath = `/${country}/${locale}`;

  let status: ResultStatus = "pending";
  let reference = id;
  let amount = "";
  let retryHref = `${basePath}/account/orders`;
  let found = false;
  let order: Order | null = null;

  if (id.startsWith("pcom_")) {
    const result = await getPaymentCombination(id);
    if (result.success) {
      const combination = result as PaymentCombination & { success: true };
      status = statusFromCombination(combination);
      amount = `${combination.amount} ${combination.currency}`;
      found = true;
    }
  } else {
    const orderData = await getOrderForCheckout(id);
    if (orderData) {
      const session = sessionId
        ? await getOrderPaymentSession(id, sessionId)
        : null;
      status = statusFromOrder(orderData, session);
      reference = orderData.number ? `#${orderData.number}` : id;
      amount = orderData.display_total ?? "";
      retryHref = `${basePath}/checkout/${orderData.id}`;
      order = orderData;
      found = true;
    }
  }

  if (!found) {
    return (
      <div className="mx-auto max-w-xl py-16 text-center">
        <CircleAlert className="mx-auto mb-4 h-14 w-14 text-red-500" />
        <h1 className="mb-3 text-2xl font-bold text-gray-900">
          {t("notFoundTitle")}
        </h1>
        <p className="mb-8 text-gray-500">{t("notFoundDescription")}</p>
        <Button asChild>
          <Link href={`${basePath}/products`}>{t("continueShopping")}</Link>
        </Button>
      </div>
    );
  }

  // PRD-20260913-checkout-txn-error-routing FR-004/FR-005 AC-005/AC-006：
  // 恢复/处理中 notice 覆盖展示文案，并抑制重试入口（防重复支付）。
  const forcedNotice =
    notice === "recovery" || notice === "processing" ? notice : null;
  const title =
    forcedNotice === "recovery"
      ? t("recoveryTitle")
      : forcedNotice === "processing"
        ? t("processingNoticeTitle")
        : t(`${status}Title`);
  const description =
    forcedNotice === "recovery"
      ? t("recoveryDescription")
      : forcedNotice === "processing"
        ? t("processingNoticeDescription")
        : t(`${status}Description`);

  const tOrder = await getTranslations("order");
  // 方案 §37：履约信息对已找到的订单**所有状态**展示（用户 2026-09-15 决策）；
  // 非成功态用「订单内容」标题，绝不出现 “Order confirmed” 以免被误读。
  const isConfirmed = status === "success" && !forcedNotice;
  const hasSavings = order
    ? Math.abs(safeParseFloat(order.discount_total)) > 0
    : false;
  const orderHref = order
    ? `${basePath}/${(await isAuthenticated()) ? "account/orders" : "order-placed"}/${order.id}`
    : "";

  return (
    <div className="mx-auto max-w-xl py-16 text-center">
      {forcedNotice ? (
        <Clock3 className="mx-auto mb-4 h-16 w-16 text-blue-500" />
      ) : status === "success" ? (
        <CircleCheckBig className="mx-auto mb-4 h-16 w-16 text-green-500" />
      ) : status === "failed" ? (
        <CircleAlert className="mx-auto mb-4 h-16 w-16 text-red-500" />
      ) : status === "canceled" ? (
        <XCircle className="mx-auto mb-4 h-16 w-16 text-amber-500" />
      ) : (
        <Clock3 className="mx-auto mb-4 h-16 w-16 text-blue-500" />
      )}

      <h1 className="mb-3 text-2xl font-bold text-gray-900">{title}</h1>
      <p className="mb-8 text-gray-500">{description}</p>

      <dl className="mb-8 rounded-xl border border-gray-200 bg-white p-5 text-left">
        <div className="flex justify-between gap-4">
          <dt className="text-gray-500">{t("reference")}</dt>
          <dd className="font-medium text-gray-900">{reference}</dd>
        </div>
        {amount ? (
          <div className="mt-3 flex justify-between gap-4 border-t border-gray-100 pt-3">
            <dt className="text-gray-500">{t("amount")}</dt>
            <dd className="font-semibold text-gray-900">{amount}</dd>
          </div>
        ) : null}
      </dl>

      {/* 履约摘要（方案 §37）：产品组 / 发货去向 / 实付 / 促销节省。
          仅消费显式业务字段 —— transaction / reservation / payment session 标识
          一律不进入 DOM（AC-006）。 */}
      {order ? (
        <div
          className="mb-8 rounded-xl border border-gray-200 bg-white p-5 text-left"
          data-testid="order-summary"
        >
          {!isConfirmed ? (
            <p
              className="mb-3 text-sm font-semibold text-gray-900"
              data-testid="order-summary-heading"
            >
              {tOrder("orderContents")}
            </p>
          ) : null}

          {order.shipping_address ? (
            <div className="mb-4">
              <p className="text-xs font-medium tracking-wide text-gray-500 uppercase">
                {tOrder("shipTo")}
              </p>
              <div className="mt-1" data-testid="order-summary-ship-to">
                <AddressBlock address={order.shipping_address} />
              </div>
            </div>
          ) : null}

          {order.fulfillments && order.fulfillments.length > 0 ? (
            <div className="mb-4">
              <p className="text-xs font-medium tracking-wide text-gray-500 uppercase">
                {tOrder("delivery")}
              </p>
              <div className="mt-1" data-testid="order-summary-delivery">
                <ShippingGroups
                  items={order.items ?? []}
                  fulfillments={order.fulfillments}
                />
              </div>
            </div>
          ) : null}

          {order.items && order.items.length > 0 ? (
            <div className="mb-4">
              <p className="text-xs font-medium tracking-wide text-gray-500 uppercase">
                {tOrder("items")}
              </p>
              <ul className="mt-1 space-y-1">
                {order.items.map((item) => (
                  <li
                    key={item.id}
                    className="flex justify-between gap-4 text-sm text-gray-700"
                    data-testid="order-summary-item"
                  >
                    <span>
                      {item.name} · {tOrder("qty", { quantity: item.quantity })}
                    </span>
                    <span className="font-medium text-gray-900">
                      {item.display_total}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}

          <div className="space-y-2 border-t border-gray-100 pt-3">
            {order.display_total ? (
              <div
                className="flex justify-between text-sm"
                data-testid="order-summary-paid"
              >
                <span className="text-gray-500">{tOrder("paid")}</span>
                <span className="font-semibold text-gray-900">
                  {order.display_total}
                </span>
              </div>
            ) : null}
            {hasSavings ? (
              <div
                className="flex justify-between text-sm"
                data-testid="order-summary-savings"
              >
                <span className="text-gray-500">
                  {tOrder("promotionSavings")}
                </span>
                <span className="text-green-700">
                  {order.display_discount_total}
                </span>
              </div>
            ) : null}
          </div>

          <Button variant="outline" size="sm" className="mt-4" asChild>
            <Link href={orderHref} data-testid="view-order-link">
              {tOrder("viewOrder")}
            </Link>
          </Button>
        </div>
      ) : null}

      <div className="flex flex-col justify-center gap-3 sm:flex-row">
        {!forcedNotice && (status === "failed" || status === "canceled") ? (
          <Button asChild>
            <Link href={retryHref}>{t("retryPayment")}</Link>
          </Button>
        ) : null}
        {!forcedNotice && status === "pending" ? (
          <Button asChild>
            <Link
              href={`${basePath}/payment-result/${id}${sessionId ? `?session=${sessionId}` : ""}`}
            >
              {t("refreshStatus")}
            </Link>
          </Button>
        ) : null}
        <Button variant="outline" asChild>
          <Link href={`${basePath}/products`}>{t("continueShopping")}</Link>
        </Button>
      </div>
    </div>
  );
}
