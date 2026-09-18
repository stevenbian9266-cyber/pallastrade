"use client";

import type { CheckoutView, Country, Order, State } from "@pallastrade/sdk";
import { X } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { toast } from "sonner";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import {
  CardPaymentForm,
  type CardPaymentFormHandle,
} from "@/components/checkout/CardPaymentForm";
import {
  type PaymentMethodWithEntries,
  PaymentSection,
  paymentEntriesFor,
} from "@/components/checkout/PaymentSection";
import { WalletPaymentButtons } from "@/components/checkout/WalletPaymentButtons";
import { Button } from "@/components/ui/button";
import { ProductImage } from "@/components/ui/product-image";
import { useCheckout } from "@/contexts/CheckoutContext";
import { useCountryStates } from "@/hooks/useCountryStates";
import { getCountry } from "@/lib/data/countries";
import {
  getOrderCheckout,
  updateOrderCheckout,
} from "@/lib/data/order-checkout";
import {
  completeOrderPaymentSession,
  completeOrderPaymentSessionAndRedirectToResult,
  createOrderPaymentSession,
} from "@/lib/data/order-payment";
import {
  type AddressFormData,
  addressToFormData,
  emptyAddress,
  formDataToAddress,
  updateAddressField,
} from "@/lib/utils/address";
import { safeParseFloat } from "@/lib/utils/format";
import { extractBasePath } from "@/lib/utils/path";
import { extractSessionClientSecret } from "@/lib/utils/stripe";

interface OrderPaymentContentProps {
  order: Order;
  /** CHK-P1-4: server CheckoutView projection (optional — fall back to Order snapshot). */
  view?: CheckoutView | null;
  /** CHK-P1-4B: countries for the inline address editor (optional). */
  countries?: Country[];
}

/**
 * CHK-P1-4: normalized read model for the pay page — served by the server
 * CheckoutView projection when available, otherwise the Order snapshot.
 * Money contract（PRD-20260913-checkout-money-contract）：raw 字段仅用于条件判断，
 * display_* 仅用于渲染（API 权威格式）。
 */
interface CheckoutReadModel {
  items: CheckoutView["items"];
  /** raw 金额——仅用于逻辑判断。 */
  delivery_total: string | null;
  tax_total: string | null;
  display_item_total: string | null;
  display_delivery_total: string | null;
  display_tax_total: string | null;
  display_total: string | null;
  /** B1（PRD-20260914-checkout）：礼卡/余额展示（raw 仅判断，display 仅渲染）。 */
  gift_card_total: string | null;
  display_gift_card_total: string | null;
  store_credit_total: string | null;
  display_store_credit_total: string | null;
  /** B1：服务端能力位（view 缺失 → null = 不限制）。 */
  capabilities: CheckoutView["capabilities"] | null;
  shipping_address: CheckoutView["shipping_address"];
}

