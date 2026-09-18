"use client";

import type { Cart } from "@pallastrade/sdk";
import {
  Elements,
  ExpressCheckoutElement,
  useElements,
  useStripe,
} from "@stripe/react-stripe-js";
import type {
  StripeExpressCheckoutElementClickEvent,
  StripeExpressCheckoutElementConfirmEvent,
  StripeExpressCheckoutElementReadyEvent,
  StripeExpressCheckoutElementShippingAddressChangeEvent,
  StripeExpressCheckoutElementShippingRateChangeEvent,
} from "@stripe/stripe-js";
import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  completeExpressCheckout,
  expressClientSecret,
  expressErrorRoute,
  expressNoticeFor,
  expressResultUrl,
  startExpressCheckout,
  WALLET_READY_TIMEOUT_MS,
} from "@/lib/checkout/express-canonical";
import {
  expressCheckoutResolveShipping,
  expressCheckoutSelectRates,
} from "@/lib/data/express-checkout-flow";
import {
  buildPallasTradeAddress,
  buildShippingRateMap,
  expressAmount,
  expressLineItems,
  parseName,
} from "@/lib/utils/express-checkout";
import {
  getStripePromise,
  isStripeConfigured,
  type PaymentClientConfig,
} from "@/lib/utils/stripe";

export interface ExpressCheckoutButtonProps {
  cart: Cart;
  basePath: string;
  onComplete: () => void | Promise<void>;
  onProcessingChange?: (processing: boolean) => void;
  onAvailabilityChange?: (available: boolean) => void;
  maxColumns?: number;
  showDivider?: boolean;
  /** PALLAS-CUSTOM: D10 —— 服务端下发的 client_config（缺省回落环境变量）。 */
  clientConfig?: PaymentClientConfig | null;
}

