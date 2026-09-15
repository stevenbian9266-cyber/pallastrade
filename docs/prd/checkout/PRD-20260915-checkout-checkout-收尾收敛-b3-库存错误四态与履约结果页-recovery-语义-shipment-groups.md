# PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：Checkout 收尾收敛 B3 —— 库存错误四态与履约结果页（recovery 语义 / shipment groups） |
| 分类 | checkout（自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | `pallastrade-storefront`（主）、`pallastrade-payments`（recovery/重试语义）、`pallastrade-data-model`（fulfillments 形状） |
| 关联 REQ | REQ-20260915-checkout-b3-fulfillment-ux.md（实施时回填） |
| 关联 PRD | 同系列 B1/B2 的后续批次（非重复需求） |
| 需求类型 | 优化迭代（storefront 消费既有契约；无后端/契约变更） |

> 📌 本 PRD 为「Checkout 收尾收敛」系列第 **B3** 批，依据《商城前台 Checkout + Transaction + Promotion + 履约完整方案》§26/§27（库存不足 / 库存变化）、§33–§38（recovery / payment failure / TTL / Order Result / Order Confirmed）与 §53-P1 Fulfillment UX 条目；总体节奏表见 B1 PRD §1.1。

---

## 1. 背景与目标

- **一句话需求原文**：需求：Checkout 收尾收敛 B3 —— 库存错误四态与履约结果页（recovery 语义 / shipment groups）
- **背景**：B1/B2 已收敛「结账页（`or_`）抵扣与支付方式」与「购物车页抵扣入口」。方案 §53 的 P1 还剩两块用户可见缺口：
  1. **库存错误四态**：`INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` 目前共用**同一条**提示（`stockUnavailableTitle` + 服务端 message）与**同一个**「返回购物车」动作；方案 §26/§27 要求三者各有专属语义与动作（Return to cart / Review cart / Retry inventory check）。`INVENTORY_RECOVERY_REQUIRED`（已收款 + commit 失败）已跳结果页并展示「无需重复支付」，但缺契约级守护。
  2. **履约结果页**：`/payment-result/[id]` 成功态只有「参考号 + 金额」（正是 §37 批评的 "Thank you / Order #123 / $55"）；而 `fulfillments`（含 `items[{item_id,variant_id,quantity}]` 与 `delivery_method`）**已在 Store API 契约里**，只是没被按履约分组展示。
  3. **不变量需要显式守护**：§34/§36 要求前台不得自行恢复库存、不得客户端倒计时释放库存；§37 要求不暴露 transaction / reservation / payment session 标识。
- **目标**：
  1. 三种库存错误各有专属文案与动作（§26/§27 + 方案错误码表）。
  2. 结果页成功态给出真正与履约相关的信息（Ship to / Delivery / Items / Paid / Promotion savings），多履约按 Shipment 分组（§37）。
  3. recovery（§33/§34）与可重试（§35）语义、trace 不泄露（§37）均有测试守护。
- **成功指标**：
  - 三态库存错误在测试中各命中专属标题与动作，且库存路径不出现 "Payment failed" 语义（§26）；
  - 多履约订单渲染 N 个 shipment 分组（N = `fulfillments.length`），单履约不渲染分组标题；
  - `?session=` 不参与任何渲染（DOM 断言）；五语言键齐备。

## 2. 用户故事 / 场景

- 作为**刚收到扣款**的顾客，我希望知道「钱已收到、订单在确认中」（而不是"支付失败"），以便不会重复支付（§33）。
- 作为**付款成功**的顾客，我希望看到发货去向、配送方式、商品与实付金额，多包裹时能看出哪个商品走哪一趟（§37）。
- 作为**库存刚被别人买走**的顾客，我希望看到明确原因与下一步动作（回购物车 / 检查购物车 / 重新确认库存），而不是"支付失败"（§26/§27）。
- 场景列表：
  1. 正常：支付成功 → 结果页 success + 履约摘要（单 shipment）。
  2. 正常：多履约（拆单 / 多仓）→ 结果页列出 Shipment 1/2 各自商品与配送方式。
  3. 异常：库存不足 → 页内专属提示 + [返回购物车]；**无 PSP 扣款**、无"支付失败"。
  4. 异常：库存变化（预留过期后重预留失败）→ 专属提示 + [检查购物车]；**不得继续创建新 PaymentSession**。
  5. 异常：预留过期 → 先自动重试**一次**（显示「正在重新确认库存」）；成功则继续，失败则手动 [重新确认库存]。
  6. 异常：已收款 + commit 失败（recovery）→ 结果页「Payment received / 订单确认中 / 无需再次支付」+ 无重试入口。
  7. 异常：PSP 明确失败（declined / expired card / 3DS 拒绝）→ 结果页 failed + [重试支付] 指向**同一订单**。
  8. 边界：`fulfillments` 缺失 / 为空 → 不渲染配送分组，其余摘要照常。

## 3. 功能需求（FR）

