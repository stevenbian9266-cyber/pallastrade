# PRD-20260919-checkout-结算页待支付订单再次支付重验-失效行剔除-优惠复核-订单金额变化提示-收银台弹窗退役

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：结算页待支付订单再次支付重验（失效行剔除/优惠复核/订单金额变化提示）+ 收银台弹窗退役 |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-checkout（主）/ pallastrade-payments / pallastrade-deals（促销）/ pallastrade-data-model / pallastrade-storefront / pallastrade-api-v3 / pallastrade-i18n / pallastrade-testing / pallastrade-customization / pallastrade-prd |
| 关联 REQ | REQ-20260919-checkout-order-repay-revalidate.md（实施时回填） |
| 关联 PRD | N/A（与 PRD-20260919-shipping-checkout-quote-preview 同族但不重复：那条是「结算页只读预览报价」，本 PRD 是「订单补付前的商业事实重验 + 失效行剔除 + 弹窗退役」） |
| 需求类型 | 优化迭代（含 Bug 修复：状态投影缺失；含前台退役：收银台弹窗） |

> 前置方案（用户逐项拍板，2026-09-19/20 两轮）：
> 1. 待支付订单补付**跳订单支付页**，移除收银台弹窗（`PaymentCheckoutModal`）及其组合支付 UI；
> 2. 不做「确认新金额」二次动作——页面**直接回显重验后金额**，但必须给出「订单金额已变化」提示（新增文案，多语言）；
> 3. 阻断类（失效）商品不可支付：UI 提示商品失效，**只对有效商品实际扣款**；若使用了优惠，须复核优惠是否仍满足当前有效商品；
> 4. 存量处理按 AI 建议：不迁移报价窗口，只回填近期订单的状态投影。

## 1. 背景与目标

- **一句话需求原文**：待支付订单再次支付时还得做一次判断，比如商品信息是否变化、发货地是否支持等，把这部分因素考虑进去；结合拍板：跳订单支付页 + 移除收银台弹窗、直接回显新金额并提示金额变化、失效商品只付有效部分且复核优惠、存量按建议处理。

- **背景（根因，dev 真机取证）**：
  - **缺口 A｜报价窗口从未签发 → 重验被整体跳过**：`checkout_expires_at` 全仓仅 `OrderCheckout::Recalculate` / `OrderCheckout::Refresh` 写入，`Carts::Submit#build_order!` 不签发；而两处门（`Transactions::Start#quote_gate_active?`、`PaymentSessions::Start#gate_active?`）都判定 `checkout_expires_at.present?` ⇒ 标准流程新订单恒为假，补付时**报价刷新、金额比对、就绪校验全部不执行**。
    dev 证据（订单 `or_X35bb5HTmV` / `#R729701382`）：`checkout_expires_at=nil`、`checkout_version=0`、`price_version=nil`、`standard_flow?=true`、`quote_gate_active?=false`。
  - **缺口 B｜即便有窗口也验不全**：`Recalculate` 只跑 `OrderUpdater#update`（用**冻结** `line_item.price`），从不调用 `update_line_item_prices!`（按当前目录/价目表重取价），从不复核 `Product#purchasable?` / 库存 / 配送可达性（`ensure_available_shipping_rates` 只在 legacy 状态机与提交时执行）。
  - **缺口 C｜剔除商品会撕掉抵扣与优惠（本轮新发现）**：订单行删除的既有权威 `LineItems::Destroy` 内部 `recalculate_service` = `CartLegacy::Recalculate`，其代码会 `order.remove_gift_card` + `order.payments.store_credits.checkout.destroy_all` + `ensure_updated_shipments`（重建 shipments）；而 `PromotionHandler::Coupon#apply` 对已应用的券直接回 `coupon_code_already_applied`（不能作为复核入口），复核/移除的正确入口是 `Coupon#remove`（含 `release_redemption_or_detach_code` + `remove_promotion_adjustments`）。⇒ 只做「删行 + 重算」会静默丢抵扣、留下过期券，导致应付金额不诚实。
  - **缺口 D｜状态投影缺失（列表空列 + 无支付入口）**：`payment_state`/`shipment_state` 仅由 `OrderUpdater#update_payment_state`/`update_shipment_state` 写入，而 `OrderUpdater#update` 只在 `order.completed?` 时调用这两者 ⇒ 已提交未支付订单两列恒为 `nil`（列表显示 `N/A`），且前台 `payment_status === 'balance_due'` 恒假 ⇒ 补付按钮永不出现；订单列表 actions 列也从来没有 Pay。

