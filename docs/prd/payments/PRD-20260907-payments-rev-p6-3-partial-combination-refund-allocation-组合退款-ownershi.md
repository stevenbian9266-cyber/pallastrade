# PRD-20260907-payments-rev-p6-3-partial-combination-refund-allocation-组合退款-ownershi

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-07 |
| 来源 | 需求：REV-P6-3 Partial/Combination Refund Allocation（组合退款 ownership 冻结 + 分摊 authority 审计冻结） |
| 分类 | payments（自动判定，关键词：退款/refund） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-pricing`（分摊/税） |
| 关联 REQ | REQ-20260907-rev-p6-3-partial-combination-refund-allocation.md（实施时回填） |
| 关联 PRD | PRD-20260906-payments-rev-p6-1/...（REV-P6-1）、PRD-20260906-payments-rev-p6-2-...（REV-P6-2，done） |
| 需求类型 | 优化迭代（资金安全增量，feature gate） |

> 🔁 **查重回写**：`harness prd new` 自动查重通过。REV-P6-1（done）已交付 durable Refund + `PaymentSplit.refunded_amount` 唯一写点 + capacity；REV-P6-2（done）已交付 async Request/ExecuteJob。本 PRD = REV-P6-3（源 REV-P6 §58 + §26-29）。
> ⚠️ **编号**：REV-P6 与内部拆单域 P5/P6/P7 为两套编号。

---

## 0. 来源与范围界定

- **源规格**：`豆包梳理业务需求/P6 — Refund, Cancellation & Dispute Orchestration.md` REV-P6 §58（REV-P6-3）与 §26-29（Partial/Combination/Tax/Shipping/Promotion）。
- **本 PRD 范围**：
  1. 组合退款 ownership 冻结贯通：新 Refund 创建即冻结 `payment_split_id`/`target_order_id`（REV-P6-1 列已存在，本包把 Admin/Request 组合路径接入），`apply_success!` 投影不再依赖运行时 reimbursement 链推导（legacy fallback 保留）；
  2. 分摊 authority 审计冻结（只读审计 + 冻结结论，不新建 calculator）：`REFUND_AMOUNT_AUTHORITY` / `REFUND_TAX_ALLOCATION_POLICY` / `REFUND_SHIPPING_ALLOCATION_POLICY` / `REFUND_PROMOTION_ALLOCATION_POLICY`；
  3. 组合/部分退款并发与上限固化测试（AC-6008/6010/6011/6012）。
- **明确不做**：Recover/Sweeper（REV-P6-6）；Cancellation Orchestrator（REV-P6-4）；Return Inspection/Restock（REV-P6-5）；reimbursement 链 async 重做（REV-P6-5）；Dispute（P7）。
- **REV-P6-1/2 已交付并被本包复用**：Refund 状态机/capacity/ownership 列、`PaymentSplit.refunded_amount` 唯一写点（`Refund#update_order`，apply_success! 内）、`Refunds::Request`/`ExecuteJob`（async 主路径）、Stripe/Adyen/PayPal `fetch_refund_details`（Stripe）等。

---

## 1. 背景与目标

### 1.1 一句话需求原文

> 需求：REV-P6-3 Partial/Combination Refund Allocation（组合退款 ownership 冻结 + 分摊 authority 审计冻结）

### 1.2 背景（代码审计，2026-09-07）

组合支付（`PaymentCombination`：1 Payment，N 成员订单各 1 `PaymentSplit`）的部分退款存在两个未收敛点：

1. **ownership 仍走运行时推导**：`Refund#update_order` 组合分支用 `self.payment_split || reimbursement_target_order.payment_splits...` 推导目标 split——新 Refund 虽已在 REV-P6-1 增加 `payment_split_id`/`target_order_id` 列，但 Admin `refunds#create`（REV-P6-2 后 async）仍未在创建时冻结 split/order，退款打到哪个成员订单依赖 Reimbursement 链/顺序推导（RISK-REV-05）。
2. **分摊 authority 未冻结**：现有金额分摊 = `ReturnItem.refund_amount_calculator`（`DefaultRefundAmount`：按退回数量加权 line_item pre-tax + 订单级 eligible non-tax 调整按订单占比分摊）+ `ReimbursementTaxCalculator`（按 pre_tax/refund 比例分摊 additional/included tax）。Shipping 与 promotion（order 级调整）都被并入订单级 non-tax 调整按商品占比分摊。这些是 legacy 派生路径（RA/CR/Reimb 专用），与 REV-P6 正向资金的 canonical 组合退款（直接对 Payment/Split 退）**并存但无统一 authority 声明**——P6-0 Q14「shipping/tax/discount partial allocation 当前怎么计算」未正式冻结。
3. 并发上限（AC-6008/6010/6011/6012）逻辑已具备（capacity + split captured−refunded），但缺组合专用回归测试（两 split 并发退、组合总额不超）。

