# PRD-20260914-checkout-checkout-收尾收敛-b1-checkoutview-扩展-credits-capabilities-availa

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | 根据《豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md》拆解任务节奏并实施（2026-09-14 会话指令） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-api-v3、pallastrade-testing、pallastrade-storefront、pallastrade-data-model |
| 关联 REQ | REQ-20260914-checkout-b1-checkoutview-extension.md（实施时回填） |
| 关联 PRD | 承接 PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview（done，本批为其缺口补齐，非重复） |
| 需求类型 | 优化迭代（接口变更 additive + 前台消费） |
| 风险级别 | critical（含支付/结算路径改动，Harness 自动判定） |

> 🔎 本 PRD 为“Checkout 收尾收敛”系列的第 B1 批（拆解自方案文档 §53 优先级 + research 2026-09-13 缺口清单），并附带 B1–B5 总体任务节奏。

## 1. 背景与目标

- **一句话需求原文**：根据《豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md》，拆解出任务节奏，输出非常细致的 PRD，然后开始实施任务。
- **背景**：
  - 方案 §17 要求 `CheckoutView` 成为 Checkout 页面唯一数据源；RESEARCH-20260913 逐项核验指出视图缺 4 组字段：`credits / capabilities / available_payment_methods / billing_mode`（§5.1 另指出 store credit 缺前台入口）。
  - 方案 §53 的 P0 组（Money 契约、use_shipping、Coupon 断链、错误落点分流、provider gating）已于 2026-09-13/14 批次落地（`66e0a1b7` 错误分流+Money、`43ead56a` billing_mode、`4bfb2084` 报价闭环 409、`7b1ebb5e`/`87cf3946`/`8dbda735` cart_ 优惠码/礼品卡/余额 canonical 化、`ed8cf787` PrefixedId 加固）。
  - 本批承接 **P1 Checkout UX 第一切片**：把上述 4 组字段补进 CheckoutView 并由 or_ 页（`OrderPaymentContent`）消费，消除页面长期依赖 Order 序列化兜底 / 无 capabilities 依据的问题。
- **目标**：CheckoutView 服务端权威输出 `credits`（礼品卡 + 店铺余额）、`capabilities`、`payment.available_payment_methods[]`、`billing_mode`；or_ 页展示 credits 两行、支付方式取自视图、编辑按钮按 capabilities 控制；OpenAPI + SDK 类型同步通过 `generated:check`。
- **成功指标**：
  - or_ 页 credits/payment/capabilities 三组数据全部来自 CheckoutView（order 兜底仅保留兼容回退）；
  - `npx harness generated:check` 通过（schema 幂等 + SDK 类型哈希一致）；
  - 定向验证器 `chk-p1-1a-rspec` 与 `chk-p1-4b-storefront` 全绿；
  - 零写路径改动（不 save/updater/状态机）。

### 1.1 任务节奏（B1–B5，拆解自方案 §53 + 现状代码核验）

| 批次 | 对应方案章节 | 内容 | 依赖 | 验收锚点 | 状态 |
|---|---|---|---|---|---|
| **B1（本 PRD）** | §17 / §53-P1 Checkout UX | CheckoutView 扩展（credits/capabilities/available_payment_methods/billing_mode）+ or_ 页消费 | 无（P0 已完成） | 本文件 AC-001..AC-014 | **实施中** |
| B2 | §15/§16 + research §5.1 | cart_ 页 Store Credit 应用/移除入口 + Order Summary 三合一（折扣/礼卡/余额）展示 | B1 视图口径 | 余额入口可应用/移除、金额一致 | 待排期 |
| B3 | §33–§38 / §53-P1 Fulfillment UX | 库存错误态页面化、recovery 页语义、多履约（shipment groups）展示、Order confirmed 状态 | B1 | 四种库存错误各有专属 UI | 待排期 |
| B4 | §29 / §45 / P0-7 | Express canonicalize（cart 域 legacy → `transactions` 链；含钱包 Express 行按支付方案 P1） | B1（支付方式服务端权威） | 日志无 legacy 会话新增、钱包走 Transaction→Reserve | 待排期 |
| B5 | §45/§47 / §53-P2 | Legacy 收尾（余下端点治理/退役、usage metric 收口）与清理 | B4 | legacy 端点零新增调用 | 待排期 |

