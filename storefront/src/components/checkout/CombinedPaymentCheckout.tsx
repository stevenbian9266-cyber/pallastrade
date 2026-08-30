"use client";

import type { Address, Country, Order, State } from "@pallastrade/sdk";
import {
  CheckCircle2,
  Loader2,
  MapPin,
  PackageCheck,
  Wallet,
} from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import {
  StripePaymentForm,
  type StripePaymentFormHandle,
} from "@/components/checkout/StripePaymentForm";
import { Button } from "@/components/ui/button";
import { ProductImage } from "@/components/ui/product-image";
import { getAddresses } from "@/lib/data/addresses";
import { getCountries, getCountry } from "@/lib/data/countries";
import {
  completeCombinationSession,
  getPaymentCombination,
  updateOrderShippingAddress,
} from "@/lib/data/payment-combination";
import {
  type AddressFormData,
  addressToFormData,
  emptyAddress,
  formDataToAddress,
} from "@/lib/utils/address";
import { extractBasePath } from "@/lib/utils/path";

interface CombinedPaymentCheckoutProps {
  combinationId: string;
  country: string;
  locale: string;
}

type Step = "shipping" | "payment";

/** 地址必填校验（AC-004：无地址订单强制填写后才能进入支付） */
function addressComplete(form: AddressFormData): boolean {
  return Boolean(
    form.first_name &&
      form.last_name &&
      form.address1 &&
      form.city &&
      form.country_iso,
  );
}

function orderHasCompleteAddress(order: Order): boolean {
  const a = order.shipping_address;
  if (!a) return false;
  return Boolean(a.first_name && a.last_name && a.address1 && a.city);
}

/**
 * 合并支付收银台（P5, 2026-08-27 + PRD-20260829-checkout 收货信息独立填写）。
 * 两步骤流程：
 *   1) 收货：逐单确认/编辑各成员订单收货地址（保存到后端），全部就绪才能继续；
 *   2) 商品 + 支付：所有成员订单商品明细 + 组合总金额 + Stripe PaymentElement 组合支付。
 * 支付卡片区域不包含任何地址输入（AC-007）。
 */
