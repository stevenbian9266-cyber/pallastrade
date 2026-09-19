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
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import {
  completeExpressCheckout,
  expressClientSecret,
  expressErrorRoute,
  expressNoticeFor,
  expressResultUrl,
  startExpressCheckout,
} from "@/lib/checkout/express-canonical";
import {
  expressPaymentMethodsFor,
  expressPaymentMethodsForKinds,
  selectedWalletAvailability,
  WALLET_READY_TIMEOUT_MS,
  type WalletAvailability,
  walletAvailabilityForKinds,
} from "@/lib/checkout/wallet-availability";
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
  stripeLocaleFor,
} from "@/lib/utils/stripe";

export interface ExpressCheckoutButtonProps {
  cart: Cart;
  basePath: string;
  onComplete: () => void | Promise<void>;
  onProcessingChange?: (processing: boolean) => void;
  /** 设备能力读数（三态 + 原因）；父级据此置灰入口并回落。 */
  onAvailabilityChange?: (result: WalletAvailability) => void;
  maxColumns?: number;
  showDivider?: boolean;
  /**
   * 选中入口的 `method_key`（如 `apple_pay`）。
   * 传入 → **点谁显示谁**（其余钱包 `never`）；不传 → 无入口上下文（抽屉：多钱包并排）。
   */
  entryKind?: string | null;
  /**
   * PRD-20260919-payments-checkout-top-express-pay-locale（2026-09-19）——
   * **多入口集合**（顶部快捷支付区）：服务端投影中全部可渲染的 express 入口。
   * 传入 → 一次启用集合内全部钱包（`always`；`link` 为 `auto`）；与 `entryKind`
   * 二者取一（`entryKinds` 优先，集合为空视为未传）。
   */
  entryKinds?: string[] | null;
  /**
   * 降级展示（PRD-20260919-payments-checkout-top-express-pay-locale FR-007）：
   * `notice`（默认，第 5 节入口槽）= 行内提示 + 重试；
   * `toast`（顶部快捷区）= 加载失败/超时弹 3s toast 后整区隐藏；`device` 等
   * 确定性不可用保持静默（不打扰、不占位）。
   */
  degradedDisplay?: "notice" | "toast";
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
  entryKind,
  entryKinds,
  degradedDisplay = "notice",
  onRetry,
}: ExpressCheckoutButtonProps & { onRetry?: () => void }) {
  const stripe = useStripe();
  const elements = useElements();
  const router = useRouter();
  const t = useTranslations("expressCheckout");
  // D7 补口 2：降级说明属于结账页文案（与 PaymentSection / WalletPaymentButtons 同命名空间）
  const tCheckout = useTranslations("checkout");
  // D7 补口 3：三态可用性（unknown / available / unavailable+原因）
  const [availability, setAvailability] = useState<WalletAvailability>({
    state: "unknown",
  });
  const [error, setError] = useState<string | null>(null);
  const [processing, setProcessing] = useState(false);
  const isConfirmingRef = useRef(false);
  const isGooglePayRef = useRef(false);
  /** PRD-20260919-payments-checkout-top-express-pay-locale AC-005：用户实际点击
   *  的钱包 kind（confirm 时作为 `option_kind` 透传 → 服务端同源复算）。 */
  const clickedKindRef = useRef<string | null>(null);
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
      // PRD-20260919-payments-checkout-top-express-pay-locale：多入口集合（顶部快捷区）
      // 与单入口（第 5 节槽位）分别读数——集合任一可用即可用。
      const result =
        entryKinds && entryKinds.length > 0
          ? walletAvailabilityForKinds(
              entryKinds,
              event.availablePaymentMethods,
            )
          : selectedWalletAvailability(
              entryKind,
              event.availablePaymentMethods,
            );
      setAvailability(result);
      onAvailabilityChangeRef.current?.(result);
    },
    [entryKind, entryKinds],
  );

  // 切换选中入口/入口集合（或重试）→ 重新探测：清掉上一轮结论并重新看门狗计时。
  // biome-ignore lint/correctness/useExhaustiveDependencies: entryKind/entryKinds 仅作触发器（重跑探测），不参与计算
  useEffect(() => {
    availabilityReportedRef.current = false;
    setAvailability({ state: "unknown" });
  }, [entryKind, entryKinds]);

  const handleClick = useCallback(
    (event: StripeExpressCheckoutElementClickEvent) => {
      const paymentType = event.expressPaymentType;
      isGooglePayRef.current = paymentType === "google_pay";
      // PRD-20260919-payments-checkout-top-express-pay-locale AC-005：记录用户实际点击
      // 的钱包（apple_pay / google_pay / link），confirm 时作为 `option_kind` 透传。
      clickedKindRef.current =
        paymentType === "apple_pay" ||
        paymentType === "google_pay" ||
        paymentType === "link"
          ? paymentType
          : null;
      event.resolve({
        lineItems: expressLineItems(cart),
      });
    },
    [cart],
  );

  // D7 补口 3（看门狗）：元素可能**永不**上报设备能力（Stripe iframe 被中断 / 移动网络慢）。
  // 只等回调会留下无限加载态；超时 → `unavailable(timeout)`（**可重试**，不判死）。
  // biome-ignore lint/correctness/useExhaustiveDependencies: entryKind/entryKinds 仅作触发器（换入口重计时）
  useEffect(() => {
    if (availability.state !== "unknown" || availabilityReportedRef.current) {
      return;
    }
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
  }, [availability.state, entryKind, entryKinds]);

  // PRD-20260919-payments-checkout-top-express-pay-locale AC-008（FR-007）：
  // 顶部快捷区（`degradedDisplay="toast"`）加载失败/超时 → 3s toast（每次挂载最多
  // 一次）；确定性不可用（device / unsupported / unconfigured）保持静默不打扰。
  const toastFiredRef = useRef(false);
  useEffect(() => {
    if (degradedDisplay !== "toast") return;
    if (availability.state !== "unavailable") return;
    if (availability.reason !== "timeout") return;
    if (toastFiredRef.current) return;
    toastFiredRef.current = true;
    toast(t("unavailableToast"), { duration: 3000 });
  }, [availability, degradedDisplay, t]);

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
        // PRD-20260919-payments-checkout-top-express-pay-locale AC-005：入口级同源校验——
        // 把用户实际点击的钱包 kind（或单入口上下文）作为 `option_kind` 透传；
        // 服务端复算可用性，不可用 → 422（不建会话，前台按既有约定提示重选）。
        const kindFromEntry =
          entryKind && isExpressWalletKind(entryKind) ? entryKind : null;
        const kindFromKinds =
          entryKinds?.length === 1 && isExpressWalletKind(entryKinds[0])
            ? (entryKinds[0] ?? null)
            : null;
        const optionKind =
          clickedKindRef.current ?? kindFromEntry ?? kindFromKinds;
        const startResult = await startExpressCheckout({
          cart_id: cart.id,
          payment_method_id: sessionPaymentMethod.id,
          payment_mode: "payment_intent",
          ...(optionKind ? { option_kind: optionKind } : {}),
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
      entryKind,
      entryKinds,
      onComplete,
      router,
      updateProcessing,
    ],
  );

  const handleCancel = useCallback(() => {
    // No-op: placeholder address on cart doesn't persist to address book
    // and will be overwritten by next checkout attempt.
  }, []);

  // D7 补口 3：**不得静默消失**，也不得把「没上报」当不可用。
  // - `unknown` → 加载中（附提示文案，移动端更慢但不判死）
  // - `unavailable` → 按**原因**给文案 + 「重试」（父级通常已自动回落卡支付）
  if (availability.state === "unavailable") {
    // 顶部快捷区（toast 模式）：不渲染行内提示/占位（异常由 3s toast 表达，整区由父级隐藏）。
    if (degradedDisplay === "toast") return null;
    const reason = availability.reason ?? "device";
    return (
      <div
        data-testid="wallet-unavailable-notice"
        data-reason={reason}
        className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
      >
        <p>
          {reason === "timeout"
            ? tCheckout("walletRetryHint")
            : reason === "unsupported"
              ? tCheckout("walletUnsupported")
              : tCheckout("walletUnavailable")}
        </p>
        {onRetry && reason !== "unsupported" ? (
          <button
            type="button"
            data-testid="wallet-retry"
            onClick={onRetry}
            className="mt-2 h-8 rounded-md border border-amber-300 bg-white px-3 text-xs font-medium text-amber-900 hover:bg-amber-100"
          >
            {tCheckout("walletRetry")}
          </button>
        ) : null}
      </div>
    );
  }

  const paymentMethodsOption =
    entryKinds && entryKinds.length > 0
      ? expressPaymentMethodsForKinds(entryKinds)
      : expressPaymentMethodsFor(entryKind);
  if (!paymentMethodsOption) return null;

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
            className={`absolute inset-0 flex flex-col items-center justify-center gap-2 transition-opacity duration-300 ${
              availability.state === "unknown" && !processing
                ? "opacity-100"
                : "opacity-0 pointer-events-none"
            }`}
          >
            <div className="w-5 h-5 border-2 border-gray-300 border-t-gray-600 rounded-full animate-spin" />
            <span className="text-xs text-gray-500">
              {tCheckout("walletLoading")}
            </span>
          </div>

          {/* Buttons — always mounted so Stripe can init, fade in when ready */}
          <div
            className={`transition-opacity duration-300 ease-out ${
              availability.state === "available" && !processing
                ? "opacity-100"
                : "opacity-0"
            }`}
          >
            <ExpressCheckoutElement
              options={{
                // D7 补口 3：点谁显示谁（选中钱包 auto，其余 never）
                paymentMethods: paymentMethodsOption,
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
            {availability.state === "available" && showDivider && (
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
  entryKind,
  entryKinds,
  degradedDisplay,
}: ExpressCheckoutButtonProps) {
  const locale = useLocale();
  const currency = cart.currency.toLowerCase();
  // D7 补口 3：重试 = 重挂载 Elements（重新初始化元素并重新探测设备能力）
  const [retryToken, setRetryToken] = useState(0);

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
      // PRD-20260919-payments-checkout-top-express-pay-locale FR-006：
      // Stripe 渲染面（钱包按钮/弹层内文案）跟随站点语种。
      locale: stripeLocaleFor(locale),
    }),
    [locale],
  );

  return (
    <Elements
      key={retryToken}
      stripe={getStripePromise(clientConfig)}
      options={options}
    >
      <ExpressCheckoutInner
        cart={cart}
        basePath={basePath}
        onComplete={onComplete}
        onProcessingChange={onProcessingChange}
        onAvailabilityChange={onAvailabilityChange}
        maxColumns={maxColumns}
        showDivider={showDivider}
        entryKind={entryKind}
        entryKinds={entryKinds}
        degradedDisplay={degradedDisplay}
        onRetry={() => setRetryToken((token) => token + 1)}
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
      onAvailabilityChange?.({ state: "unavailable", reason: "unconfigured" });
    }
  }, [configured, onAvailabilityChange]);

  // 未配置 publishable key：同样给显式状态（旧行为是静默 `return null` → 空白）。
  if (!configured) {
    return (
      <div
        data-testid="wallet-unavailable-notice"
        data-reason="unconfigured"
        className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
      >
        {t("walletUnconfigured")}
      </div>
    );
  }

  return <ExpressCheckoutWithElements {...props} />;
}
