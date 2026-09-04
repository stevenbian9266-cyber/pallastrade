"use client";

import {
  CardCvcElement,
  CardExpiryElement,
  CardNumberElement,
  Elements,
  useElements,
  useStripe,
} from "@stripe/react-stripe-js";
import { Loader2, Lock } from "lucide-react";
import { useTranslations } from "next-intl";
import {
  forwardRef,
  useCallback,
  useEffect,
  useImperativeHandle,
  useRef,
  useState,
} from "react";
import { Input } from "@/components/ui/input";
import { stripePromise } from "@/lib/utils/stripe";

export interface CardPaymentFormHandle {
  /** 校验卡字段并用 Elements 卡号字段 confirmCardPayment(pi_secret)。 */
  confirmPayment: (clientSecret: string) => Promise<{ error?: string }>;
  /** 本地校验卡字段是否完整有效（供 Pay Now 前置禁用）。 */
  validate: () => boolean;
}

interface CardPaymentFormProps {
  /** 加载后回调 handle（父组件存 ref 供 Pay Now 调用）。 */
  onReady: (handle: CardPaymentFormHandle) => void;
}

/**
 * Stripe Elements 经典模式样式（三个独立卡字段共用）。
 * 注：iframe 内无法读取 CSS 变量，配色与 StripePaymentForm（PaymentElement
 * appearance）保持一致——`colorPrimary: #171717` 已在原组件使用。
 */
const cardElementOptions = {
  style: {
    base: {
      fontSize: "14px",
      color: "#171717",
      fontFamily: 'Geist, "Geist Fallback", system-ui, sans-serif',
      "::placeholder": { color: "#9ca3af" },
    },
  },
} as const;

/**
 * PALLAS-CUSTOM (2026-08-31, PRD-20260831-payments-stripe-自绘卡支付表单):
 * 自绘卡支付表单 — Stripe 经典 Elements 模式（CardNumber/CardExpiry/CardCvc
 * 三个独立字段，视觉上等同自绘卡号/有效期/CVC）。
 *
 * 替代 CheckoutProvider + PaymentElement（懒加载全量 iframe，需等后端返回
 * `cs_` client_secret 才能初始化；CN 网络下 js.stripe.com 初始化失败 →
 * 表单卡 "Loading payment form..." + 空购物车 bug）。
 *
 * 关键差异：
 * - Elements 经典模式只需 **publishable key**（stripePromise）即可**立即渲染**，
 *   不依赖 client_secret / 后端 Checkout Session；
 * - 点 Pay Now 才提交订单 + 创建 PaymentIntent 会话（pi_..._secret）→
 *   confirmCardPayment 完成支付。
 *
 * PCI 合规：Stripe.js v8 已移除原始卡字段（自绘 HTML input 会暴露卡号，破坏
 * SAQ-A）——经典 Elements 是 Stripe 官方支持的自定义卡表单，卡数据经 Stripe.js
 * 加密直传 Stripe，不经过本服务器/日志/DB。
 */
export const CardPaymentForm = forwardRef<
  CardPaymentFormHandle,
  CardPaymentFormProps
>(function CardPaymentForm({ onReady }, ref) {
  return (
    <Elements stripe={stripePromise}>
      <CardPaymentFormInner onReady={onReady} ref={ref} />
    </Elements>
  );
});

const CardPaymentFormInner = forwardRef<
  CardPaymentFormHandle,
  CardPaymentFormProps