### 1.3 目标

1. 组合退款在创建时冻结 `payment_split`/`target_order`（可证明才填），`apply_success!` 组合投影直接命中冻结 split，兄弟 split 不变（AC-6011/6012）。
2. 正式冻结 4 项分摊 authority（基于审计结论，REUSE 现状 primitive；禁止 Controller/UI 临时计算），并文档化到 payments skill。
3. 补组合/部分退款并发与上限回归测试（AC-6008/6010/6011/6012 + P0-P5 baseline）。

### 1.4 成功指标

- 新组合 Refund 均带冻结 `payment_split_id`+`target_order_id`（可通过 API/serializer 观测）；legacy 链（RA/CR/Reimb）行为不变。
- 分摊 authority 冻结项写入 payments/pricing skill；无新 Calculator 代码。
- 组合并发 spec + backend-rspec 全量绿。

---

## 2. 用户故事 / 场景

- 作为 **Admin 运营**，我希望对组合支付的某个成员订单退款时明确指定目标 Order/Split，退款只影响该成员（兄弟单不变、可退额度按 split）。
- 作为 **系统（apply projection）**，我希望每笔组合 Refund 命中创建时冻结的 split，而不是每次运行时从 Reimbursement 链推导。
- 作为 **财务/审计**，我希望 shipping/tax/promotion 的部分退款分摊口径有唯一 authority 且可追溯。

**场景**
- N1 组合（Payment=100, SplitA=60, SplitB=40）对 A 退 20：Refund 冻结 SplitA/OrderA；成功后 SplitA.refunded=20、SplitB 不变；Journal -20。
- N2 单订单多次部分退款：各自独立 Refund/fact/journal（REV-P6-1 已支持，补回归）。
- B1 组合退款请求时 split 已退满（refunded==captured）→ 拒绝（容量=0）。
- B2 并发：SplitA 60/60、SplitB 40/40 同时各自退满 → 各自成立且总额不超 100。
- E1 组合 payment 上按全局额度退了 100 的一部分 → split 上限约束（captured−refunded）。

---

## 3. 功能需求（FR）

### 3.1 组合退款 Ownership 冻结（贯通 REV-P6-1 列）

- **FR-R63-101**：Admin `refunds#create`（组合支付场景）支持可选参数 `payment_split_id`/`target_order_id`（可解析 prefixed id）；提供时在 `Refunds::Request` 创建时冻结（`refund.payment_split=`/`target_order=`）。不提供时：若 payment 属组合且可证明唯一目标（split 由请求方语义决定）则保持现有路径；不可证明则不猜（NULL）。
- **FR-R63-102**：`Refund#update_order` 组合分支：**优先使用冻结的 `self.payment_split`/`self.target_order`**；仅当冻结缺失（legacy 退款）才走 `reimbursement_target_order` 推导 fallback（注释标明 legacy）。冻结命中时直接 `split.refunded_amount += amount`，不再按 order.payment_splits 重新查询（消除顺序歧义）。
- **FR-R63-103**：组合上限校验统一：冻结 split 时，退款 amount 不得超过 `split.captured_amount − split.refunded_amount`（创建校验并入现有 `amount ≤ capacity` 门禁；组合场景 = payment 全局 capacity AND 冻结 split 上限，取严格者）。
- **FR-R63-104**：serializer（admin）暴露 `payment_split_id`/`target_order_id`（只读，便于审计/对账）；不新增路由。

### 3.2 分摊 Authority 审计冻结（只读，REUSE）

