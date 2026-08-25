"use client";

// PALLAS-CUSTOM: 公用收银台支付表单（PRD-20260824 FR-013）
// 从 CombinedPaymentContent 抽出的共享收银台组件：支付方式选择 → 创建 payment session
// → Stripe 表单 → 完成支付。单订单付款与多订单合并支付复用同一组件（payment group 语义，
// 单订单也走 1 订单支付组）。同时处理 Stripe 3DS 回跳（?session=）。
import type { PaymentMethod } from "@pallastrade/sdk";
import { CircleAlert, Loader2 } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  StripePaymentForm,
  type StripePaymentFormHandle,
} from "@/components/checkout/StripePaymentForm";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import {
  completeGroupPaymentSession,
  createGroupPaymentSession,
} from "@/lib/data/payment-groups";

interface GroupPaymentFormProps {
  groupId: string;
  basePath: string;
  paymentMethods: PaymentMethod[];
  /** 支付成功回调（由宿主展示成功态/跳转） */
  onPaid: () => void;
  /** 支付失败回调（可选，宿主可感知） */
  onError?: (error: string) => void;
}

export function GroupPaymentForm({
  groupId,
  basePath,
  paymentMethods,
  onPaid,
  onError,
}: GroupPaymentFormProps) {
  const t = useTranslations("combinedPayment");
  const tRef = useRef(t);
  tRef.current = t;
  const router = useRouter();
  const searchParams = useSearchParams();
  const [error, setError] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [selectedMethodId, setSelectedMethodId] = useState<string | null>(null);
  const stripeFormRef = useRef<StripePaymentFormHandle | null>(null);

  const stripeMethod =
    paymentMethods.find((pm) => pm.id === selectedMethodId) ?? null;

  // Stripe redirect-back (e.g. 3D Secure): `stripe.confirmPayment` with
  // `redirect: "if_required"` sends the browser to Stripe, then back to the
  // return_url with ?session=<sessionId>&redirect_status=... . After the reload
  // our local sessionId state is gone, so we read it from the URL and complete
  // the payment group here instead of leaving the customer stuck on the page.
  const redirectSessionId = searchParams.get("session");
  const redirectStatus = searchParams.get("redirect_status");
  const redirectHandledRef = useRef(false);

  useEffect(() => {
    if (!redirectSessionId || redirectHandledRef.current) return;
    redirectHandledRef.current = true;

    if (redirectStatus === "failed") {
      setError(tRef.current("payFailed"));
      onError?.(tRef.current("payFailed"));
      return;
    }

    (async () => {
      setProcessing(true);
      const complete = await completeGroupPaymentSession(
        groupId,
        redirectSessionId,
      );
      setProcessing(false);
      if (complete.success) {
        onPaid();
        router.replace(`${basePath}/account/combined-payment/${groupId}`);
      } else {
        const message = complete.error || tRef.current("payFailed");
        setError(message);
        onError?.(message);
      }
    })();
  }, [
    groupId,
    redirectSessionId,
    redirectStatus,
    basePath,
    router,
    onPaid,
    onError,
  ]);

  const startPayment = useCallback(async () => {
    if (!stripeMethod) return;
    setError(null);
    setProcessing(true);
    const result = await createGroupPaymentSession(groupId, stripeMethod.id);
    setProcessing(false);
    if (!result.success) {
      const message = result.error || tRef.current("payFailed");
      setError(message);
      onError?.(message);
      return;
    }
    const secret = result.session.external_data?.client_secret as
      | string
      | undefined;
    if (!secret) {
      const message = tRef.current("payFailed");
      setError(message);
      onError?.(message);
      return;
    }
    setClientSecret(secret);
    setSessionId(result.session.id);
  }, [groupId, stripeMethod, onError]);

  const confirmPayment = useCallback(async () => {
    if (!stripeFormRef.current || !sessionId) return;
    setProcessing(true);
    setError(null);

    const result = await stripeFormRef.current.confirmPayment(
      `${window.location.origin}${basePath}/account/combined-payment/${groupId}?session=${sessionId}`,
    );

    if (result.error) {
      setError(result.error);
      setProcessing(false);
      onError?.(result.error);
      return;
    }

    const complete = await completeGroupPaymentSession(groupId, sessionId);
    setProcessing(false);

    if (!complete.success) {
      const message = complete.error || tRef.current("payFailed");
      setError(message);
      onError?.(message);
      return;
    }
    onPaid();
  }, [basePath, groupId, sessionId, onPaid, onError]);

  return (
    <div className="bg-white rounded-xl border border-gray-200 p-6">
      {!clientSecret ? (
        <>
          <p className="text-sm text-gray-600 mb-4">
            {t("selectPaymentMethod")}
          </p>
          {paymentMethods.length > 0 ? (
            <>
              <RadioGroup
                value={selectedMethodId ?? ""}
                onValueChange={setSelectedMethodId}
                className="gap-2 mb-4"
                data-testid="combined-payment-methods"
              >
                {paymentMethods.map((pm) => (
                  <label
                    key={pm.id}
                    className="flex items-center gap-3 rounded-md border border-gray-200 px-4 py-3 cursor-pointer bg-white hover:bg-gray-50"
                  >
                    <RadioGroupItem value={pm.id} />
                    <span className="text-sm font-medium text-gray-900">
                      {pm.name}
                    </span>
                  </label>
                ))}
              </RadioGroup>
              <Button
                onClick={startPayment}
                disabled={!stripeMethod || processing}
                data-testid="start-combined-payment"
              >
                {processing && (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                )}
                {t("confirmPay")}
              </Button>
            </>
          ) : (
            <p className="text-sm text-gray-500">{t("noPaymentMethod")}</p>
          )}
        </>
      ) : (
        <>
          <StripePaymentForm
            clientSecret={clientSecret}
            onReady={(handle) => {
              stripeFormRef.current = handle;
            }}
          />
          <Button
            className="mt-4 w-full"
            onClick={confirmPayment}
            disabled={processing}
            data-testid="confirm-combined-payment"
          >
            {processing && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            {t("confirmPay")}
          </Button>
        </>
      )}

      {error && (
        <Alert variant="destructive" className="mt-4">
          <CircleAlert />
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
    </div>
  );
}
