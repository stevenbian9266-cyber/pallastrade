"use client";

import type {
  Cart,
  Country,
  DeliveryMethod,
  PaymentMethod,
  ShoppingCart,
  State,
} from "@pallastrade/sdk";
import {
  BadgeCheck,
  CircleAlert,
  CreditCard,
  Headset,
  Loader2,
  RefreshCcw,
  ShoppingBag,
  Truck,
} from "lucide-react";
import Link from "next/link";
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
import { AddOnsSection } from "@/components/checkout/AddOnsSection";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import {
  CardPaymentForm,
  type CardPaymentFormHandle,
} from "@/components/checkout/CardPaymentForm";
import { CheckoutSectionTitle } from "@/components/checkout/CheckoutSectionTitle";
import { CouponCode } from "@/components/checkout/CouponCode";
import { SaveInfoSection } from "@/components/checkout/SaveInfoSection";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { ProductImage } from "@/components/ui/product-image";
import { useCheckout } from "@/contexts/CheckoutContext";
import { getCountry } from "@/lib/data/countries";
import {
  type AddressFormData,
  addressToFormData,
  emptyAddress,
  formDataToAddress,
} from "@/lib/utils/address";
import { safeParseFloat } from "@/lib/utils/format";
import { extractBasePath } from "@/lib/utils/path";

interface UnifiedCheckoutProps {
  cart: ShoppingCart;
  shippingMethods: DeliveryMethod[];
  countries: Country[];
  isAuthenticated: boolean;
}

interface CouponHandlers {
  onApply: (code: string) => Promise<{ success: boolean; error?: string }>;
  onRemoveDiscount: (
    code: string,
  ) => Promise<{ success: boolean; error?: string }>;
  onRemoveGiftCard: (
    giftCardId: string,
  ) => Promise<{ success: boolean; error?: string }>;
}

/**
 * 折扣码/礼品卡应用后由 BFF 返回的完整 Cart（含 discount_total / tax_total /
 * gift_card 等字段）。未应用时基于 ShoppingCart 构造空壳以满足 CouponCode
 * 对 Cart 类型的读取。
 */
function buildCouponCart(cart: ShoppingCart, discountCart: Cart | null): Cart {
  if (discountCart) return discountCart;
  return {
    ...cart,
    discounts: [],
    gift_card: null,
    discount_total: null,
    display_discount_total: null,
    tax_total: null,
    display_tax_total: null,
    gift_card_total: null,
    display_gift_card_total: null,
    store_credit_total: null,
    display_store_credit_total: null,
    amount_due: null,
    display_total: cart.display_item_total,
  } as unknown as Cart;
}

