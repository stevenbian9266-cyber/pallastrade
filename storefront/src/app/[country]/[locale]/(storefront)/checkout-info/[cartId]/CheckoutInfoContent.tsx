"use client";

import type { Country, DeliveryMethod, ShoppingCart } from "@pallastrade/sdk";
import { useTranslations } from "next-intl";
import { useEffect, useState, useTransition } from "react";
import { toast } from "sonner";
import { AddressFormFields } from "@/components/checkout/AddressFormFields";
import { Button } from "@/components/ui/button";
import { ProductImage } from "@/components/ui/product-image";
import { Input } from "@/components/ui/input";
import {
  submitCartAndGoToCheckout,
  updateShoppingCartDetails,
} from "@/lib/data/shopping-cart";
import { getCountry } from "@/lib/data/countries";
import {
  addressToFormData,
  emptyAddress,
  formDataToAddress,
  type AddressFormData,
} from "@/lib/utils/address";
import type { State } from "@pallastrade/sdk";

interface CheckoutInfoContentProps {
  cart: ShoppingCart;
  shippingMethods: DeliveryMethod[];
  countries: Country[];
}

/**
 * 订单确认页：收件信息 + 物流方式 + 商品/金额预览 + 提交订单。
 */
export function CheckoutInfoContent({
  cart,
  shippingMethods,
  countries,
}: CheckoutInfoContentProps) {
  const t = useTranslations("checkout");
  const tc = useTranslations("common");
  const [isPending, startTransition] = useTransition();

  const [email, setEmail] = useState(cart.email ?? "");
  const [address, setAddress] = useState<AddressFormData>(
    addressToFormData(cart.shipping_address),
  );
  const [shippingMethodId, setShippingMethodId] = useState(
    cart.shipping_method_id ?? "",
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

  const handleSubmit = () => {
    startTransition(async () => {
      // 1. 保存 email/收件地址/配送方式到购物车
      const saveResult = await updateShoppingCartDetails(cart.id, {
        email: email || undefined,
        shipping_address: formDataToAddress(address),
        shipping_method_id: shippingMethodId || undefined,
      });
      if (saveResult && "success" in saveResult && !saveResult.success) {
        toast.error(saveResult.error);
        return;
      }
      // 2. 提交订单 → 跳转 /checkout/[orderId]
      try {
        await submitCartAndGoToCheckout(cart.id);
      } catch (error) {
        toast.error(
          error instanceof Error ? error.message : "Failed to submit order",
        );
      }
    });
  };

  const canSubmit = email.trim().length > 0;

  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">
        {t("orderConfirmation")}
      </h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* 表单 */}
        <div className="lg:col-span-2 space-y-8">
          {/* 联系方式 */}
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {t("contactInfo")}
            </h2>
            <Input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder={t("emailPlaceholder")}
              aria-label={t("email")}
            />
          </section>

          {/* 收件信息 */}
          <section className="bg-white rounded-xl border border-gray-200 p-6">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {t("shippingAddress")}
            </h2>
            <AddressFormFields
              address={address}
              countries={countries}
              states={states}
              loadingStates={loadingStates}
              onChange={onAddressChange}
              idPrefix="checkout-info"
            />
          </section>

          {/* 物流方式 */}
          {shippingMethods.length > 0 && (
            <section className="bg-white rounded-xl border border-gray-200 p-6">
              <h2 className="text-lg font-medium text-gray-900 mb-4">
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
        </div>

        {/* 商品/金额预览 */}
        <div className="lg:col-span-1">
          <div className="bg-white rounded-xl border border-gray-200 p-6 sticky top-24">
            <h2 className="text-lg font-medium text-gray-900 mb-4">
              {tc("orderSummary")}
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
                    <p className="text-sm text-gray-500">
                      × {item.quantity}
                    </p>
                  </div>
                  <p className="text-sm font-semibold text-gray-900">
                    {item.display_amount}
                  </p>
                </div>
              ))}
            </div>

            <dl className="mt-6 space-y-4 border-t border-gray-100 pt-4">
              <div className="flex justify-between">
                <dt className="text-gray-500">{tc("subtotal")}</dt>
                <dd className="text-gray-900">{cart.display_item_total}</dd>
              </div>
              <div className="flex justify-between border-t pt-4">
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
              onClick={handleSubmit}
            >
              {isPending ? t("submitting") : t("submitOrder")}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
}
