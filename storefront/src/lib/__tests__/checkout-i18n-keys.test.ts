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
  ],
  paymentResult: [
    "recoveryTitle",
    "recoveryDescription",
    "processingNoticeTitle",
    "processingNoticeDescription",
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
