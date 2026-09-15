"use client";

import type { ShoppingCart } from "@pallastrade/sdk";
import { X } from "lucide-react";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  applyDiscountCode,
  applyGiftCard,
  applyStoreCredit,
  removeDiscountCode,
  removeGiftCard,
  removeStoreCredit,
} from "@/lib/data/shopping-cart";

interface CartCreditsPanelProps {
  cart: ShoppingCart;
  /** 服务端 `isAuthenticated()` 结论：店铺余额是账户资产，游客不可用。 */
  isLoggedIn: boolean;
  /** 登录后回到本车（由页面拼装 base path）。 */
  loginHref: string;
  onCartUpdated: (cart: ShoppingCart) => void;
}

/** 服务端 v3 错误码 → 页面文案（未知码回退到原始 message / 通用文案）。 */
const COUPON_ERROR_KEYS: Record<string, string> = {
  coupon_code_not_found: "invalidCode",
  coupon_code_expired: "invalidCode",
  gift_card_not_found: "giftCardNotFound",
  gift_card_expired: "giftCardExpired",
  gift_card_already_redeemed: "giftCardAlreadyRedeemed",
};

const CART_ERROR_KEYS: Record<string, string> = {
  store_credit_requires_login: "storeCreditRequiresLogin",
  store_credit_not_available: "storeCreditNotAvailable",
  store_credit_invalid_amount: "storeCreditInvalidAmount",
  store_credit_gift_card_conflict: "storeCreditGiftCardConflict",
  gift_card_using_store_credit_error: "storeCreditGiftCardConflict",
};

/**
 * 购物车页「优惠与抵扣」模块（PRD-20260914-checkout B2 FR-002..FR-007）。
 *
 * 三种抵扣在 `cart_` 上都是**意图**（零资金副作用）：本模块只调用服务端动作
 * 记住/忘掉意图，然后用返回的 cart 快照刷新 UI（金额一律以服务端为准）。
 *
 * 交互约定（B2 决策）：
 * - 单一输入框同时接受优惠码与礼品卡码：先按优惠码提交，服务端答
 *   `coupon_code_not_found` 时再按礼品卡试一次（两类码各有独立错误码，
 *   不会把无效输入误记成礼品卡）；
 * - 店铺余额用按钮（省略金额 = 用尽可用余额），不做金额输入框；
 * - 游客看到禁用按钮 + 登录引导（**不发起请求**）；礼品卡已应用时余额入口禁用。
 */
