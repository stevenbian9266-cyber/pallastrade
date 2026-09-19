"use client";

import {
  Elements,
  ExpressCheckoutElement,
  useElements,
  useStripe,
} from "@stripe/react-stripe-js";
import type { StripeExpressCheckoutElementConfirmEvent } from "@stripe/stripe-js";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import type {
  PaymentEntry,
  PaymentMethodWithEntries,
} from "@/components/checkout/PaymentSection";
import {
  expressErrorRoute,
  expressNoticeFor,
} from "@/lib/checkout/express-canonical";
import {
  expressPaymentMethodsFor,
  selectedWalletAvailability,
  WALLET_READY_TIMEOUT_MS,
  type WalletAvailability,
} from "@/lib/checkout/wallet-availability";
import {
  completeOrderPaymentSessionAndRedirectToResult,
  createOrderPaymentSession,
} from "@/lib/data/order-payment";
import {
  extractSessionClientSecret,
  getStripePromise,
  isStripeConfigured,
  type PaymentClientConfig,
  stripeLocaleFor,
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
  /** 钱包在该设备不可用（含原因）→ 父级可置灰入口 + 回落其它入口。 */
  onAvailabilityChange?: (result: WalletAvailability) => void;
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
      // D7 补口 3：**只认选中钱包那一个键**（点谁显示谁），未知不判死
      onAvailabilityChange?.(
        selectedWalletAvailability(
          entry.method_key,
          event.availablePaymentMethods,
        ),
      );
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
        options={{
          buttonHeight: 44,
          // D7 补口 3：点谁显示谁
          ...(expressPaymentMethodsFor(entry.method_key)
            ? { paymentMethods: expressPaymentMethodsFor(entry.method_key)! }
            : {}),
        }}
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
  const locale = useLocale();
  const [session, setSession] = useState<{
    id: string;
    clientSecret: string;
  } | null>(null);
  // D7 补口 3：三态可用性（unknown / available / unavailable + 原因）
  const [availability, setAvailability] = useState<WalletAvailability>({
    state: "unknown",
  });
  const [retryToken, setRetryToken] = useState(0);
  /** 元素是否已上报过设备能力（看门狗据此决定是否降级）。 */
  const availabilityReportedRef = useRef(false);
  const onAvailabilityChangeRef = useRef(onAvailabilityChange);
  onAvailabilityChangeRef.current = onAvailabilityChange;

  const handleAvailabilityChange = useCallback(
    (result: WalletAvailability) => {
      availabilityReportedRef.current = true;
      setAvailability(result);
      onAvailabilityChange?.(result);
    },
    [onAvailabilityChange],
  );

  // D7 补口 3（看门狗）：会话就绪、元素已挂载但**永不**上报（iframe 被中断 / 移动网络慢）
  // → 超时 = `unavailable(timeout)`（**可重试**，不判死）。
  // biome-ignore lint/correctness/useExhaustiveDependencies: retryToken 仅作触发器（重试后重新计时）
  useEffect(() => {
    if (!session || availabilityReportedRef.current) return;
    const timer = setTimeout(() => {
      if (availabilityReportedRef.current) return;
      const result: WalletAvailability = {
        state: "unavailable",
        reason: "timeout",
      };
      setAvailability(result);
      onAvailabilityChangeRef.current?.(result);
    }, WALLET_READY_TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, [session, retryToken]);

  const clientConfig: PaymentClientConfig | null = method.client_config ?? null;
  const stripeConfigured = isStripeConfigured(clientConfig);

  const unavailableNotice = (reason: string) => (
    <div
      data-testid="wallet-unavailable-notice"
      data-reason={reason}
      className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
    >
      <p>
        {reason === "timeout"
          ? t("walletRetryHint")
          : reason === "unsupported"
            ? t("walletUnsupported")
            : reason === "unconfigured"
              ? t("walletUnconfigured")
              : t("walletUnavailable")}
      </p>
      {reason !== "unsupported" && reason !== "unconfigured" ? (
        <button
          type="button"
          data-testid="wallet-retry"
          onClick={() => {
            setAvailability({ state: "unknown" });
            availabilityReportedRef.current = false;
            setSession(null);
            setRetryToken((token) => token + 1);
          }}
          className="mt-2 h-8 rounded-md border border-amber-300 bg-white px-3 text-xs font-medium text-amber-900 hover:bg-amber-100"
        >
          {t("walletRetry")}
        </button>
      ) : null}
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

  // 前台不支持该钱包 kind（如 paypal / shop_pay）→ 不建会话，直接说明行
  if (!expressPaymentMethodsFor(entry.method_key)) {
    return unavailableNotice("unsupported");
  }
  // 不可用（没配 Stripe / 探测为不可用）→ 显式状态，不返回 null。
  if (!stripeConfigured) return unavailableNotice("unconfigured");
  if (availability.state === "unavailable") {
    return unavailableNotice(availability.reason ?? "device");
  }

  if (session) {
    return (
      <Elements
        key={retryToken}
        stripe={getStripePromise(clientConfig)}
        options={{
          clientSecret: session.clientSecret,
          // PRD-20260919-payments-checkout-top-express-pay-locale FR-006：
          // Stripe 渲染面跟随站点语种。
          locale: stripeLocaleFor(locale),
        }}
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
