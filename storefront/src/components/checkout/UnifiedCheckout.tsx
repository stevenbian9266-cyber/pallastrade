"use client";

import type {
  Country,
  DeliveryMethod,
  PaymentMethod,
  ShoppingCart,
  State,
} from "@pallastrade/sdk";
import { CreditCard, Loader2, ShoppingBag } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import {
  useCallback,
  useEffect,
  useLayoutEffect,
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
import { Input } from "@/components/ui/input";
import { ProductImage } from "@/components/ui/product-image";
import { useCheckout } from "@/contexts/CheckoutContext";
import { getCountry } from "@/lib/data/countries";
import {
  submitCartOrder,
  updateShoppingCartDetails,
} from "@/lib/data/shopping-cart";
import {
  type AddressFormData,
  addressToFormData,
  emptyAddress,
  formDataToAddress,
} from "@/lib/utils/address";
import { extractBasePath } from "@/lib/utils/path";

interface UnifiedCheckoutProps {
  cart: ShoppingCart;
  shippingMethods: DeliveryMethod[];
  countries: Country[];
}

function UnifiedOrderSummary({ cart }: { cart: ShoppingCart }) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");

  return (
    <div data-testid="unified-order-summary">
      <div className="flex items-center gap-2 mb-4">
        <ShoppingBag className="w-5 h-5 text-gray-500" />
        <h2 className="text-lg font-bold text-gray-900">
          {tc("orderSummary")}
        </h2>
      </div>

      <dl className="space-y-4">
        <div className="flex justify-between">
          <dt className="text-gray-500">{tc("subtotal")}</dt>
          <dd className="text-gray-900">{cart.display_item_total}</dd>
        </div>
        <div className="flex justify-between border-t border-gray-100 pt-4">
          <dt className="text-lg font-medium text-gray-900">{tc("total")}</dt>
          <dd className="text-lg font-bold text-gray-900">
            {cart.display_item_total}
          </dd>
        </div>
      </dl>

      <p className="mt-3 text-xs text-gray-400">
        {t("shippingCalculatedAtSubmit")}
      </p>
    </div>
  );
}

/**
 * 下单链路统一化（PRD-20260830-checkout，场景 A/B）：统一下单页 — 购物车模式。
 * 左侧：收件地址 + 商品信息 + 物流方式 + 支付方式选择（选中后显示对应支付表单）；
 * 右侧：订单小结 + Pay Now。
 * 支付流程（同页完成，不跳转独立支付页）：
 *   1) Pay Now → PATCH cart（保存邮箱/地址/物流）→ Carts::Submit 生成 or_ 订单；
 *   2) Stripe（自绘卡字段，PRD-20260831-payments-stripe-自绘卡支付表单）→ 创建
 *      PaymentIntent 会话（pi_..._secret）→ 自绘卡字段 createPaymentMethod +
 *      confirmCardPayment 完成支付；支付失败 → 跳 or_ 支付页可重试；
 *   3) 支付成功 → completeOrderPaymentSession + completeOrder → /order-placed。
 * 非会话类（Check/Store Credit）→ 提交后直接跳完成页（线下收款）。
 * 参考阿里国际站：确认 + 支付同一页面，选择支付方式即显示对应表单。
 */
