# PRD-20260827-payments-实施-p3-父子单金额与支付状态派生-combined_total-payment-shipment_state-聚合

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-27 |
| 来源 | 需求：实施 P3 父子单金额与支付状态派生（combined_total/payment/shipment_state 聚合） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-data-model、pallastrade-payments、pallastrade-checkout、pallastrade-testing |
| 关联 REQ | REQ-20260827-order-lifecycle-p3.md（实施时回填） |
| 关联 PRD | N/A（全新；上游方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md` §P3） |
| 需求类型 | 新功能（金额/支付派生，Risk critical，需恢复计划） |

---

## 1. 背景与目标

- **一句话需求原文**：需求：实施 P3 父子单金额与支付状态派生
- **背景**：P2 拆单引擎已能生成父子订单，但父订单（容器）金额/支付/发货状态目前仅基于自身（拆空后为 0），无法反映子订单聚合。P3 提供**聚合派生方法**，供父订单序列化/查询正确展示。
- **目标**：
  1. `Order#combined_total`（own + Σ children 递归聚合）；
  2. `Order#combined_payment_total` / `combined_outstanding_balance` / `combined_amount_due`（支付聚合）；
  3. `Order#combined_shipment_state` / `combined_payment_state`（状态聚合，与 `OrderUpdater` 规则一致）；
  4. `Order#effective_payment_total`（子订单有 `PaymentSplit` 时按 split 推导）；
  5. Store/Admin `OrderSerializer` 在**父订单**时输出聚合值（无 children 零变化）。
- **成功指标**：聚合方法不覆写核心 `total`/`payment_total`/`shipment_state`（不破坏 OrderUpdater/状态机）；无 children 时 `combined_*` 与原值一致；父订单聚合值正确（spec 断言）。

---

# PRD-{YYYYMMDD}-{category}-{slug}

| 元数据 | 值 |
|---|---|
| 状态 | draft / reviewing / approved / implementing / verifying / done / rejected / merged |
| 创建日期 | YYYY-MM-DD |
| 来源 | 一句话需求原文 |
| 分类 | （自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | （对应领域 skill 名） |
| 关联 REQ | REQ-YYYYMMDD-xxx.md（实施时回填） |
| 关联 PRD | （查重回写时填原 PRD ID；全新需求填 N/A） |
| 需求类型 | 新功能 / 优化迭代 / Bug 修复 / 接口变更 / 样式 / 文档 |

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **一句话需求原文**：<用户输入原文>
- **背景**：为什么做、解决什么问题
- **目标**：期望达成的结果
- **成功指标**：可量化指标（如：导入 1 万 SKU 耗时 < 60s）

## 2. 用户故事 / 场景

> P3 是金额/状态派生能力，无直接用户故事；技术场景供测试映射。

- **S1（父订单聚合）**：父订单含 2 子订单 → `combined_total` = Σ children，`combined_payment_total` = Σ children。
- **S2（无 children 回退）**：单笔订单（无 children）→ `combined_*` 与原值完全一致（零行为变化）。
- **S3（发货状态聚合）**：1 子已 shipped、1 子 pending → 父 `combined_shipment_state` = `partial`；全部 shipped → `shipped`。
- **S4（支付状态聚合）**：Σ 已付 == Σ 总额 → 父 `combined_payment_state` = `paid`；不足 → `balance_due`。
- **S5（PaymentSplit 推导）**：子订单有 `PaymentSplit`（captured=10, refunded=3）→ `effective_payment_total` = 7。
- **S6（序列化器）**：父订单 Store API 输出聚合 `total`/`payment_status`/`fulfillment_status`；单笔订单输出不变。

## 3. 功能需求（FR）

- **FR-001**：`Order#combined_total`——有 children 时 = `own_total + Σ children.combined_total`（递归）；无 children = `total`。
- **FR-002**：`Order#combined_payment_total`——有 children 时 = `own payment_total + Σ children.combined_payment_total`；无 children = `payment_total`。
- **FR-003**：`Order#combined_outstanding_balance`——有 children 时 = `combined_total - (combined_payment_total + reimbursement_paid_total)`（取消时 -combined_payment_total）；无 children = `outstanding_balance`。
- **FR-004**：`Order#combined_amount_due`——`[combined_outstanding_balance - total_applied_store_credit, 0].max`。
- **FR-005**：`Order#combined_shipment_state`——聚合 own shipments + children 状态，套用 `OrderUpdater#update_shipment_state` 规则（backorder/partial/pending/ready/shipped）。
- **FR-006**：`Order#combined_payment_state`——基于 `combined_outstanding_balance` 套用 `update_payment_state` 规则（paid/balance_due/credit_owed/failed/void）。
- **FR-007**：`Order#effective_payment_total`——存在有效 `PaymentSplit` 时用 `captured_amount - refunded_amount`，否则 `payment_total`。
- **FR-008**：Store/Admin `OrderSerializer` 父订单（`parent_order?`）时 `total`/`display_total`/`amount_due`/`payment_status`/`fulfillment_status` 用聚合值；无 children 不变。