- **FR-R63-201**：冻结 **REFUND_AMOUNT_AUTHORITY** = `PallasTrade::ReturnItem.refund_amount_calculator`（当前 `Calculator::Returns::DefaultRefundAmount`）：line_item 按退回数量加权（`return_quantity/line_item.quantity`）× pre-tax，加订单级 eligible non-tax 调整（shipping/promotion 等）按 line 占订单 pre-tax 比例分摊；`exchange_requested?` → 0。新代码（Admin 直接对 Payment/Split 退的部分退款）金额由请求方提供（Admin 决定 amount），不走此 calculator——两条路径 authority 分别声明并文档化。
- **FR-R63-202**：冻结 **REFUND_TAX_ALLOCATION_POLICY** = `ReimbursementTaxCalculator`：按 `pre_tax_amount/calculated_refund` 比例把 additional/included tax 分摊到 return_item（3rd-party tax 可替换 `ReturnAuthorization.reimbursement_tax_calculator=`）。
- **FR-R63-203**：冻结 **REFUND_SHIPPING_ALLOCATION_POLICY / REFUND_PROMOTION_ALLOCATION_POLICY** = 订单级 eligible non-tax adjustment 按商品占比分摊（`weighted_order_adjustment_amount`）；gateway `cancel` 的整笔 shipping 退款特例（`for_shipment?` skip）保持现状。
- **FR-R63-204**：禁止在 Controller/UI/服务内临时计算分摊金额（应复用上述 calculator 或显式金额来源）；审计结论写入 `ai/skills/pallastrade-payments/SKILL.md` 与 `pallastrade-pricing/SKILL.md`（REV-P6-3 章节）。本包**不新增任何 Calculator**（REUSE）。

### 3.3 并发与上限固化（测试/回归）

- **FR-R63-301**：补组合并发 spec：SplitA/SplitB 同时（顺序）退满 → 各自 split 上限生效、组合 Payment 全局 capacity 生效（总额不超 100），互不越界（AC-6011/6012）。
- **FR-R63-302**：补多笔部分退款回归（单订单 N 笔独立 Refund/fact/journal；AC-6010）。
- **FR-R63-303**：补「split 已退满拒绝」spec（创建校验失败 → 不 enqueue，AC-6002 语义延伸）。

---

## 4. 非功能需求（NFR）

- 兼容：legacy 退货链（RA/CR/Reimb）分摊行为零变化（REUSE + fallback 保留）；P0-P5 baseline 绿。
- 幂等/并发：组合退款命中冻结 split；同一 split 并发按 `payment.with_lock` + 冻结 split 上限（REV-P6-1 claim 内重校验扩展）。
- 安全：退款仍敏感操作（权限+Audit 保留）；serializer 只读新增字段。
- 数据正确：`PaymentSplit.refunded_amount` 唯一写点仍为 `apply_success!`（succeeded 才写）。

---

## 5. 验收标准（AC）

> 编号 AC-R63-xxx；「源」列引用 REV-P6 源 AC-60xx。

| AC | 源 | 验收条件 | 覆盖 FR |
|---|---|---|---|
| AC-R63-01 | AC-6011 | 组合退款（冻结 split）只影响目标 PaymentSplit/Order | FR-R63-101/102 |
| AC-R63-02 | AC-6012 | 组合退款不修改兄弟 Order/Split | FR-R63-102 + spec |
| AC-R63-03 | AC-6008 | 并发 partial refund 总额不超 Payment refundable（含组合全局与 split 上限） | FR-R63-103/301 |
| AC-R63-04 | AC-6010 | 一个 Payment/Split 支持多笔成功 partial refund（每笔独立 row/fact/journal） | FR-R63-302 |
| AC-R63-05 | — | 冻结 split 的退款 amount ≤ split.captured − refunded，超限拒绝且不 enqueue | FR-R63-103/303 |
| AC-R63-06 | — | legacy（无冻结）退款仍经 reimbursement 链推导 fallback，行为不变（回归） | FR-R63-102 |
| AC-R63-07 | — | 分摊 authority 4 项冻结已文档化（payments/pricing skill）；无新 Calculator | FR-R63-201~204 |
| AC-R63-08 | AC-6030~6035 | P0-P5 baseline 全绿 + backend-rspec 全量 | 全部 |

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | refund / split | 无宿主 override | 否——改框架层 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Refund/PaymentSplit/calculator/tax | `models/.../refund.rb`（update_order）、`payment_split.rb`、`calculator/returns/default_refund_amount.rb`、`reimbursement_tax_calculator.rb`、`reimbursement_type/{original_payment,reimbursement_helpers}.rb` | 部分——所有权冻结/校验需补，calculator 审计即可 |
| API | `pallastrade_gems/pallastrade_api/app/` | refunds | `admin/orders/refunds_controller.rb`、serializer | 部分——组合参数/字段 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | refunds | legacy | 本包不动 |
| Storefront | `storefront/src/` | refund | 无 | 否 |
| Platform | `platform/packages/` | refund | admin-sdk 类型（生成） | admin.yaml 更新后同步 |