>(function CardPaymentFormInner({ onReady }, ref) {
  const t = useTranslations("checkout");
  const stripe = useStripe();
  const elements = useElements();
  const [cardholderName, setCardholderName] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const completeRef = useRef({ number: false, expiry: false, cvc: false });

  const validate = useCallback((): boolean => {
    const { number, expiry, cvc } = completeRef.current;
    if (!stripe || !elements || !number || !expiry || !cvc) {
      setError(t("invalidCardDetails"));
      return false;
    }
    // PRD 3.6：持卡人姓名为空 → 提示必填
    if (!cardholderName.trim()) {
      setError(t("cardholderRequired"));
      return false;
    }
    setError(null);
    return true;
  }, [stripe, elements, cardholderName, t]);

  const confirmPayment = useCallback(
    async (clientSecret: string): Promise<{ error?: string }> => {
      setSubmitting(true);
      setError(null);
      try {
        if (!stripe || !elements) {
          const msg = t("stripeNotLoaded");
          setError(msg);
          return { error: msg };
        }
        if (!validate()) return { error: t("invalidCardDetails") };

        const cardElement = elements.getElement(CardNumberElement);
        if (!cardElement) {
          const msg = t("stripeNotLoaded");
          setError(msg);
          return { error: msg };
        }

        // 确认 PaymentIntent（pi_..._secret）；卡数据由 Elements 加密直传 Stripe
        const result = await stripe.confirmCardPayment(clientSecret, {
          payment_method: {
            card: cardElement,
            ...(cardholderName.trim()
              ? { billing_details: { name: cardholderName.trim() } }
              : {}),
          },
        });

        if (result.error) {
          setError(result.error.message ?? t("paymentError"));
          return { error: result.error.message ?? t("paymentError") };
        }

        return {};
      } finally {
        setSubmitting(false);
      }
    },
    [stripe, elements, cardholderName, t, validate],
  );

  useImperativeHandle(ref, () => ({ confirmPayment, validate }), [
    confirmPayment,
    validate,
  ]);

  useEffect(() => {
    onReady({ confirmPayment, validate });
  }, [onReady, confirmPayment, validate]);

  return (
    <div className="space-y-3" data-testid="card-payment-form">
      {/* PRD 3.6：支付渠道图标展示（VISA / MasterCard / AMEX，纯装饰） */}
      <div
        className="flex items-center gap-2"
        data-testid="card-brand-badges"
        aria-hidden="true"
      >
        <strong className="rounded border border-blue-700 px-1.5 py-0.5 text-[11px] font-bold italic text-blue-700">
          VISA
        </strong>
        <span className="flex items-center gap-0.5">
          <span className="h-3.5 w-3.5 rounded-full bg-red-500" />
          <span className="h-3.5 w-3.5 -ml-1.5 rounded-full bg-amber-400" />
        </span>
        <strong className="rounded border border-sky-700 px-1.5 py-0.5 text-[11px] font-bold text-sky-700">
          AMEX
        </strong>
      </div>

      <div>
        <label
          htmlFor="card-number"
          className="mb-1 block text-sm font-medium text-gray-700"
        >
          {t("cardNumber")}
        </label>
        <div
          className="rounded-md border border-gray-300 bg-white px-3 py-2.5 focus-within:border-indigo-400 focus-within:ring-2 focus-within:ring-indigo-100"
          data-testid="card-number"
        >
          <CardNumberElement
            options={{ ...cardElementOptions, showIcon: true }}
            onChange={(e) => (completeRef.current.number = e.complete)}
          />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div>
          <label
            htmlFor="card-expiry"
            className="mb-1 block text-sm font-medium text-gray-700"
          >
            {t("cardExpiryLabel")}
          </label>
          <div
            className="rounded-md border border-gray-300 bg-white px-3 py-2.5 focus-within:border-indigo-400 focus-within:ring-2 focus-within:ring-indigo-100"
            data-testid="card-expiry"
          >
            <CardExpiryElement
              options={cardElementOptions}
              onChange={(e) => (completeRef.current.expiry = e.complete)}
            />
          </div>
        </div>
        <div>
          <label
            htmlFor="card-cvc"
            className="mb-1 block text-sm font-medium text-gray-700"
          >
            {t("cardCvc")}
          </label>
          <div
            className="rounded-md border border-gray-300 bg-white px-3 py-2.5 focus-within:border-indigo-400 focus-within:ring-2 focus-within:ring-indigo-100"
            data-testid="card-cvc"
          >
            <CardCvcElement
              options={cardElementOptions}
              onChange={(e) => (completeRef.current.cvc = e.complete)}
            />
          </div>
        </div>
      </div>

      <div>
        <label
          htmlFor="cardholder-name"
          className="mb-1 block text-sm font-medium text-gray-700"
        >
          {t("cardholderName")}
        </label>
        <Input
          id="cardholder-name"
          autoComplete="cc-name"
          placeholder={t("cardholderNamePlaceholder")}
          value={cardholderName}
          onChange={(e) => setCardholderName(e.target.value)}
          aria-label={t("cardholderName")}
          data-testid="cardholder-name"
        />
      </div>

      <p className="flex items-center gap-1.5 text-xs text-gray-500">
        <Lock className="h-3.5 w-3.5" />
        {t("secureTransactions")}
      </p>

      {submitting && (
        <p className="flex items-center gap-2 text-sm text-gray-500">
          <Loader2 className="h-4 w-4 animate-spin" />
          {t("processing")}
        </p>
      )}

      {error && (
        <p
          className="text-sm text-red-600"
          role="alert"
          data-testid="card-error"
        >
          {error}
        </p>
      )}
    </div>
  );
});