export function CartCreditsPanel({
  cart,
  isLoggedIn,
  loginHref,
  onCartUpdated,
}: CartCreditsPanelProps) {
  const t = useTranslations("cart");
  const tCoupon = useTranslations("coupon");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const discountCode = cart.discount_code ?? null;
  const giftCard = cart.gift_card ?? null;
  const storeCredit = cart.store_credit ?? null;

  const messageFor = (failure: { error: string; code?: string }): string => {
    const errorCode = failure.code;
    if (errorCode && CART_ERROR_KEYS[errorCode]) {
      return t(CART_ERROR_KEYS[errorCode]);
    }
    if (errorCode && COUPON_ERROR_KEYS[errorCode]) {
      return tCoupon(COUPON_ERROR_KEYS[errorCode]);
    }
    return failure.error || tCoupon("applyFailed");
  };

  const handleApply = async (event: React.FormEvent) => {
    event.preventDefault();
    const value = code.trim();
    if (!value || busy) return;

    setBusy("apply");
    setError(null);
    try {
      let result = await applyDiscountCode(cart.id, value);
      if (!result.success && result.code === "coupon_code_not_found") {
        result = await applyGiftCard(cart.id, value);
      }

      if (result.success) {
        setCode("");
        onCartUpdated(result.cart);
      } else {
        setError(messageFor(result));
      }
    } finally {
      setBusy(null);
    }
  };

  const handleRemoveDiscount = async (value: string) => {
    if (busy) return;
    setBusy("discount");
    setError(null);
    try {
      const result = await removeDiscountCode(cart.id, value);
      if (result.success) {
        onCartUpdated(result.cart);
      } else {
        setError(messageFor(result));
      }
    } finally {
      setBusy(null);
    }
  };

  const handleRemoveGiftCard = async (value: string) => {
    if (busy) return;
    setBusy("gift_card");
    setError(null);
    try {
      const result = await removeGiftCard(cart.id, value);
      if (result.success) {
        onCartUpdated(result.cart);
      } else {
        setError(messageFor(result));
      }
    } finally {
      setBusy(null);
    }
  };

  const handleApplyStoreCredit = async () => {
    // 游客与礼卡互斥都在这里短路：不产生无意义的 401/422 请求。
    if (busy || !isLoggedIn || giftCard) return;

    setBusy("store_credit");
    setError(null);
    try {
      const result = await applyStoreCredit(cart.id);
      if (result.success) {
        onCartUpdated(result.cart);
      } else {
        setError(messageFor(result));
      }
    } finally {
      setBusy(null);
    }
  };

  const handleRemoveStoreCredit = async () => {
    if (busy) return;
    setBusy("store_credit");
    setError(null);
    try {
      const result = await removeStoreCredit(cart.id);
      if (result.success) {
        onCartUpdated(result.cart);
      } else {
        setError(messageFor(result));
      }
    } finally {
      setBusy(null);
    }
  };

  const storeCreditBlocked = Boolean(giftCard);
  const storeCreditNeedsLogin = !isLoggedIn;

  return (
    <div className="mt-6 border-t pt-4" data-testid="cart-credits-panel">
      <h3 className="text-sm font-medium text-gray-900">{t("creditsTitle")}</h3>

      {/* 已应用的优惠码 / 礼品卡 */}
      <div className="mt-3 space-y-2">
        {discountCode ? (
          <div
            className="flex items-center justify-between rounded-sm border border-gray-200 bg-gray-50 px-3 py-2"
            data-testid="applied-discount-code"
          >
            <span className="text-sm font-medium text-gray-900">
              {discountCode}
            </span>
            <button
              type="button"
              onClick={() => handleRemoveDiscount(discountCode)}
              disabled={busy !== null}
              aria-label={tCoupon("removeCoupon", { code: discountCode })}
              className="cursor-pointer p-0.5 text-gray-400 hover:text-gray-600"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ) : null}

        {giftCard ? (
          <div
            className="flex items-center justify-between rounded-sm border border-gray-200 bg-gray-50 px-3 py-2"
            data-testid="applied-gift-card"
          >
            <span className="text-sm font-medium text-gray-900">
              {tCoupon("giftCardCode", { code: giftCard.code })}
            </span>
            <button
              type="button"
              onClick={() => handleRemoveGiftCard(giftCard.code)}
              disabled={busy !== null}
              aria-label={tCoupon("removeGiftCard")}
              className="cursor-pointer p-0.5 text-gray-400 hover:text-gray-600"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ) : null}

        {storeCredit ? (
          <div
            className="flex items-center justify-between rounded-sm border border-gray-200 bg-gray-50 px-3 py-2"
            data-testid="applied-store-credit"
          >
            <span className="text-sm font-medium text-gray-900">
              {t("storeCreditApplied", { amount: storeCredit.display_amount })}
            </span>
            <button
              type="button"
              onClick={handleRemoveStoreCredit}
              disabled={busy !== null}
              aria-label={t("removeStoreCredit")}
              className="cursor-pointer p-0.5 text-gray-400 hover:text-gray-600"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ) : null}
      </div>

      {/* 输入框：优惠码 / 礼品卡码 */}
      <form onSubmit={handleApply} className="mt-3 flex gap-2">
        <Input
          type="text"
          value={code}
          onChange={(event) => {
            setCode(event.target.value);
            setError(null);
          }}
          placeholder={tCoupon("placeholder")}
          aria-label={tCoupon("placeholder")}
          aria-invalid={Boolean(error)}
          className="flex-1"
        />
        <Button type="submit" disabled={busy !== null || !code.trim()}>
          {busy === "apply" ? tCoupon("applying") : tCoupon("apply")}
        </Button>
      </form>

      {/* 店铺余额 */}
      {!storeCredit ? (
        <div className="mt-3">
          <Button
            type="button"
            variant="outline"
            size="sm"
            data-testid="use-store-credit"
            disabled={
              busy !== null || storeCreditBlocked || storeCreditNeedsLogin
            }
            onClick={handleApplyStoreCredit}
          >
            {busy === "store_credit"
              ? tCoupon("applying")
              : t("useStoreCredit")}
          </Button>

          {storeCreditBlocked ? (
            <p className="mt-2 text-xs text-gray-500">
              {t("storeCreditGiftCardConflict")}
            </p>
          ) : null}

          {!storeCreditBlocked && storeCreditNeedsLogin ? (
            <p className="mt-2 text-xs text-gray-500">
              {t("storeCreditLoginRequired")}{" "}
              <Link href={loginHref} className="underline">
                {t("logIn")}
              </Link>
            </p>
          ) : null}
        </div>
      ) : null}

      {error ? (
        <p
          role="alert"
          className="mt-2 text-sm text-red-600"
          data-testid="cart-credits-error"
        >
          {error}
        </p>
      ) : null}
    </div>
  );
}