function OrderPaymentSummary({ read }: { read: CheckoutReadModel }) {
  const tc = useTranslations("common");

  return (
    <div data-testid="order-payment-summary">
      <h2 className="text-lg font-medium text-gray-900 mb-4">
        {tc("orderSummary")}
      </h2>

      <div className="space-y-4 divide-y divide-gray-100">
        {(read.items ?? []).map((item) => (
          <div key={item.id} className="flex gap-4 pt-4 first:pt-0">
            <div className="relative w-16 h-16 bg-gray-100 rounded-lg overflow-hidden flex-shrink-0">
              <ProductImage
                src={item.thumbnail_url}
                alt={item.name}
                fill
                className="object-cover"
                sizes="64px"
              />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 truncate">
                {item.name}
              </p>
              <p className="text-sm text-gray-500">× {item.quantity}</p>
            </div>
            <p className="text-sm font-semibold text-gray-900">
              {item.display_total}
            </p>
          </div>
        ))}
      </div>

      <dl className="mt-6 space-y-4 border-t border-gray-100 pt-4">
        <div className="flex justify-between">
          <dt className="text-gray-500">{tc("subtotal")}</dt>
          <dd className="text-gray-900">{read.display_item_total}</dd>
        </div>
        {read.display_delivery_total &&
          safeParseFloat(read.delivery_total) > 0 && (
            <div className="flex justify-between">
              <dt className="text-gray-500">{tc("shipping")}</dt>
              <dd className="text-gray-900">{read.display_delivery_total}</dd>
            </div>
          )}
        {read.display_tax_total && safeParseFloat(read.tax_total) > 0 && (
          <div className="flex justify-between">
            <dt className="text-gray-500">{tc("tax")}</dt>
            <dd className="text-gray-900">{read.display_tax_total}</dd>
          </div>
        )}
        {/* B1：礼卡/余额抵扣行（order 口径为正值，展示时加负号；无则不加行） */}
        {read.gift_card_total && safeParseFloat(read.gift_card_total) > 0 && (
          <div className="flex justify-between" data-testid="gift-card-row">
            <dt className="text-gray-500">{tc("giftCard")}</dt>
            <dd className="text-green-600">-{read.display_gift_card_total}</dd>
          </div>
        )}
        {read.store_credit_total &&
          safeParseFloat(read.store_credit_total) > 0 && (
            <div
              className="flex justify-between"
              data-testid="store-credit-row"
            >
              <dt className="text-gray-500">{tc("storeCredit")}</dt>
              <dd className="text-green-600">
                -{read.display_store_credit_total}
              </dd>
            </div>
          )}
        <div className="flex justify-between border-t pt-4">
          <dt className="text-lg font-medium text-gray-900">{tc("total")}</dt>
          <dd className="text-lg font-bold text-gray-900">
            {read.display_total}
          </dd>
        </div>
      </dl>
    </div>
  );
}

/**
 * 订单流程标准电商改造 P1（2026-08-30）：Checkout 纯支付页（标准流程订单）。
 * 收货/物流只读；仅支付。支付完成 → 订单 paid → 跳转 order-placed。
 * 下单链路统一化（PRD-20260830-checkout）：支持 ?pm=<payment_method_id> 预选支付方式
 * （统一下单页 UnifiedCheckout 提交后携带预选方式跳转）。
 */
