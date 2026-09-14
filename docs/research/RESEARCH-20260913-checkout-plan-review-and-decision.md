# RESEARCH-20260913 · 商城前台 Checkout 方案评审与决策（维持单页一步）

| 元数据 | 值 |
|---|---|
| 日期 | 2026-09-13 |
| 类型 | 方案评审 + 决策落档（docs） |
| 任务 | `TASK-20260913144749-671fc348` · Gate `GATE-2026-09-13T14-48-20`（docs） |
| 评审对象 | `豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md`（55 节；git-ignored 本地源规格） |
| REQ | `harness/requirements/REQ-20260913-checkout-plan-review-and-decision.md` |
| 核心决策 | **维持单页一步支付（方案 A）**，不采纳源规格 §19/§20 的「提交中转 → `or_` 页 Review & Pay」 |
| 证据口径 | 全部论断以 `dev@ecd71c29` 工作区代码核验为准（文件级证据见 §13） |

---

## 1. 背景与方法

**背景**：源规格提出"在现有架构上完成最后一次收敛"，主张把用户可见的 Checkout 拆为两阶段（`cart_` 编辑 → `or_` Review & Pay），并配套 CheckoutView 契约扩展、统一 Mutation 模型、legacy 六端点迁移矩阵等。本文档记录对该规格的逐项核验结果、用户决策与决策后的实施方案。

**方法**：

1. 源规格逐节通读（55 节 / 2197 行）；
2. 六层代码核验（`backend/app` → core → api → admin → `storefront/src` → `platform/packages`），逐条论断取证；
3. 与既有工件交叉：`P0任务.md`（P0-7 原文）、`harness/reviews/REVIEW-20260908-promotions-module-audit.md`、`docs/research/RESEARCH-20260913-*`、项目记忆（promotion 批次进度 / 标准流履约缺口）；
4. 对每条论断给出准确性分级：**✅ 准确 / ⚠️ 部分准确或已过时 / ❌ 与现状冲突或缺失**。

---

## 2. 总体判断

> 方向正确、与仓库既有演进路线（`CHK-P1-*` / `TXN-P2-*` / `P3` 库存 / `P0-7`）高度一致，属于"收尾收敛方案"而非新架构设计；但存在 **4 处已过时论断、3 个关键缺口、1 个需要用户拍板的产品决策**。

其五条核心冻结规则（源规格 §55）与仓库现有实现**不冲突**；冲突仅存在于 §19/§20 的交互形态与 §2 的流程叙述。

---

## 3. 逐项核验（准确性分级）

### 3.1 ✅ 论断准确（有代码证据）

