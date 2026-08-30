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
import { useEffect, useState, useTransition } from "react";
import { toast } from "sonner";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ProductImage } from "@/components/ui/product-image";
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

/**
 * 下单链路统一化（PRD-20260830-checkout，场景 A/B）：统一下单页 — 购物车模式。
 * 左侧：收件地址 + 商品信息 + 物流方式 + 支付方式选择；右侧：订单小结 + Pay Now。
 * Pay Now 内联「保存(PATCH cart) + 提交(Carts::Submit 生成 or_ 订单)」，
 * 提交后 router.replace 到 /checkout/[orderId]（同页切换为订单支付态）。
 * 参考阿里国际站：确认 + 支付同一页面，一次 Pay Now 完成。
 */
export function UnifiedCheckout({
  cart,
  shippingMethods,
  countries,
}: UnifiedCheckoutProps) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);
  const [isPending, startTransition] = useTransition();

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

  const handlePayNow = () => {
    if (!canSubmit || isPending) return;
    startTransition(async () => {
      // 1. 保存 email/收件地址/物流方式到购物车
      const saveResult = await updateShoppingCartDetails(cart.id, {
        email: email || undefined,
        shipping_address: formDataToAddress(address),
        shipping_method_id: shippingMethodId || undefined,
      });
      if (saveResult && "success" in saveResult && !saveResult.success) {
        toast.error(saveResult.error);
        return;
      }
      // 2. 提交订单（Carts::Submit → or_ 订单 pending）
      try {
        const order = await submitCartOrder(cart.id);
        // 3. 同页切换为订单支付态（携带预选支付方式）
        const pm = paymentMethodId
          ? `?pm=${encodeURIComponent(paymentMethodId)}`
          : "";
        router.replace(`${basePath}/checkout/${order.id}${pm}`);
      } catch (error) {
        toast.error(
          error instanceof Error ? error.message : "Failed to submit order",
        );
      }
    });
  };

  return (
    <div className="mx-auto max-w-6xl px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">
        {t("orderConfirmation")}
      </h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* 左侧 — 订单基础信息 */}
        <div className="lg:col-span-2 space-y-8">
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
            <h2 className="text-lg font-bold text-gray-900 mb-4">
              {t("items")}
            </h2>
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

          {/* 支付方式选择 */}
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
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 cursor-pointer hover:border-indigo-300"
                  >
                    <input
                      type="radio"
                      name="payment-method"
                      checked={paymentMethodId === method.id}
                      onChange={() => setPaymentMethodId(method.id ?? "")}
                      className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
                    />
                    <div className="flex-1">
                      <p className="font-medium text-gray-900">{method.name}</p>
                    </div>
                  </label>
                ))}
              </div>
            )}
          </section>
        </div>

        {/* 右侧 — 订单小结 */}
        <div className="lg:col-span-1">
          <div className="bg-white rounded-xl border border-gray-200 p-6 sticky top-24">
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
                <dt className="text-lg font-medium text-gray-900">
                  {tc("total")}
                </dt>
                <dd className="text-lg font-bold text-gray-900">
                  {cart.display_item_total}
                </dd>
              </div>
            </dl>

            <p className="mt-3 text-xs text-gray-400">
              {t("shippingCalculatedAtSubmit")}
            </p>

            <Button
              size="lg"
              className="w-full mt-6"
              disabled={!canSubmit || isPending}
              onClick={handlePayNow}
            >
              {isPending ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  {t("submitting")}
                </>
              ) : (
                t("payNow")
              )}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