export function OrderPaymentContent({
  order,
  view,
  countries,
}: OrderPaymentContentProps) {
  const t = useTranslations("checkout");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const searchParams = useSearchParams();
  const { setSummaryContent } = useCheckout();
  // PRD-20260913-checkout-txn-error-routing AC-007：报价变化横幅（?notice=quote_changed）。
  const [showQuoteNotice, setShowQuoteNotice] = useState(
    () => searchParams?.get("notice") === "quote_changed",
  );

  // B1（PRD-20260914-checkout B1）：服务端 CheckoutView 为页面唯一数据源；
  // 可被编辑/409 刷新覆盖（初始来自 props.view）。
  const [liveView, setLiveView] = useState<CheckoutView | null>(view ?? null);
  const effectiveView = liveView ?? view;

  // B1：支付方式服务端权威（CheckoutView.payment.available_payment_methods），order 快照回退。
  // D7（PRD-20260918-payments-d7-payment-section-express）：支付方式列表 = 服务端投影
  // 的**入口级**列表（一入口一行）；`entries` 缺失的旧响应由 `paymentEntriesFor` 回退单入口。
  const paymentMethods = useMemo(
    () =>
      (effectiveView?.payment?.available_payment_methods ??
        order.payment_methods ??
        []) as PaymentMethodWithEntries[],
    [effectiveView, order.payment_methods],
  );

  // 入口展开（顺序 = 服务端 `position`）
  const paymentOptions = useMemo(
    () =>
      paymentMethods.flatMap((method) =>
        paymentEntriesFor(method).map((entry) => ({ entry, method })),
      ),
    [paymentMethods],
  );

  // 默认选中：URL 预选（`?pm=` 兼容 provider id 与 option_id）> 首个可用入口
  const [selectedOptionId, setSelectedOptionId] = useState<string | null>(
    () => {
      const preset = searchParams?.get("pm") ?? "";
      const presetOption =
        paymentOptions.find((o) => o.entry.option_id === preset) ??
        paymentOptions.find((o) => o.method.id === preset);
      return (
        presetOption?.entry.option_id ??
        paymentOptions[0]?.entry.option_id ??
        null
      );
    },
  );
  const selectedOption =
    paymentOptions.find((o) => o.entry.option_id === selectedOptionId) ??
    paymentOptions[0];
  const selectedMethod = selectedOption?.method;
  const selectedEntry = selectedOption?.entry;
  // 渲染形态由服务端投影的 `frontend_kind` 决定（钱包 = express；卡字段 = inline）
  const selectedIsWallet = selectedEntry?.frontend_kind === "express";
  const selectedIsInline =
    !selectedIsWallet && selectedEntry?.frontend_kind === "inline";

  const [processing, setProcessing] = useState(false);
  const [walletProcessing, setWalletProcessing] = useState(false);
  const cardFormRef = useRef<CardPaymentFormHandle | null>(null);

  const isPaid = order.state === "paid" || order.state === "completed";

  const [editing, setEditing] = useState<"address" | "delivery" | null>(null);
  const [saving, setSaving] = useState(false);

  const refreshView = useCallback(async () => {
    const fresh = await getOrderCheckout(order.id);
    if (fresh) setLiveView(fresh);
  }, [order.id]);

  // CHK-P1-4: 只读投影优先，Order 快照回退（view 缺失防端点抖动）。
  const read: CheckoutReadModel = useMemo(
    () =>
      effectiveView
        ? {
            items: effectiveView.items,
            delivery_total: effectiveView.delivery_total,
            tax_total: effectiveView.tax_total,
            display_item_total: effectiveView.display_item_total,
            display_delivery_total: effectiveView.display_delivery_total,
            display_tax_total: effectiveView.display_tax_total,
            display_total: effectiveView.display_total,
            gift_card_total:
              effectiveView.credits?.gift_cards?.[0]?.amount ?? null,
            display_gift_card_total:
              effectiveView.credits?.gift_cards?.[0]?.display_amount ?? null,
            store_credit_total:
              effectiveView.credits?.store_credit?.amount ?? null,
            display_store_credit_total:
              effectiveView.credits?.store_credit?.display_amount ?? null,
            capabilities: effectiveView.capabilities ?? null,
            shipping_address: effectiveView.shipping_address,
          }
        : {
            items: order.items ?? [],
            delivery_total: order.delivery_total,
            tax_total: order.tax_total,
            display_item_total: order.display_item_total,
            display_delivery_total: order.display_delivery_total,
            display_tax_total: order.display_tax_total,
            display_total: order.display_total,
            gift_card_total: order.gift_card_total ?? null,
            display_gift_card_total: order.display_gift_card_total ?? null,
            store_credit_total: order.store_credit_total ?? null,
            display_store_credit_total:
              order.display_store_credit_total ?? null,
            capabilities: null,
            shipping_address: order.shipping_address ?? null,
          },
    [effectiveView, order],
  );

  // Server Readiness: view 缺失时不做前端猜测（回退放行——后端 Start Gate 兜底）。
  const checkoutReady = effectiveView?.ready ?? true;
  const missingRequirements = effectiveView?.missing_requirements ?? [];

  // CHK-P1-4B: 物流 rate 列表（来自 CheckoutView fulfillments）——无 shipments/digital 为空。
  const deliveryRates = useMemo(
    () =>
      (effectiveView?.fulfillments ?? []).flatMap(
        (f) => f.delivery_rates ?? [],
      ),
    [effectiveView],
  );
  const viewSelectedRateId =
    deliveryRates.find((r) => r.selected)?.id ?? deliveryRates[0]?.id ?? "";
  const [rateOverride, setRateOverride] = useState<string | null>(null);
  const activeRateId = rateOverride ?? viewSelectedRateId;

  useLayoutEffect(() => {
    setSummaryContent(<OrderPaymentSummary read={read} />);
    return () => setSummaryContent(null);
  }, [read, setSummaryContent]);

  const handleCardReady = useCallback((handle: CardPaymentFormHandle) => {
    cardFormRef.current = handle;
  }, []);

  // CHK-P1-4B: 物流 rate 变更 → PATCH delivery_rate_id → 采用服务端最新 view。
  const handleSaveDelivery = useCallback(async () => {
    if (!editing || editing !== "delivery" || !activeRateId) return;
    setSaving(true);
    const result = await updateOrderCheckout(order.id, {
      delivery_rate_id: activeRateId,
    });
    setSaving(false);
    if (result.success) {
      setLiveView(result.view);
      setRateOverride(null);
      setEditing(null);
      toast.success(t("saved"));
    } else {
      toast.error(result.error || t("failedToUpdateCheckout"));
    }
  }, [editing, activeRateId, order.id, t]);

  // 已支付 → 直接跳完成页
  useEffect(() => {
    if (isPaid) {
      router.replace(`${basePath}/payment-result/${order.id}`);
    }
  }, [isPaid, order.id, basePath, router]);

  // CHK-P1-4B: 会话创建失败处理——quote 已变（409）→ 提示 + 刷新 view（不自动支付）。
  // TXN-P2-6 轮3: transaction-first 后 transactions.create 的 quote 冲突码为
  // quote_changed / checkout_version_conflict（P1-5），同一映射（INV-07）。
  const handleSessionCreateError = useCallback(
    async (result: { success: false; code?: string; error: string }) => {
      // D7（PRD-20260918-payments-d7-payment-section-express）：入口级可用性拒绝
      // —— 沿用 D8 约定：刷新支付方式列表 + 提示重选（不进入支付流程）。
      if (result.code === "payment_option_not_available") {
        toast.error(result.error);
        await refreshView();
        return;
      }
      if (
        result.code === "checkout_version_conflict" ||
        result.code === "quote_changed"
      ) {
        toast.error(t("quoteUpdated"));
        await refreshView();
        return;
      }
      toast.error(result.error || t("failedToCreateSession"));
    },
    [refreshView, t],
  );

  const handlePay = async () => {
    if (!selectedMethod) return;

    // CHK-P1-4: server readiness gate（前端镜像；后端 Start Gate 兜底）
    if (!checkoutReady) {
      toast.error(t("checkoutNotReady"));
      return;
    }
    setProcessing(true);
    try {
      const gatewayType = selectedMethod.type;
      const isSessionBased = selectedMethod.session_required === true;

      if (isSessionBased && gatewayType === "stripe") {
        // Stripe 自绘卡字段（PRD-20260831-payments-stripe-自绘卡支付表单）：
        // 表单已渲染；Pay Now → 创建 PaymentIntent 会话 → confirmCardPayment。
        if (!cardFormRef.current?.validate()) {
          setProcessing(false);
          return;
        }
        const result = await createOrderPaymentSession(
          order.id,
          selectedMethod.id,
          undefined,
          "payment_intent",
          // D7：入口（method kind）随请求下发 —— 服务端 `PaymentSessions::Start`
          // 用同一入口集合同源复算可用性（不可用 → 422，不建会话）。
          { optionKind: selectedEntry?.method_key },
        );
        if (!result.success) {
          await handleSessionCreateError(result);
          setProcessing(false);
          return;
        }
        const session = result.session as {
          id: string;
          external_data?: Record<string, unknown>;
        };
        // client_secret 位于 external_data 且 URL 编码（%2F）→ 解码后传给 Stripe
        const stripeSecret = extractSessionClientSecret(session);

        if (!stripeSecret) {
          router.push(
            `${basePath}/payment-result/${order.id}?session=${session.id}`,
          );
          return;
        }

        const confirmResult =
          await cardFormRef.current?.confirmPayment(stripeSecret);
        if (confirmResult?.error) {
          await completeOrderPaymentSession(order.id, session.id);
          router.push(
            `${basePath}/payment-result/${order.id}?session=${session.id}`,
          );
          return;
        }

        // 支付确认成功 → 完成会话 + 完成订单 → 由 server action 内 redirect
        // 导航（确定性，规避自动 refresh 竞态）
        await completeOrderPaymentSessionAndRedirectToResult(
          order.id,
          session.id,
          basePath,
        );
        return;
      }

      if (isSessionBased) {
        // 其他 session-based（PayPal/Adyen）：创建订单支付会话 → 直接完成会话
        const result = await createOrderPaymentSession(
          order.id,
          selectedMethod.id,
          undefined,
          undefined,
          { optionKind: selectedEntry?.method_key },
        );
        if (!result.success) {
          await handleSessionCreateError(result);
          setProcessing(false);
          return;
        }
        const session = result.session as {
          id: string;
          external_data?: Record<string, unknown>;
        };
        // 其他 session-based（PayPal/Adyen）：直接完成会话（provider 回调驱动）
        await completeOrderPaymentSessionAndRedirectToResult(
          order.id,
          session.id,
          basePath,
        );
        return;
      }

      // 非 session（Check/COD/银行转账）：无在线支付，订单保持 pending（线下收款），
      // 直接跳完成页。
      router.push(`${basePath}/payment-result/${order.id}`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Payment failed");
    } finally {
      setProcessing(false);
    }
  };

  // ── CHK-P1-4B: 收货地址内联编辑（复用 AddressFormFields + useCountryStates）──
  const [addressForm, setAddressForm] = useState<AddressFormData>(() =>
    read.shipping_address
      ? addressToFormData(read.shipping_address)
      : emptyAddress,
  );
  const [addressTouched, setAddressTouched] = useState(false);

  const startAddressEdit = useCallback(() => {
    const base = read.shipping_address;
    setAddressForm(base ? addressToFormData(base) : emptyAddress);
    setAddressTouched(false);
    setEditing("address");
  }, [read.shipping_address]);

  const fetchStates = useCallback(
    async (countryIso: string): Promise<State[]> => {
      try {
        const country = await getCountry(countryIso);
        return country?.states || [];
      } catch {
        return [];
      }
    },
    [],
  );

  const [states, statesLoading] = useCountryStates(
    addressForm.country_iso,
    fetchStates,
    editing === "address" && !isPaid,
  );

  const handleAddressChange = useCallback(
    (field: keyof AddressFormData, value: string) => {
      setAddressTouched(true);
      setAddressForm((prev) => updateAddressField(prev, field, value));
    },
    [],
  );

  const handleSaveAddress = useCallback(async () => {
    setSaving(true);
    const result = await updateOrderCheckout(order.id, {
      shipping_address: formDataToAddress(addressForm),
    });
    setSaving(false);
    if (result.success) {
      setLiveView(result.view);
      setAddressTouched(false);
      setEditing(null);
      toast.success(t("saved"));
    } else {
      toast.error(result.error || t("failedToUpdateCheckout"));
    }
  }, [order.id, addressForm, t]);

  const handleDeliverySelect = useCallback((rateId: string) => {
    setRateOverride(rateId);
  }, []);

  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">{t("payment")}</h1>

      {/* PRD-20260913-checkout-txn-error-routing AC-007：报价变化横幅 */}
      {showQuoteNotice && (
        <div
          role="status"
          data-testid="quote-updated-banner"
          className="mb-6 flex items-start justify-between gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3"
        >
          <p className="text-sm text-amber-800">{t("quoteUpdatedBanner")}</p>
          <button
            type="button"
            aria-label={t("dismissBanner")}
            className="shrink-0 text-amber-700 hover:text-amber-900"
            onClick={() => setShowQuoteNotice(false)}
          >
            <X className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>
      )}

      <div className="space-y-8">
        {/* 收货信息——CHK-P1-4: 以 CheckoutView 投影为准（回退 order 快照）
            CHK-P1-4B: 支持内联编辑（复用 AddressFormFields） */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-medium text-gray-900">
              {t("shippingAddress")}
            </h2>
            {!isPaid && countries && countries.length > 0 && (
              <Button
                variant="ghost"
                size="sm"
                data-testid="edit-address"
                disabled={read.capabilities?.can_edit_address === false}
                onClick={() =>
                  editing === "address" ? setEditing(null) : startAddressEdit()
                }
              >
                {editing === "address" ? t("cancel") : t("edit")}
              </Button>
            )}
          </div>

          {editing === "address" && countries && countries.length > 0 ? (
            <div className="space-y-4" data-testid="address-editor">
              <AddressFormFields
                address={addressForm}
                countries={countries}
                states={states}
                loadingStates={statesLoading}
                onChange={handleAddressChange}
                idPrefix="or-address"
              />
              {addressTouched && (
                <p className="text-xs text-gray-500">{t("addressHint")}</p>
              )}
              <div className="flex gap-3">
                <Button
                  data-testid="save-address"
                  disabled={saving}
                  onClick={handleSaveAddress}
                >
                  {saving ? t("processing") : t("save")}
                </Button>
                <Button variant="outline" onClick={() => setEditing(null)}>
                  {t("cancel")}
                </Button>
              </div>
            </div>
          ) : read.shipping_address ? (
            <div className="text-sm text-gray-700">
              <p>
                {read.shipping_address.first_name}{" "}
                {read.shipping_address.last_name}
              </p>
              <p>{read.shipping_address.address1}</p>
              {read.shipping_address.address2 && (
                <p>{read.shipping_address.address2}</p>
              )}
              <p>
                {read.shipping_address.city}
                {read.shipping_address.state_abbr
                  ? `, ${read.shipping_address.state_abbr}`
                  : ""}{" "}
                {read.shipping_address.postal_code}
              </p>
              {read.shipping_address.country_iso && (
                <p>{read.shipping_address.country_iso}</p>
              )}
              {read.shipping_address.phone && (
                <p>{read.shipping_address.phone}</p>
              )}
            </div>
          ) : (
            <p className="text-sm text-gray-500">{t("noShippingAddress")}</p>
          )}
        </section>

        {/* CHK-P1-4B: 配送方式（rate 单选，来自 CheckoutView fulfillments） */}
        {deliveryRates.length > 0 && !isPaid && (
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-medium text-gray-900">
                {t("shippingMethod")}
              </h2>
              <Button
                variant="ghost"
                size="sm"
                data-testid="edit-delivery"
                disabled={read.capabilities?.can_change_shipping === false}
                onClick={() =>
                  editing === "delivery"
                    ? setEditing(null)
                    : setEditing("delivery")
                }
              >
                {editing === "delivery" ? t("cancel") : t("edit")}
              </Button>
            </div>
            {editing === "delivery" ? (
              <div
                className="flex flex-col gap-2"
                data-testid="delivery-editor"
              >
                {deliveryRates.map((rate) => (
                  <label
                    key={rate.id}
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer hover:border-indigo-300"
                  >
                    <input
                      type="radio"
                      name="order-delivery-rate"
                      data-testid={`rate-${rate.id}`}
                      checked={activeRateId === rate.id}
                      onChange={() => handleDeliverySelect(rate.id)}
                      className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                    />
                    <span className="flex-1 font-medium text-gray-900">
                      {rate.name}
                    </span>
                    <span className="text-sm text-gray-700">
                      {rate.display_cost}
                    </span>
                  </label>
                ))}
                <div className="flex gap-3 mt-2">
                  <Button
                    data-testid="save-delivery"
                    disabled={saving || !activeRateId}
                    onClick={handleSaveDelivery}
                  >
                    {saving ? t("processing") : t("save")}
                  </Button>
                  <Button variant="outline" onClick={() => setEditing(null)}>
                    {t("cancel")}
                  </Button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-gray-700">
                {deliveryRates.find((r) => r.id === activeRateId)?.name ??
                  activeRateId}
              </p>
            )}
          </section>
        )}

        {/* 支付方式 —— D7：入口级列表（一入口一行；服务端决定出现哪些） */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-medium text-gray-900 mb-4">
            {t("paymentMethod")}
          </h2>

          <PaymentSection
            methods={paymentMethods}
            selectedOptionId={selectedOptionId}
            onSelect={(entry) => setSelectedOptionId(entry.option_id)}
            emptyLabel={t("noPaymentMethod")}
            // PALLAS-CUSTOM: D15 切片3 —— 服务端已按 3DS/SCA 认证需求过滤入口
            //（前端**不做筛选**）；这里只把「为什么只剩这些」说清楚。
            authenticationNotice={
              paymentMethods.some((m) => m.requires_authentication)
                ? t("authenticationRequired")
                : null
            }
          >
            {/* 形态槽：inline → 卡表单；express → 钱包按钮（manual 仅说明行） */}
            {selectedIsWallet && selectedMethod && selectedEntry ? (
              <div className="mt-4 rounded-lg border border-gray-200 p-4">
                <WalletPaymentButtons
                  orderId={order.id}
                  basePath={basePath}
                  method={selectedMethod}
                  entry={selectedEntry}
                  onProcessingChange={setWalletProcessing}
                  onUnavailable={refreshView}
                />
              </div>
            ) : null}

            {/* Stripe 自绘卡字段（PRD-20260831-payments-stripe-自绘卡支付表单）：
                表单始终渲染，不依赖 client_secret / js.stripe.com iframe */}
            {selectedIsInline &&
            selectedMethod?.type === "stripe" &&
            selectedMethod.session_required ? (
              <div className="mt-4 rounded-lg border border-gray-200 p-4">
                {/* PALLAS-CUSTOM: D10 —— 服务端下发 client_config（回落 NEXT_PUBLIC_*） */}
                <CardPaymentForm
                  onReady={handleCardReady}
                  clientConfig={selectedMethod.client_config ?? null}
                />
              </div>
            ) : null}

            {/* CHK-P1-4: server readiness 门控——ready=false 时禁用 Pay 并提示 */}
            {!checkoutReady && (
              <div
                data-testid="checkout-not-ready"
                data-missing={missingRequirements.join(",")}
                className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
              >
                {t("checkoutNotReady")}
              </div>
            )}
            {!selectedIsWallet && (
              <Button
                size="lg"
                data-testid="pay-now-button"
                className="w-full mt-6"
                disabled={
                  !selectedMethod ||
                  !checkoutReady ||
                  processing ||
                  read.capabilities?.can_pay === false
                }
                onClick={handlePay}
              >
                {processing
                  ? t("processing")
                  : t("payAmount", {
                      amount: read.display_total ?? "",
                    })}
              </Button>
            )}
          </PaymentSection>
        </section>
      </div>

      {/* D7 FR-007 / AC-009：移动端吸底 Pay 条 —— 与页内按钮**同一 handler**
          （钱包入口交给同一个钱包组件，不复制支付逻辑） */}
      <div
        data-testid="mobile-pay-bar"
        className="lg:hidden fixed bottom-0 left-0 right-0 z-40 border-t border-gray-200 bg-white/95 backdrop-blur px-4 py-3 flex items-center justify-between gap-4"
      >
        <span className="text-sm font-semibold text-gray-900">
          {read.display_total ?? ""}
        </span>
        {selectedIsWallet && selectedMethod && selectedEntry ? (
          <div className="w-1/2">
            <WalletPaymentButtons
              orderId={order.id}
              basePath={basePath}
              method={selectedMethod}
              entry={selectedEntry}
              onProcessingChange={setWalletProcessing}
              onUnavailable={refreshView}
            />
          </div>
        ) : (
          <Button
            size="lg"
            data-testid="mobile-pay-button"
            disabled={
              !selectedMethod ||
              !checkoutReady ||
              processing ||
              walletProcessing ||
              read.capabilities?.can_pay === false
            }
            onClick={handlePay}
          >
            {processing
              ? t("processing")
              : t("payAmount", { amount: read.display_total ?? "" })}
          </Button>
        )}
      </div>
    </div>
  );
}
