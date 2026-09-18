"use client";

import {
  Elements,
  ExpressCheckoutElement,
  useElements,
  useStripe,
} from "@stripe/react-stripe-js";
import type { StripeExpressCheckoutElementConfirmEvent } from "@stripe/stripe-js";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import type {
  PaymentEntry,
  PaymentMethodWithEntries,
} from "@/components/checkout/PaymentSection";
import {
  expressErrorRoute,
  expressNoticeFor,
  WALLET_READY_TIMEOUT_MS,
} from "@/lib/checkout/express-canonical";
import {
  completeOrderPaymentSessionAndRedirectToResult,
  createOrderPaymentSession,
} from "@/lib/data/order-payment";
import {
  extractSessionClientSecret,
  getStripePromise,
  isStripeConfigured,
  type PaymentClientConfig,
} from "@/lib/utils/stripe";

/**
 * PALLAS-CUSTOM: D7（PRD-20260918-payments-d7-payment-section-express）—— FR-004 / AC-007
 *
 * or_ 订单页 · 钱包（Apple Pay / Google Pay）快捷支付：
 *
 *   选择钱包入口 → 创建 **PaymentIntent 模式**会话（带 `option_kind`）→
 *   挂载 `ExpressCheckoutElement`（client_secret）→ 确认 → 完成会话 → 结果页
 *
 * 与 cart 抽屉（`ExpressCheckoutButton`，cart 绑定 + `/api/checkout/start`）共用同一套
 * **错误落点**（`lib/checkout/express-canonical`）与**结果页路由** —— 不为钱包新增第二条流程。
 * 入口可用性仍然只由服务端决定：被拒（`payment_option_not_available`）→ 通知父级刷新列表。
 */

export interface WalletPaymentButtonsProps {
  orderId: string;
  basePath: string;
  /** 选中入口所属 provider（提供 `client_config` 下发的前台密钥）。 */
  method: PaymentMethodWithEntries;
  /** 选中的钱包入口（`method_key` = 钱包 kind，随会话下发做同源校验）。 */
  entry: PaymentEntry;
  /** 会话/确认过程中的忙状态（父级据此禁用页内 Pay 按钮）。 */
  onProcessingChange?: (processing: boolean) => void;
  /** 入口被服务端拒绝 → 父级刷新支付方式列表 + 提示重选。 */
  onUnavailable?: () => void;
  /** 钱包在该设备不可用（如未安装）→ 父级可回落其它入口。 */
  onAvailabilityChange?: (available: boolean) => void;
}

interface WalletInnerProps extends Omit<WalletPaymentButtonsProps, "method"> {
  clientSecret: string;
  sessionId: string;
  onDone: () => void;
}

function WalletInner({
  orderId,
  basePath,
  entry,
  clientSecret,
  sessionId,
  onProcessingChange,
  onUnavailable,
  onAvailabilityChange,
  onDone,
}: WalletInnerProps) {
  const stripe = useStripe();
  const elements = useElements();
  const processingRef = useRef(false);

  const setProcessing = useCallback(
    (value: boolean) => {
      processingRef.current = value;
      onProcessingChange?.(value);
    },
    [onProcessingChange],
  );

  const handleReady = useCallback(
    (event: { availablePaymentMethods?: Record<string, boolean> }) => {
      const methods = event.availablePaymentMethods;
      // 未给数据（undefined）= **未知**，不得当作不可用（与 ExpressCheckoutButton 一致）。
      if (methods === undefined) {
        onAvailabilityChange?.(true);
        return;
      }
      const isWallet = entry.method_key.startsWith("google")
        ? methods.googlePay === true
        : methods.applePay === true;
      onAvailabilityChange?.(isWallet);
    },
    [entry.method_key, onAvailabilityChange],
  );

  const handleConfirm = useCallback(
    async (_event: StripeExpressCheckoutElementConfirmEvent) => {
      if (!stripe || !elements || processingRef.current || !clientSecret)
        return;
      setProcessing(true);
      try {
        const result = await stripe.confirmPayment({
          elements,
          clientSecret,
          confirmParams: {
            return_url: `${basePath}/payment-result/${orderId}`,
          },
        });

        if (result.error) {
          toast.error(result.error.message ?? "Payment failed");
          return;
        }

        // 确认成功 → 完成会话 + 完成订单（server action 内重定向，确定性导航）
        await completeOrderPaymentSessionAndRedirectToResult(
          orderId,
          sessionId,
          basePath,
        );
      } catch (error) {
        toast.error(error instanceof Error ? error.message : "Payment failed");
      } finally {
        setProcessing(false);
        onDone();
      }
    },
    [
      basePath,
      clientSecret,
      elements,
      onDone,
      orderId,
      sessionId,
      setProcessing,
      stripe,
    ],
  );

  return (
    <div data-testid="wallet-payment-element">
      <ExpressCheckoutElement
        onReady={handleReady}
        onConfirm={handleConfirm}
        options={{ buttonHeight: 44 }}
      />
    </div>
  );
}

