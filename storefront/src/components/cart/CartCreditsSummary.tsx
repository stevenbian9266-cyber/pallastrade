"use client";

import type { ShoppingCart } from "@pallastrade/sdk";
import { useTranslations } from "next-intl";
import { safeParseFloat } from "@/lib/utils/format";

/**
 * 购物车 Order Summary 的「抵扣三合一」行（PRD-20260914-checkout B2 FR-001）。
 *
 * 数据全部来自服务端 `ShoppingCart` 快照 —— 车阶段三种抵扣都只是**意图**：
 * - `discount_code`：用户输入的优惠码（金额在结算时才计算 → 行内标注）
 * - `gift_card`    ：卡码（金额在提交生成 Order 时落地）
 * - `store_credit` ：已固化的请求额（提交时按订单应付收敛）
 *
 * money 契约：金额（raw）只用于**判断是否渲染**，`display_*` 只用于渲染；
 * 三者都不参与前端合计计算（合计仍是 `display_item_total`）。
 */
export function CartCreditsSummary({ cart }: { cart: ShoppingCart }) {
  const t = useTranslations("cart");

  const discountCode = cart.discount_code ?? null;
  const giftCard = cart.gift_card ?? null;
  const storeCredit = cart.store_credit ?? null;
  const hasStoreCredit =
    storeCredit !== null && safeParseFloat(storeCredit.amount) > 0;

  if (!discountCode && !giftCard && !hasStoreCredit) return null;

  // 作为 Order Summary `<dl>` 里的分组片段渲染（HTML5 允许 dl 内用 div 分组）——
  // 与 Subtotal / Total 同行同列，保证金额列对齐。
  return (
    <div className="space-y-4" data-testid="cart-credits-summary">
      {discountCode ? (
        <div
          className="flex justify-between text-sm"
          data-testid="discount-code-row"
        >
          <dt className="text-gray-500">{t("discountCode")}</dt>
          <dd className="text-gray-900">
            {discountCode}
            <span className="ml-2 text-xs text-gray-500">
              {t("discountCalculatedAtSubmit")}
            </span>
          </dd>
        </div>
      ) : null}

      {giftCard ? (
        <div
          className="flex justify-between text-sm"
          data-testid="gift-card-row"
        >
          <dt className="text-gray-500">{t("giftCard")}</dt>
          <dd className="text-gray-900">{giftCard.code}</dd>
        </div>
      ) : null}

      {hasStoreCredit && storeCredit ? (
        <div
          className="flex justify-between text-sm"
          data-testid="store-credit-row"
        >
          <dt className="text-gray-500">{t("storeCredit")}</dt>
          <dd className="text-green-600">-{storeCredit.display_amount}</dd>
        </div>
      ) : null}
    </div>
  );
}