**结论**：组合 ownership 列/写点/capacity 已在 REV-P6-1 就绪；本包做「创建冻结接入（Admin/Request）+ update_order 优先冻结 + 上限校验 + 审计冻结文档 + 并发回归」。分摊 authority 现状 primitive 已具备按数量/占比分摊能力，**REUSE**（无新 Calculator）。无重复能力。

---

## 7. 技术影响

- Core：`refund.rb`（update_order 组合分支优先冻结 + 校验）、`payment.rb`（split 上限并入 capacity 门禁，读侧）、`reimbursement_type/*`（无改动，回归验证）、`services/refunds/request.rb`（已支持 target/payment_split，Admin 接线即可）。
- API：`admin/orders/refunds_controller.rb`（可选 payment_split_id/target_order_id 参数解析 + 传给 Request）、`admin/refund_serializer.rb`（暴露 payment_split_id/target_order_id）、admin.yaml ×2。
- 数据：无 migration（列 REV-P6-1 已建）。
- 测试：新增组合并发/上限/冻结 spec；适配既有 serializer/request spec（如有）。
- 文档：payments skill（分摊 authority 冻结 + REV-P6-3）、pricing skill（税/shipping/promo 分摊冻结）、admin.yaml、scenarios GS-061、README（无）。

**风险**
- Admin 新增可选参数不影响既有调用（向后兼容）。
- update_order 优先冻结行为变更仅影响「新创建且带冻结」的组合退款（legacy 走 fallback 不变）。
- 无资金语义倒推/回退。

---

## 8. 测试计划

**新增**
- `backend/spec/models/pallastrade/refund_combination_allocation_spec.rb`：冻结 split 投影/兄弟不变/上限拒绝（AC-R63-01~06）。
- `backend/spec/requests/api/v3/admin/orders/refunds_combination_spec.rb`（或并入既有）：组合退款带 payment_split_id → 冻结 + async 执行（AC-R63-01/03）。
- `backend/spec/services/pallastrade/financial_facts/` 补：组合 partial 多笔独立 fact（AC-R63-04）。

**更新**
- `payment_refund_capacity_spec.rb`：组合 split 上限场景。
- serializer spec：`payment_split_id/target_order_id` 字段。

每 spec 头部标注 `# PRD-REV-P6-3 AC-R63-xx`。

---

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml`（组合退款参数/字段）
- [x] Skill：`pallastrade-payments`（REV-P6-3：ownership 冻结 + 分摊 authority 4 冻结）、`pallastrade-pricing`（tax/shipping/promo 分摊冻结）
- [x] 场景库：`harness/scenarios/scenarios.json`（GS-061）
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引 + `harness doc-impact`

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-07 | 0.1 | 初稿（依据 REV-P6 §58/§26-29 + 2026-09-07 分摊代码审计） | AI |
| 2026-09-07 | 0.2 | 实施：controller 可选冻结参数（预检失败立即渲染返回，勿依赖 save 前 errors）；`amount_within_frozen_split_limit` 创建期上限；admin serializer + admin.yaml×2 + skills + GS-061；新增 `refund_combination_allocation_spec.rb`（AC-R63-01~05：组合冻结投影/兄弟不变/上限拒绝/多笔 partial/第二成员单）与 `refunds_controller_spec.rb`（FR-R63-101：参数冻结/归属拒绝/超限 422/扁平响应断言）。AC-R63-04 多笔独立 fact 由模型 spec 顺序 partial + 既有 resolve_refund 覆盖（未另建 financial_facts spec）；无新 Calculator（REUSE 冻结）。 | AI |
| 2026-09-07 | 0.3 | 验证完成：commit `23128ab`，gate 16/16 finished，提交前+提交后全量 backend-rspec 绿（EVD-…050445/…053154），recovery manual-only，`doc-impact` 通过，push dev 发布。 | AI |

