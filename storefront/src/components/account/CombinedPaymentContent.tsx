"use client";

import type { PaymentGroup, PaymentMethod } from "@pallastrade/sdk";
import { CircleAlert, Loader2, ShieldCheck } from "lucide-react";
import Link from "next/link";
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
  getPaymentGroup,
} from "@/lib/data/payment-groups";
import { getPaymentMethods } from "@/lib/data/payment-methods";

/**
 * PALLAS-CUSTOM: 多订单合并支付（PRD-20260823-checkout-多订单拆分与合并支付）
 * Renders the combined payment page: order list + total, then a Stripe
 * Elements form for one payment covering all orders in the group.
 */
interface CombinedPaymentContentProps {
  groupId: string;
  basePath: string;
}

export function CombinedPaymentContent({
  groupId,
  basePath,
}: CombinedPaymentContentProps) {
  const t = useTranslations("combinedPayment");
  // PALLAS-CUSTOM: 修复无限请求循环（2026-08-24）— next-intl 的 useTranslations
  // 返回的 t 引用不稳定，若放进 useEffect/useCallback 依赖会导致每次 setState
  // 重渲染后 effect 重跑 → 反复调用 server action（getPaymentGroup/getPaymentMethods）
  // → 无限请求。改用 ref 持有 t，副作用依赖只保留真实数据源。
  const tRef = useRef(t);
  tRef.current = t;
  const router = useRouter();
  const searchParams = useSearchParams();
  const [group, setGroup] = useState<PaymentGroup | null>(null);
  const [paymentMethods, setPaymentMethods] = useState<PaymentMethod[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);
  const [paid, setPaid] = useState(false);
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [selectedMethodId, setSelectedMethodId] = useState<string | null>(null);
  const stripeFormRef = useRef<StripePaymentFormHandle | null>(null);
  const loadedRef = useRef(false);

  useEffect(() => {
    if (loadedRef.current) return;
    loadedRef.current = true;
    let cancelled = false;
    (async () => {
      const [groupResult, methodsResult] = await Promise.all([
        getPaymentGroup(groupId, { expand: ["orders"] }),
        getPaymentMethods(),
      ]);
      if (cancelled) return;
      if (!groupResult.success) {
        setError(groupResult.error || tRef.current("loadFailed"));
        return;
      }
      setGroup(groupResult.group);
      setPaymentMethods(methodsResult);
    })();
    return () => {
      cancelled = true;
    };
  }, [groupId]);

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
        setPaid(true);
        router.replace(`${basePath}/account/combined-payment/${groupId}`);
      } else {
        setError(complete.error || tRef.current("payFailed"));
      }
    })();
  }, [groupId, redirectSessionId, redirectStatus, basePath, router]);

  const orders = group?.orders ?? [];

  const total = orders.reduce((sum: number, order) => {
    return sum + (parseFloat(order.total ?? "0") || 0);
  }, 0);

  // PALLAS-CUSTOM: 收银台选择支付方式（PRD-20260824-checkout-订单列表状态选项卡）—
  // 用户先选择支付方式，确认后再创建 payment session 显示 Stripe 表单。
  const stripeMethod =
    paymentMethods.find((pm) => pm.id === selectedMethodId) ?? null;

  const startPayment = useCallback(async () => {
    if (!stripeMethod) return;
    setError(null);
    setProcessing(true);
    const result = await createGroupPaymentSession(groupId, stripeMethod.id);
    setProcessing(false);
    if (!result.success) {
      setError(result.error || tRef.current("payFailed"));
      return;
    }
    const secret = result.session.external_data?.client_secret as
      | string
      | undefined;
    if (!secret) {
      setError(tRef.current("payFailed"));
      return;
    }
    setClientSecret(secret);
    setSessionId(result.session.id);
  }, [groupId, stripeMethod]);

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
      return;
    }

    const complete = await completeGroupPaymentSession(groupId, sessionId);
    setProcessing(false);

    if (!complete.success) {
      setError(complete.error || tRef.current("payFailed"));
      return;
    }
    setPaid(true);
  }, [basePath, groupId, sessionId]);

  if (paid) {
    return (
      <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
        <ShieldCheck className="w-12 h-12 text-green-600 mx-auto mb-4" />
        <h2 className="text-xl font-medium text-gray-900 mb-2">
          {t("paymentSuccess")}
        </h2>
        <p className="text-gray-500 mb-6">{t("paymentSuccessDescription")}</p>
        <Button asChild>
          <Link href={`${basePath}/account/orders`}>{t("backToOrders")}</Link>
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Order summary */}
      <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h2 className="font-medium text-gray-900">{t("orders")}</h2>
        </div>
        <ul className="divide-y divide-gray-100">
          {orders.map((order) => (
            <li
              key={order.id}
              className="px-6 py-3 flex items-center justify-between text-sm"
            >
              <span className="font-medium text-gray-900">#{order.number}</span>
              <span className="text-gray-500">
                {order.currency} {order.total}
              </span>
            </li>
          ))}
        </ul>
        <div className="px-6 py-4 bg-gray-50 flex items-center justify-between">
          <span className="font-medium text-gray-900">{t("total")}</span>
          <span className="font-bold text-gray-900">
            {group?.currency} {total.toFixed(2)}
          </span>
        </div>
      </div>

      {/* Payment */}
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
    </div>
  );
}