## 4. 非功能需求（NFR）

- **不破坏核心**：不覆写 `total`/`payment_total`/`outstanding_balance`/`shipment_state` 方法（OrderUpdater/状态机/校验依赖原语义）。
- **零行为变化**：无 children 时聚合方法回退原值，序列化器仅父订单用聚合。
- **递归安全**：`combined_*` 依赖 children 树，防环由 `root_order` 语义保证（P1）；测试覆盖深层。
- **可回滚**：纯代码（模型方法 + 序列化器字段），无迁移；删除即退。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：父订单 `combined_total` = Σ children（含多级递归）；无 children 与原值一致。
- **AC-002 ← FR-002**：父订单 `combined_payment_total` 聚合正确。
- **AC-003 ← FR-003**：`combined_outstanding_balance` 聚合正确（含取消场景）。
- **AC-004 ← FR-004**：`combined_amount_due` 正确。
- **AC-005 ← FR-005**：`combined_shipment_state` 各分支（partial/shipped/backorder/pending）。
- **AC-006 ← FR-006**：`combined_payment_state` 各分支（paid/balance_due）。
- **AC-007 ← FR-007**：`effective_payment_total` 走 split 推导。
- **AC-008 ← FR-008**：序列化器父订单输出聚合值；单笔订单输出不变（request spec）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | combined / parent total | 无 | ⛔ 需新建（core） |
| Core | `pallastrade_gems/pallastrade_core/app/models/pallastrade/order.rb` | total / payment_total / shipment_state | 现有 `total`/`outstanding_balance`/`payment_state` 单订单逻辑 | ⛔ 需新增聚合方法 |
| Core | `order_updater.rb` | update_shipment_state / update_payment_state | 现有派生规则（供聚合复用） | ✅ 参照规则 |
| API | `pallastrade_gems/pallastrade_api/app/serializers/.../order_serializer.rb` | total / payment_status | 现有字段（P1 已加父子字段） | ⛔ 需加聚合分支 |
| Admin | `pallastrade_admin/app/` | combined | 无 | ⛔ 序列化器继承 Store |
| Storefront | `storefront/src/` | combinedTotal | 无 | ⛔ P3 不涉及 |
| Platform | `platform/packages/` | combinedTotal | 无 | ⛔ P3 不涉及 |

**结论**：无聚合派生实现；P3 在 `Order` 模型新增 `combined_*`/`effective_*` 方法 + 序列化器父订单分支。不覆写核心方法。

## 7. 技术影响

- **模型**：`order.rb` 新增聚合方法（`combined_total`/`combined_payment_total`/`combined_outstanding_balance`/`combined_amount_due`/`combined_shipment_state`/`combined_payment_state`/`effective_payment_total`）。
- **序列化器**：Store + Admin `order_serializer.rb` 父订单分支用聚合值。
- **测试**：`backend/spec/models/pallastrade/order_parent_child_spec.rb`（新增聚合用例）+ serializer request spec。
- **无迁移 / 无 API 变更**；`combined_*` 默认不影响单笔订单。

## 8. 测试计划

- **更新** `backend/spec/models/pallastrade/order_parent_child_spec.rb`：AC-001~007（聚合金额/支付/发货状态/effective_payment_total）。
- **更新** `backend/spec/requests/api/v3/store/order_serializer_parent_child_spec.rb`：AC-008（父订单序列化聚合输出）。
- 运行：`harness check --profile quick` + 相关 rspec（docker exec）。

## 9. 文档同步清单（知识同步门）

- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引（P3 已建索引，状态随提交更新）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（新增「Order 聚合派生 (P3)」段：combined_*/effective_payment_total + money_methods）
- [x] `ai/skills/pallastrade-payments/SKILL.md`（新增「支付聚合派生（P3）」段：combined_payment_total/state + effective_payment_total）
- [x] `ai/skills/pallastrade-checkout/SKILL.md`（新增「发货状态聚合（P3）」段：combined_shipment_state）
- [x] API 文档：P3 无新端点，序列化器字段类型不变（string money/string enum），`backend/public/api-docs/{store,admin}.yaml` 已评估无需变更（语义增强随 P5 接口正式化一并落 yaml）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-27 | 0.1 | 初稿：P3 父子单金额与支付状态派生（combined_* 聚合） | AI |
| 2026-08-27 | 0.2 | 实施完成：order.rb 新增 combined_*/effective_payment_total（不覆写核心）；Store/Admin OrderSerializer 父订单聚合输出；22 用例全绿；gate GATE-2026-08-27T13-20-27 关闭；同步 data-model/payments/checkout Skill | AI |