- **目标**：
  1. 补付入口可用：订单列表 / 订单详情直接跳**订单支付页**（`/{country}/{locale}/checkout/or_...`），单一路径；
  2. 补付前**同源重验**：价格、可售性、库存、配送可达、运费、税、优惠、抵扣、就绪度、支付入口、订单状态；
  3. 失效行**剔除但不阻断整体支付**（只付有效商品），并在写路径同步复核优惠与抵扣；
  4. 页面**直接展示重验后金额** + 金额变化提示（无需二次确认）；
  5. 收银台弹窗退役（含组合支付前台入口）。

- **成功指标**：
  - 页面显示金额 == 实际扣款金额（同源率 100%；不一致时 409 `quote_changed` 而非静默扣款）；
  - preflight 页面加载**零写库**（0 Order/Order 行/事件/会话写入）；
  - `PaymentCheckoutModal` 全仓引用 0；`storefront-test` 全绿；
  - 订单列表 date/payment/shipment 三列不再为空（dev 真机验收 `#R729701382`）；
  - 新增文案键在 5 语言（en/de/es/fr/pl）键集一致。

## 2. 用户故事 / 场景

- 作为**买家**，我希望在订单列表/详情点 Pay 就回到支付页，而不是弹出收银台弹窗，以便一屏看清金额与明细。
- 作为**买家**，我希望补付时系统告诉我「金额变了、为什么变」（商品失效/价格变化/优惠调整），而不是静默按新金额扣款。
- 作为**买家**，我希望失效商品不会让我整单无法支付——只支付仍然有效的商品金额。
- 作为**商家**，我希望失效商品不会被扣款、其库存占用被释放，且优惠只在仍满足时生效（不产生超收/多扣）。

场景：
1. **正常**：订单提交 2 天内补付，价格未变、商品有效 → 直接支付（金额与提交时一致）；
2. **价格变化**：目录价上涨 → 页面直接显示新金额 + 「订单金额已更新：$X → $Y（商品价格变化）」→ 点 Pay 按新金额扣款；
3. **失效行**：某商品已下架 → 页面提示「该商品已失效，不计入本次支付」→ 剔除后按剩余商品金额支付（库存占用释放）；
4. **优惠不再满足**：券为「满 3 件 8 折」，剔除后只剩 2 件 → 提示「优惠不再满足当前商品，已移除」→ 金额随之上升并展示；
5. **抵扣再平衡**：礼品卡/店铺余额已应用，剔除后总额下降 → 抵扣上限重新按新应付封顶（不多扣余额，也不丢抵扣）；
6. **配送不可达**：所选配送方式被停用 / 地址不在 zone 内 → 阻断 + [更换配送方式]/[修改地址]（复用既有 PATCH），Pay 禁用；
7. **全部失效**：整单商品均失效 → `no_payable_items` 硬阻断 + 引导；
8. **窗口边界**：报价窗口内 → 锁价（不重定价）；窗口过期/从未签发（历史单）→ 全量重验并签发新窗口；
9. **竞态**：页面停留期间价格又变 → 点 Pay 返回 409 `quote_changed`（带 `changes[]`）→ 页面刷新展示新金额（仍无二次确认动作）；
10. **绕过前台**：直接用 API 调 `orders/:id/transactions` → 同样被同源重验拦截。

## 3. 功能需求（FR）