> 节奏依据：方案 §53 的阶段优先序（P0 → P1 UX/Contract/Fulfillment → P2 Legacy/Cleanup）；B4 的 Express 迁移受 P0-7「不得在 legacy 上新增能力」约束，且需 B1 的 `available_payment_methods` 服务端权威口径打底。

## 2. 用户故事 / 场景

- 作为顾客，在 or_ 补付页我希望看到「礼品卡 / 店铺余额」的金额行，以便知道还差多少钱需要支付。
- 作为顾客，我希望支付方式列表永远与服务端可支付能力一致（不会出现「选得上、付不了」）。
- 作为顾客，我希望订单已支付后，地址/配送等编辑入口不再出现（避免无效操作）。

场景列表：

- **S1 正常流（含抵扣）**：下单使用礼品卡 + 店铺余额 → or_ 页渲染 `Gift card -$3.00`、`Store credit -$2.00` 行与 `Amount due`。
- **S2 边界（无抵扣）**：无礼品卡/余额 → 对应行不渲染（不出现 `-$0.00`）。
- **S3 边界（价格门控）**：`prices_hidden` 渠道的游客 → 金额字段为 null，页面不渲染任何金额行（既有规则不变）。
- **S4 异常（已支付）**：订单处于已支付/已完成 → `capabilities` 全 false → Pay 按钮禁用、编辑入口隐藏。
- **S5 边界（账单语义）**：`billing_mode = same_as_shipping` → 账单区默认收起；`custom` → 默认展开（派生值仅用于初始态提示，不改变写路径）。
- **S6 兼容**：or_ 页历史行为（409 报价差异确认、内联编辑地址、补付换卡）保持不变。

## 3. 功能需求（FR）

- **FR-001 `credits.gift_cards[]`**：视图暴露已应用礼品卡数组（当前数据模型为单卡：`order.gift_card`；数组化保持契约前向兼容）。每项字段与既有 `gift_card_serializer` 保持同源：`{ id, code, amount, display_amount }`；无卡 → `[]`；`hide_prices` → 金额 null。
- **FR-002 `credits.store_credit`**：`{ amount, display_amount } | null`，分别取 `total_applied_store_credit` / `display_total_applied_store_credit`；为 0 → `null`；`hide_prices` → null。
- **FR-003 `capabilities`**：`{ can_edit_address, can_change_shipping, can_apply_promotion, can_pay }`，服务端只读计算，规则：
  - `can_edit_address` / `can_change_shipping`：`order.state == 'pending'` 且 `payment_state ∈ [nil, 'unpaid', 'balance_due']`；
  - `can_apply_promotion`：同上且 `!order.completed?`；
  - `can_pay`：`ready == true` 且 `amount_due > 0` 且 `state == 'pending'`。
- **FR-004 `payment.available_payment_methods[]`**：与 `PaymentSessions::Start` 校验同源——`order.payment_methods`（= `store.payment_methods.active.available_on_front_end.select(&:available_for_order?)`），经 `payment_method_serializer` 输出（id/name/description/type/session_required/source_required）。
- **FR-005 `billing_mode`**：派生字段 `'same_as_shipping' | 'custom'`：`bill_address` 缺失 → `same_as_shipping`；否则关键字段（name/address1/address2/city/zipcode/country/state）与 `ship_address` 全等 → `same_as_shipping`，否则 `custom`。
- **FR-006 or_ 页消费（`OrderPaymentContent.tsx`）**：
  - 渲染 credits 概览行（礼品卡、店铺余额；负值/暗色样式与既有金额行一致；null/0 不渲染）；
  - 支付方式列表优先取 `view.payment.available_payment_methods`（order 回退保留）；
  - 编辑入口按 `capabilities.can_edit_address / can_change_shipping` 控制显隐；Pay 按钮按 `can_pay` 禁用；
  - 账单区初始展开状态采用 `billing_mode`。
- **FR-007 契约同步**：CheckoutView 序列化变更同步 `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/` 副本 + SDK `types/zod`（typelizer 再生成），`harness generated:check` 通过。
- **FR-008 兼容与安全**：新增字段全部 additive；金额门控沿用 `money_attributes` / `hide_prices`；不触碰写路径、状态机、PaymentSession 创建逻辑；不引入新的数据源表。

## 4. 非功能需求（NFR）