| # | 论断 | 代码证据 | 结论 |
|---|---|---|---|
| 1 | Canonical 链 `Start→Freeze→Reserve→Pay→Commit→Finalize`，**Reserve 失败不得建 PaymentSession** | `transactions/start.rb` ③「INV-P3-2：Reserve before PaymentSession」，失败返回 `INSUFFICIENT_STOCK/INVENTORY_CHANGED` 且不创建会话 | ✅ 已实现 |
| 2 | 后端已有 expected version / 409 机制；**storefront 未带回 expected 字段** | 后端 `CHK-P1-5`（`checkout_version_conflict`）+ `TXN-P2-2`（`quote_changed`，含 `order_id`）；前端 `api/checkout/start/route.ts` 调 `transactions.create` 仅传 `payment_method_id/external_data`，全 storefront 无 `expected_*` | ✅ 准确，闭环未合上 |
| 3 | §7 Billing「`use_shipping=true` 前端提交、后端未处理 → `Order.bill_address` 可能为空」 | `Carts::Update` 只处理显式 `billing_address`，**不处理 `use_shipping`**；`Carts::Submit#build_order!` 仅 `if cart.billing_address.present?` 才复制，无兜底；`UnifiedCheckout#handlePayNow` 勾选时确实只发 `{ use_shipping: true }` | ✅ 缺陷真实 |
| 4 | §13 Coupon 坏链 `cart_ → /carts/:id/discount_codes → find_cart! → Legacy Order 同表` | `Carts::DiscountCodesController` 用 legacy `find_cart!`（`current_store.carts` = `PallasTrade::Order` 关联）；`items_controller` 才用 `find_shopping_cart!`；storefront 优惠码 BFF 将 `cart_` id 原样透传至该端点 | ✅ 方向正确（另有更深隐患，见 §5.2） |
| 5 | §16 TOTAL SAVINGS 三合一（Promotion + GiftCard + StoreCredit） | `UnifiedCheckout.tsx` L111-115：`savings = discount_total + gift_card_total + store_credit_total` | ✅ 准确 |
| 6 | §18 `parseFloat(display_*)` 违反 Money 契约 | `OrderPaymentContent.tsx` L112 `parseFloat(read.display_delivery_total) > 0`（display 含货币符号 → `NaN` → Shipping/Tax 行不渲染） | ✅ 准确 |
| 7 | §17 CheckoutView 应成为唯一数据源；现有缺 `credits / available_payment_methods / capabilities / billing_mode` | 现状已有 `version(checkout_version) / price_version / expires_at / ready / missing_requirements / discounts / taxes / items / fulfillments / ship&bill_address`；上述四项**确实缺失** | ✅ 增量清单可执行 |
| 8 | §28 前台选得上、`PaymentSessions::Start` 拒绝 | `Cart#payment_methods` = `store.payment_methods.active.available_on_front_end`（**无** `available_for_order?` 过滤）；`Order#payment_methods` 有过滤但**被 memoize**；Start 走**实时查询** + `available_for_order?` → 三处口径不一致 | ✅ 有依据 |
| 9 | §45 六个 legacy nested endpoint | `routes.rb` 全部存在：`discount_codes / gift_cards / fulfillments / payments / payment_sessions / store_credits`（共享 `carts/*` legacy resolver） | ✅ 与实现一致 |
| 10 | §46 Legacy usage metric / 不删除只观测 | 与 `P0任务.md` §十（P0-7）逐字对齐（deprecated 标注 + 结构化 usage log + metric + "DO NOT ADD NEW PAYMENT FEATURES TO LEGACY"） | ✅ 引用准确（措辞差异见 §5.5） |
| 11 | §19 提交管线 `validate cart → Carts::Submit → Promotion/Shipping/Tax → OrderUpdater → CheckoutView` | `Carts::Submit#build_order!`：快照地址/行项目 → `update_line_item_prices! → create_tax_charge! → update_with_updater! → build_fulfillment!` | ✅ 与实现一致 |
| 12 | §9 多履约分组展示 | `CheckoutView.fulfillments[]` + Order shipments/rates 已具备；`OrderPaymentContent` 已用 fulfillments 的 `delivery_rates` 做物流选择（CHK-P1-4B） | ✅ 已具备 |

### 3.2 ⚠️ 部分准确 / 已过时

| # | 论断 | 实际情况 |
|---|---|---|
| 13 | §14「新的 CheckoutView 只读取 order-level adjustments，行级/免邮不展示」 | **已过时**：2026-09-09 批次2（`911c5bf`）已统一为 `Promotions::Projection::DiscountProjection`（order/line/shipment 三层、eligible-only、`Σ==discount_total`，并有 `projection_parity_spec`）。历史背景见 `REVIEW-20260908` 发现 D。**实施时勿重复开发** |
| 14 | §2「三套互相漂移：UnifiedCheckout / OrderPaymentContent / Legacy CheckoutPageContent」 | **部分过时**：Legacy 一页式已于 `CHK-P1-4C4` 退役（页面 redirect 回首页）；现状为**两套**且共享 `CheckoutContext / CheckoutSummary / CardPaymentForm` |
| 15 | §41 错误码 `CHECKOUT_CHANGED` | 实际码为 `quote_changed / checkout_version_conflict / checkout_not_ready / checkout_already_updated`（`error_handler.rb`）→ 契约命名需以现网码为准 |
| 16 | §13「移除：`DELETE /orders/:id/checkout/promotions/:promotion`」 | 与 §43 自相矛盾（§43 将要建设该 DELETE）；现状不存在该路由 → **表述待澄清** |

### 3.3 ❌ 与现状冲突 / 缺失（须决策或新增）

| # | 事项 | 说明 |
|---|---|---|
| 17 | §19/§20 两段式中转 | 与现状单页一步支付冲突 → 已由用户决策（§6） |
| 18 | §13 新链 `POST /orders/:id/checkout/promotions` | 现状不存在；`OrderCheckout::ApplyPromotion` 也未实现（§43 的其余子资源同样未建） |
| 19 | §5/§47 占位功能（营销订阅 / SMS / Save Info / Add-ons） | `SaveInfoSection.tsx` 自注 "UI placeholder only"；建议按 §47 隐藏，需单独排期 |

---