- **FR-001 库存三态分流**（§26/§27 + 错误表）：按 `INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` 分别渲染标题、说明与动作（返回购物车 / 检查购物车 / 重新确认库存）；禁止出现 "Payment failed" 语义；页内提示（`role="alert"`），不跳结果页（此三态均无 PSP 扣款）。
  - **用户决策（2026-09-15）**：`RESERVATION_EXPIRED` 额外允许**自动重试一次**（**仅该码**）——先展示「正在重新确认库存」，重试成功则继续正常流程，失败则回落为手动 [重新确认库存]。
  - **约束**（不得违反）：`INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` **不得自动重试**（§26/§27：不得继续创建新 PaymentSession）；自动重试只重走库存确认+启动流程，**不得新建订单/新交易**，且必须幂等于同一订单（`Carts::Submit` 幂等）；一次失败后绝不循环重试。
- **FR-002 已收款待恢复**（§33/§34）：`INVENTORY_RECOVERY_REQUIRED` → 结果页 `notice=recovery`：标题「Payment received」+ 说明「订单确认中 / 无需再次支付」+ 订单参考；**不渲染任何重试/支付入口**。
- **FR-003 可重试支付失败**（§35）：结果页 failed/canceled 显示重试入口，指向**同一订单** `/{basePath}/checkout/{order.id}`，不创建新订单 / 新交易。
- **FR-004 履约摘要**（§37）：结果页在**已找到订单的所有状态**渲染 Ship to（收货地址）、Delivery（配送方式 / 分组）、Items（商品 + 数量）、Paid（实付）、Promotion savings（折扣，仅 > 0 时），并提供「查看订单」入口。
  - **用户决策（2026-09-15）**：所有状态都展示。**约束**：标题仍由状态决定（成功/失败/处理中/recovery 各自文案），非成功态的摘要区块必须带「订单内容」类副标题（不得出现 “Order confirmed” 字样），避免被误读为已确认；recovery/failed 仍不因摘要而恢复任何支付/重试入口。
- **FR-005 多履约分组**（§37）：`fulfillments.length > 1` 时按 Shipment 分组展示（组内 = 该履约的 items + delivery_method）；`length <= 1` 时退化为单列表且**不显示分组标题**；关联口径 = `fulfillment.items[].item_id` ↔ `order.items[].id`。
- **FR-006 trace 标识不外泄**（§37）：结果页与确认页不渲染 transaction / reservation / payment session 标识；`?session=` **仅用于服务端状态判定**，不进入任何文案与 DOM。
- **FR-007 不变量守护**（§34/§36）：前端不自行恢复库存、不自行创建 Payment、不做倒计时释放库存；UI 只对服务端 code 反应。
- **FR-008 i18n**：`checkout` / `paymentResult` / `orderPlaced` 命名空间补键 / 改键，五语言（en/de/es/fr/pl）一致。
- **FR-009 非目标**（记录，不在本批）：
  - §38：不新增仓库拣货 / 物流跟踪 / 签收 UI（属订单详情与履约页面职责）；
  - 不做 **item 级库存明细**（"Requested: 2 / Available: 1"）：服务端当前只回 `items[]` 标识（`order_id/line_item_id/variant_id`），无 requested/available 数量，需另开契约切片。

## 4. 非功能需求（NFR）