function UnifiedOrderSummary({
  cart,
  discountCart,
  couponHandlers,
}: {
  cart: ShoppingCart;
  discountCart: Cart | null;
  couponHandlers: CouponHandlers;
}) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const couponCart = buildCouponCart(cart, discountCart);

  // TOTAL SAVINGS — sum of discount + gift card + store credit amounts.
  const savings =
    Math.abs(safeParseFloat(couponCart.discount_total) || 0) +
    Math.abs(safeParseFloat(couponCart.gift_card_total) || 0) +
    Math.abs(safeParseFloat(couponCart.store_credit_total) || 0);
  const hasDiscounts =
    discountCart !== null && (savings > 0 || couponCart.discounts?.length > 0);

  const trustBenefits = [
    { icon: RefreshCcw, label: t("benefitMoneyBack") },
    { icon: BadgeCheck, label: t("benefitWarranty") },
    { icon: Headset, label: t("benefitSupport") },
    { icon: Truck, label: t("benefitFreeShipping") },
  ];

  return (
    <div data-testid="unified-order-summary">
      <div className="flex items-center gap-2 mb-4">
        <ShoppingBag className="w-5 h-5 text-gray-500" />
        <h2 className="text-lg font-bold text-gray-900">
          {tc("orderSummary")}
        </h2>
      </div>

      {/* Line items — quantity badge top-right */}
      <div className="space-y-4 pb-6">
        {cart.items.map((item) => (
          <div key={item.id} className="flex items-center gap-4">
            <div className="relative w-[64px] h-[64px] flex-shrink-0">
              <div className="relative w-full h-full rounded-lg overflow-hidden border border-gray-200 bg-gray-50">
                <ProductImage
                  src={item.thumbnail_url}
                  alt={item.name}
                  fill
                  className="object-cover"
                  iconClassName="w-6 h-6"
                />
              </div>
              <div className="absolute -top-2 -right-2 w-5 h-5 bg-[rgba(114,114,114,0.9)] text-white text-[11px] font-medium rounded-full flex items-center justify-center">
                {item.quantity}
              </div>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-gray-900 leading-snug">
                {item.name}
              </p>
              {item.options_text && (
                <p className="text-xs text-gray-500 mt-0.5">
                  {item.options_text}
                </p>
              )}
            </div>
            <div className="text-sm text-gray-900">{item.display_amount}</div>
          </div>
        ))}
      </div>

      {/* Discount code / gift card module */}
      <div className="border-t border-gray-200 pt-4 pb-2">
        <CouponCode
          cart={couponCart}
          onApply={couponHandlers.onApply}
          onRemoveDiscount={couponHandlers.onRemoveDiscount}
          onRemoveGiftCard={couponHandlers.onRemoveGiftCard}
        />
      </div>

      {/* Price breakdown */}
      <dl className="border-t border-gray-200 pt-4 space-y-2">
        <div className="flex justify-between text-sm">
          <dt className="text-gray-700">{tc("subtotal")}</dt>
          <dd className="text-gray-900">{cart.display_item_total}</dd>
        </div>

        {/* Shipping — FREE highlighted green when a zero-cost method is selected */}
        <div className="flex justify-between text-sm">
          <dt className="text-gray-700">{tc("shipping")}</dt>
          <dd className="text-gray-900">{t("shippingCalculatedAtSubmit")}</dd>
        </div>

        {hasDiscounts && safeParseFloat(couponCart.discount_total) !== 0 && (
          <div className="flex justify-between text-sm">
            <dt className="text-gray-700">{tc("discount")}</dt>
            <dd className="text-green-700">
              {couponCart.display_discount_total}
            </dd>
          </div>
        )}

        {safeParseFloat(couponCart.tax_total) > 0 && (
          <div className="flex justify-between text-sm">
            <dt className="text-gray-700">{t("estimatedTaxes")}</dt>
            <dd className="text-gray-900">{couponCart.display_tax_total}</dd>
          </div>
        )}

        {couponCart.gift_card &&
          safeParseFloat(couponCart.gift_card_total) > 0 && (
            <div className="flex justify-between text-sm">
              <dt className="text-gray-700">{tc("giftCard")}</dt>
              <dd className="text-green-700">
                -{couponCart.display_gift_card_total}
              </dd>
            </div>
          )}

        <div className="flex justify-between items-baseline pt-3 border-t border-gray-100">
          <dt className="text-lg font-medium text-gray-900">{tc("total")}</dt>
          <dd className="text-lg font-bold text-gray-900">
            {discountCart?.display_total ?? cart.display_item_total}
          </dd>
        </div>
      </dl>

      {/* TOTAL SAVINGS — green band when any discount applies */}
      {hasDiscounts && savings > 0 && (
        <div
          data-testid="total-savings"
          className="mt-4 rounded-md bg-green-50 px-3 py-2 text-center text-[13px] font-bold text-green-700"
        >
          {t("totalSavings", {
            amount: couponCart.display_total
              ? buildSavingsLabel(couponCart, savings)
              : "",
          })}
        </div>
      )}

      {/* Why Buy From Us — trust benefits */}
      <div className="mt-6 pt-6 border-t border-gray-200">
        <h3 className="text-sm font-bold text-gray-900 mb-3">
          {t("whyBuyFromUs")}
        </h3>
        <ul className="space-y-2">
          {trustBenefits.map(({ icon: Icon, label }) => (
            <li
              key={label}
              className="flex items-center gap-2.5 text-[13px] text-gray-600"
            >
              <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary-50 shrink-0">
                <Icon className="h-4 w-4 text-primary" aria-hidden="true" />
              </span>
              {label}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}

/** Format TOTAL SAVINGS amount from the applied discount cart. */
function buildSavingsLabel(cart: Cart, savings: number): string {
  const currency = cart.currency ?? "USD";
  try {
    return new Intl.NumberFormat("en", {
      style: "currency",
      currency,
    }).format(savings);
  } catch {
    return `${currency} ${savings.toFixed(2)}`;
  }
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
  isAuthenticated,
}: UnifiedCheckoutProps) {
  const t = useTranslations("checkout");
  const tcoupon = useTranslations("coupon");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const { setSummaryContent } = useCheckout();

  const paymentMethods: PaymentMethod[] = cart.payment_methods ?? [];
  const [email, setEmail] = useState(cart.email ?? "");
  const [emailError, setEmailError] = useState<string | null>(null);
  // Marketing opt-in — UI placeholder (backend subscription API not integrated).
  const [marketingOptIn, setMarketingOptIn] = useState(true);
  // SMS opt-in — UI placeholder (backend subscription API not integrated).
  const [smsOptIn, setSmsOptIn] = useState(false);
  const [address, setAddress] = useState<AddressFormData>(
    cart.shipping_address
      ? addressToFormData(cart.shipping_address)
      : emptyAddress,
  );
  const [shippingMethodId, setShippingMethodId] = useState(
    cart.shipping_method_id ?? "",
  );
  // PRD: Credit card 默认选中（优先 Stripe，否则回退第一个可用方式）。
  const [paymentMethodId, setPaymentMethodId] = useState(
    paymentMethods.find((m) => m.type === "stripe")?.id ??
      paymentMethods[0]?.id ??
      "",
  );
  const [states, setStates] = useState<State[]>([]);
  const [loadingStates, setLoadingStates] = useState(false);

  // ── Billing address（PRD 3.6：Use shipping address as billing address，
  //    默认勾选；取消时展开独立账单地址表单）──────────────────────────
  const [useShippingForBilling, setUseShippingForBilling] = useState(true);
  const [billAddress, setBillAddress] = useState<AddressFormData>(
    cart.billing_address
      ? addressToFormData(cart.billing_address)
      : emptyAddress,
  );
  const [billStates, setBillStates] = useState<State[]>([]);
  const [loadingBillStates, setLoadingBillStates] = useState(false);

  // ── 折扣码 / 礼品卡（右栏 Order summary，BFF /api/checkout/coupon）──
  const [discountCart, setDiscountCart] = useState<Cart | null>(null);

  // ── 支付（同页完成）──────────────────────────────────────────────
  // 会话类支付方式需创建订单支付会话获取 client_secret；订单 id 存 ref 防重入
  const [payProcessing, setPayProcessing] = useState(false);
  const [processingStage, setProcessingStage] = useState<
    "idle" | "submitting" | "confirming"
  >("idle");
  const cardFormRef = useRef<CardPaymentFormHandle | null>(null);
  const orderIdRef = useRef<string | null>(null);

  const selectedMethod =
    paymentMethods.find((m) => m.id === paymentMethodId) ?? paymentMethods[0];
  const isSessionBased = selectedMethod?.session_required === true;
  const isStripe = selectedMethod?.type === "stripe";

  // 折扣码回调（BFF 保持 SDK 凭证/guest token 服务端）
  const handleCouponApply = useCallback(
    async (code: string) => {
      try {
        const res = await fetch("/api/checkout/coupon", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ cart_id: cart.id, code, kind: "discount" }),
        });
        const data = (await res.json()) as { cart?: Cart; error?: string };
        if (!res.ok || !data.cart) {
          return {
            success: false,
            error: data.error ?? tcoupon("applyFailed"),
          };
        }
        setDiscountCart(data.cart);
        return { success: true };
      } catch {
        return { success: false, error: tcoupon("applyFailed") };
      }
    },
    [cart.id, tcoupon],
  );

  const handleCouponRemove = useCallback(
    async (code: string) => {
      try {
        const res = await fetch("/api/checkout/coupon", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ cart_id: cart.id, code, kind: "discount" }),
        });
        const data = (await res.json()) as { cart?: Cart; error?: string };
        if (!res.ok || !data.cart) {
          return {
            success: false,
            error: data.error ?? tcoupon("applyFailed"),
          };
        }
        setDiscountCart(data.cart);
        return { success: true };
      } catch {
        return { success: false, error: tcoupon("applyFailed") };
      }
    },
    [cart.id, tcoupon],
  );

  const handleGiftCardRemove = useCallback(
    async (giftCardId: string) => {
      try {
        const res = await fetch("/api/checkout/coupon", {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            cart_id: cart.id,
            gift_card_id: giftCardId,
            kind: "gift_card",
          }),
        });
        const data = (await res.json()) as { cart?: Cart; error?: string };
        if (!res.ok || !data.cart) {
          return {
            success: false,
            error: data.error ?? tcoupon("applyFailed"),
          };
        }
        setDiscountCart(data.cart);
        return { success: true };
      } catch {
        return { success: false, error: tcoupon("applyFailed") };
      }
    },
    [cart.id, tcoupon],
  );

  // 折扣码 handlers 用 ref 保持最新引用，避免 useTranslations 每次渲染产生新
  // 函数导致 summary 发布 effect 依赖变化 → setState 无限循环。
  const couponHandlersRef = useRef<CouponHandlers>({
    onApply: handleCouponApply,
    onRemoveDiscount: handleCouponRemove,
    onRemoveGiftCard: handleGiftCardRemove,
  });
  useLayoutEffect(() => {
    couponHandlersRef.current = {
      onApply: handleCouponApply,
      onRemoveDiscount: handleCouponRemove,
      onRemoveGiftCard: handleGiftCardRemove,
    };
  });

  // The checkout route group owns the real desktop sticky sidebar. Publish the
  // summary there instead of nesting another three-column grid inside its main
  // content column.
  useLayoutEffect(() => {
    setSummaryContent(
      <UnifiedOrderSummary
        cart={cart}
        discountCart={discountCart}
        couponHandlers={couponHandlersRef.current}
      />,
    );
    return () => setSummaryContent(null);
  }, [cart, discountCart, setSummaryContent]);

  // 国家变更 → 加载州/省（配送地址）
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

  // 国家变更 → 加载州/省（账单地址）
  useEffect(() => {
    if (!billAddress.country_iso) {
      setBillStates([]);
      return;
    }
    let active = true;
    setLoadingBillStates(true);
    getCountry(billAddress.country_iso)
      .then((country) => {
        if (active) setBillStates(country?.states ?? []);
      })
      .catch(() => setBillStates([]))
      .finally(() => {
        if (active) setLoadingBillStates(false);
      });
    return () => {
      active = false;
    };
  }, [billAddress.country_iso]);

  // 邮箱失焦校验（PRD 3.2）
  const handleEmailBlur = useCallback(() => {
    const trimmed = email.trim();
    if (!trimmed) {
      setEmailError(null);
      return;
    }
    const valid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed);
    setEmailError(valid ? null : t("invalidEmail"));
  }, [email, t]);

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

  const onBillAddressChange = (field: keyof AddressFormData, value: string) => {
    setBillAddress((prev) => {
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
  // 注意：email 不参与 canSubmit——PRD 3.2 要求点击 Pay now 时邮箱为空要
  // 弹提示（而非直接 disabled），由 handlePayNow 前置校验处理。
  const canSubmit =
    addressComplete &&
    shippingMethodId.length > 0 &&
    paymentMethodId.length > 0;

  const handleCardReady = useCallback((handle: CardPaymentFormHandle) => {
    cardFormRef.current = handle;
  }, []);

  // The same-origin Route Handler performs Cart update + idempotent submit +
  // PaymentSession start without a Server Action/RSC refresh. Stripe confirmation
  // therefore remains in this single Pay click.
  const handlePayNow = async () => {
    if (!canSubmit || payProcessing || !selectedMethod) return;
    // PRD 3.2 异常：点击 Pay now 时邮箱为空 → 提示
    if (!email.trim()) {
      setEmailError(t("emailRequired"));
      toast.error(t("emailRequired"));
      return;
    }
    if (emailError) {
      toast.error(emailError);
      return;
    }
    if (isSessionBased && isStripe && !cardFormRef.current?.validate()) return;

    setPayProcessing(true);
    setProcessingStage("submitting");
    try {
      const response = await fetch("/api/checkout/start", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          cart_id: cart.id,
          payment_method_id: selectedMethod.id,
          ...(isStripe && { payment_mode: "payment_intent" }),
          checkout: {
            email: email || undefined,
            shipping_address: formDataToAddress(address),
            shipping_method_id: shippingMethodId || undefined,
            ...(useShippingForBilling
              ? { use_shipping: true }
              : { billing_address: formDataToAddress(billAddress) }),
          },
        }),
      });
      const result = (await response.json()) as {
        order?: { id: string };
        order_id?: string;
        session?: {
          id: string;
          external_data?: Record<string, unknown>;
        } | null;
        error?: string;
      };
      const targetOrderId = result.order?.id ?? result.order_id;
      if (targetOrderId) orderIdRef.current = targetOrderId;

      if (!response.ok || !targetOrderId) {
        if (targetOrderId) {
          router.replace(`${basePath}/payment-result/${targetOrderId}`);
        } else {
          toast.error(result.error ?? t("checkoutError"));
        }
        return;
      }

      const session = result.session;
      if (isSessionBased && isStripe && session) {
        const clientSecret = session.external_data?.client_secret;
        if (typeof clientSecret !== "string") {
          router.replace(
            `${basePath}/payment-result/${targetOrderId}?session=${session.id}`,
          );
          return;
        }

        setProcessingStage("confirming");
        await cardFormRef.current?.confirmPayment(
          decodeURIComponent(clientSecret),
        );

        // Complete on both success and provider rejection so the server records
        // the authoritative terminal session state for the result page.
        await fetch("/api/checkout/start", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            order_id: targetOrderId,
            session_id: session.id,
          }),
        }).catch(() => null);

        router.replace(
          `${basePath}/payment-result/${targetOrderId}?session=${session.id}`,
        );
        return;
      }

      router.replace(`${basePath}/payment-result/${targetOrderId}`);
    } catch (error) {
      const targetOrderId = orderIdRef.current;
      if (targetOrderId) {
        router.replace(`${basePath}/payment-result/${targetOrderId}`);
      } else {
        toast.error(
          error instanceof Error ? error.message : t("checkoutError"),
        );
      }
    } finally {
      setPayProcessing(false);
      setProcessingStage("idle");
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
        {/* 1 Contact — 邮箱 + 登录入口 + 营销订阅 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <div className="flex items-baseline justify-between mb-4">
            <CheckoutSectionTitle step={1} title={t("contactInformation")} />
            {!isAuthenticated && (
              <div className="flex items-center gap-2.5 text-[13px]">
                <Link
                  href={`${basePath}/account?redirect=${encodeURIComponent(pathname)}`}
                  className="text-gray-700 underline underline-offset-2 hover:text-black"
                >
                  {t("signIn")}
                </Link>
                <span className="text-gray-300" aria-hidden="true">
                  /
                </span>
                <Link
                  href={`${basePath}/account/register`}
                  className="text-gray-700 underline underline-offset-2 hover:text-black"
                >
                  {t("signUp")}
                </Link>
              </div>
            )}
          </div>
          <Input
            type="email"
            value={email}
            onChange={(e) => {
              setEmail(e.target.value);
              if (emailError) setEmailError(null);
            }}
            onBlur={handleEmailBlur}
            placeholder={t("emailPlaceholder")}
            aria-label={t("email")}
            aria-invalid={!!emailError}
            data-testid="checkout-email"
          />
          {emailError && (
            <p
              className="mt-1 text-xs text-red-600"
              role="alert"
              data-testid="email-error"
            >
              {emailError}
            </p>
          )}
          {/* Marketing subscription — UI placeholder (backend not integrated) */}
          <label
            className="flex items-center gap-2.5 mt-3 cursor-pointer"
            data-testid="marketing-opt-in"
          >
            <Checkbox
              checked={marketingOptIn}
              onCheckedChange={(checked) => setMarketingOptIn(checked === true)}
            />
            <span className="text-[13px] text-gray-600">
              {t("marketingOptIn")}
            </span>
          </label>
        </section>

        {/* 2 Delivery address */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <CheckoutSectionTitle
            step={2}
            title={t("shippingAddress")}
            className="mb-4"
          />
          <AddressFormFields
            address={address}
            countries={countries}
            states={states}
            loadingStates={loadingStates}
            onChange={onAddressChange}
            idPrefix="unified"
            showSmsOptIn
            smsOptIn={smsOptIn}
            onSmsOptInChange={setSmsOptIn}
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

        {/* 3 Shipping method */}
        {shippingMethods.length > 0 && (
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <CheckoutSectionTitle
              step={3}
              title={t("shippingMethod")}
              className="mb-4"
            />
            {/* PRD 3.4：配送选项变化黄色警告框（占位，后端推送变更信号后驱动） */}
            <div
              className="flex items-start gap-2.5 rounded-md border border-amber-200 bg-amber-50 px-4 py-3 mb-4"
              data-testid="shipping-options-changed"
            >
              <CircleAlert
                className="h-4 w-4 text-amber-500 shrink-0 mt-0.5"
                aria-hidden="true"
              />
              <span className="text-[13px] text-amber-800">
                {t("shippingOptionsChanged")}
              </span>
            </div>
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
            <p className="text-xs text-gray-500 mt-2">
              {t("shippingRestrictionNote")}
            </p>
          </section>
        )}

        {/* 4 Add-ons — value-added service (UI placeholder) */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <AddOnsSection />
        </section>

        {/* 5 Payment — 支付方式选择 + 对应表单 */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <CheckoutSectionTitle step={5} title={t("paymentMethod")} />
          <p className="text-sm text-gray-500 mt-1 mb-4">
            {t("secureTransactions")}
          </p>
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
                  {/* PRD 3.6：Use shipping address as billing address（默认勾选） */}
                  <div className="mt-4">
                    <label
                      className="flex items-center gap-2.5 cursor-pointer"
                      data-testid="billing-use-shipping"
                    >
                      <Checkbox
                        checked={useShippingForBilling}
                        onCheckedChange={(checked) =>
                          setUseShippingForBilling(checked === true)
                        }
                      />
                      <span className="text-sm text-gray-900">
                        {t("sameAsShipping")}
                      </span>
                    </label>
                    {!useShippingForBilling && (
                      <div className="mt-4">
                        <h3 className="text-sm font-bold text-gray-900 mb-3">
                          {t("billingAddress")}
                        </h3>
                        <AddressFormFields
                          address={billAddress}
                          countries={countries}
                          states={billStates}
                          loadingStates={loadingBillStates}
                          onChange={onBillAddressChange}
                          idPrefix="bill"
                        />
                      </div>
                    )}
                  </div>
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
                {processingStage === "confirming"
                  ? t("processing")
                  : t("submitting")}
              </>
            ) : (
              t("payNow")
            )}
          </Button>
        </section>

        {/* Save my information — UI placeholder */}
        <section className="bg-white rounded-xl border border-gray-200 p-6">
          <SaveInfoSection isAuthenticated={isAuthenticated} />
        </section>
      </div>
    </div>
  );
}