- **FR-001 报价窗口签发**：`Carts::Submit` 建单成功后签发 `checkout_expires_at = now + OrderCheckout::Policies.quote_window`（新流程订单从此进入 quote 门）。
- **FR-002 门扩面**：`Transactions::Start#quote_gate_active?` 改为 `standard_flow? && !completed?`（无窗口=陈旧 ⇒ 全量重验；窗口内=锁价）。
  **实施收敛（2026-09-19）**：`PaymentSessions::Start#gate_active?` **保持原窗口语义不变**作为防御层——重验的**唯一权威**在 `Transactions::Start → OrderCheckout::Revalidate`，避免对直连 payment_sessions 的旧客户端改变契约（实测会误拦无地址的历史/测试订单）。
  又：报告中的 `checkout_not_ready` 阻断仅在「曾签发报价窗口」的订单上强制（无窗口的历史/异常订单保留旧行为，但仍做商品/金额/优惠/抵扣/配送可达重验）。
- **FR-003 重验服务**：新增 `PallasTrade::OrderCheckout::Revalidate.call(order:, dry_run: true)`，产出结构化报告 `{payable, blockers[], changes[], invalid_items[], quote{}, amount_due_before/after, total_before/after, display_*}`；dry-run 在 `order.with_lock` + 事务内执行并 `Rollback`（零副作用）。
- **FR-004 失效行判定（与购物车同源）**：失效原因枚举 `archived|deleted|discontinued|out_of_stock|channel_excluded`；判定谓词抽取为共享模块（购物车 `CartLegacy::RemoveOutOfStockItems` 与订单重验共用一份实现）。
- **FR-005 剔除写路径**：复用 `LineItems::Destroy`（不新增删除逻辑）→ 逐行释放库存预留（`StockReservations::Release` 增加 `line_item:` 过滤，`reason: 'line_item_unavailable'`）→ 审计 `order.publish_event('order.items_removed', …)` + `warnings` 复用 `line_item_removed` 结构。
- **FR-006 优惠复核**：对已挂订单的促销逐条 `Promotion#eligible?(order)` 复核；不再满足 → 走 `PromotionHandler::Coupon#remove`（自动释放核销 + 移除调整行），并计入 `changes[]`（`kind: promotion_changed`）。
- **FR-007 抵扣再平衡**：礼品卡 / 店铺余额上限 = 新应付（复用 `GiftCards::Apply` / `Checkout::AddStoreCredit` 的 `min(意图, outstanding)` 口径），变化计入 `changes[]`（`kind: credit_changed`）。
- **FR-008 重定价**：窗口失效/缺失 → `update_line_item_prices!`（当前目录/价目表价）；窗口内 → 保持锁价（不重定价）。
- **FR-009 只读预检端点**：`GET /api/v3/store/orders/:order_id/payment_preflight`（授权复用 `OrderResolvable`），返回 FR-003 报告；**零副作用**。
- **FR-010 写路径接线**：`Transactions::Start` 步骤 ① 由 `quote_consent` 扩为 `reconcile`（Revalidate 写路径 `dry_run: false` + 金额/版本比对），`quote_changed` 的 `latest` 附 `changes[]`；通过后沿用既有 ②③④⑤（交易幂等/Snapshot/库存门/会话）。
- **FR-011 支付页提示 UI**：`OrderPaymentContent`（or_ 页）消费 preflight，**直接回显重验后金额**（无二次确认动作），并在摘要下方新起一行提示块：金额变化（旧→新）+ 失效商品清单 + 优惠/抵扣调整原因；硬阻断时禁用 Pay 并给出定向动作。
- **FR-012 弹窗退役与入口**：删除 `PaymentCheckoutModal` 及其组合支付 UI；`OrderPayButton`、`OrderList` actions 列一律**跳转**订单支付页；`OrderCombinedPay` 多选合并支付 UI 下线（后端 `payment_combinations` API/SDK/jobs 保留）。
- **FR-013 状态投影修复**：`Carts::Submit` 提交后显式写 `payment_state`/`shipment_state`（不再只在 `completed?` 时）；读侧对存量行给出等效派生；前台可支付判定改金额权威 `amount_due > 0 && !is_child && !completed`；列表 Date 列回落到 `completed_at ?? submitted_at`。
- **FR-014 存量回填**：一次性脚本/任务只回填**近 7 天** pending 单的状态投影列（不迁移报价窗口）。
- **FR-015 契约与客户端**：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/` 增 preflight schema 与 `quote_changed.latest.changes[]`；SDK 增 `orders.paymentPreflight.get`；BFF 增 `GET /api/checkout/preflight`（客户端刷新用）。
- **FR-016 i18n**：新增文案键在 5 语言（en/de/es/fr/pl）键集一致，`pnpm check:locales` 通过。

## 4. 非功能需求（NFR）

- **零副作用**：preflight 只读（无 Order/行/事件/会话写入；dry-run 回滚）；页面加载绝不改单。
- **同源**：金额与判定只有一份实现（`Revalidate`），读端点与写路径共用；不允许出现第二套「失效判定/优惠复核」。
- **幂等**：支付仍由 `operation_key` / 交易幂等保证；剔除与抵扣再平衡在重入时保持终态一致（不重复释放、不重复扣抵扣）。
- **性能**：preflight 查询数不随订单行数线性膨胀（预加载 variant/product/stock_items/rates）。
- **兼容**：legacy 订单 / completed 订单 / 组合支付后端行为不变；`cart_`（UnifiedCheckout）分支零改动。
- **权限**：preflight 与写路径同权限（订单 token / JWT，`OrderResolvable`），不新增暴露面。
- **审计**：剔除/优惠移除/抵扣调整均可追溯（事件 + warnings + 交易快照）。

## 5. 验收标准（AC，与测试一一映射）

> **覆盖状态（2026-09-19 实施后核对，`harness prd verify`）**：AC-001/002/003/006/007/008/009/010/012 已有自动化测试覆盖（`revalidate_spec.rb` / `transactions/start_spec.rb` / `start_inventory_spec.rb` / `OrderPaymentContent.test.tsx` / `OrderPayButton.test.tsx`）。
> **四项不由自动化测试覆盖，按下列方式验收（显式记录，不伪造测试）**：
> - **AC-004（优惠复核）/ AC-005（抵扣再平衡）**：由 **dev 真机验收 + 代码评审**覆盖（用「失效商品 + 券 + 礼品卡」组合单实测券被移除、抵扣按新应付封顶）；后续切片补自动化。
> - **AC-011（列表三列 + 补付入口）**：由 **dev 真机验收**覆盖（订单 `#R729701382` 列表三列有值 + actions 出现 Pay）。
> - **AC-013（契约一致）**：由 `typelizer:generate` + `api:docs:schemas`（幂等无漂移）+ `harness generated:check` 覆盖。
> - **AC-014（5 语言键集）**：由 `pnpm check:locales`（All locale files are in sync）覆盖。

