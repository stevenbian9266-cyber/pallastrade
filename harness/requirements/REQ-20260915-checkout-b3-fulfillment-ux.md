# REQ-20260915-checkout-b3-fulfillment-ux

> 关联 PRD：`docs/prd/checkout/PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups.md`
> 关联任务：TASK-20260915002720-046cff53 · Gate `GATE-2026-09-15T00-27-29`
> 前置批次：B1（CheckoutView 扩展）、B2（购物车页抵扣入口），均已 done

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `INVENTORY_*` / `stock` / `fulfillment` | 仅生成类型产物（`app/javascript/types/serializers/*`）；无业务代码 | 否（宿主层无需改动） |
| App — views/decorators | `backend/app/` | 同上 | 无 | 否 |
| Core Gem — services | `pallastrade_core/app/services/pallastrade/` | `INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `recovery_required` | `transactions/start.rb`（Payment Start Policy：recovery 态对前端暴露 `INVENTORY_RECOVERY_REQUIRED`）、`transactions/reserve_inventory.rb`（Reserve 失败→不创建 PaymentSession；预留 EXPIRED 后重预留失败→`INVENTORY_CHANGED`；`missing_demand` 分支带 `items[]` 标识）、`transactions/{recover,finalize}.rb`、`gateway/bogus.rb` | 是（服务端权威已就绪） |
| Core Gem — models | `pallastrade_core/app/models/pallastrade/` | `commerce_transaction` / `stock_reservation` | `commerce_transaction.rb`（`recovery_required` / `manual_review` 状态机 + 时间戳）、`stock_reservation.rb`（RESERVED→COMMITTED/RELEASED/EXPIRED） | 是（本批只消费状态语义） |
| API Gem — controllers | `pallastrade_api/app/controllers/` | `error_handler` / `reservation` | `concerns/.../error_handler.rb`（错误码表）、`store/...` 错误渲染 | 是（结构化 code/message 已透出） |
| Admin Gem | `pallastrade_admin/app/` | `transactions` / `recovery` | `admin/transactions_controller.rb`（recovery_required/manual_review 运营视图 + recover 动作） | 是（后台自有页面，本批零改动） |
| Storefront | `storefront/src/` | `INSUFFICIENT_STOCK` / `recovery` / `fulfillments` | `components/checkout/UnifiedCheckout.tsx` L297-299/719-745（三码**共用**一条提示 + 同一个返回购物车动作；recovery 跳结果页）、`app/[country]/[locale]/(checkout)/payment-result/[id]/page.tsx`（成功态仅参考号 + 金额）、`order-placed/[id]/page.tsx`（items/地址/支付已有；配送区**未按履约分组**）、`app/api/checkout/start/route.ts`（透传 code/message/order_id/quote） | **部分 → 本批实现** |
| Platform | `platform/packages/` | `fulfillments` / `Fulfillment` | `sdk/src/types/generated/{Order,Cart,Fulfillment}.ts`（`fulfillments[].items[{item_id,variant_id,quantity}]` + `delivery_method` + `status` 均已存在） | 是（契约就绪，无需生成物改动） |

### 搜索结论

- 服务端（Core/API）已经把四种库存/恢复语义都做成**结构化错误码**（`INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` / `INVENTORY_RECOVERY_REQUIRED`），并保证 Reserve 失败**不创建 PaymentSession**；前台只需按 code 分流，不自行判断库存。
- `fulfillments`（含 items 与 delivery method）**已在 Store API 契约中**；本批是纯前台消费，无后端、无契约、无生成物改动。
- 防重复：`PRD-20260913-checkout-txn-error-routing`（错误落点分流）已交付 notice=recovery/processing 与库存三码页内提示；`PRD-20260914-checkout-quote-confirmation-loop` 交付报价漂移页内确认 —— B3 只补「三态专属动作 + 履约结果页」，均非重复。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 定制优先级 Settings→Configuration→Events→Dependencies→Admin/Ransack→Generators→Decorators→Extensions；本批不新增定制模式（消费既有契约），不引入 decorator/subscriber |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 阶段 0-5：`prd new` → 模板扩充 → **用户确认** → gate → 实施 → AC↔测试（`prd verify`）→ 知识同步门 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ✅ | ✅ 已读 | ① 客户端组件不得直接 `getClient()`，服务端读取走 `lib/data/*`；② money 契约（raw 判逻辑、display 仅渲染）；③ 改 storefront 必须 `pnpm test` + `check`(biome) + `typecheck` 三绿；④ 库存类错误留在 `cart_` 页内（`checkout-error-notice`，`role="alert"`），不出现"支付失败"字样 |
| `pallastrade-payments` | ✅ | ✅ 已读 | 付款/退款状态机与「资金先入账、后成员完成」不变量：PSP success + local incomplete = `recovery_required`（**不是 payment failed**）；重试必须落在同一订单/交易；store credit 单列不计入 savings |
| `pallastrade-data-model` | ✅ | ✅ 已读 | `Order → Shipment → ShippingRate → ShippingMethod`；Shipment 有自己的状态机（pending→ready→shipped）；`Adjustment` 多态挂在 Order/LineItem/Shipment 上（履约行的金额口径来源） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 后端 RSpec + Factory Bot；storefront 侧 vitest（组件/页面/数据层），断言要环境无关 |
| `pallastrade-api-v3` | ⛔ | ⛔ | 本批不改端点、不改序列化器（契约已含 fulfillments） |
| `pallastrade-decorators` / `pallastrade-dependencies` / `pallastrade-events-webhooks` / `pallastrade-admin` | ⛔ | ⛔ | 无类结构改动 / 无服务替换 / 无事件订阅 / 无 admin 页面改动 |

---

## 需求标题

Checkout 收尾收敛 B3：库存错误四态与履约结果页（recovery 语义 / shipment groups）

## 任务类型

功能优化（纯 storefront 消费既有契约）

## 需求描述

方案 §53-P1 的两块用户体验缺口：① 库存错误三态（`INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED`）目前共用一条提示与同一个动作，未按 §26/§27 给出专属语义与下一步；② 支付成功页只有「参考号 + 金额」，没有发货去向 / 配送方式 / 多履约分组等真正与履约相关的信息（§37）。本批按服务端权威错误码分流三态 UI，并把结果页升级为履约摘要（含多 shipment 分组），同时守护 §33/§34/§35/§36/§37 的不变量（不重付、不自行恢复、不倒计时、不暴露 trace 标识）。

## 影响范围（harness affected 输出）

受影响：storefront（`payment-result` 结果页、`UnifiedCheckout` 错误分流、新 `ShippingGroups` 组件、`order-placed` 复用、5 语言文案）+ 三个测试文件扩展。
不涉及：后端、契约生成物、数据库、订单状态机、支付会话创建。

## 技术方案（初步）

1. **错误三态分流**（`UnifiedCheckout`）：`payError.kind` 由 `"stock"` 细化为 `insufficient-stock` / `inventory-changed` / `reservation-expired`，各带专属 title/description/action（返回购物车 / 检查购物车 / 重新确认库存）；`INVENTORY_RECOVERY_REQUIRED` 维持结果页 recovery（无重试入口）。
2. **履约摘要**（`payment-result` 成功态）：新组件按 `fulfillments` 渲染配送分组（`fulfillment.items[].item_id` ↔ `order.items[].id`），并渲染 Ship to / Items / Paid / Promotion savings；提供「查看订单」入口；`?session=` 仅用于状态判定（不渲染）。
3. **复用**：`order-placed` 的配送区改用同一分组组件。
4. **i18n**：新增键落 `checkout` / `paymentResult` / `orderPlaced` 三命名空间，五语言一致。

## 风险点

- 最高风险：结果页是支付后的唯一落点（or_ / 收银台 / 统一结账共用），改动可能影响「已收款待恢复」的防重付语义 → 以既有 `notice=recovery/processing` 分支为回归基线，测试逐条断言「无重试链接」。
- 分组渲染风险：`fulfillments[].items` 可能与 `order.items` 对不上（拆单/数量拆分）→ 降级策略 = 找不到就不显示该行（不显示 `undefined`），单履约退化为平铺。
- regression 风险：`UnifiedCheckout` 是核心下单页 → 三态分流只改**文案与动作渲染**，不改任何请求路径（test 断言 start 调用次数不变）。

## 决策节点

> ⏸️ **等待用户确认**（R3/R7）：PRD 与 REQ 呈现后，用户明确「确认/实施」才清除 `user-confirmed` 并进入实施。
>
> 开放决策（AI 建议已在括号内）：
> 1. 「重新确认库存」动作语义：**留在结账页让用户再点一次 Pay**（服务端重新 Reserve）vs 自动重试一次 —— 建议**用户再点一次**（§26/§27 明确"不得继续创建新 PaymentSession"，自动重试会破坏该不变量）。
> 2. 结果页履约摘要的展示范围：**成功态**才展示（failed/pending/recovery 保持精简状态页）vs 所有状态都展示 —— 建议**仅成功态**（失败态展示商品列表易被误读为"订单已确认"）。
> 3. 多履约分组标题文案：`Shipment 1 / Shipment 2`（§37 原文）vs `Delivery 1 / Delivery 2` —— 建议 **Shipment N**（与 §37 一致，且避免与单配送方式的 "Delivery" 行重名）。
>
> **用户已确认（2026-09-15）**：① 自动重试一次（仅 `RESERVATION_EXPIRED`，失败回落手动）；② 履约摘要所有状态展示（非成功态带「订单内容」副标题）；③ 分组标题用 `Shipment N`。约束已写入 PRD v0.2 FR-001/FR-004。

---

## 阶段③：实施后验证（不可跳过）

> ⚠️ 每项改动都必须有对应的最低验证。

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 前端（结账页错误分流） | `components/checkout/UnifiedCheckout.tsx` | `pnpm -C storefront test`（UnifiedCheckout 30 例） | ✅ 通过（含三态专属 + 自动重试一次 + 不自动重试） | ✅ |
| 前端（结果页 + 分组组件） | `payment-result/[id]/page.tsx`、`components/order/ShippingGroups.tsx`、`order-placed/[id]/page.tsx` | `pnpm -C storefront test` + `check` + `typecheck` | ✅ 54 文件 / 338 例全绿；biome exit 0（3 条既有 warning）；tsc exit 0 | ✅ |
| 文案 | `messages/{en,de,es,fr,pl}.json` | i18n 守护测试（五语言齐备） | ✅ 通过（`order` 命名空间 + checkout 8 键） | ✅ |
| AC 映射 | PRD AC-001..010 | `npx harness prd verify --id <本PRD>` | ✅ 16 AC 全覆盖 | ✅ |
| 其它 | PRD/README 状态 | `node scripts/ci/prd-status-sync.mjs --check` | ✅ 134/134 一致 | ✅ |
| 声明无需验证 → 原因：_____ | — | — | — | — |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

**本批不涉及 admin 页面** —— 无 admin 视图/控制器改动，三项检查豁免（记录在案）。

### 验证结论

- 前端：`pnpm -C storefront test` 全量 54 文件 / **338 例全绿**（新增：ShippingGroups 4 例；扩展：结果页 +7 例、UnifiedCheckout 三态分流与自动重试重构）；`biome check` exit 0（3 条既有 warning）；`tsc --noEmit` exit 0。
- AC 映射：`prd verify` 16 AC 全覆盖（AC-002/003 复用既有 recovery/重试用例并补 B3 标记）。
- 零后端改动：未触碰后端、契约生成物、数据库 —— `fulfillments[].items` 与四态错误码均为既有服务端能力。
- 不变量守护：库存两码不自动重试（fetch 次数断言）、预留过期自动重试一次且一次为限、recovery 态无重试入口、结果页 DOM 不含 `?session=` 值。

### 用户决策与建议不一致之处（已回写 PRD v0.2）

1. **预留过期自动重试一次**（建议为“用户再点一次”）→ 已实现，并加了三道约束：仅该码、一次为限（`stockRetryRef`）、不新建订单/交易（复用同一提交路径）；失败后回落为手动 [重新确认库存]。
2. **履约摘要所有状态展示**（建议为仅成功态）→ 已实现，并加约束：非成功态用「订单内容」副标题、状态标题仍为状态文案（绝不出现 “Order confirmed”）。
