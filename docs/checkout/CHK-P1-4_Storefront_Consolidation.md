# CHK-P1-4 — Storefront Consolidation（首步：Order Checkout 只读消费 + 轻量收编）

> 日期：2026-09-03 ｜ PRD：`PRD-20260903-checkout-chk-p1-1...`（§12 CHK-P1-4）
> Task：`TASK-20260903155808-74f09f4c`；Gate：`GATE-2026-09-03T15-58-34`
> 范围（用户确认，两轮 vscode_askQuestions 2026-09-03）：4A 只读试点；SDK/yaml 手写兜底（rswag/typelizer 基建缺失=R1）；试点=OrderPaymentContent；legacy=轻量收编。

## 1. SDK（手写，platform/packages/sdk）

- `src/types/index.ts`：`CheckoutView` interface + `CheckoutViewLine`（镜像 CheckoutSerializer：状态/email/currency/version/price_version/expires_at/ready/missing_requirements + 全部 money/display_* + items/fulfillments/addresses/discounts/taxes）。
- `src/store-client.ts` orders 资源：`checkout.get(orderId)` → `GET /orders/:id/checkout`（仿 `orders.paymentSessions` 手写先例）。
- 不新增 zod（zod 仅覆盖 generated 源；CheckoutView 无 typelizer 源，R1）。
- 构建：`pnpm --filter @pallastrade/sdk build` → storefront `.sdk-vendor` 刷新（Copy-Item dist + package.json）。

## 2. storefront 读取层 + 试点

- `lib/data/order-checkout.ts`（server）`getOrderCheckout`：`getClient().orders.checkout.get`，失败返回 null（与 `getOrderForCheckout` 一致）。
- `checkout/[id]/page.tsx` or_ 分支：`Promise.all([getOrderForCheckout, getOrderCheckout])` → `OrderPaymentContent order + view`。
- `OrderPaymentContent`：新增可选 `view?: CheckoutView | null`；summary 金额/商品/收货地址改由 CheckoutView 投影（`view` 缺失回退 order 快照）；`ready === false` → Pay 禁用 + `checkout-not-ready` 提示（i18n `checkoutNotReady`，data-missing 暴露 codes）；session create/complete 逻辑不变。
- i18n：`checkoutNotReady` key ×5 locale（check:locales 通过）。

## 3. legacy 轻量收编

- 死代码删除：`lib/data/shopping-cart.ts` `submitCartOrder`/`submitCartAndGoToCheckout` + `isRedirectError`（全仓 0 调用者，已验证）。
- 边界注释：`CheckoutPageContent`（LEGACY/COMPATIBILITY ONLY）、`PaymentSection`（LEGACY）、`CombinedPaymentCheckout`（孤儿页显式决策：保留 for 存量链接，候选 4C 移除）。
- **platform docs 副本既有损坏修复**：`platform/docs/api-reference/store.yaml` 第 8593 行 `symbol: "閳?`（€ 乱码截断）→ 修复为 `"€"`，Psych 校验通过（该文件在 P1-4 前即不可解析）。

## 4. API docs 手写同步

- store.yaml×2（backend/public/api-docs + platform/docs/api-reference）：`/api/v3/store/orders/{order_id}/checkout`（GET+PATCH，rswag 风格）+ `components/schemas/Checkout` + `CheckoutViewLine`。backend 经容器 Psych 校验；platform 修复后经 Psych 校验。

## 5. 测试结果

- storefront typecheck 0 error；biome 0；check:locales 全 sync。
- vitest：OrderPaymentContent 7/7（含 3 新 P1-4 例：view 驱动金额 / ready 禁用 Pay / !ready 不建会话）；checkout 相关 12 文件 104 例通过（批量运行 1 个 vitest teardown 全局 error，非测试失败——单文件复跑干净）。

## 6. DEFERRED

- PATCH mutation 消费（contact/address/delivery 编辑 on or_ 页等）→ 4B
- legacy 退役重构 / 组合支付双实现收敛 / CombinedPaymentCheckout 移除 / 死代码更多清理 → 4C
- 409 CHECKOUT_VERSION_CONFLICT 端点语义
- rswag/typelizer 基建（spec/dummy + 容器 shim）→ R1 独立包（届时 SDK/checkout schema 可全量生成替代手写）