- **安全 / 合规**：不泄露 tracing 标识（FR-006）；错误文案一律经 `normalizeErrorMessage`（React #31 防线，bugfix 2026-09-06）。
- **一致性**：money 契约（raw 判逻辑、display 仅渲染；Promotion savings 用 `|discount_total|` 判定）。
- **兼容**：不改后端、不改契约（`fulfillments[].items` / `delivery_method` 已在 Store API 契约中，B3 只消费）。
- **可维护性**：履约分组建独立组件 + 单测；页面只做编排。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：三种库存错误各自渲染专属标题与动作文案（测试逐码断言）。
- **AC-002 ← FR-002**：`notice=recovery` 渲染 recovery 文案且**无**重试链接。
- **AC-003 ← FR-003**：failed 状态渲染重试入口，href 指向同一订单 id。
- **AC-004 ← FR-004**：已找到订单的**所有状态**均渲染履约摘要（非成功态带「订单内容」副标题且不含 “Order confirmed”）；折扣为 0 时不渲染 savings 行。
- **AC-005 ← FR-005**：多履约（2 个）→ 渲染 2 个分组且每组含对应商品与配送方式；单履约 → 不渲染分组标题。
- **AC-006 ← FR-006**：即使 URL 带 `?session=`，结果页 DOM 不包含该 session id。
- **AC-007 ← FR-007**：`INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` 不触发自动重试（start 调用次数不变）；`RESERVATION_EXPIRED` **恰好自动重试一次**，失败后回落为手动提示且不再自动重试。
- **AC-008 ← FR-008**：五语言均含新增 / 调整后的键（i18n 守护测试逐语言断言）。
- **AC-009 ← FR-004**：`fulfillments` 缺失 / 为空时页面仍渲染其余摘要（边界）。
- **AC-010 ← FR-005**：履约 `items` 找不到对应 line item 时降级展示（不崩溃、不出 `undefined`）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `INVENTORY_*` / `stock` / `fulfillment` | 仅生成类型产物 | ⚠️ 无业务代码（本批不涉） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `INVENTORY_CHANGED` / `INSUFFICIENT_STOCK` / `recovery_required` | `services/pallastrade/transactions/{start,reserve_inventory}.rb`（Reserve 失败→不创建 PaymentSession；预留过期→`INVENTORY_CHANGED`；`missing_demand` 分支带 `items[]` 标识） | ✅ 服务端权威已就绪 |
| API | `pallastrade_gems/pallastrade_api/app/` | `error_handler` / `INVENTORY` | `controllers/concerns/.../error_handler.rb`、`store/...` 错误码映射 | ✅ 错误码与 HTTP 语义齐备 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `transactions` / `recovery` | `admin/transactions_controller.rb`（recovery_required / manual_review 运营视图） | ✅ 后台自有用例（本批零改动） |
| Storefront | `storefront/src/` | `INSUFFICIENT_STOCK` / `recovery` / `fulfillments` | `components/checkout/UnifiedCheckout.tsx`（三码共用一条提示）、`app/[country]/[locale]/(checkout)/payment-result/[id]/page.tsx`（仅参考号 + 金额）、`order-placed/[id]/page.tsx`（有 items/地址但无分组）、`app/api/checkout/start/route.ts`（透传 code/message/order_id/quote） | ❌ 三态未分流、结果页无履约信息 → **本批实现** |
| Platform | `platform/packages/` | `fulfillments` / `Fulfillment` | `types/generated/{Order,Cart,Fulfillment}.ts`（`fulfillments[].items[]` + `delivery_method` 已存在）；`sdk/src/types/index.ts` 同步字段 | ✅ 契约就绪，无需生成物改动 |

**结论**：本批为**纯 storefront 消费**（无后端、无契约变更）。防重复判定：`PRD-20260913-checkout-txn-error-routing` 已交付「错误落点分流」（notice=recovery/processing 与库存三码页内提示），B3 在其上补「**三态专属动作** + **履约结果页**」，不是重复需求；`fulfillments` 数据已由既有 Store API 契约提供。

## 7. 技术影响

- **storefront**：`app/[country]/[locale]/(checkout)/payment-result/[id]/page.tsx`（履约摘要 + recovery/failed 语义）、`components/checkout/UnifiedCheckout.tsx`（三态分流文案/动作）、新组件 `components/order/ShippingGroups.tsx`（履约分组）、`app/[country]/[locale]/(checkout)/order-placed/[id]/page.tsx`（复用分组组件）、`messages/{en,de,es,fr,pl}.json`。
- **不涉及**：后端、契约生成物、数据库、订单状态机、支付会话创建。

## 8. 测试计划

- **扩展（结果页）**：`storefront/src/app/[country]/[locale]/(checkout)/payment-result/[id]/__tests__/page.test.tsx` → AC-002/003/004/005/006/009
- **扩展（结账页）**：`storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` → AC-001/007
- **新增（履约分组）**：`storefront/src/components/order/__tests__/ShippingGroups.test.tsx` → AC-005/010
- **扩展（i18n 守护）**：`storefront/src/lib/__tests__/checkout-i18n-keys.test.ts` → AC-008
- **回归**：`pnpm -C storefront test` / `check` / `typecheck` 三绿
- **AC ↔ 测试映射**：见上逐条标注；测试文件内同行写 `# PRD-<本PRD-ID> AC-xxx` 供 `prd verify` 校验

## 9. 文档同步清单（知识同步门）

- [x] Skill：`pallastrade-storefront`（购物车/结账流程条目新增 B3 口径：三态分流 + 自动重试一次约束 + 履约摘要 + 不泄露 trace）
- [x] 场景库：新增 **GS-122**（库存错误各自落点 + 履约结果页不暴露 trace + 不自行恢复），`eval-ai --scenarios` = 123/123 valid
- [x] 本 PRD 状态 → done + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）
- [x] **已评估，无需更新**：API 文档 / SDK 生成物（无契约变更）、`pallastrade-payments` / `pallastrade-api-v3` Skill（服务端语义未变）、`platform/packages/README.md`（无 SDK 能力变更）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿：B3 范围（库存四态 + 履约结果页）+ FR-001..009 / AC-001..010 / 跨层搜索 / 测试与同步计划 | AI || 2026-09-15 | 0.2 | 用户确认实施并定下三项决策：① `RESERVATION_EXPIRED` **自动重试一次**（仅该码；约束：不新建订单/不循环、stock 两码不得自动重试）；② 履约摘要**所有状态**展示（约束：非成功态带「订单内容」副标题且不得出现 “Order confirmed”）；③ 分组标题用 **Shipment N**。AC-001/004/007 随之调整 | AI |