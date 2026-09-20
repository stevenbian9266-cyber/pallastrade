import { describe, expect, it } from "vitest";
import {
  comparableFromPreview,
  diffQuotes,
  quoteChangeRows,
} from "@/lib/checkout-quote";

/**
 * P1-a（PRD-20260920-checkout 支付核心统一 FR-012）——「仅当金额发生变化才确认」
 * 的比对口径（纯函数层）：
 *   - 基准 = 顾客**已看到**的只读预览报价（无预览 → 快照 → 无基准）；
 *   - 变化判定沿用既有 `diffQuotes`（raw 判变化 / display 仅展示）；
 *   - **绝不凭空造出变化**：无基准或权威报价缺失 → 空数组（一次点击直达）。
 */
describe("checkout quote change detection (P1-a FR-012)", () => {
  /** Order 权威报价（Prepare 返回），与预览同参数时金额逐字段一致。 */
  const after = {
    checkout_version: 3,
    price_version: "pv_3",
    delivery_total: "9.0",
    display_delivery_total: "$9.00",
    discount_total: "0.0",
    display_discount_total: "$0.00",
    tax_total: "0.0",
    display_tax_total: "$0.00",
    amount_due: "28.98",
    display_amount_due: "$28.98",
  };

  it("treats the preview quote as the buyer-visible baseline (no change → no gate)", () => {
    const before = comparableFromPreview({
      delivery_total: "9.0",
      display_delivery_total: "$9.00",
      discount_total: "0.0",
      display_discount_total: "$0.00",
      amount_due: "28.98",
      display_amount_due: "$28.98",
    });

    const rows = quoteChangeRows(before, after);
    expect(rows).toHaveLength(3);
    expect(rows.map((row) => row.changed)).toEqual([false, false, false]);
  });

  it("marks the rows that really moved (old → new) when the amount differs", () => {
    const before = comparableFromPreview({
      delivery_total: "5.0",
      display_delivery_total: "$5.00",
      discount_total: "0.0",
      display_discount_total: "$0.00",
      amount_due: "24.98",
      display_amount_due: "$24.98",
    });

    const rows = quoteChangeRows(before, after);
    expect(rows.find((row) => row.key === "shipping")).toMatchObject({
      before: "$5.00",
      after: "$9.00",
      changed: true,
    });
    expect(rows.find((row) => row.key === "amountDue")).toMatchObject({
      before: "$24.98",
      after: "$28.98",
      changed: true,
    });
  });

  it("never invents a change without a comparable baseline", () => {
    // 无预览 / 预览不可判定（金额为 null）
    expect(quoteChangeRows(null, after)).toEqual([]);
    expect(quoteChangeRows(undefined, after)).toEqual([]);
    expect(comparableFromPreview({ amount_due: null })).toBeNull();
    expect(quoteChangeRows(comparableFromPreview({}), after)).toEqual([]);
    // 服务端降级：Prepare 未返回权威报价
    expect(
      quoteChangeRows(comparableFromPreview({ amount_due: "28.98" }), null),
    ).toEqual([]);
  });

  it("keeps the legacy 409 semantics (no snapshot → every row marked changed)", () => {
    const rows = diffQuotes(null, after);
    expect(rows).toHaveLength(3);
    expect(rows.every((row) => row.changed)).toBe(true);
  });
});