export function WalletPaymentButtons({
  orderId,
  basePath,
  method,
  entry,
  onProcessingChange,
  onUnavailable,
  onAvailabilityChange,
}: WalletPaymentButtonsProps) {
  const t = useTranslations("checkout");
  const [session, setSession] = useState<{
    id: string;
    clientSecret: string;
  } | null>(null);
  // D7 补口 2（2026-09-18）：本设备无该钱包（Stripe `availablePaymentMethods` 明确 false）
  // → 不再留空白：渲染显式说明，父级据此置灰入口 + 回落卡支付。
  const [walletUnavailable, setWalletUnavailable] = useState(false);
  /** D7 补口 2b：元素是否已上报过设备能力（看门狗据此决定是否降级）。 */
  const availabilityReportedRef = useRef(false);
  const onAvailabilityChangeRef = useRef(onAvailabilityChange);
  onAvailabilityChangeRef.current = onAvailabilityChange;

  const handleAvailabilityChange = useCallback(
    (available: boolean) => {
      availabilityReportedRef.current = true;
      setWalletUnavailable(!available);
      onAvailabilityChange?.(available);
    },
    [onAvailabilityChange],
  );

  // D7 补口 2b（看门狗）：会话就绪、元素已挂载但**永不**上报设备能力（iframe 被中断 /
  // 设备无钱包）→ 超时即降级，不给用户留一个无限加载的空槽位。
  useEffect(() => {
    if (!session || availabilityReportedRef.current) return;
    const timer = setTimeout(() => {
      if (availabilityReportedRef.current) return;
      setWalletUnavailable(true);
      onAvailabilityChangeRef.current?.(false);
    }, WALLET_READY_TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, [session]);

  const clientConfig: PaymentClientConfig | null = method.client_config ?? null;
  const stripeConfigured = isStripeConfigured(clientConfig);

  const unavailableNotice = (
    <div
      data-testid="wallet-unavailable-notice"
      className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
    >
      {t("walletUnavailable")}
    </div>
  );

  const handleStart = useCallback(async () => {
    onProcessingChange?.(true);
    try {
      const result = await createOrderPaymentSession(
        orderId,
        method.id,
        undefined,
        "payment_intent",
        { optionKind: entry.method_key },
      );

      if (!result.success) {
        // D8 既有约定：入口不可用 → 刷新列表 + 提示重选（不进入支付流程）
        if (result.code === "payment_option_not_available") {
          toast.error(result.error);
          onUnavailable?.();
          return;
        }
        // 已收款/处理中类错误 → 结果页（绝不能二次支付）
        const notice = expressNoticeFor(result.code);
        if (expressErrorRoute(result.code) === "recovery" && notice) {
          window.location.assign(
            `${basePath}/payment-result/${orderId}?notice=${notice}`,
          );
          return;
        }
        toast.error(result.error);
        return;
      }

      const secret = extractSessionClientSecret(result.session);
      if (!secret) {
        toast.error("Payment method did not produce a client secret");
        return;
      }

      setSession({ id: result.session.id, clientSecret: secret });
    } finally {
      onProcessingChange?.(false);
    }
  }, [
    basePath,
    entry.method_key,
    method.id,
    onProcessingChange,
    onUnavailable,
    orderId,
  ]);

  // 不可用（没配 Stripe 或本设备无该钱包）→ 显式状态，不返回 null。
  if (!stripeConfigured || walletUnavailable) return unavailableNotice;

  if (session) {
    return (
      <Elements
        stripe={getStripePromise(clientConfig)}
        options={{ clientSecret: session.clientSecret }}
      >
        <WalletInner
          orderId={orderId}
          basePath={basePath}
          entry={entry}
          clientSecret={session.clientSecret}
          sessionId={session.id}
          onProcessingChange={onProcessingChange}
          onUnavailable={onUnavailable}
          onAvailabilityChange={handleAvailabilityChange}
          onDone={() => setSession(null)}
        />
      </Elements>
    );
  }

  return (
    <button
      type="button"
      data-testid="wallet-pay-button"
      data-option-id={entry.option_id}
      onClick={handleStart}
      className="w-full h-11 rounded-lg bg-gray-900 text-white text-sm font-medium hover:bg-gray-800"
    >
      {entry.display_name}
    </button>
  );
}
