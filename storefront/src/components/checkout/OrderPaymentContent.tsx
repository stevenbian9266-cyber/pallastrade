"use client";

import type {
  CheckoutView,
  Country,
  Order,
  PaymentMethod,
  State,
} from "@pallastrade/sdk";
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
 * Money always uses display_* (API-authoritative formatting).
 */
interface CheckoutReadModel {
  items: CheckoutView["items"];
  display_item_total: string | null;
  display_delivery_total: string | null;
  display_tax_total: string | null;
  display_total: string | null;
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
          parseFloat(read.display_delivery_total) > 0 && (
            <div className="flex justify-between">
              <dt className="text-gray-500">{tc("shipping")}</dt>
              <dd className="text-gray-900">{read.display_delivery_total}</dd>
            </div>
          )}
        {read.display_tax_total && parseFloat(read.display_tax_total) > 0 && (
          <div className="flex justify-between">
            <dt className="text-gray-500">{tc("tax")}</dt>
            <dd className="text-gray-900">{read.display_tax_total}</dd>
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

  const paymentMethods: PaymentMethod[] = order.payment_methods ?? [];
  // 默认选中：URL 预选（?pm=）> 首个可用支付方式
  const [selectedMethodId, setSelectedMethodId] = useState(() => {
    const preset = searchParams?.get("pm") ?? "";
    return paymentMethods.some((m) => m.id === preset)
      ? preset
      : (paymentMethods[0]?.id ?? "");
  });
  const selectedMethod =
    paymentMethods.find((m) => m.id === selectedMethodId) ?? paymentMethods[0];

  const [processing, setProcessing] = useState(false);
  const cardFormRef = useRef<CardPaymentFormHandle | null>(null);

  const isPaid = order.state === "paid" || order.state === "completed";

  // CHK-P1-4B: 服务端 view 可被编辑/409 刷新覆盖（初始来自 props.view）。
  const [liveView, setLiveView] = useState<CheckoutView | null>(view ?? null);
  const [editing, setEditing] = useState<"address" | "delivery" | null>(null);
  const [saving, setSaving] = useState(false);
  const effectiveView = liveView ?? view;

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
            display_item_total: effectiveView.display_item_total,
            display_delivery_total: effectiveView.display_delivery_total,
            display_tax_total: effectiveView.display_tax_total,
            display_total: effectiveView.display_total,
            shipping_address: effectiveView.shipping_address,
          }
        : {
            items: order.items ?? [],
            display_item_total: order.display_item_total,
            display_delivery_total: order.display_delivery_total,
            display_tax_total: order.display_tax_total,
            display_total: order.display_total,
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

        {/* 支付方式 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-medium text-gray-900 mb-4">
            {t("paymentMethod")}
          </h2>

          <div className="flex flex-col gap-3">
            {paymentMethods.map((method) => (
              <label
                key={method.id}
                className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer hover:border-indigo-300"
              >
                <input
                  type="radio"
                  name="payment-method"
                  checked={selectedMethodId === method.id}
                  onChange={() => setSelectedMethodId(method.id ?? "")}
                  className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                />
                <span className="font-medium text-gray-900">{method.name}</span>
              </label>
            ))}
          </div>

          {/* Stripe 自绘卡字段（PRD-20260831-payments-stripe-自绘卡支付表单）：
              表单始终渲染，不依赖 client_secret / js.stripe.com iframe */}
          {selectedMethod?.type === "stripe" &&
          selectedMethod.session_required ? (
            <div className="mt-4 rounded-lg border border-gray-200 p-4">
              <CardPaymentForm onReady={handleCardReady} />
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
          <Button
            size="lg"
            className="w-full mt-6"
            disabled={!selectedMethod || !checkoutReady || processing}
            onClick={handlePay}
          >
            {processing
              ? t("processing")
              : t("payAmount", {
                  amount: read.display_total ?? "",
                })}
          </Button>
        </section>
      </div>
    </div>
  );
}