## 4. 已过时项（实施时勿重复开发）

1. **§14 discount projection 统一** —— 批次2 `911c5bf` 已完成（`DiscountProjection` + 契约 spec）；仅需核对前端展示是否消费到位。
2. **§2 "消灭三套壳"** —— Legacy 已退役；剩余为 `UnifiedCheckout`（`cart_`）与 `OrderPaymentContent`（`or_`）两套，可做组件级收敛，但不是"消灭漂移"级工程。
3. **§41 错误码命名** —— 以现网码为准，避免前端 mapping 落空。
4. **§13 的 DELETE 矛盾** —— 澄清前不要按字面实施。

---

## 5. 关键缺口（源规格未回答，评审补充）

### 5.1 `cart_` 阶段的优惠码/礼品卡替代端点未设计

§13 只给出 `or_` 阶段的 `POST /orders/:id/checkout/promotions`；而**主购物路径在 `cart_`**（`UnifiedCheckout`），其优惠码/礼品卡目前正是打在 legacy 端点（§3.1 #4）。若按 §45"新 Checkout 明确禁止调用 legacy"，必须为 `pallastrade_carts` 设计等价端点（或把优惠模块整体后移到 `or_` 阶段——影响 UX 与 §15 的分区展示）。另：BFF 现状只支持 `discount | gift_card` 两种 kind，**store credit 无前端入口**，与 §15 目标有差距。

### 5.2 `PrefixedId` 前缀解析不安全（比"坏链"更深一层）

`PrefixedId.decode_prefixed_id` **只拆前缀、只 decode，不校验前缀归属**；`find_by_prefix_id!` 直接 `find(decoded)`。因此 `cart_` id 打到 legacy 端点不只是"404"，而是**按解码后的整数 id 到 Order 表找人** —— 存在命中无关 Order 的串单风险（带 token 鉴权可挡一部分，登录态下不一定）。建议列为 P0 安全加固项（`find_by_prefix_id!` 增加前缀校验，或 controller 显式选用 resolver）。

### 5.3 单页一步下的错误落点未分化（现状缺陷）

现 BFF `errorResponse(error, submitted?.id)` 恒附 `order_id`，而 `UnifiedCheckout` 是"有 `order_id` 就跳 `payment-result`"。因此 **`quote_changed` / 库存四码 / `INVENTORY_RECOVERY_REQUIRED` 都被打到 `payment-result` 的 pending 状态**（无分化 UI；库存类错误码前端全仓仅 BFF 透传、无消费）。其中 `INVENTORY_RECOVERY_REQUIRED`（已扣款、待恢复）落在通用 pending 页，存在诱导用户重复支付的风险，与 §33 的警告直接冲突。

### 5.4 无 AC/REQ/测试映射

§53 优先级与 §54 验收场景写得很好，但该文档不是 PRD（无 AC 编号、无 REQ 溯源、无"AC → 测试"映射）。按仓库 R8，落地前必须转 PRD。

### 5.5 P0-7 措辞差异（轻微）

`P0任务.md` §十原文限定"**DO NOT ADD NEW PAYMENT FEATURES TO LEGACY FLOW**"；源规格扩写为"不得为 Legacy 增加新能力"。方向上一致，引用时应还原原文范围。

---

## 6. 决策记录（2026-09-13，用户拍板）

**决策**：**方案 A —— 维持单页一步支付**。不引入 §19/§20 的「提交中转 → `or_` 页 Review & Pay」；`cart_` 页继续承担「填写 → 提交 → 交易启动 → 支付」全流程，`or_` 页维持**补付 / 恢复 / 邮件回流**定位。

**决策依据（评审建议）**：

1. 现状已上线且验证通过；两段式引入 +1 跳转 +1 点击，转化率影响未经验证；
2. `or_` 页当前展示能力**弱于** `cart_` 页（无折扣/礼卡/余额渲染）——两段式落地前必须先补齐，否则 Review 页信息不全；
3. Express / Buy Now / 邮件回流 / 合并支付 / 账户补付等旁路需要逐一适配，成本与风险集中在非主干；
4. 方案 A 与 §55 五条核心规则**不冲突**（逐条：CheckoutView 单一权威 ✅、Promotion 不重算 ✅、Pay=确认报价+启动交易 ✅（落点为 `cart_` 页）、Reserve-before-Pay ✅（后端不变）、P0-7 ✅）。

**被否决选项（保留复议条件）**：

