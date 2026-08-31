"use client";

import type {
  Order,
  PaymentCombination,
  PaymentMethod,
} from "@pallastrade/sdk";
import { CircleAlert, Loader2, Wallet } from "lucide-react";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { StripePaymentFormHandle } from "@/components/checkout/StripePaymentForm";
import { StripePaymentForm } from "@/components/checkout/StripePaymentForm";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  completeOrder,
  completeOrderPaymentSession,
  createOrderPaymentSession,
} from "@/lib/data/order-payment";
import {
  completeCombinationSession,
  createPaymentCombination,
  getPaymentCombination,
} from "@/lib/data/payment-combination";

interface PaymentCheckoutModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** 待支付订单：1 笔 → 单笔弹窗；2+ 笔 → 合并支付弹窗 */
  orders: Order[];
  basePath: string;
}

/**
 * 下单链路统一化（PRD-20260830-checkout，场景 C）：收银台弹窗 — 仅支付方式相关信息。
 * - 单笔（AC-005）：直接以该订单支付（Orders::PaymentSessions 会话）。
 * - 多笔（AC-006）：先 createPaymentCombination → 组合总金额 + 各单分摊 → 支付
 *   （PaymentCombinations::Complete 幂等链路）。不提供逐单收货地址编辑（AC-006）。
 * 复用 StripePaymentForm（与 OrderPaymentContent / CombinedPaymentCheckout 同一支付组件）。
 */
