import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * PRD-20260913-checkout-billing-mode 契约守护：
 * - AC-007：Store API 契约（`backend/public/api-docs/store.yaml`）必须声明 `billing_mode`
 *   （字段未进参数白名单/契约时会被静默忽略，参见缺陷根因）。
 * - AC-008：Storefront 与 BFF 不得再发送 legacy `use_shipping`（服务端不 permit → 静默丢弃）。
 *
 * 说明：跨包读取仓库根目录文件属有意为之 —— 这是"前端载荷 ↔ 服务端契约"的一致性守护，
 * 与 `money-contract-guard.test.ts` 的源码扫描同一模式。
 */

const REPO_ROOT = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "..",
  "..",
);

describe("Checkout billing_mode contract (PRD-20260913-checkout-billing-mode)", () => {
  it("PRD-20260913-checkout-billing-mode AC-007: documents billing_mode for the carts endpoint in the Store API spec", () => {
    const storeSpec = readFileSync(
      join(REPO_ROOT, "backend", "public", "api-docs", "store.yaml"),
      "utf8",
    );

    expect(storeSpec).toContain("billing_mode:");
    expect(storeSpec).toContain("same_as_shipping");
  });

  it("PRD-20260913-checkout-billing-mode AC-008: the checkout UI sends billing_mode instead of the legacy use_shipping flag", () => {
    const checkout = readFileSync(
      join(
        REPO_ROOT,
        "storefront",
        "src",
        "components",
        "checkout",
        "UnifiedCheckout.tsx",
      ),
      "utf8",
    );

    expect(checkout).toContain('billing_mode: "same_as_shipping"');
    expect(checkout).toContain('billing_mode: "custom"');
    // legacy 字段在服务端参数白名单中会静默丢弃 → 前端禁止再发送
    expect(checkout).not.toMatch(/use_shipping:\s*true/);
  });
});