function ExpressCheckoutInner({
  cart,
  basePath,
  onComplete,
  onProcessingChange,
  onAvailabilityChange,
  maxColumns = 1,
  showDivider = true,
}: ExpressCheckoutButtonProps) {
  const stripe = useStripe();
  const elements = useElements();
  const router = useRouter();
  const t = useTranslations("expressCheckout");
  // D7 补口 2：降级说明属于结账页文案（与 PaymentSection / WalletPaymentButtons 同命名空间）
  const tCheckout = useTranslations("checkout");
  const [available, setAvailable] = useState<boolean | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);
  const isConfirmingRef = useRef(false);
  const isGooglePayRef = useRef(false);
  const shippingRateMapRef = useRef(
    new Map<string, Array<{ fulfillmentId: string; rateId: string }>>(),
  );
  const onProcessingChangeRef = useRef(onProcessingChange);
  onProcessingChangeRef.current = onProcessingChange;
  const onAvailabilityChangeRef = useRef(onAvailabilityChange);
  onAvailabilityChangeRef.current = onAvailabilityChange;
  /** D7 补口 2b：元素是否已上报过设备能力（看门狗据此决定是否降级）。 */
  const availabilityReportedRef = useRef(false);

  const updateProcessing = useCallback((value: boolean) => {
    setProcessing(value);
    onProcessingChangeRef.current?.(value);
  }, []);

  // P0-4 (PRD FR-040/041): 金额唯一来自服务端 express_payment.amount（order.amount_due 子单位），
  // 不同步 Elements 时会显示与实收不一致。随 cart（地址/运费/优惠变化）同步，不重挂载。
  const elementsAmount = useMemo(() => expressAmount(cart), [cart]);

  useEffect(() => {
    if (!elements) return;
    try {
      elements.update({ amount: elementsAmount });
    } catch (_) {
      /* non-fatal */
    }
  }, [elements, elementsAmount]);

  const handleReady = useCallback(
    (event: StripeExpressCheckoutElementReadyEvent) => {
      availabilityReportedRef.current = true;
      const methods = event.availablePaymentMethods;
      // 未给数据（undefined）= **未知**，不得当作不可用：元素已挂载，Stripe 自己不会
      // 渲染设备用不了的钱包按钮。只有明确的全 false 才走降级（D7 补口 2）。
      if (methods === undefined) {
        setAvailable(true);
        onAvailabilityChangeRef.current?.(true);
        return;
      }
      const isAvailable = Boolean(
        methods.applePay || methods.googlePay || methods.link,
      );
      setAvailable(isAvailable);
      onAvailabilityChangeRef.current?.(isAvailable);
    },
    [],
  );

  const handleClick = useCallback(
    (event: StripeExpressCheckoutElementClickEvent) => {
      isGooglePayRef.current = event.expressPaymentType === "google_pay";
      event.resolve({
        lineItems: expressLineItems(cart),
      });
    },
    [cart],
  );

  // D7 补口 2b（看门狗）：元素可能**永不**上报设备能力（Stripe iframe 被中断 / 设备无钱包）
  // —— 只等回调会留下无限加载态；超时即按「本设备不可用」降级（说明 + 置灰 + 回落卡支付）。
  useEffect(() => {
    if (available !== null || availabilityReportedRef.current) return;
    const timer = setTimeout(() => {
      if (availabilityReportedRef.current) return;
      setAvailable(false);
      onAvailabilityChangeRef.current?.(false);
    }, WALLET_READY_TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, [available]);

  const handleShippingAddressChange = useCallback(
    async (event: StripeExpressCheckoutElementShippingAddressChangeEvent) => {
      try {
        const { address } = event;
        const result = await expressCheckoutResolveShipping(cart.id, {
          city: address.city,
          postal_code: address.postal_code,
          country_iso: address.country,
          state_name: address.state || undefined,
        });

        if (!result.success) {
          event.reject();
          return;
        }

        const order = result.cart;

        const { shippingRates, selectionMap } = buildShippingRateMap(
          order.fulfillments || [],
          isGooglePayRef.current,
          order.currency,
        );
        shippingRateMapRef.current = selectionMap;

        if (shippingRates.length === 0) {
          event.reject();
          return;
        }

        // P0-4: 行项目与金额均来自服务端（express_payment）。运费由 shippingRates
        // 展示；rate 选定后经 shippingratechange → selectRates 服务端入账，amount 更新。
        if (!elements) throw new Error("Elements not available");
        elements.update({ amount: expressAmount(order) });

        event.resolve({ shippingRates, lineItems: expressLineItems(order) });
      } catch (err) {
        console.error("[ExpressCheckout] shipping address error:", err);
        try {
          event.reject();
        } catch (_) {
          /* already resolved/rejected */
        }
      }
    },
    [cart.id, elements],
  );

  const handleShippingRateChange = useCallback(
    async (event: StripeExpressCheckoutElementShippingRateChangeEvent) => {
      try {
        const { shippingRate } = event;

        const selections = shippingRateMapRef.current.get(shippingRate.id);
        if (!selections || selections.length === 0) {
          event.reject();
          return;
        }

        const result = await expressCheckoutSelectRates(cart.id, selections);
        if (!result.success) {
          event.reject();
          return;
        }

        // P0-4: rate 已由服务端选定（selectDeliveryRate）→ cart.amount_due 已含该运费。
        // 金额取服务端权威 express_payment.amount；shipping 行仅作钱包展示（不参与金额合计）。
        const lineItems = [
          ...expressLineItems(result.cart),
          { name: t("shipping"), amount: shippingRate.amount },
        ];

        if (!elements) throw new Error("Elements not available");
        elements.update({ amount: expressAmount(result.cart) });

        event.resolve({ lineItems });
      } catch (_err) {
        try {
          event.reject();
        } catch (_) {
          /* already resolved/rejected */
        }
      }
    },
    [cart.id, elements, t],
  );

  const handleConfirm = useCallback(
    async (event: StripeExpressCheckoutElementConfirmEvent) => {
      if (isConfirmingRef.current) return;

      if (!stripe || !elements) {
        event.paymentFailed({ reason: "fail" });
        return;
      }

      isConfirmingRef.current = true;
      const orderId = cart.id;
      setError(null);
      updateProcessing(true);

      let stripePaymentConfirmed = false;

      const fail = (
        reason:
          | "fail"
          | "invalid_shipping_address"
          | "invalid_billing_address"
          | "invalid_payment_data"
          | "address_unserviceable",
        msg: string,
      ) => {
        if (!stripePaymentConfirmed) {
          event.paymentFailed({ reason });
        }
        setError(msg);
        updateProcessing(false);
        isConfirmingRef.current = false;
      };

      try {
        const billing = event.billingDetails;
        const shipping = event.shippingAddress;
        const email = billing?.email || "";
        const phone = billing?.phone || "";

        const shippingName = parseName(shipping?.name || billing?.name || "");
        const billingName = parseName(billing?.name || shipping?.name || "");

        const shipAddr = shipping?.address || billing?.address;
        const billAddr = billing?.address || shipping?.address;

        if (!shipAddr || !billAddr) {
          fail("invalid_shipping_address", "Missing address");
          return;
        }

        const submitResult = await elements.submit();
        if (submitResult.error) {
          fail(
            "fail",
            submitResult.error.message || "Payment submission failed",
          );
          return;
        }

        const sessionPaymentMethod = cart.payment_methods?.find(
          (pm) => pm.session_required,
        );
        if (!sessionPaymentMethod) {
          fail("fail", "No payment method available");
          return;
        }

        // PRD-20260915-checkout B4 FR-001：地址/邮箱并入 canonical start body；
        // BFF 内部完成 carts.update → 幂等 submit → orders.transactions.create
        // （Transactions::Start → StockReserve → PaymentSessions::Start）。
        const startResult = await startExpressCheckout({
          cart_id: cart.id,
          payment_method_id: sessionPaymentMethod.id,
          payment_mode: "payment_intent",
          checkout: {
            email: email || undefined,
            shipping_address: buildPallasTradeAddress(
              shippingName,
              shipAddr,
              phone,
            ),
            billing_address: buildPallasTradeAddress(
              billingName,
              billAddr,
              phone,
            ),
            billing_mode: "custom",
          },
        });

        if (!startResult.ok) {
          // FR-005：已收款/处理中 → 结果页（禁止重付）；其余 canonical 错误 → 抽屉内提示。
          if (expressErrorRoute(startResult.error.code) === "recovery") {
            stripePaymentConfirmed = true; // 已发生资金事实：不得再报 paymentFailed
            const notice = expressNoticeFor(startResult.error.code);
            router.push(
              `${expressResultUrl(window.location.origin, basePath, orderId)}?notice=${notice ?? "recovery"}`,
            );
            return;
          }
          fail("fail", startResult.error.message);
          return;
        }

        const canonicalOrderId = startResult.data.order.id;
        const session = startResult.data.session;
        const clientSecret = expressClientSecret(session);
        const sessionId = session?.id ?? null;

        if (!sessionId || !clientSecret) {
          fail("fail", "Failed to initialize payment");
          return;
        }

        // FR-004：return_url 指向 canonical 结果页（不再进 legacy /confirm-payment）
        const returnUrl = expressResultUrl(
          window.location.origin,
          basePath,
          canonicalOrderId,
          sessionId,
        );
        const { error: confirmError } = await stripe.confirmPayment({
          elements,
          clientSecret,
          confirmParams: { return_url: returnUrl },
          redirect: "if_required",
        });

        if (confirmError) {
          fail("fail", confirmError.message || "Payment confirmation failed");
          return;
        }
        stripePaymentConfirmed = true;

        // FR-003/FR-007：best-effort 驱动服务端完成（失败不阻塞，webhook 兜底）
        await completeExpressCheckout(canonicalOrderId, sessionId);

        router.push(returnUrl);
        try {
          await onComplete();
        } catch (_onCompleteErr) {
          /* onComplete failed — non-blocking, navigation already fired */
        } finally {
          isConfirmingRef.current = false;
        }
      } catch (err) {
        const msg =
          err instanceof Error ? err.message : "An unexpected error occurred";
        fail("fail", msg);
      }
    },
    [
      stripe,
      elements,
      cart.id,
      cart.payment_methods,
      basePath,
      onComplete,
      router,
      updateProcessing,
    ],
  );

  const handleCancel = useCallback(() => {
    // No-op: placeholder address on cart doesn't persist to address book
    // and will be overwritten by next checkout attempt.
  }, []);

  // D7 补口 2（2026-09-18）：**不得静默消失**。本设备无可用钱包时保留一个显式说明块，
  // 父级已接 `onAvailabilityChange` → 自动回落到卡支付并置灰该入口（见 UnifiedCheckout /
  // OrderPaymentContent）；未接的调用方（cart 抽屉）也能看到原因而不是空白。
  if (available === false) {
    return (
      <div
        data-testid="wallet-unavailable-notice"
        className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
      >
        {tCheckout("walletUnavailable")}
      </div>
    );
  }

  return (
    <div className="w-full">
      {/* Shared container — smoothly transitions between buttons and finalizing state */}
      <div className="relative overflow-hidden">
        {/* Finalizing overlay — fades in on top of the button area */}
        <div
          className={`absolute inset-0 z-10 flex flex-col items-center justify-center transition-opacity duration-500 ease-out ${
            processing ? "opacity-100" : "opacity-0 pointer-events-none"
          }`}
        >
          <div className="w-10 h-10 border-4 border-primary-600 border-t-transparent rounded-full animate-spin" />
          <p className="mt-4 text-sm font-medium text-gray-700">
            {t("finalizingPayment")}
          </p>
        </div>

        {/* Buttons area — min-h keeps space, content fades out when processing */}
        <div className="relative min-h-12">
          {/* Spinner — overlays the button area, fades out when ready */}
          <div
            className={`absolute inset-0 flex items-center justify-center transition-opacity duration-300 ${
              available === null && !processing
                ? "opacity-100"
                : "opacity-0 pointer-events-none"
            }`}
          >
            <div className="w-5 h-5 border-2 border-gray-300 border-t-gray-600 rounded-full animate-spin" />
          </div>

          {/* Buttons — always mounted so Stripe can init, fade in when ready */}
          <div
            className={`transition-opacity duration-300 ease-out ${
              available === true && !processing ? "opacity-100" : "opacity-0"
            }`}
          >
            <ExpressCheckoutElement
              options={{
                paymentMethods: {
                  applePay: "auto",
                  googlePay: "auto",
                  link: "auto",
                },
                buttonType: {
                  applePay: "check-out",
                  googlePay: "checkout",
                },
                buttonTheme: {
                  applePay: "black",
                  googlePay: "black",
                },
                layout: {
                  maxColumns,
                  maxRows: 2,
                },
                emailRequired: true,
                phoneNumberRequired: true,
                shippingAddressRequired: true,
              }}
              onReady={handleReady}
              onClick={handleClick}
              onConfirm={handleConfirm}
              onCancel={handleCancel}
              onShippingAddressChange={handleShippingAddressChange}
              onShippingRateChange={handleShippingRateChange}
            />
            {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
            {available && showDivider && (
              <div className="relative mt-4">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-gray-200" />
                </div>
                <div className="relative flex justify-center text-sm">
                  <span className="px-2 bg-white text-gray-500">{t("or")}</span>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function ExpressCheckoutWithElements({
  cart,
  basePath,
  onComplete,
  onProcessingChange,
  onAvailabilityChange,
  maxColumns,
  showDivider,
  clientConfig,
}: ExpressCheckoutButtonProps) {
  const currency = cart.currency.toLowerCase();

  // P0-4 (FR-040/041): 初始 Elements 金额 = 服务端权威 amount（order.amount_due 子单位）。
  // 后续金额变化走 elements.update()（内层组件）。用 ref 保持 options 稳定、避免重挂载。
  const initialAmountRef = useRef(() => expressAmount(cart));
  const initialCurrencyRef = useRef(currency);

  const options = useMemo(
    () => ({
      mode: "payment" as const,
      amount: initialAmountRef.current(),
      currency: initialCurrencyRef.current,
      paymentMethodCreation: "manual" as const,
    }),
    [],
  );

  return (
    <Elements stripe={getStripePromise(clientConfig)} options={options}>
      <ExpressCheckoutInner
        cart={cart}
        basePath={basePath}
        onComplete={onComplete}
        onProcessingChange={onProcessingChange}
        onAvailabilityChange={onAvailabilityChange}
        maxColumns={maxColumns}
        showDivider={showDivider}
      />
    </Elements>
  );
}

export function ExpressCheckoutButton(props: ExpressCheckoutButtonProps) {
  const { onAvailabilityChange, clientConfig } = props;
  const t = useTranslations("checkout");
  const configured = isStripeConfigured(clientConfig);

  useEffect(() => {
    if (!configured) {
      onAvailabilityChange?.(false);
    }
  }, [configured, onAvailabilityChange]);

  // 未配置 publishable key：同样给显式状态（旧行为是静默 `return null` → 空白）。
  if (!configured) {
    return (
      <div
        data-testid="wallet-unavailable-notice"
        className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
      >
        {t("walletUnavailable")}
      </div>
    );
  }

  return <ExpressCheckoutWithElements {...props} />;
}
