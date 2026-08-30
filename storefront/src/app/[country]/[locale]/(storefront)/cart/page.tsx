"use client";

import type { ShoppingCart } from "@pallastrade/sdk";
import { Check, ShoppingBag } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { ProductImage } from "@/components/ui/product-image";
import { QuantityPicker } from "@/components/ui/quantity-picker";
import {
  getShoppingCart,
  removeCartItem,
  setAllCartItemsSelected,
  updateCartItemQuantity,
  updateCartItemSelection,
} from "@/lib/data/shopping-cart";
import { extractBasePath } from "@/lib/utils/path";

/**
 * 订单流程标准电商改造 P1（2026-08-30）：购物车页（新 Cart 实体）。
 * 支持勾选/全选/删除/数量调整；「去结算」仅在有勾选商品时可用，
 * 跳转统一下单页 /checkout/[cartId]（下单链路统一化 PRD-20260830-checkout）。
 */
export default function CartPage() {
  const t = useTranslations("cart");
  const tc = useTranslations("common");
  const router = useRouter();
  const pathname = usePathname();
  const basePath = extractBasePath(pathname);

  const [cart, setCart] = useState<ShoppingCart | null>(null);
  const [loading, setLoading] = useState(true);
  const [updating, setUpdating] = useState(false);
  const [busyItem, setBusyItem] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const data = await getShoppingCart();
    setCart(data);
    setLoading(false);
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  const items = cart?.items ?? [];
  const selectedCount = items.filter((i) => i.selected).length;
  const allSelected = items.length > 0 && selectedCount === items.length;
  const someSelected = selectedCount > 0;

  const toggleAll = async () => {
    if (!cart) return;
    setUpdating(true);
    const result = await setAllCartItemsSelected(cart.id, !allSelected);
    if (result && "success" in result && result.success && result.cart) {
      setCart(result.cart);
    } else if (result && "error" in result) {
      toast.error(result.error);
    }
    setUpdating(false);
  };

  const toggleItem = async (itemId: string, selected: boolean) => {
    if (!cart) return;
    setUpdating(true);
    const result = await updateCartItemSelection(cart.id, itemId, selected);
    if (result && "success" in result && result.success && result.cart) {
      setCart(result.cart);
    } else if (result && "error" in result) {
      toast.error(result.error);
    }
    setUpdating(false);
  };

  const updateQuantity = async (itemId: string, quantity: number) => {
    if (!cart) return;
    setBusyItem(itemId);
    try {
      const result = await updateCartItemQuantity(cart.id, itemId, quantity);
      if (result.success) {
        setCart(result.cart);
      } else {
        toast.error(result.error);
      }
    } finally {
      setBusyItem(null);
    }
  };

  const removeItem = async (itemId: string) => {
    if (!cart) return;
    setBusyItem(itemId);
    try {
      const result = await removeCartItem(cart.id, itemId);
      if (result.success) {
        setCart(result.cart);
      } else {
        toast.error(result.error);
      }
    } finally {
      setBusyItem(null);
    }
  };

  if (loading) {
    return (
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="animate-pulse">
          <div className="h-8 bg-gray-200 rounded w-32 mb-8"></div>
          <div className="space-y-4">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-24 bg-gray-200 rounded"></div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (!cart || items.length === 0) {
    return (
      <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-16">
        <div className="text-center">
          <ShoppingBag
            className="w-24 h-24 text-gray-300 mx-auto"
            strokeWidth={1}
          />
          <h1 className="mt-4 text-2xl font-bold text-gray-900">
            {t("emptyCart")}
          </h1>
          <p className="mt-2 text-gray-500">{t("emptyCartDescription")}</p>
          <div className="mt-6">
            <Button size="lg" asChild>
              <Link href={`${basePath}/products`}>
                {tc("continueShopping")}
              </Link>
            </Button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-3xl font-bold text-gray-900 mb-8">
        {t("shoppingCart")}
      </h1>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Cart Items */}
        <div className="lg:col-span-2">
          {/* 全选 */}
          <div className="mb-4 flex items-center gap-3 px-1">
            <label className="inline-flex items-center gap-2 text-sm text-gray-700 cursor-pointer">
              <input
                type="checkbox"
                checked={allSelected}
                onChange={toggleAll}
                disabled={updating}
                className="w-4 h-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
              />
              {tc("selectAll")}
            </label>
            <span className="text-sm text-gray-500">
              {t("selectedCount", { count: selectedCount })}
            </span>
          </div>

          <div className="bg-white rounded-xl border border-gray-200 divide-y">
            {items.map((item) => (
              <div
                key={item.id}
                className={`p-6 flex gap-6 ${
                  item.selected ? "" : "opacity-60"
                }`}
              >
                {/* 勾选 */}
                <label className="inline-flex items-start pt-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={item.selected}
                    onChange={(e) => toggleItem(item.id, e.target.checked)}
                    disabled={updating}
                    className="w-4 h-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-500"
                    aria-label={t("selectItemLabel", { name: item.name })}
                  />
                </label>

                {/* Image */}
                <div className="relative w-24 h-24 bg-gray-100 rounded-xl overflow-hidden shrink-0">
                  <ProductImage
                    src={item.thumbnail_url}
                    alt={item.name}
                    fill
                    className="object-cover"
                    sizes="96px"
                  />
                </div>

                {/* Details */}
                <div className="flex-1 min-w-0">
                  <h3 className="text-lg font-medium text-gray-900 truncate">
                    {item.name}
                  </h3>
                  {item.options_text && (
                    <p className="mt-1 text-sm text-gray-500">
                      {item.options_text}
                    </p>
                  )}
                  <p className="mt-2 text-lg font-semibold text-gray-900">
                    {item.display_unit_price}
                  </p>
                </div>

                {/* Quantity & Actions */}
                <div className="flex flex-col items-end gap-2">
                  <QuantityPicker
                    quantity={item.quantity}
                    disabled={busyItem === item.id}
                    onDecrement={() =>
                      updateQuantity(item.id, Math.max(1, item.quantity - 1))
                    }
                    onIncrement={() =>
                      updateQuantity(item.id, item.quantity + 1)
                    }
                  />
                  <Button
                    variant="destructive"
                    size="sm"
                    disabled={busyItem === item.id}
                    aria-label={t("removeItemLabel", { name: item.name })}
                    onClick={() => removeItem(item.id)}
                  >
                    {tc("remove")}
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Order Summary */}
        <div className="lg:col-span-1">
          <div className="bg-white rounded-xl border border-gray-200 p-6 sticky top-24">
            <h2 className="text-lg font-medium text-gray-900">
              {tc("orderSummary")}
            </h2>

            <dl className="mt-6 space-y-4">
              <div className="flex justify-between">
                <dt className="text-gray-500">{tc("subtotal")}</dt>
                <dd className="text-gray-900">{cart.display_item_total}</dd>
              </div>
              <div className="border-t pt-4 flex justify-between">
                <dt className="text-lg font-medium text-gray-900">
                  {tc("total")}
                </dt>
                <dd className="text-lg font-bold text-gray-900">
                  {cart.display_item_total}
                </dd>
              </div>
            </dl>

            <div className="mt-6">
              <Button
                size="lg"
                className="w-full"
                disabled={!someSelected || updating}
                onClick={() =>
                  // 下单链路统一化（PRD-20260830-checkout）：去结算进入统一下单页
                  router.push(`${basePath}/checkout/${cart.id}`)
                }
              >
                {t("checkout")}
                {someSelected ? <Check className="w-4 h-4 ml-2" /> : null}
              </Button>
              <p className="mt-2 text-xs text-gray-400 text-center">
                {someSelected
                  ? t("checkoutSelectedHint")
                  : t("checkoutDisabledHint")}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
