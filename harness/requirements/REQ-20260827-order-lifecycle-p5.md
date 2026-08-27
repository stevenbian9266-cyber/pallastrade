# REQ-20260827-order-lifecycle-p5 — Checkout 集成（自动拆单 + 合并支付收银台 + Buy Now，flag 灰度）

> 关联 PRD：`docs/prd/checkout/PRD-20260827-checkout-实施-p5-checkout-集成-自动拆单-合并支付收银台-buy-now-flag-灰度.md`
> 关联 Task：`TASK-20260827152703-1081d38b`｜Gate：`GATE-2026-08-27T15-27-14`（Risk critical）
> 任务类型：新功能（flag 灰度）

---

## Step 0：跨层搜索（6 层强制）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | 自动拆单, payment_combinations | 无 | 否——P5 接线在 Core/API，App 无重复 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Carts::Complete, Splitter, PaymentCombinations | `carts/complete.rb`、`orders/splitter.rb`（P2）、`payments/payment_combinations/{create,complete}.rb`（P4）、`combination_settle_job.rb` | **已就绪**——P5 在 Carts::Complete 加拆单 hook |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_sessions, combination | `store/carts/payment_sessions_controller.rb`（单订单） | 部分——**需新建组合端点** |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 拆单, combination | 无 | 否——P5 不动 Admin（P6） |
| Storefront | `storefront/src/` | PaymentSection, OrderList, confirm-payment, Buy Now | `components/checkout/PaymentSection.tsx`、`components/account/OrderList.tsx`、`(checkout)/confirm-payment/`、`lib/data/payment.ts`、`account/orders/` | 部分——**需新建合并支付收银台 + Buy Now** |
| Platform | `platform/packages/sdk/` | paymentSessions, PaymentCombination | `src/store-client.ts`（`carts.paymentSessions` CRUD）、`types/generated/PaymentSession.ts` | 部分——**需加 PaymentCombination 类型/方法** |

### 搜索结论

后端能力（Splitter P2 / PaymentCombinations P4）已就绪，P5 聚焦接线：Core 拆单 hook、API 组合端点、SDK 类型/方法、Storefront 收银台 + Buy Now。无跨层重复能力。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读（P4 同会话） | 决策树：P5 属能力接线（Carts::Complete hook + API 端点 + storefront 组件），配置用 `PallasTrade::Config`（flag 灰度）优先于装饰器 |
| `ai/skills/pallastrade-checkout/SKILL.md`（domain） | ✅ 已读 | 拆单引擎 P2 已就绪（默认不接入流程，P5 自动拆单负责接入）；组合完成 P4（checkout 状态机放行已具备）；P5 在 `Carts::Complete` 完成事务后执行拆单评估 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读（P4 同会话） | 工作流 §3：PRD 需用户明确确认（"实施"）后进入实施；§4 gate 前生成 REQ，user-confirmed 由用户确认清除 |

---

## 需求标题

P5 Checkout 集成：P5a 自动拆单（Carts::Complete hook + `Config[:auto_split_orders]` flag）+ P5b 合并支付收银台（组合 API 端点 + SDK + Storefront 多选收银台）+ P5c Buy Now（详情页快捷下单）。

## 任务类型

新功能（flag 灰度，默认关闭）

## 需求描述

- **P5a 自动拆单**：`Config[:auto_split_orders]`（store `preferred_auto_split_orders` 覆盖）配置策略列表（默认 `[]` 关闭）。`Carts::Complete` 在订单完成（支付确认后）执行拆单评估：按 `ByStockLocation`/`ByStore` 拆分已完成订单为子订单（挂父订单 + PaymentSplit 分摊 + OrderUpdater 重算）；**不在 cart 中途拆**；拆单失败不影响订单完成（`Rails.error.report`）。
- **P5b 合并支付收银台**：Store API `POST /payment_combinations`（order_ids + payment_method_id → `PaymentCombinations::Create`）；SDK 加 `PaymentCombination` 类型 + `paymentCombinations.create/complete`；Storefront 账户订单多选待支付 → `(checkout)/combined-payment/[id]` 收银台（Stripe Elements 单次扣款）→ 复用 confirm-payment 回调 → 成员订单完成 + 列表父子视图。
- **P5c Buy Now**：商品详情页快捷下单（当前商品直接进确认页，不污染购物车），复用公用确认页/支付流程。

## 恢复计划（Risk critical）

- **失败判据**：自动拆单导致订单状态错乱 / 金额重复 / 组合支付失败 / 单笔订单流程回归 / SDK 类型破坏。
- **停止条件**：发现上述任一即停；flag 关闭（`auto_split_orders=[]` + store 开关关）即完全回到老流程。
- **代码恢复**：`git revert` P5 commit（移除 hook/端点/SDK/storefront 新增；`preferred_auto_split_orders` 迁移可 down）。
- **数据恢复**：自动拆单数据为业务数据，以 `scripts/ops/db_backup.sh` 备份核对；回滚后父/子订单关系经 `orders.parent_id` 置空恢复单笔。
- **验证**：`harness check --profile quick` + 相关 rspec + `pnpm test`（sdk/storefront）+ `generated:check` + E2E；人工确认 flag 关闭时单笔订单流程不变。

## 验收映射

AC-001~003 → `carts/auto_split_spec.rb`；AC-004/005 → `payment_combinations_controller_spec.rb`；AC-006 → `sdk/tests/payment-combinations.test.ts`；AC-007/008 → storefront 组件测试 + E2E。