| 选项 | 内容 | 否决理由 | 复议条件 |
|---|---|---|---|
| B 完整两段式 | 按源规格 §19/§20 原样改造 | 转化风险 + `or_` 展示缺口 + 旁路适配成本 | 若埋点显示单页模式错误恢复体验差，或产品明确要求"支付前显式 Review 页"，可复议 |
| C 混合 | `or_` 升级为完整 Review & Pay 页承接全部错误/恢复，主路径不强制二次点击 | 与 A 实质重叠，其中"错误落点分化"已纳入 A 的 P0 清单 | — |

**决策保持的开放项**：未来若做 A/B，可先补埋点（`begin_checkout / submit_order / add_payment_info / purchase`）再评估。

---

## 7. 决策后目标形态（A 版）

```text
/cart · Buy Now · CartDrawer「去结算」· 邮件回流(?token=)
   ↓
/checkout/cart_xxx（UnifiedCheckout：单页一步）
   ├─ 填写：Contact / 地址 / 物流 / 优惠（Coupon + Gift Card）
   ├─ 报价：cart 态 CheckoutView
   └─ Pay Now（一次点击）
        POST /api/checkout/start
          ├─ carts.update（email / 地址 / 物流 / use_shipping）
          ├─ carts.submit（→ or_ 订单 + successor cart）
          └─ transactions.create（Freeze → Reserve → PaymentSession）
        → Stripe 内联确认 → PATCH complete
   ↓
/payment-result/or_xxx（结果页：success / failed / canceled / pending）
   ↳ 失败 / 中断 / 补付 → /checkout/or_xxx（or_ 页：恢复与补付落点）
```

后端 canonical 链（与页面形态无关，保持冻结）：`Start → Freeze → Reserve → Payment → Payment Confirmed → Commit → Finalize → Carts::Complete`。

---

## 8. 源规格文档修订清单（已执行）

| 位置 | 修订 | 标记 |
|---|---|---|
| 文首 | 新增「决策备忘（2026-09-13）」块：未采纳项、A 版链路、受影响章节、指向本报告 | — |
| §2 | 「一个 Checkout，两阶段」→「单页一步」；修正"三套壳"表述（Legacy 已退役，现存两套共享上下文） | `〔A-20260913〕` |
| §19 | Review 中转标注**未采纳**；保留服务端提交链（即 BFF 内部顺序）；给出页内 Review 折叠区可选增强 | `〔A-20260913：不采用中转〕` |
| §20 | 降级为 `or_` 页（补付/恢复）目标形态；标注现状展示缺口 | `〔A-20260913：降级为 or_ 页目标形态〕` |
| §21 | 补充落点说明：expected versions 由 `cart_` 页 Pay Now 携带；409 留在当前页做差异确认 | `〔A-20260913〕` |
| §40 | 追加"页内状态映射"小节（DRAFT→COMPLETED 对应 UnifiedCheckout 阶段 + 结果页） | `〔A-20260913：单页一步映射〕` |
| §53 | P0 增加「错误落点分流」；标注 `discount projection` 已完成（勿重复）；P1 行改为 A 版口径 | `〔A-20260913〕` |
| §54 | 「Quote 变化」验收改为"留在当前页显示差异并要求重新确认" | `〔A-20260913〕` |

> 注：源规格位于 `豆包梳理业务需求/`（`.gitignore:36`），属本地资料，不入版本库；本次修订不产生代码/索引变更。

---

## 9. 实施方案（A 版）

### 9.1 P0（Correctness / 体验安全）

| # | 事项 | 要点 |
|---|---|---|
| P0-a | Money 契约 | 逻辑用 `raw` 字段，`display_*` 仅渲染；清理 `parseFloat(display_*)` 与合并 savings 口径 |
| P0-b | billing 缺陷 | `use_shipping` → `billing_mode`（`same_as_shipping` 服务端克隆 / `custom` 独立地址）；覆盖 `Carts::Update`、`Carts::Submit`、PATCH checkout、UI |
| P0-c | **错误落点分流**（新增） | 见 §9.2 |
| P0-d | 报价确认闭环 | `cart_` 页 Pay Now 携带 `expected_checkout_version / expected_price_version`；409 → 页内差异确认（不跳转） |
| P0-e | 优惠码断面 | 先决策 `cart_` 阶段端点方向；再建 canonical 端点 + legacy 观测 |
| P0-f | `PrefixedId` 前缀校验 | `find_by_prefix_id!` 增加前缀归属校验（防串单）—— **已完成 2026-09-14**：`decode_with_prefix` 保留前缀，`find_by_prefix_id(!)` 校验归属（外来前缀 → 404 / nil / 空集），`Order.find_by_param` 与 `Orders::FindComplete` 限自有 `or_`；规格 `backend/spec/models/pallastrade/prefixed_id_spec.rb`（AC-001..006，含前缀唯一性守护 pin `ps`）。PRD-20260914-other-prefixedid-ownership-validation |