| AC | ← FR | 判定条件 | 测试 |
|---|---|---|---|
| AC-001 | FR-003/009 | preflight 零副作用：连续调用后 Order 金额列/行数/事件/会话计数不变 | `spec/services/pallastrade/order_checkout/revalidate_spec.rb` |
| AC-002 | FR-010 | 页面显示金额 == 写路径扣款金额（同源）；不一致 → 409 `quote_changed` 且 `latest.changes[]` 非空 | `spec/services/pallastrade/transactions/start_revalidate_spec.rb` |
| AC-003 | FR-004/005 | 失效行被剔除：行不存在、其预留已释放（`state=released`）、`warnings` 含 `line_item_removed` | 同上（含 reserve 断言） |
| AC-004 | FR-006 | 券不再满足 → 调整行与核销被移除（`PromotionRedemption` 释放）；仍满足 → 保留 | `revalidate_spec.rb`（coupon 分支） |
| AC-005 | FR-007 | 抵扣按新应付款封顶：总额下降后 `amount_due` 不为负、抵扣不超扣 | `revalidate_spec.rb`（credit 分支） |
| AC-006 | FR-004/005 | 全部失效 → `no_payable_items`，不建会话 | `revalidate_spec.rb` + request spec |
| AC-007 | FR-008/002 | 窗口内锁价（重定价不执行）；窗口过期/缺失（历史单）→ 重定价 + 签发新窗口 | `revalidate_spec.rb` |
| AC-008 | FR-011 | or_ 页：金额变化时直接显示新金额 + 提示块可见；无变化时不渲染提示 | `OrderPaymentContent.test.tsx` |
| AC-009 | FR-011 | 硬阻断（配送不可达/全失效）→ Pay 禁用 + 原因可见 | 同上 |
| AC-010 | FR-012 | `PaymentCheckoutModal` 全仓 0 引用；列表/详情 Pay 跳订单支付页 URL | `OrderPayButton.test.tsx` / `OrderList` 页测试 + 全仓 grep |
| AC-011 | FR-013 | 列表三列有值 + actions 有 Pay（新流程 pending 单） | `OrderList` 页测试 + dev 真机 |
| AC-012 | FR-010 | 绕过前台直调 `transactions.create` 同样被重验拦截 | request spec |
| AC-013 | FR-015 | `store.yaml` / SDK 类型与实现一致（`generated:check` 通过） | `harness generated:check` |
| AC-014 | FR-016 | 5 语言键集一致 | `pnpm check:locales` |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | revalidate / preflight / line_item / payment_session / checkout | 仅类型声明（`app/javascript/types/serializers/*`）与 build 产物，**无业务实现** | ❌ 需新建（Core 层） |
| Core | `pallastrade_gems/pallastrade_core/app/` | order_checkout / transactions / stock_reservations / promotions / line_items | `order_checkout/{recalculate,refresh,readiness,expiration,policies,view,snapshot}.rb`、`transactions/{start,reserve_inventory}.rb`、`stock_reservations/release.rb`、`promotion_handler/coupon.rb`、`line_items/destroy.rb`、`cart_legacy/{recalculate,remove_out_of_stock_items}.rb`、`order_updater.rb`、`carts/submit.rb` | ⚠️ 部分（重验/剔除/复核的能力**零件齐全但无编排**）→ 新增 `OrderCheckout::Revalidate` 编排，其余全部复用 |
| API | `pallastrade_gems/pallastrade_api/app/` | orders / checkout / payment_sessions / transactions | `store/orders/{checkout_controller,payment_sessions_controller,transactions_controller}.rb`、`OrderResolvable` | ⚠️ 部分（无 preflight 端点）→ 新增 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | line_item_destroy_service / remove_out_of_stock | `admin/line_items_controller.rb`（订单行删除走 `PallasTrade.line_item_destroy_service`） | ✅ 已有（作为订单行删除的既有权威被复用，不新增后台能力） |
| Storefront | `storefront/src/` | OrderPaymentContent / PaymentCheckoutModal / OrderList / OrderPayButton | `(checkout)/checkout/[id]/page.tsx`（`cart_`→UnifiedCheckout / `or_`→OrderPaymentContent 同路由分流）、`components/checkout/OrderPaymentContent.tsx`、`components/checkout/PaymentCheckoutModal.tsx`、`components/account/{OrderList,OrderPayButton,OrderCombinedPay,OrderDetail}.tsx`、`lib/data/order-payment.ts`、`messages/*.json`（en/de/es/fr/pl） | ⚠️ 部分（页与组件在，preflight 未接；弹窗待退役） |
| Platform | `platform/packages/` | orders.transactions / paymentSessions | `sdk/src/store-client.ts`（`orders.transactions.create` L815+、`orders.paymentSessions` L829+）、`sdk/src/types/index.ts` | ⚠️ 部分（缺 preflight 方法/类型）→ 新增 |