export function UnifiedCheckout({
  cart,
  shippingMethods,
  countries,
}: UnifiedCheckoutProps) {
  const t = useTranslations("checkout");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const { setSummaryContent } = useCheckout();

  const paymentMethods: PaymentMethod[] = cart.payment_methods ?? [];
  const [email, setEmail] = useState(cart.email ?? "");
  const [address, setAddress] = useState<AddressFormData>(
    cart.shipping_address
      ? addressToFormData(cart.shipping_address)
      : emptyAddress,
  );
  const [shippingMethodId, setShippingMethodId] = useState(
    cart.shipping_method_id ?? "",
  );
  const [paymentMethodId, setPaymentMethodId] = useState(
    paymentMethods[0]?.id ?? "",
  );
  const [states, setStates] = useState<State[]>([]);
  const [loadingStates, setLoadingStates] = useState(false);

  // ── 支付（同页完成）──────────────────────────────────────────────
  // 会话类支付方式需创建订单支付会话获取 client_secret；订单 id 存 ref 防重入
  const [payProcessing, setPayProcessing] = useState(false);
  const cardFormRef = useRef<CardPaymentFormHandle | null>(null);
  const orderIdRef = useRef<string | null>(null);

  const selectedMethod =
    paymentMethods.find((m) => m.id === paymentMethodId) ?? paymentMethods[0];
  const isSessionBased = selectedMethod?.session_required === true;
  const isStripe = selectedMethod?.type === "stripe";

  // The checkout route group owns the real desktop sticky sidebar. Publish the
  // summary there instead of nesting another three-column grid inside its main
  // content column.
  useLayoutEffect(() => {
    setSummaryContent(<UnifiedOrderSummary cart={cart} />);
    return () => setSummaryContent(null);
  }, [cart, setSummaryContent]);

  // 国家变更 → 加载州/省
  useEffect(() => {
    if (!address.country_iso) {
      setStates([]);
      return;
    }
    let active = true;
    setLoadingStates(true);
    getCountry(address.country_iso)
      .then((country) => {
        if (active) setStates(country?.states ?? []);
      })
      .catch(() => setStates([]))
      .finally(() => {
        if (active) setLoadingStates(false);
      });
    return () => {
      active = false;
    };
  }, [address.country_iso]);

  const onAddressChange = (field: keyof AddressFormData, value: string) => {
    setAddress((prev) => {
      const next = { ...prev, [field]: value };
      // 国家变更清空州/省
      if (field === "country_iso") {
        next.state_abbr = "";
        next.state_name = "";
      }
      return next;
    });
  };

  // 地址完整性校验（必要字段）
  const addressComplete = Boolean(
    address.first_name &&
      address.last_name &&
      address.address1 &&
      address.city &&
      address.postal_code &&
      address.country_iso &&
      (address.state_abbr || address.state_name),
  );
  const canSubmit =
    email.trim().length > 0 &&
    addressComplete &&
    shippingMethodId.length > 0 &&
    paymentMethodId.length > 0;

  const handleCardReady = useCallback((handle: CardPaymentFormHandle) => {
    cardFormRef.current = handle;
  }, []);

  const submitCartForPayment = useCallback(async (): Promise<string | null> => {
    if (orderIdRef.current) return orderIdRef.current;

    const saveResult = await updateShoppingCartDetails(cart.id, {
      email: email || undefined,
      shipping_address: formDataToAddress(address),
      shipping_method_id: shippingMethodId || undefined,
    });
    if (saveResult && "success" in saveResult && !saveResult.success) {
      toast.error(saveResult.error);
      return null;
    }

    try {
      const order = await submitCartOrder(cart.id);
      orderIdRef.current = order.id;
      return order.id;
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : "Failed to submit order",
      );
      return null;
    }
  }, [address, cart.id, email, shippingMethodId]);

  // Stripe 自绘卡字段（PRD-20260831-payments-stripe-自绘卡支付表单）：
  // 表单始终渲染（不依赖 client_secret / js.stripe.com），Pay Now 时
  // 提交订单并立即跳转 or_ 支付页（?pm= 预选），在 or_ 页创建
  // PaymentIntent 会话 + confirmCardPayment。
  //
  // 为什么不在 cart_ 页同页支付：提交订单后（cart → or_），本页后续任何
  // server action 完成都会触发 Next.js 自动 router.refresh →
  // CheckoutDataLoader 发现 cart 已转订单 → 重定向回购物车页抢占导航 →
  // "Your cart is empty" bug。提交后立刻离开本页，refresh 落在 or_ 页上
  // （订单存在，安全）。
  const handlePayNow = async () => {
    if (!canSubmit || payProcessing || !selectedMethod) return;

    if (isSessionBased) {
      // Stripe / PayPal / Adyen 等会话类：提交订单 → 立即跳 or_ 支付页
      setPayProcessing(true);
      try {
        const targetOrderId = await submitCartForPayment();
        if (targetOrderId) {
          router.replace(
            `${basePath}/checkout/${targetOrderId}?pm=${selectedMethod.id}`,
          );
        }
      } finally {
        setPayProcessing(false);
      }
      return;
    }

    setPayProcessing(true);
    try {
      const targetOrderId = await submitCartForPayment();
      if (targetOrderId) {
        router.push(`${basePath}/order-placed/${targetOrderId}`);
      }
    } finally {
      setPayProcessing(false);
    }
  };

  const handlePaymentMethodChange = (methodId: string) => {
    if (methodId === paymentMethodId) return;
    setPaymentMethodId(methodId);
    cardFormRef.current = null;
  };

  return (
    <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">
        {t("orderConfirmation")}
      </h1>

      <div className="space-y-8">
        {/* 收件地址信息 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-bold text-gray-900 mb-4">
            {t("shippingAddress")}
          </h2>
          <div className="mb-4">
            <Input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder={t("emailPlaceholder")}
              aria-label={t("email")}
            />
          </div>
          <AddressFormFields
            address={address}
            countries={countries}
            states={states}
            loadingStates={loadingStates}
            onChange={onAddressChange}
            idPrefix="unified"
          />
        </section>

        {/* 商品信息 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-bold text-gray-900 mb-4">{t("items")}</h2>
          <div className="space-y-4 divide-y divide-gray-100">
            {cart.items.map((item) => (
              <div key={item.id} className="flex gap-4 pt-4 first:pt-0">
                <div className="relative w-16 h-16 bg-gray-100 rounded-lg overflow-hidden shrink-0">
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
                  {item.display_amount}
                </p>
              </div>
            ))}
          </div>
        </section>

        {/* 物流方式 */}
        {shippingMethods.length > 0 && (
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-lg font-bold text-gray-900 mb-4">
              {t("deliveryMethod")}
            </h2>
            <div className="flex flex-col gap-3">
              {shippingMethods.map((method) => (
                <label
                  key={method.id}
                  className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer hover:border-indigo-300"
                >
                  <input
                    type="radio"
                    name="shipping-method"
                    checked={shippingMethodId === method.id}
                    onChange={() => setShippingMethodId(method.id ?? "")}
                    className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                  />
                  <div className="flex-1">
                    <p className="font-medium text-gray-900">{method.name}</p>
                    {method.display_estimated_price && (
                      <p className="text-sm text-gray-500">
                        {method.display_estimated_price}
                      </p>
                    )}
                  </div>
                </label>
              ))}
            </div>
          </section>
        )}

        {/* 支付方式选择 + 对应表单 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <h2 className="text-lg font-bold text-gray-900 mb-4">
            {t("paymentMethod")}
          </h2>
          {paymentMethods.length === 0 ? (
            <div className="rounded-sm border bg-gray-50 px-4 py-8 text-center">
              <CreditCard
                className="w-10 h-10 text-gray-300 mx-auto mb-3"
                strokeWidth={1.5}
              />
              <p className="text-sm text-gray-500">{t("noPaymentMethods")}</p>
            </div>
          ) : (
            <div className="flex flex-col gap-3">
              {paymentMethods.map((method) => (
                <label
                  key={method.id}
                  className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer hover:border-indigo-300 ${
                    paymentMethodId === method.id
                      ? "border-indigo-400 bg-indigo-50/40"
                      : "border-gray-200"
                  }`}
                >
                  <input
                    type="radio"
                    name="payment-method"
                    checked={paymentMethodId === method.id}
                    onChange={() => handlePaymentMethodChange(method.id ?? "")}
                    className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                  />
                  <div className="flex-1">
                    <p className="font-medium text-gray-900">{method.name}</p>
                  </div>
                </label>
              ))}
            </div>
          )}

          {/* 选中支付方式后的对应表单 */}
          {selectedMethod ? (
            <div className="mt-4">
              {isSessionBased && isStripe ? (
                // Stripe 自绘卡字段（PRD-20260831-payments-stripe-自绘卡支付表单）：
                // 纯 HTML 卡字段立即渲染，不依赖 client_secret / js.stripe.com iframe。
                <div className="rounded-lg border border-gray-200 p-4">
                  <CardPaymentForm onReady={handleCardReady} />
                </div>
              ) : isSessionBased ? (
                // 其他会话类支付方式（PayPal/Adyen 等）：同页支付或跳转由网关决定
                <p className="text-sm text-gray-500">{t("processing")}</p>
              ) : (
                // 非会话类（Check/Store Credit）：线下收款说明
                <div className="rounded-sm border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-600">
                  {t("manualPaymentInfo")}
                </div>
              )}
            </div>
          ) : null}

          <Button
            size="lg"
            className="w-full mt-6"
            disabled={!canSubmit || payProcessing}
            onClick={handlePayNow}
          >
            {payProcessing ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                {t("submitting")}
              </>
            ) : (
              t("payNow")
            )}
          </Button>
        </section>
      </div>
    </div>
  );
}