### 9.2 错误落点分流规则（P0-c）

| 后端 code / 事实 | 现状行为（缺陷） | 目标行为 |
|---|---|---|
| `quote_changed` / `checkout_version_conflict` | 跳 `payment-result`（pending） | **留在 `cart_` 页**：刷新报价 + 显示逐步差异（Shipping / Promotion / Amount due）+ 要求重新点击；**绝不自动扣款** |
| `INSUFFICIENT_STOCK` / `INVENTORY_CHANGED` / `RESERVATION_EXPIRED` | 跳 `payment-result`（pending） | **留在 `cart_` 页**：显示"商品不可用/库存变化 + 请求量 vs 可用量" + CTA 回购物车；**禁止"支付失败"字样** |
| `INVENTORY_RECOVERY_REQUIRED` / `manual_review` | 跳 `payment-result`（pending，无差别文案） | 跳 `payment-result` 但用专属文案"**已收到付款，订单确认中；无需重复支付**"，**不得提供重试支付按钮** |
| 支付类失败（declined / expired / 3DS 失败） | `payment-result`（failed）→ 重试 | 保留；重试 = 同 Transaction 换卡（后端已支持串行 PaymentSession） |
| `transaction_not_payable` / `checkout_not_ready` | 跳 `payment-result` | 页内提示 + 引导（回订单详情 / 补全缺失项） |

> 实现要点：分流以 **code** 为准，而不是以 `order_id` 是否存在为准。

### 9.3 P1 / P2

| 优先级 | 事项 |
|---|---|
| P1 | CheckoutView 扩展（`credits / capabilities / available_payment_methods / billing_mode`）→ 前端统一消费；`available_payment_methods` 优先（§28 影响主路径） |
| P1 | 占位功能治理（§47：Add-ons / Save Info / Marketing / SMS） |
| P2 | legacy 六端点收敛 + usage metric（P0-7 流量阈值驱动）；`or_` 页展示小步补齐（折扣/礼卡/余额）；组件级 `CheckoutShell` 拆分（不改交互模型） |

---

## 10. 验收差异（§54 A 版）

| 场景 | 必须结果（A 版） |
|---|---|
| Quote 变化 | 409 → **留在当前页**显示新旧金额差异 → 用户重新确认；不自动支付 |
| Reserve 失败 | 不产生 PaymentSession；用户看到"商品不可用"，不是"支付失败" |
| 已扣款 + commit 异常 | "已收到付款，确认中"；**无重复支付入口** |
| 最后一件库存竞争 | 仅一个 Transaction 可付款（后端不变量，不变） |
| 多 shipment / fulfillment split | 一次付款、多履约、不新建支付交易（不变） |
| Express / Wallet | 必经 `Transaction → Reserve → Payment`（不变） |
| Legacy Checkout | 原行为保持 + usage metric（不变） |
| 重复点击 Pay | 不重复 Transaction / Payment（`operation_key` + 幂等，已有） |

---

## 11. 后续 PRD 拆分建议

| # | 类型 | 内容 | 前置 |
|---|---|---|---|
| PRD-1 | 修复 | 错误落点分流（§9.2）+ Money 契约（P0-a） | 无 |
| PRD-2 | 修复 | billing 缺陷（`use_shipping` → `billing_mode`） | 无 |
| PRD-3 | 优化 | 报价确认闭环（expected versions + 409 页内确认） | 无 |
| PRD-4 | 需求 | 优惠码断面（`cart_` 端点决策 + legacy 观测） | 用户确认端点方向 |
| 后续 | 优化 | CheckoutView 扩展（P1）、占位治理（P1）、legacy 收敛（P2） | PRD-1..4 之后 |

---

## 12. 未覆盖与待验证

