import type {
  Order,
  PaymentCombination,
  PaymentSession,
} from "@pallastrade/sdk";
import { CircleAlert, CircleCheckBig, Clock3, XCircle } from "lucide-react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Button } from "@/components/ui/button";
import {
  getOrderForCheckout,
  getOrderPaymentSession,
} from "@/lib/data/order-payment";
import { getPaymentCombination } from "@/lib/data/payment-combination";

type ResultStatus = "success" | "failed" | "canceled" | "pending";

interface PaymentResultPageProps {
  params: Promise<{
    id: string;
    country: string;
    locale: string;
  }>;
  searchParams: Promise<{ session?: string }>;
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
  const { session: sessionId } = await searchParams;
  const t = await getTranslations("paymentResult");
  const basePath = `/${country}/${locale}`;

  let status: ResultStatus = "pending";
  let reference = id;
  let amount = "";
  let retryHref = `${basePath}/account/orders`;
  let found = false;

  if (id.startsWith("pcom_")) {
    const result = await getPaymentCombination(id);
    if (result.success) {
      const combination = result as PaymentCombination & { success: true };
      status = statusFromCombination(combination);
      amount = `${combination.amount} ${combination.currency}`;
      found = true;
    }
  } else {
    const order = await getOrderForCheckout(id);
    if (order) {
      const session = sessionId
        ? await getOrderPaymentSession(id, sessionId)
        : null;
      status = statusFromOrder(order, session);
      reference = order.number ? `#${order.number}` : id;
      amount = order.display_total ?? "";
      retryHref = `${basePath}/checkout/${order.id}`;
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

  const title = t(`${status}Title`);
  const description = t(`${status}Description`);

  return (
    <div className="mx-auto max-w-xl py-16 text-center">
      {status === "success" ? (
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

      <div className="flex flex-col justify-center gap-3 sm:flex-row">
        {status === "failed" || status === "canceled" ? (
          <Button asChild>
            <Link href={retryHref}>{t("retryPayment")}</Link>
          </Button>
        ) : null}
        {status === "pending" ? (
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
