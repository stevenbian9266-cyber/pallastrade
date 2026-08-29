"use client";

import { Loader2, PackageCheck } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { use, useRef, useState } from "react";
import {
  StripePaymentForm,
  type StripePaymentFormHandle,
} from "@/components/checkout/StripePaymentForm";
import { Button } from "@/components/ui/button";
import {
  completeCombinationSession,
  getPaymentCombination,
} from "@/lib/data/payment-combination";
import { extractBasePath } from "@/lib/utils/path";

interface CombinedPaymentCheckoutProps {
  combinationId: string;
  country: string;
  locale: string;
}

/**
 * 合并支付收银台（P5, 2026-08-27，flag 灰度）。
 * 展示组合金额与成员订单，经 Stripe PaymentElement 确认支付后完成组合会话——
 * 后端 PaymentCombinations::Complete 先入账支付再逐个完成成员订单。
 * PALLAS-CUSTOM (2026-08-29, PRD-20260829-payments): 补渲染 Stripe Elements——
 * Checkout Session 必须由 PaymentElement 确认（此前只 complete 未确认，PI 迁移后无法扣款）。
 */
export function CombinedPaymentCheckout({
  combinationId,
  country,
  locale,
}: CombinedPaymentCheckoutProps) {
  const t = useTranslations("checkout");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [combination, setCombination] = useState<Awaited<
    ReturnType<typeof getPaymentCombination>
  > | null>(null);
  const [loaded, setLoaded] = useState(false);
  const loadedRef = useRef(false);
  const gatewayRef = useRef<StripePaymentFormHandle | null>(null);

  // Load the combination once on mount (client-side, with JWT refresh)
  if (!loadedRef.current && !loaded) {
    loadedRef.current = true;
    getPaymentCombination(combinationId)
      .then(setCombination)
      .catch(() => setError(t("paymentError")))
      .finally(() => setLoaded(true));
  }

  async function handleConfirm() {
    if (!combination || "error" in combination) return;
    const session = combination.payment_session;
    if (!session?.order_id || !session?.id) {
      setError(t("paymentError"));
      setProcessing(false);
      return;
    }
    setProcessing(true);
    setError(null);

    // Confirm the Checkout Session via the PaymentElement first (the session
    // must be confirmed before the backend can complete the combination).
    if (gatewayRef.current) {
      const returnUrl = `${window.location.origin}${basePath}/confirm-payment/${session.order_id}?session=${session.id}`;
      const confirm = await gatewayRef.current.confirmPayment(returnUrl);
      if (confirm.error) {
        setError(confirm.error);
        setProcessing(false);
        return;
      }
    }

    const result = await completeCombinationSession(
      session.order_id,
      session.id,
    );
    if ("error" in result) {
      setError(result.error);
      setProcessing(false);
      return;
    }
    router.replace(`${basePath}/account/orders`);
  }

  if (!loaded) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    );
  }

  if (!combination || "error" in combination) {
    const message =
      combination && "error" in combination
        ? combination.error
        : t("paymentError");
    return <div className="text-center py-24 text-gray-500">{message}</div>;
  }

  const combo = combination;

  return (
    <div className="mx-auto max-w-lg space-y-6 py-10">
      <div className="flex items-center gap-3">
        <PackageCheck className="h-6 w-6 text-gray-600" />
        <h1 className="text-xl font-medium text-gray-900">
          {t("combinedPayment")}
        </h1>
      </div>

      <div className="rounded-xl border border-gray-200 bg-white p-6">
        <dl className="space-y-3 text-sm">
          <div className="flex justify-between">
            <dt className="text-gray-500">{t("total")}</dt>
            <dd className="font-medium text-gray-900">
              {combo.amount} {combo.currency}
            </dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-gray-500">{t("paymentStatus")}</dt>
            <dd className="text-gray-900">{combo.status}</dd>
          </div>
        </dl>
      </div>

      {error ? (
        <p className="text-sm text-red-600" role="alert">
          {error}
        </p>
      ) : null}

      {/* Stripe PaymentElement — confirms the combined-payment Checkout Session */}
      {(() => {
        const session = combo.payment_session;
        const secret = session?.external_data?.client_secret as
          | string
          | undefined;
        return secret ? (
          <div className="rounded-xl border border-gray-200 bg-white p-6">
            <StripePaymentForm
              clientSecret={secret}
              onReady={(handle) => {
                gatewayRef.current = handle;
              }}
            />
          </div>
        ) : null;
      })()}

      <Button
        onClick={handleConfirm}
        disabled={processing}
        className="w-full"
        size="lg"
      >
        {processing ? (
          <>
            <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            {t("processing")}
          </>
        ) : (
          t("payNow")
        )}
      </Button>
    </div>
  );
}