export function PaymentCheckoutModal({
  open,
  onOpenChange,
  orders,
  basePath,
}: PaymentCheckoutModalProps) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const router = useRouter();

  const isSingle = orders.length === 1;
  const singleOrder = isSingle ? orders[0] : null;

  // 支付方式：单笔取订单自身；组合取成员订单首个
  const availableMethods: PaymentMethod[] = useMemo(
    () => singleOrder?.payment_methods ?? orders[0]?.payment_methods ?? [],
    [singleOrder, orders],
  );

  const [selectedMethodId, setSelectedMethodId] = useState("");
  const selectedMethod =
    availableMethods.find((m) => m.id === selectedMethodId) ??
    availableMethods[0];

  const [stripeSecret, setStripeSecret] = useState<string | null>(null);
  const [stripeSessionId, setStripeSessionId] = useState<string | null>(null);
  const [combination, setCombination] = useState<PaymentCombination | null>(
    null,
  );
  const [loading, setLoading] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const stripeRef = useRef<StripePaymentFormHandle | null>(null);
  const requestIdRef = useRef(0);

  // 打开弹窗 → 重置状态 + 预选支付方式
  useEffect(() => {
    if (!open) return;
    const first =
      availableMethods.find((m) => m.session_required)?.id ??
      availableMethods[0]?.id ??
      "";
    setSelectedMethodId(first);
    setStripeSecret(null);
    setStripeSessionId(null);
    setCombination(null);
    setError(null);
    setProcessing(false);
    setLoading(true);
  }, [open, availableMethods]);

  const createStripeSession = useCallback(
    async (method: PaymentMethod) => {
      if (!singleOrder) return;
      const requestId = ++requestIdRef.current;
      setLoading(true);
      setError(null);
      setStripeSecret(null);
      setStripeSessionId(null);
      stripeRef.current = null;
      const result = await createOrderPaymentSession(singleOrder.id, method.id);
      if (requestId !== requestIdRef.current) return;
      if (result.success && result.session) {
        const session = result.session as {
          id: string;
          external_data?: Record<string, unknown>;
        };
        setStripeSessionId(session.id);
        // client_secret 位于 external_data 且 URL 编码（%2F）→ 解码后传给 Stripe
        const secret = session.external_data?.client_secret as
          | string
          | undefined;
        const stripeSecret = secret ? decodeURIComponent(secret) : undefined;
        if (stripeSecret) {
          setStripeSecret(stripeSecret);
        } else {
          setError(t("failedToInitPayment"));
        }
      } else {
        const message = "error" in result ? result.error : undefined;
        setError(message || t("failedToCreateSession"));
      }
      setLoading(false);
    },
    [singleOrder, t],
  );

  // 单笔：打开/切换方式 → 创建订单支付会话（session-based）
  useEffect(() => {
    if (!open || !isSingle || !singleOrder || !selectedMethod) return;
    if (!selectedMethod.session_required) {
      // 非 session（Check/COD/银行转账）：无需在线会话
      setStripeSecret(null);
      setStripeSessionId(null);
      setLoading(false);
      return;
    }
    createStripeSession(selectedMethod);
  }, [open, isSingle, singleOrder, selectedMethod, createStripeSession]);

  // 组合：打开/切换方式 → 创建支付组合并加载（含 payment_session + 成员订单）
  useEffect(() => {
    if (!open || isSingle) return;
    if (!selectedMethod) return;
    const requestId = ++requestIdRef.current;
    setLoading(true);
    setError(null);
    setCombination(null);
    stripeRef.current = null;
    const orderIds = orders.map((o) => o.id);
    (async () => {
      const created = await createPaymentCombination(
        orderIds,
        selectedMethod.id || undefined,
      );
      if (requestId !== requestIdRef.current) return;
      if ("error" in created) {
        setError(created.error);
        setLoading(false);
        return;
      }
      const combo = await getPaymentCombination(created.combination.id);
      if (requestId !== requestIdRef.current) return;
      if ("error" in combo) {
        setError(combo.error);
        setLoading(false);
        return;
      }
      setCombination(combo as PaymentCombination);
      // 组合支付会话的 client_secret → 渲染 StripePaymentForm
      const secret = (combo as PaymentCombination).payment_session
        ?.external_data?.client_secret as string | undefined;
      setStripeSecret(secret ?? null);
      setLoading(false);
    })();
  }, [open, isSingle, orders, selectedMethod]);

  const handleStripeReady = useCallback((handle: StripePaymentFormHandle) => {
    stripeRef.current = handle;
  }, []);

  const handlePay = async () => {
    if (!selectedMethod || processing) return;
    setProcessing(true);
    setError(null);
    try {
      if (isSingle && singleOrder) {
        // 单笔
        if (selectedMethod.session_required) {
          if (!stripeRef.current || !stripeSessionId) {
            setError(t("failedToInitPayment"));
            setProcessing(false);
            return;
          }
          const returnUrl = `${window.location.origin}${basePath}/order-placed/${singleOrder.id}`;
          const result = await stripeRef.current.confirmPayment(returnUrl);
          if (result.error) {
            setError(result.error);
            setProcessing(false);
            return;
          }
          await completeOrderPaymentSession(singleOrder.id, stripeSessionId);
          await completeOrder(singleOrder.id);
        }
        // 非 session 支付方式：无在线支付（线下收款），订单保持 pending
        onSuccess();
        return;
      }

      // 组合
      const session = combination?.payment_session;
      if (!session?.order_id || !session?.id) {
        setError(t("paymentError"));
        setProcessing(false);
        return;
      }
      if (stripeRef.current) {
        const returnUrl = `${window.location.origin}${basePath}/confirm-payment/${session.order_id}?session=${session.id}`;
        const result = await stripeRef.current.confirmPayment(returnUrl);
        if (result.error) {
          setError(result.error);
          setProcessing(false);
          return;
        }
      }
      await completeCombinationSession(session.order_id, session.id);
      onSuccess();
    } catch (e) {
      setError(e instanceof Error ? e.message : t("paymentError"));
      setProcessing(false);
    }
  };

  const onSuccess = () => {
    onOpenChange(false);
    router.refresh();
  };

  const comboOrders = combination?.orders ?? [];
  const canPay =
    !!selectedMethod &&
    (isSingle ? true : !!combination) &&
    (isSingle
      ? !selectedMethod.session_required ||
        (!!stripeSecret && !!stripeSessionId)
      : !!combination?.payment_session);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Wallet className="h-4 w-4 text-gray-500" />
            {isSingle ? t("payment") : t("combinedPayment")}
          </DialogTitle>
        </DialogHeader>

        {/* 应付金额 */}
        <div className="flex items-center justify-between rounded-xl border border-gray-200 bg-gray-50 px-4 py-3">
          <span className="text-sm text-gray-500">{tc("amountDue")}</span>
          <span className="text-lg font-bold text-gray-900">
            {isSingle && singleOrder
              ? singleOrder.display_amount_due
              : combination
                ? `${combination.amount} ${combination.currency}`
                : "—"}
          </span>
        </div>

        {/* 组合分摊 */}
        {!isSingle && comboOrders.length > 0 && (
          <div className="space-y-1 rounded-xl border border-gray-200 p-3">
            {comboOrders.map((order) => (
              <div
                key={order.id}
                className="flex items-center justify-between text-sm"
              >
                <span className="text-gray-500">
                  {t("orderNumber", { number: order.number })}
                </span>
                <span className="font-medium text-gray-900">
                  {order.display_total}
                </span>
              </div>
            ))}
          </div>
        )}

        {/* 支付方式 radio */}
        {availableMethods.length > 0 ? (
          <div className="flex flex-col gap-2">
            {availableMethods.map((method) => (
              <label
                key={method.id}
                className="flex cursor-pointer items-center gap-3 rounded-lg border border-gray-200 p-3 hover:border-indigo-300"
              >
                <input
                  type="radio"
                  name="modal-payment-method"
                  checked={selectedMethodId === method.id}
                  onChange={() => setSelectedMethodId(method.id ?? "")}
                  className="h-4 w-4 text-indigo-600 focus:ring-indigo-500"
                />
                <span className="font-medium text-gray-900">{method.name}</span>
              </label>
            ))}
          </div>
        ) : (
          <div className="rounded-sm border border-gray-200 bg-gray-50 px-4 py-8 text-center text-sm text-gray-500">
            {t("noPaymentMethods")}
          </div>
        )}

        {/* 支付表单 / loading / 错误 */}
        {error ? (
          <div className="flex items-center gap-2 rounded-sm border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
            <CircleAlert className="h-4 w-4 shrink-0" />
            {error}
          </div>
        ) : null}

        {loading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
          </div>
        ) : null}

        {!loading && stripeSecret ? (
          <StripePaymentForm
            clientSecret={stripeSecret}
            onReady={handleStripeReady}
          />
        ) : null}

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={processing}
          >
            {tc("cancel")}
          </Button>
          <Button onClick={handlePay} disabled={!canPay || processing}>
            {processing ? (
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
            ) : null}
            {isSingle && selectedMethod?.session_required && stripeSecret
              ? t("confirmPayment")
              : t("payNow")}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