- **只读零副作用**：`OrderCheckout::View` 不得 save/updater/requote/推进状态机（既有约束）；capabilities 计算仅读列与方法。
- **性能**：不新增 N+1 —— `View::INCLUDES` 增补 `:gift_card`（若缺失）并复用既有预加载。
- **安全**：金额字段遵守 `hide_prices` 门控；不新增任何对外暴露的敏感字段（礼卡 code 沿用既有 serializer 的暴露口径）。
- **兼容**：新增字段为 additive；老前端忽略新字段不产生行为变化；SDK 类型再生成保持哈希一致。
- **可维护**：capabilities 规则集中在一处（View 私有方法），避免前后端各自推断。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：应用礼品卡的订单 → `credits.gift_cards[0]` 含 `id/amount/display_amount`（`checkout_serializer_spec`）。
- AC-002 ← FR-001：无礼品卡订单 → `credits.gift_cards == []`（`checkout_serializer_spec`）。
- AC-003 ← FR-002：使用店铺余额的订单 → `credits.store_credit.amount == total_applied_store_credit.to_s`；未使用 → `null`（`checkout_serializer_spec`）。
- AC-004 ← FR-002/FR-008：`hide_prices` 请求 → `credits.store_credit` 与礼品卡金额均为 `null`（`checkout_serializer_spec`）。
- AC-005 ← FR-003：pending 且未支付且 ready 订单 → 四个 capabilities 均为 true（`view_spec` / `checkout_serializer_spec`）。
- AC-006 ← FR-003：completed 订单 → 四个 capabilities 均为 false（`view_spec`）。
- AC-007 ← FR-004：视图 `payment.available_payment_methods` 与 `order.payment_methods` 口径一致；停用方法（active=false / display_on=back_end）不出现（`checkout_serializer_spec`）。
- AC-008 ← FR-004：Stripe 支付方式输出 `type='stripe'`、`session_required=true`（`checkout_serializer_spec`）。
- AC-009 ← FR-005：账单缺失或与配送一致 → `'same_as_shipping'`；账单独立 → `'custom'`（`view_spec`）。
- AC-010 ← FR-006：or_ 页渲染礼品卡/余额行（值为负、含 display_* 展示）；无抵扣时不渲染（`OrderPaymentContent.test.tsx`）。
- AC-011 ← FR-006：`can_pay=false` 时 Pay 按钮禁用（`OrderPaymentContent.test.tsx`）。
- AC-012 ← FR-006：支付方式仅存在于视图字段（order 无该数据）时仍能渲染并可选（`OrderPaymentContent.test.tsx`）。
- AC-013 ← FR-007：`harness generated:check` 通过（api-docs 幂等 + SDK 类型哈希一致）。
- AC-014 ← FR-008：既有 or_ 用例（409 差异确认 / 内联编辑 / 补付）全绿，无回归（`OrderPaymentContent.test.tsx` + `chk-p1-1a-rspec`）。

## 6. 跨层搜索记录（6 层，gate 强制；2026-09-14 实测）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | credits/capabilities/checkout | 仅生成类型（`javascript/types/serializers/*`）；无业务实现 | 否（宿主层无需改） |
| Core | `pallastrade_core/app/` | credits/gift_card/store_credit/billing_mode | `order_checkout/view.rb`（缺 credits/capabilities/payment）、`order/gift_card.rb`（`gift_card`/`gift_card_total`）、`order/store_credit.rb`（`total_applied_store_credit`/`display_total_applied_store_credit`）、`order.rb#payment_methods`（active+front_end+available_for_order?） | 部分（需扩展视图，不新建数据源） |
| API | `pallastrade_api/app/` | checkout serializer / payment_methods | `store/checkout/checkout_serializer.rb`（缺 credits/capabilities/payment/billing_mode）、`order_serializer.rb`（已有 store_credit_total/gift_card_total/gift_card 先例）、`payment_method_serializer.rb`（可复用） | 部分（需扩展 serializer） |
| Admin | `pallastrade_admin/app/` | checkout/credits | 无 checkout 前台相关实现 | 否 |
| Storefront | `storefront/src/` | credit/gift/discount/capabilities | `OrderPaymentContent.tsx`（金额行无礼卡/余额；支付方式取 order 回退；无 capabilities）、`UnifiedCheckout.tsx`（cart_ 页，另有 gift card 交互） | 部分（需消费新字段） |
| Platform | `platform/packages/` | checkout types | `sdk/src/types|zod/generated/*`（Checkout/CheckoutView 类型为生成物） | 部分（需再生成） |

