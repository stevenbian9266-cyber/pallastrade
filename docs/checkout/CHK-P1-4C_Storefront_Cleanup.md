# CHK-P1-4C — Storefront 清理：孤儿页移除 + 死代码清理

> 日期：2026-09-04 ｜ PRD：`PRD-20260903-checkout-chk-p1-1...`（§12 CHK-P1-4C）
> Task：`TASK-20260903180522-87f488f3`；Gate：`GATE-2026-09-03T18-05-36`
> 范围（用户确认 2026-09-04）：4C-2 孤儿页移除 + 4C-3 死代码清理；4C-4（legacy 退役）延后。

## 1. 交付

- **删除**：`src/app/[country]/[locale]/(checkout)/combined-payment/[id]/page.tsx` + `src/components/checkout/CombinedPaymentCheckout.tsx`（4A 决策注释落地；旧深链 404，账户列表/弹窗为现行入口）。
- **删除死代码**：`lib/data/payment-combination.ts#updateOrderShippingAddress`（仅孤儿页调用）+ 未用 `AddressParams` import。
- **保留**：`getPaymentCombination`（payment-result + modal）、`createPaymentCombination`/`completeCombinationSession`（modal）；legacy 一页式（CheckoutPageContent/PaymentSection/Express/confirm-payment）服务无前缀存量订单——4C-4 后续。

## 2. 验证

- 全仓 grep `CombinedPaymentCheckout|updateOrderShippingAddress|combined-payment` → 0 引用。
- storefront typecheck 0；biome 0。
- 受影响回归：PaymentCheckoutModal / payment-result / OrderCombinedPay / OrderPayButton 16/16 绿。

## 3. DEFERRED

- 4C-4：legacy 一页式退役/存量订单兜底（高风险，后续单独包）。