1. **未做运行时验证**（本任务为文档评审）——建议 dev 实测两项以闭环代码级推断：
   - ① 对 `POST /api/v3/store/carts/cart_xxx/discount_codes` 实际返回码（验证 §5.1/§5.2）；→ **已闭环 2026-09-14**：修复前 dev 实测 403，修复后 422 `coupon_code_not_found` / 201（真实码）/ 200（DELETE），见 PRD-20260914-checkout-cart-discount-codes-canonical。
   - ② 走一单"勾选同配送地址"，检查 `order.bill_address` 是否为空（验证 §3.1 #3）。→ **已闭环**：dev 实测 `same_as_shipping` → 订单 `bill_address` = 配送地址副本；`custom` → 独立地址，见 PRD-20260913-checkout-billing-mode。
2. 未逐条复算源规格 §3/§4 功能项总表的每一项现状（抽样核验）。
3. 未评估 §3 推荐页面布局与现状 `UnifiedCheckout` 布局的逐项差异（属 UX 细节，随 PRD 做）。
4. 源规格 §13「移除 DELETE …」与 §43 的矛盾未裁决（登记为待澄清）。

---

## 13. 证据索引

| 证据 | 位置 |
|---|---|
| CheckoutView 投影与版本字段 | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/order_checkout/view.rb`；`.../pallastrade_api/app/serializers/pallastrade/api/v3/store/checkout/checkout_serializer.rb` |
| Reserve-before-PaymentSession | `.../services/pallastrade/transactions/start.rb`（③ 库存门） |
| quote/version 同意 | `.../services/pallastrade/transactions/start.rb`（`quote_changed_error` 含 `order_id`）；`.../services/pallastrade/payment_sessions/start.rb`（`CHK-P1-5`） |
| 单页一步支付链路 | `storefront/src/components/checkout/UnifiedCheckout.tsx`（`handlePayNow`）；`storefront/src/app/api/checkout/start/route.ts` |
| billing 缺陷 | `.../services/pallastrade/carts/update.rb`（无 `use_shipping`）；`.../carts/submit.rb`（`build_order!` 条件复制）；`UnifiedCheckout.tsx`（`use_shipping: true`） |
| 优惠码 legacy 链 | `.../pallastrade_api/app/controllers/pallastrade/api/v3/store/carts/discount_codes_controller.rb`（`find_cart!`）；`.../concerns/pallastrade/api/v3/cart_resolvable.rb`；`storefront/src/app/api/checkout/coupon/route.ts` |
| `PrefixedId` 前缀盲解码 | `.../models/concerns/pallastrade/prefixed_id.rb`（`decode_prefixed_id` / `find_by_prefix_id!`） |
| 错误码透传与落点 | `storefront/src/app/api/checkout/start/route.ts`（`errorResponse`）；`UnifiedCheckout.tsx`（有 `order_id` 即跳结果页）；`storefront/src/app/[country]/[locale]/(checkout)/payment-result/[id]/page.tsx`（pending/failed 判定、retry → `/checkout/or_`） |
| Money 契约违例 | `storefront/src/components/checkout/OrderPaymentContent.tsx` L112；`UnifiedCheckout.tsx` L111-115 |
| DiscountProjection 已统一（批次2） | `.../services/pallastrade/promotions/projection/discount_projection.rb`（`PRD-20260909-promotions-promo-batch2`）；`backend/spec/services/pallastrade/promotions/projection_parity_spec.rb`；历史发现 `harness/reviews/REVIEW-20260908-promotions-module-audit.md` §发现 D |
| 支付方式三口径 | `.../models/pallastrade/cart.rb`（`payment_methods` 无过滤）；`.../models/pallastrade/order.rb`（memoize + `available_for_order?`）；`.../services/pallastrade/payment_sessions/start.rb`（实时查询） |
| P0-7 原文 | `豆包梳理业务需求/P0任务.md` §十 |
| Legacy 一页式退役 | `storefront/.../checkout/[id]/page.tsx`（CHK-P1-4C4 注释） |
| 邮件回流 | `storefront/src/proxy.ts`（`?token=` 仅 `/checkout/`）；`.../mailers/pallastrade/abandoned_cart_mailer.rb`（`recovery_url`） |

---

## 14. 结论

- 源规格的**方向与不变量正确**（Canonical 链、CheckoutView 单一权威、报价确认、Legacy 观测），可作为后续 PRD 的设计输入；
- 实施前需剔除 4 项已过时叙述（§14/§2/§41/§13），补 3 个缺口（`cart_` 优惠端点、前缀校验、错误落点分流）；
- **已决策：方案 A（维持单页一步）**——相关修订已回写源规格文档；实施按 §11 拆分为 4 个 PRD。
