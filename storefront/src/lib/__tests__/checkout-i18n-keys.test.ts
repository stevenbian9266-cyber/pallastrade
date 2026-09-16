import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * PRD-20260913-checkout-txn-error-routing AC-010 守护：
 * 错误分流 / 已收款恢复文案的键必须在全部 5 个语言文件中齐备
 * （缺键在运行时会渲染成 key 本身，属用户可见缺陷）。
 */

const MESSAGES_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "..",
  "messages",
);

const LOCALES = ["de", "en", "es", "fr", "pl"] as const;

const REQUIRED: Record<string, string[]> = {
  checkout: [
    "stockUnavailableTitle",
    "returnToCart",
    "quoteUpdatedBanner",
    "dismissBanner",
    // PRD-20260913-checkout-billing-mode AC-011
    "billingAddressIncomplete",
    // PRD-20260914-checkout-quote-confirmation-loop AC-007
    "quoteChangedTitle",
    "quoteChangedBody",
    "quoteConfirmAgain",
    "quoteRowShipping",
    "quoteRowPromotion",
    "quoteRowAmountDue",
    // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-008：
    // 库存三态各自的标题/说明/动作（§26/§27 + 错误码表）。
    "stockInsufficientTitle",
    "stockChangedTitle",
    "stockChangedHint",
    "reservationExpiredTitle",
    "reservationExpiredHint",
    "reservationRetryingTitle",
    "reviewCart",
    "retryInventoryCheck",
  ],
  paymentResult: [
    "recoveryTitle",
    "recoveryDescription",
    "processingNoticeTitle",
    "processingNoticeDescription",
  ],
  order: [
    // PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups AC-008：
    // 履约结果页（§37）的 Ship to / Delivery / Items / Paid / savings 与多 Shipment 分组文案。
    "orderContents",
    "shipTo",
    "delivery",
    "items",
    "paid",
    "promotionSavings",
    "viewOrder",
    "shipment",
    "qty",
    "deliveryFallback",
  ],
  cart: [
    // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-010：
    // 购物车页「优惠与抵扣」模块 + 服务端错误码文案，五语言齐备。
    "creditsTitle",
    "discountCode",
    "discountCalculatedAtSubmit",
    "useStoreCredit",
    "storeCreditApplied",
    "removeStoreCredit",
    "storeCreditLoginRequired",
    "storeCreditGiftCardConflict",
    "storeCreditNotAvailable",
    "storeCreditInvalidAmount",
    "logIn",
  ],
  coupon: [
    // PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 AC-010
    "giftCardNotFound",
    "giftCardExpired",
    "giftCardAlreadyRedeemed",
  ],
  products: [
    // PRD-20260915-catalog-pdp-state-correctness AC-012：
    // PDP 预售 / 缺货可超卖四态文案，五语言齐备。
    "preorder",
    "preorderShipsBy",
    "backorder",
    "backorderNote",
    // PRD-20260915-catalog-batch-c1-discovery AC-010：
    // 发现区块（相关商品 / 最近浏览）标题。
    "relatedTitle",
    "recentlyViewedTitle",
    // PRD-20260916-catalog-batch-f2-stock-shipping AC-009：
    // 库存稀缺（分桶）与配送时效 / 免运费提示，五语言齐备。
    "onlyFewLeft",
    "shippingEstimate",
    "transitDaysRange",
    "transitDaysSingle",
    "estimatedArrival",
    "shippingAtCheckout",
    "instantDownload",
    "freeShipping",
    "freeShippingOver",
  ],
  // PRD-20260915-catalog-batch-c1-discovery AC-010：Wishlist V1 全量文案。
  wishlist: ["title", "empty", "browse", "add", "remove", "removeAria"],
  // PRD-20260916-catalog-batch-f1-reviews AC-009：
  // 评论分页 Load more 与图片评论（选择/上限/类型/大小/移除）文案，五语言齐备。
  reviews: [
    "ratingBreakdown",
    "loadMore",
    "loadingMore",
    "loadMoreError",
    "addPhotos",
    "photoLimit",
    "photoLimitReached",
    "photoTooLarge",
    "photoTypeInvalid",
    "photoUploadFailed",
    "removePhoto",
  ],
};

describe("Checkout error i18n keys (PRD-20260913-checkout-txn-error-routing AC-010)", () => {
  it.each(LOCALES)("has every required key in %s.json", (locale) => {
    const messages = JSON.parse(
      readFileSync(join(MESSAGES_DIR, `${locale}.json`), "utf8"),
    ) as Record<string, Record<string, unknown>>;

    for (const [namespace, keys] of Object.entries(REQUIRED)) {
      for (const key of keys) {
        expect(
          messages[namespace]?.[key],
          `${locale}.json → ${namespace}.${key}`,
        ).toBeTruthy();
      }
    }
  });
});