**结论**：能力载体全部已在 Core/API 层存在（Order 列与方法），本批为**视图 + 序列化 + 前台消费**的增量扩展；无需新表/新服务；防重复判定——`PRD-20260903-checkout-chk-p1-1a`（done）建立只读 CheckoutView，本批为其 §17 缺口补齐，不属于重复 PRD。

## 7. 技术影响

**改动文件（预计）**：

- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/order_checkout/view.rb`：新增 `credits` / `capabilities` / `available_payment_methods` / `billing_mode` 只读方法；`INCLUDES` 增补 `:gift_card`。
- `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/store/checkout/checkout_serializer.rb`：typelize + attribute 输出 4 组新字段（金额走 `hide_prices` 门控）。
- `storefront/src/components/checkout/OrderPaymentContent.tsx`：credits 行渲染、支付方式视图优先、capabilities 控制、billing_mode 初始态。
- 测试：`spec/services/pallastrade/order_checkout/view_spec.rb`、`spec/serializers/.../checkout_serializer_spec.rb`、`storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`。
- 契约生成物：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/*`、`platform/packages/sdk/src/{types,zod}/generated/*`。

**影响面**：Store API Checkout 序列化（additive）；or_ 页渲染；SDK 类型。**不涉及**：数据库迁移、写路径、状态机、支付会话创建、cart_ 页（归 B2）。

## 8. 测试计划

**更新测试文件**：

| 文件 | 变更点 | 覆盖 AC |
|---|---|---|
| `spec/services/pallastrade/order_checkout/view_spec.rb` | 新增 credits/available_payment_methods/billing_mode/capabilities 断言 | AC-005/006/009 |
| `spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb` | 新字段序列化 + hide_prices 门控 | AC-001/002/003/004/007/008 |
| `storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx` | credits 行渲染/不渲染、can_pay 禁用、视图支付方式渲染、回归 | AC-010/011/012/014 |

**验证器（注册 verifier，勿新造）**：

- 后端：`npx harness verify chk-p1-1a-rspec --task <id>`（含 view_spec + checkout_serializer_spec + checkout_controller_spec + 订单域回归）
- 前端：`npx harness verify chk-p1-4b-storefront --task <id>`（OrderPaymentContent + PaymentCheckoutModal + UnifiedCheckout）
- 契约：`npx harness generated:check`（AC-013；含 typelizer + api-docs schema 幂等）

**AC → 测试映射**：AC-001..AC-009 → 后端 spec；AC-010..AC-012/AC-014 → storefront 组件测试；AC-013 → generated:check。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（Checkout schema 新增字段；`generated:check` = no drift）
- [x] SDK 生成物：`platform/packages/sdk/src/{types,zod}/generated/`（typelizer 再生成 + `generate:zod` + `build`；`generated:check` 校验通过）
- [x] SDK 手写类型：`platform/packages/sdk/src/types/index.ts#CheckoutView` 同步扩展（dist 重建 + storefront junction 刷新，`tsc --noEmit` 通过）
- [x] Skill 文档：`pallastrade-storefront`（or_ 页消费口径）+ `pallastrade-typescript-sdk`（`orders.checkout.get` 新字段）已更新；`pallastrade-api-v3` / `pallastrade-payments` 评估为**无需更新**（未新增端点/路由，字段为既有投影 additive）
- [x] 场景库：新增 **GS-120**（支付/抵扣/能力位服务端权威），`harness eval-ai --scenarios` = 121/121 valid
- [x] 包文档：`platform/packages/README.md` SDK 段落已更新；根 README / AGENTS / copilot-instructions / pallastrade-prd Skill 评估为**无需更新**（流程与规则未变）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引（`prd-status-sync --fix` 修复 1 处，`--check` 通过 132/132）
- [x] 方案文档《商城前台 Checkout…完整方案.md》§17 缺口：本批已补齐四组字段（git-ignored 本地文档，在 §1.1 节奏表标注 B1 完成）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 0.1 | 初稿：B1 范围 + B1–B5 任务节奏 + FR/AC/测试/同步计划 | AI |
| 2026-09-14 | 0.2 | 实施完成并验证：View/Serializer 四组字段 + or_ 页消费；`chk-p1-1a-rspec` / `chk-p1-4b-storefront` / `generated:check` 全绿；PRD 置 done | AI |
| 2026-09-14 | 0.3 | 知识同步完成：storefront/ts-sdk Skill、packages README、GS-120、PRD 索引；`sync-check --ack` | AI |