export function CombinedPaymentCheckout({
  combinationId,
  country,
  locale,
}: CombinedPaymentCheckoutProps) {
  const t = useTranslations("checkout");
  const ta = useTranslations("address");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);

  const [step, setStep] = useState<Step>("shipping");
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [combination, setCombination] = useState<Awaited<
    ReturnType<typeof getPaymentCombination>
  > | null>(null);
  const [countries, setCountries] = useState<Country[]>([]);
  const [savedAddresses, setSavedAddresses] = useState<Address[]>([]);

  // 逐单收货表单 / 州列表 / 就绪标记
  const [forms, setForms] = useState<Record<string, AddressFormData>>({});
  const [states, setStates] = useState<Record<string, State[]>>({});
  const [loadingStates, setLoadingStates] = useState<Record<string, boolean>>(
    {},
  );
  const [ready, setReady] = useState<Record<string, boolean>>({});
  const [savingOrderId, setSavingOrderId] = useState<string | null>(null);

  const [processing, setProcessing] = useState(false);
  const gatewayRef = useRef<StripePaymentFormHandle | null>(null);
  const loadedRef = useRef(false);

  const orders: Order[] = useMemo(() => {
    if (!combination || "error" in combination) return [];
    return combination.orders ?? [];
  }, [combination]);

  const allReady =
    orders.length > 0 && orders.every((order) => ready[order.id] === true);

  useEffect(() => {
    if (loadedRef.current) return;
    loadedRef.current = true;
    Promise.all([getPaymentCombination(combinationId), getCountries()])
      .then(([combo, countriesData]) => {
        setCombination(combo);
        setCountries(countriesData?.data ?? []);
        if (!("error" in combo) && combo.orders) {
          const nextForms: Record<string, AddressFormData> = {};
          const nextReady: Record<string, boolean> = {};
          for (const order of combo.orders) {
            nextForms[order.id] = addressToFormData(order.shipping_address);
            nextReady[order.id] = orderHasCompleteAddress(order);
          }
          setForms(nextForms);
          setReady(nextReady);
        }
      })
      .catch(() => setError(t("paymentError")))
      .finally(() => setLoaded(true));
    getAddresses()
      .then((res) => setSavedAddresses(res?.data ?? []))
      .catch(() => {});
  }, [combinationId, t]);

  // 国家变更 → 加载州/省（逐单）
  const onAddressChange = (
    orderId: string,
    field: keyof AddressFormData,
    value: string,
  ) => {
    setForms((prev) => {
      const next = { ...prev[orderId] };
      next[field] = value;
      if (field === "country_iso") {
        next.state_abbr = "";
        next.state_name = "";
      }
      return { ...prev, [orderId]: next };
    });
    if (field === "country_iso" && value) {
      setLoadingStates((prev) => ({ ...prev, [orderId]: true }));
      getCountry(value)
        .then((c) => {
          setStates((prev) => ({ ...prev, [orderId]: c?.states ?? [] }));
        })
        .catch(() => setStates((prev) => ({ ...prev, [orderId]: [] })))
        .finally(() =>
          setLoadingStates((prev) => ({ ...prev, [orderId]: false })),
        );
    }
  };

  // 保存某笔订单的收货地址（AC-003）
  async function handleSaveShipping(order: Order) {
    const form = forms[order.id];
    if (!form || !addressComplete(form)) {
      toast.error(t("shippingAddressRequired"));
      return;
    }
    setSavingOrderId(order.id);
    const result = await updateOrderShippingAddress(order.id, {
      shipping_address: formDataToAddress(form),
    });
    setSavingOrderId(null);
    if (result.success) {
      toast.success(t("shippingSaved"));
      setReady((prev) => ({ ...prev, [order.id]: true }));
    } else {
      toast.error(result.error);
    }
  }

  // 选择已存地址 → 直接落库（AC-003）
  async function handleUseSavedAddress(orderId: string, addressId: string) {
    setSavingOrderId(orderId);
    const result = await updateOrderShippingAddress(orderId, {
      shipping_address_id: addressId,
    });
    setSavingOrderId(null);
    if (result.success) {
      const addr = savedAddresses.find((a) => a.id === addressId);
      if (addr) {
        setForms((prev) => ({
          ...prev,
          [orderId]: addressToFormData(
            addr as unknown as Order["shipping_address"],
          ),
        }));
      }
      toast.success(t("shippingSaved"));
      setReady((prev) => ({ ...prev, [orderId]: true }));
    } else {
      toast.error(result.error);
    }
  }

  async function handleConfirm() {
    if (!combination || "error" in combination) return;
    const session = combination.payment_session;
    if (!session?.order_id || !session?.id) {
      setError(t("paymentError"));
      setProcessing(false);
      return;
    }
    setProcessing(true);
    setError(null);

    // Confirm the Checkout Session via the PaymentElement first (the session
    // must be confirmed before the backend can complete the combination).
    if (gatewayRef.current) {
      const returnUrl = `${window.location.origin}${basePath}/confirm-payment/${session.order_id}?session=${session.id}`;
      const confirm = await gatewayRef.current.confirmPayment(returnUrl);
      if (confirm.error) {
        setError(confirm.error);
        setProcessing(false);
        return;
      }
    }

    const result = await completeCombinationSession(
      session.order_id,
      session.id,
    );
    if ("error" in result) {
      setError(result.error);
      setProcessing(false);
      return;
    }
    router.replace(`${basePath}/account/orders`);
  }

  if (!loaded) {
    return (
      <div className="flex items-center justify-center py-24">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    );
  }

  if (!combination || "error" in combination) {
    const message =
      combination && "error" in combination
        ? combination.error
        : t("paymentError");
    return <div className="text-center py-24 text-gray-500">{message}</div>;
  }

  const combo = combination;

  return (
    <div className="mx-auto max-w-3xl space-y-6 py-10">
      {/* 标题 */}
      <div className="flex items-center gap-3">
        <PackageCheck className="h-6 w-6 text-gray-600" />
        <h1 className="text-xl font-medium text-gray-900">
          {t("combinedPayment")}
        </h1>
      </div>

      {/* 步骤指示 */}
      <ol className="flex items-center gap-2 text-sm">
        <li
          className={
            step === "shipping"
              ? "font-medium text-indigo-600"
              : "flex items-center gap-1 text-gray-500"
          }
        >
          {step !== "shipping" ? (
            <CheckCircle2 className="h-4 w-4 text-green-500" />
          ) : null}
          1. {t("shippingStep")}
        </li>
        <li className="text-gray-300">→</li>
        <li
          className={
            step === "payment" ? "font-medium text-indigo-600" : "text-gray-500"
          }
        >
          2. {t("paymentStep")}
        </li>
      </ol>

      {error ? (
        <p className="text-sm text-red-600" role="alert">
          {error}
        </p>
      ) : null}

      {/* ============ 步骤 1：收货信息（逐单确认/编辑） ============ */}
      {step === "shipping" ? (
        <>
          <div className="space-y-6">
            {orders.map((order) => {
              const form = forms[order.id] ?? emptyAddress;
              const isReady = ready[order.id] === true;
              const isSaving = savingOrderId === order.id;
              return (
                <div
                  key={order.id}
                  className="rounded-xl border border-gray-200 bg-white p-6"
                >
                  <div className="mb-4 flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <MapPin className="h-4 w-4 text-gray-500" />
                      <h2 className="font-medium text-gray-900">
                        {t("shippingForOrder", { number: order.number })}
                      </h2>
                    </div>
                    {isReady ? (
                      <span className="inline-flex items-center gap-1 text-sm text-green-600">
                        <CheckCircle2 className="h-4 w-4" />
                        {t("shippingConfirmed")}
                      </span>
                    ) : (
                      <span className="text-sm text-amber-600">
                        {t("shippingRequired")}
                      </span>
                    )}
                  </div>

                  {/* 已存地址选择（可选，AC-003） */}
                  {savedAddresses.length > 0 && (
                    <div className="mb-4">
                      <label className="mb-1 block text-sm text-gray-500">
                        {ta("savedAddresses")}
                      </label>
                      <select
                        className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
                        value=""
                        onChange={(e) => {
                          if (e.target.value) {
                            handleUseSavedAddress(order.id, e.target.value);
                          }
                        }}
                      >
                        <option value="">{t("chooseSavedAddress")}</option>
                        {savedAddresses.map((a) => (
                          <option key={a.id} value={a.id}>
                            {a.first_name} {a.last_name} — {a.address1},{" "}
                            {a.city}
                          </option>
                        ))}
                      </select>
                    </div>
                  )}

                  <AddressFormFields
                    address={form}
                    countries={countries}
                    states={states[order.id] ?? []}
                    loadingStates={loadingStates[order.id] === true}
                    onChange={(field, value) =>
                      onAddressChange(order.id, field, value)
                    }
                    idPrefix={`ship-${order.id}`}
                  />

                  <div className="mt-4 flex justify-end">
                    <Button
                      size="sm"
                      disabled={!addressComplete(form) || isSaving}
                      onClick={() => handleSaveShipping(order)}
                    >
                      {isSaving ? (
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      ) : (
                        <CheckCircle2 className="mr-2 h-4 w-4" />
                      )}
                      {t("saveShipping")}
                    </Button>
                  </div>
                </div>
              );
            })}
          </div>

          <Button
            size="lg"
            className="w-full"
            disabled={!allReady}
            onClick={() => setStep("payment")}
          >
            <Wallet className="mr-2 h-4 w-4" />
            {allReady
              ? t("continueToPayment")
              : t("shippingNotReady", {
                  count: orders.filter((o) => ready[o.id] !== true).length,
                })}
          </Button>
        </>
      ) : null}

      {/* ============ 步骤 2：商品明细 + 组合支付 ============ */}
      {step === "payment" ? (
        <>
          {/* 组合金额 */}
          <div className="rounded-xl border border-gray-200 bg-white p-6">
            <dl className="space-y-3 text-sm">
              <div className="flex justify-between">
                <dt className="text-gray-500">{t("total")}</dt>
                <dd className="font-medium text-gray-900">
                  {combo.amount} {combo.currency}
                </dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">{t("paymentStatus")}</dt>
                <dd className="text-gray-900">{combo.status}</dd>
              </div>
            </dl>
          </div>

          {/* 成员订单商品明细（AC-005） */}
          <div className="space-y-6">
            {orders.map((order) => (
              <div
                key={order.id}
                className="rounded-xl border border-gray-200 bg-white p-6"
              >
                <div className="mb-3 flex items-center justify-between">
                  <h2 className="font-medium text-gray-900">
                    {t("orderNumber", { number: order.number })}
                  </h2>
                  <span className="text-sm font-semibold text-gray-900">
                    {order.display_total}
                  </span>
                </div>

                <div className="space-y-3">
                  {(order.items ?? []).map((item) => (
                    <div key={item.id} className="flex items-center gap-3">
                      <div className="relative h-12 w-12 shrink-0 overflow-hidden rounded-lg bg-gray-100">
                        <ProductImage
                          src={item.thumbnail_url}
                          alt={item.name}
                          fill
                          className="object-cover"
                          sizes="48px"
                        />
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm font-medium text-gray-900">
                          {item.name}
                        </p>
                        <p className="text-sm text-gray-500">
                          × {item.quantity}
                        </p>
                      </div>
                      <p className="text-sm font-medium text-gray-900">
                        {item.display_total}
                      </p>
                    </div>
                  ))}
                </div>

                <dl className="mt-4 space-y-1 border-t border-gray-100 pt-3 text-sm">
                  <div className="flex justify-between">
                    <dt className="text-gray-500">{t("subtotal")}</dt>
                    <dd className="text-gray-900">
                      {order.display_item_total}
                    </dd>
                  </div>
                  {order.display_delivery_total &&
                    parseFloat(order.display_delivery_total) > 0 && (
                      <div className="flex justify-between">
                        <dt className="text-gray-500">{t("shipping")}</dt>
                        <dd className="text-gray-900">
                          {order.display_delivery_total}
                        </dd>
                      </div>
                    )}
                  <div className="flex justify-between border-t pt-1">
                    <dt className="font-medium text-gray-900">
                      {t("orderTotal")}
                    </dt>
                    <dd className="font-bold text-gray-900">
                      {order.display_total}
                    </dd>
                  </div>
                </dl>
              </div>
            ))}
          </div>

          {/* Stripe PaymentElement — 无地址输入（AC-007） */}
          {(() => {
            const session = combo.payment_session;
            const secret = session?.external_data?.client_secret as
              | string
              | undefined;
            return secret ? (
              <div className="rounded-xl border border-gray-200 bg-white p-6">
                <StripePaymentForm
                  clientSecret={secret}
                  onReady={(handle) => {
                    gatewayRef.current = handle;
                  }}
                />
              </div>
            ) : null;
          })()}

          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={() => setStep("shipping")}
              disabled={processing}
              className="w-1/3"
            >
              {t("back")}
            </Button>
            <Button
              onClick={handleConfirm}
              disabled={processing}
              className="w-2/3"
              size="lg"
            >
              {processing ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {t("processing")}
                </>
              ) : (
                t("payNow")
              )}
            </Button>
          </div>
        </>
      ) : null}
    </div>
  );
}