**结论**：
- **已有能力（复用，不重写）**：金额重算（`OrderUpdater`/`Recalculate`/`Refresh`）、报价窗口（`Policies`/`Expiration`）、就绪度（`Readiness`）、库存预留与释放（`ReserveInventory`/`StockReservations::Release`）、订单行删除（`LineItems::Destroy`）、优惠应用/移除与核销（`PromotionHandler::Coupon`、`Promotions::Redemption::*`）、失效判定谓词（`CartLegacy::RemoveOutOfStockItems`）、支付会话（`PaymentSessions::Start`）、支付入口可用性（`Payments::Availability::Resolver`）。
- **需新建**：`OrderCheckout::Revalidate`（编排 + 报告）、preflight 端点 + serializer、SDK/BFF、or_ 页提示 UI、（微改）`StockReservations::Release#line_item`、两处门扩面、`Carts::Submit` 签窗与投影。
- **防重复判定**：不新建第二个「订单行删除」「失效判定」「优惠重算」「金额重算」实现；一切落到既有权威服务。

## 7. 技术影响

- 后端（Core）：`order_checkout/revalidate.rb`（新）、`transactions/start.rb`、`payment_sessions/start.rb`、`carts/submit.rb`、`stock_reservations/release.rb`、`catalog/line_item_availability.rb`（抽共享谓词，新）、`cart_legacy/remove_out_of_stock_items.rb`（改用共享谓词）、`order_updater.rb`（提交后投影，最小改动）。
- 后端（API）：`orders/payment_preflight_controller.rb`（新）+ serializer + `config/routes.rb`。
- 契约：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/`（typedoc）。
- 前端：`(checkout)/checkout/[id]/page.tsx`（透传 preflight）、`OrderPaymentContent.tsx`、`api/checkout/preflight/route.ts`（新）、`lib/data/order-payment.ts`、`messages/*.json`×5、`components/account/{OrderList,OrderPayButton,OrderCombinedPay(删),OrderDetail}.tsx`、删除 `PaymentCheckoutModal.tsx` + 其测试。
- 数据库：**无 schema 变更**（FR-014 仅回填既有列）。
- 影响面：`harness affected` 待实施时执行并回填。

## 8. 测试计划

- 新增测试：
  - `backend/spec/services/pallastrade/order_checkout/revalidate_spec.rb`（AC-001/003/004/005/006/007）
  - `backend/spec/services/pallastrade/transactions/start_revalidate_spec.rb`（AC-002/012）
  - `backend/spec/requests/pallastrade/api/v3/store/orders/payment_preflight_spec.rb`（AC-001/006/009 端点契约）
  - `storefront/src/components/checkout/__tests__/OrderPaymentContent.preflight.test.tsx`（AC-008/009）
- 更新测试：
  - `storefront/src/components/account/__tests__/OrderPayButton.test.tsx`（改为跳转断言，AC-010）
  - `storefront/src/components/account/__tests__/OrderCombinedPay.test.tsx`（随组件下线删除/改写）
  - 删除 `storefront/src/components/checkout/__tests__/PaymentCheckoutModal.test.tsx`
  - `harness.config.mjs` 中引用被删测试的两个 verifier 条目同步更新。
- 新增 verifier：`order-repay-rspec`（已注册于 `harness.config.mjs`：`order_checkout/revalidate_spec.rb` + `order_checkout` + `transactions` 全域）。

### 实施落点（2026-09-19 实际落地）

| 层 | 文件 |
|---|---|
| Core 新服务 | `catalog/line_item_availability.rb`（共享判废谓词）、`promotions/remove_application.rb`（摘除促销唯一原语）、`order_checkout/revalidate.rb`（重验编排 + 报告） |
| Core 改 | `transactions/start.rb`（reconcile 接线 / expected_amount_due / 门扩面 / `quote_changed.latest.changes[]`）、`stock_reservations/release.rb`（`line_item:` 过滤）、`cart_legacy/remove_out_of_stock_items.rb`（改用共享谓词）、`promotion_handler/coupon.rb`（委托 RemoveApplication）、`carts/submit.rb`（签窗 + 状态投影）、`order.rb`（读侧状态派生） |
| API | `orders/payment_preflight_controller.rb` + `store/orders/payment_preflight_serializer.rb` + `routes.rb`；`orders/transactions_controller.rb` 接受 `expected_amount_due` |
| 契约 | `backend/public/api-docs/store.yaml`（+`StoreOrdersPaymentPreflight` schema，typelizer/api:docs:schemas 生成）+ `platform/docs/api-reference/` + `backend|platform/packages/sdk/src/types/generated/` |
| SDK | `store-client.ts`（`orders.paymentPreflight.get`）、`types/index.ts`（类型导出 + `expected_amount_due`） |
| Storefront | `lib/data/order-payment.ts#getOrderPaymentPreflight`、`api/checkout/preflight/route.ts`、`(checkout)/checkout/[id]/page.tsx`（透传 preflight）、`OrderPaymentContent.tsx`（提示块 + 金额回显 + `expectedAmountDue`）、`lib/account/order-payable.ts`、`OrderPayButton.tsx`（跳转）、`OrderList.tsx`（Pay 列 + 日期回落）、`account/orders/page.tsx`（移除多选合并）、删除 `PaymentCheckoutModal.tsx` / `OrderCombinedPay.tsx` 及其测试、`messages/{en,de,es,fr,pl}.json` |
- 覆盖映射：见 §5 表（每 AC 至少一条测试）。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（preflight + 409 changes）
- [x] Skill 文档：`pallastrade-checkout`（补付重验章节）、`pallastrade-storefront`（弹窗退役 + 提示 UI + 入口）
- [x] README / Agent 文件：`AGENTS.md §6` 增 `order-repay-rspec` 行；`docs/prd/README.md` 索引
- [x] 场景库：`harness/scenarios/scenarios.json` 增 GS-197
- [x] 本 PRD 状态更新（approved → implementing → done）+ README 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-19 | 0.1 | 初稿（根因 A/B/C/D + FR-001..016 + AC-001..014 + 6 层搜索 + 测试计划） | AI |
| 2026-09-19 | 1.0 | 用户两轮拍板（跳订单支付页并退役弹窗 / 不做二次确认但提示金额变化 / 失效只付有效部分并复核优惠 / 存量按建议）+ 用户「实施」→ 状态 → approved | AI |
| 2026-09-19 | 1.1 | 实施：Revalidate/RemoveApplication/LineItemAvailability 新服务 + Start 接线（expected_amount_due / 门扩面）+ Submit 签窗与状态投影 + preflight 端点与契约/SDK/BFF + 支付页提示（5 语言）+ 弹窗与合并支付 UI 退役；`order-repay-rspec` 注册；门扩面收敛为 Transactions::Start 侧（防御层保持窗口语义）；状态 → implementing | AI |
| 2026-09-20 | 1.2 | CI 红光复盘与修复（首轮推送实际抓到本 PRD 的三类回归）：① **门扩面的请求面回归**（`transactions` / `d7` 请求规格 6 例）：门扩面后「无窗口的历史标准流待支付单」会被重定价 → 未声明 `expected_amount_due` 的客户端得 409 `quote_changed`；夹具改为**签发未过期报价窗口**（= `Carts::Submit` 的生产行为，窗口内锁价 → 重验零变化），既有 201/409/422 契约与意图全部保持；② **验证器覆盖面缺口**：`order-repay-rspec` 此前只跑 services 面，请求面（orders 通道 + 入口门禁）不在门禁内 → 本次把 3 个请求规格纳入同一验证器（GS-197 增对应 mustDo/mustNotDo），AGENTS.md §6 同步；③ **前台与 SDK 的 biome 红线**：`order-payment.ts` / `preflight/route.ts` / `OrderPaymentContent.tsx` / `order-payable.ts` / `store-client.ts` 格式 + 未用导入 + 副作用依赖表（`TurnstileWidget` 多余依赖 `retryKey`、`CategoryNav` 外点关闭 effect 引用未记忆化 `close`）全部修复（storefront Skill 记第四次/第五次红灯教训）；状态 → done | AI |
