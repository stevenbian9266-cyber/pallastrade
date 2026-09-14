# REQ-20260914-checkout-cart-store-credits-canonical — cart_ 店铺余额端点 canonical 化（收敛切片 2）

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-cart-store-credits-canonical.md`
> 来源：research §9.3 P2「legacy 六端点收敛」；切片 1（gift_cards）已完成并 dev 验证
> Task：`TASK-20260914130424-6a15412d`；Gate：待开（feature）
> 产出：`cart_` 余额端点可用（修 404）+ 提交兑现 + 互斥防护 + 余下 legacy 端点流量观测

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 结果 |
|---|---|---|
| App | `backend/app/` | 无实现 |
| Core | `pallastrade_core/app/` | 权威 `Checkout::AddStoreCredit`（`min(amount, outstanding_balance)`；多张余额按 `order_by_priority` 取用）；`StoreCredit`（`amount_remaining`/`available`/`for_store`）；`GiftCards::Apply` 拒绝与余额混用 |
| API | `pallastrade_api/app/` | `store/carts/store_credits_controller.rb`（`find_cart!` → **404 根因**）；`payments_controller` / `fulfillments_controller`（缺观测日志）；`shopping_cart_serializer.rb`（无 `store_credit`） |
| Admin | `pallastrade_admin/app/` | admin 侧 store credit 管理（不受影响） |
| Storefront | `storefront/src/` | 仅展示余额付款（`OrderTotals`/`PaymentInfo`），**不调用** `carts.storeCredits` → 零改动 |
| Platform | `platform/packages/sdk/` | `carts.storeCredits.*` 已存在，URL/类型不变 |

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-payments`（域） | ✅ 已读 | `StoreCredit` 为账户资产：`amount_remaining = amount - amount_used - amount_authorized`；`Checkout::AddStoreCredit` 只创建 `state: checkout` 的 store-credit payment（未 capture）；`GiftCards::Apply` 拒绝与余额混用 |
| `pallastrade-api-v3`（域） | ✅ 已读 | 车侧端点双解析范本（切片 1 `gift_cards_controller`）；错误信封 `render_error(code:, message:, status:)`；前缀 id 契约 |
| `pallastrade-testing`（域） | ✅ 已读 | 服务规格 + 请求规格分层；`create(:store_credit, ...)` 工厂；金额断言用 BigDecimal |

## 决策记录（ADR 摘要）

1. **车阶段只承载意图**（`private_metadata['store_credit_amount']`，`'full'` 为用尽哨兵）：canonical 购物车无 payments，零资金副作用；占用在提交时经**既有权威服务** `Checkout::AddStoreCredit` 完成（不新写资金逻辑）。
2. **金额顺序与切片 1 一致**：先 `order.update_with_updater!`（落最终 total）→ 兑现 → 再跑 updater 刷新 `payment_total/amount_due`（切片 1 的 dev 缺陷教训）。
3. **互斥在意图层**：镜像 `GiftCards::Apply` 的权威约束，避免提交时才失败。
4. **零额订单跳过**：`order.total.zero?` 时不建 0 额 payment。
5. **余下 legacy 端点只加观测**（不改语义）：`payments` / `fulfillments` 记 `cart.legacy_flow.used`；是否迁 canonical 由 P0-7 流量数据决定。
6. **范围外**：`payments` / `fulfillments` 的 canonical 化（订单域语义，canonical 等价能力已在 `/orders/...` 与 `PATCH /carts/:id`）。

## 实施结果

| 项 | 结果 |
|---|---|
| FR-001 双解析 + 观测 | ✅ `store_credits_controller.rb#find_cart_or_shopping_cart!`（保留 `require_authentication!`）+ `legacy_flow_observable.rb` |
| FR-002/003 应用/移除意图 | ✅ `Carts::ApplyStoreCredit`（登录/可用余额/同币种/金额合法/与礼品卡互斥；省略金额=可用合计） `Carts::RemoveStoreCredit`（幂等） |
| FR-004 提交兑现 | ✅ `Carts::Submit#apply_store_credit!`：金额管线后、零额跳过、按需建 `PaymentMethod::StoreCredit`、失败不落单 |
| FR-005 互斥 | ✅ 双向（`gift_card_store_credit_conflict` / `store_credit_gift_card_conflict`）+ i18n 文案 |
| FR-006 序列化 | ✅ `ShoppingCart.store_credit = { amount, display_amount }` |
| FR-007 legacy 观测 | ✅ `payments` / `fulfillments` 记 `cart.legacy_flow.used`（`cart_` 不计）；`payment_sessions` 保持历史 key |
| FR-008 知识同步 | ✅ OpenAPI + Skill×3 + GS-118 + research §9.3 + platform README + 契约重生成 |

## 验证与证据

| 证据 | 结果 |
|---|---|
| AC-001/002/003/004/007/008 请求规格 | ✅ `spec/requests/api/v3/store/carts/store_credits_spec.rb` 7 examples 0 failures |
| AC-001..004/006 服务规格 | ✅ `spec/services/pallastrade/carts/store_credit_spec.rb` 6 examples 0 failures |
| AC-005 提交规格 | ✅ `spec/services/pallastrade/carts/submit_spec.rb`（兑现 + 不落单 2 例） |
| 验证器 | ✅ `p1-order-flow-rspec`（已扩入两个新 spec 文件） |
| 契约产物 | ✅ `typelizer:generate` + `api:docs:schemas`（`ShoppingCart.store_credit`）+ platform 副本同步 |
| dev 实测 | ✅ 2026-09-14（部署 `8dbda735`）：用户自有 `cart_` 车 + JWT → `POST store_credits {amount:20}` **201** 且载荷 `store_credit {amount:20.0, display_amount:$20.00}`；无 JWT → **401**；移除 → **200**；游客车 + JWT → `store_credit_requires_login`（意图需用户自有车，已在 Skill 记录） |
| dev 提交兑现 | ✅ 2026-09-14（部署 `8dbda735` + 修复后重跑）：订单产出 store-credit payment 且 `amount_due` 相应减少（修复前 `RuntimeError: Store credit payment method could not be found`） |
