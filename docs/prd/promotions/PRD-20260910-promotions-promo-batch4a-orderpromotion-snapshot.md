# PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-10 |
| 来源 | `promotion模块架构-任务拆解.md` 批次 4 → Phase 5（PR-P5-1..4）；架构 §35 Promotion Snapshot、§100/§101 Admin 面板、§134 Order Snapshot 与当前 Promotion 分离、§142 Order Freeze/Snapshot Invariant |
| 分类 | promotions |
| 关联 Skill | pallastrade-promotions、pallastrade-data-model、pallastrade-admin、pallastrade-api-v3、pallastrade-testing |
| 关联 REQ | REQ-20260910-promo-batch4a-orderpromotion-snapshot.md（实施时回填） |
| 关联 PRD | batch1（invariants）、batch2（DiscountProjection）、batch3a/3b/3c（Redemption ledger + 加固 + 只读观测） |
| 需求类型 | 优化迭代（历史订单折扣展示冻结，消除「当前促销定义漂移」） |

> **口径原则**：本批次**不改金额**、**不改核销语义**；只把「订单成交时的折扣事实」固化到 `order_promotions`，
> 展示层（API / Admin / 邮件 / CSV）改为「有快照读快照，无快照读实时（购物车与存量订单兼容）」。

---

## 1. 背景与目标

### 1.1 现状问题

`pallastrade_order_promotions` 当前**只有** `order_id / promotion_id / created_at / updated_at`（`backend/db/schema.rb:1177`），
所有展示字段都是**实时委托**到当前促销定义：

- `OrderPromotion` 模型：`delegate :name, :description, :code, :public_metadata, to: :promotion`（`order_promotion.rb:7`）
- 统一投影 `DiscountProjection::Line`：`name → promotion.name`、`code → promotion.code_for_order(order)`（`discount_projection.rb:41,48`）
- Admin 订单面板：`_order_promotion.html.erb:1,4` 直接读 `order_promotion.promotion.name` 与 `promotion.coupon_code?`
- 订单 CSV：`order_line_item_presenter.rb:84` 用 `order.promo_code`（实时查 `CouponCode` / `promotions.code`）

于是出现 **漂移**：运营改名 / 改 kind / 停用或改码 / 删除促销动作后，**历史订单**的折扣文案、
折扣码、折扣类型在 API、订单确认邮件、Admin 订单页、CSV 导出中全部跟着变——违反架构 §134
「Order 成交后：Promotion 修改/删除/Code Disabled/Campaign Ended 都不影响历史 OrderPromotion / Frozen Adjustments」。

### 1.2 目标

1. `order_promotions` 增加**成交快照列**（name/kind/code/description/definition_digest/三分项金额/总额/币种/冻结时间）。
2. 订单**成交（资金确认）时冻结**：legacy 流程 `complete`、标准流程 `paid`、以及 `commerce_transaction.payment_confirmed` 兜底；幂等，不阻塞资金链路。
3. 展示层（Store/Admin API `discounts[]`、Admin 订单促销面板、订单 CSV）**冻结后只读快照**；购物车 / 未成交流程仍读实时定义（行为不变）。
4. 提供**存量回填**（rake，dry-run 默认，APPLY=1 落库，幂等），回填前不改变任何展示。
5. Invariant 可测：**成交订单不受促销后续修改/删除/停用影响**（金额 + 文案 + 折扣码 + 类型全部不变）。

### 1.3 成功指标

- 修改促销名 / kind / code、停用码、删除促销动作后，`GET /api/v3/store/orders/:id`（含 `discounts`）与 Admin 订单页输出 **0 变化**。
- 冻结写路径对未成交订单 **0 写入**（购物车/未支付订单不产生快照）；重复触发 **0 重复行**（幂等）。
- 回填 rake 对已冻结行 **0 改写**（dry-run 与 apply 输出一致）。

---

## 2. 名词与决策（D1–D7）

| # | 决策 | 结论 | 理由 |
|---|---|---|---|
| **D1** | 列命名 | 直接采用架构 §35 语义列名：`name / kind / code / description / definition_digest / item_amount / order_amount / shipping_amount / total_amount / currency / frozen_at`（**不加 `snapshot_` 前缀**） | 与架构文本一致；`nil` 即「未冻结」；读方法显式 fallback，避免中间态被误读 |
| **D2** | 冻结时点 | 订单**资金确认**时：legacy `after_transition to: :complete`、标准流程 `after_transition to: :paid`、以及 `commerce_transaction.payment_confirmed` 事件（订阅者兜底，覆盖"记账确认但未走状态机"，该路径传 `force: true`——事件本身即资金信号） | 与 batch3a 核销 commit / batch3b FinalizeOrder 同一业务点，避免「双轨冻结点」；架构 §142 Order Freeze |
| **D3** | 无 OrderPromotion 行的促销 | 冻结时**补建** `order_promotions` 行（`find_or_create_by`）再写快照 | 保证「成交订单的每个生效促销都有冻结事实」；顺带让 `Promotion#not_used?` 正确阻止删除已用促销（历史保护） |
| **D4** | 未冻结订单 | 读方法 fallback 到实时定义（**购物车行为零变化**）；回填是**可选**的运维动作 | 避免本批次把「购物车实时展示」变成回归风险 |
| **D5** | `definition_digest` | `SHA256(canonical_json)`，覆盖 `id/kind/name/code/multi_codes/starts_at/expires_at/usage_limit/rules/actions`（规则/动作用类名 + `api_type` + 关键属性，稳定排序） | 提供"定义是否变过"的可比对证据（审计 / 未来重算判定），不参与金额计算 |
| **D6** | 金额来源 | 三分项金额直接取 batch2 的统一投影 `DiscountProjection::Line`（`item_amount/order_amount/shipping_amount`），`total_amount = 三者之和`；**不重算引擎** | 复用唯一权威口径；invariant `SUM(discounts) == discount_total` 在冻结后仍成立 |
| **D7** | 失败处理 | 冻结服务整体 rescue + 日志，**不打断** `complete/pay` 事务与支付确认链路（与 batch3b 订阅者同款） | 展示冻结不是资金前置条件；宁可缺快照（fallback 实时）也不能阻断成交 |

---

## 3. 功能需求（FR）

- **FR-001 迁移（P5-1）**：host 迁移 `add_snapshot_to_pallastrade_order_promotions`，新增上表 11 列（decimal `precision: 10, scale: 2, default: 0.0, null: false` for 4 个金额列；`frozen_at` datetime；其余 string）。**不**新建表、不改现有列、不需要回填即可部署（全部 nullable/有默认值）。
- **FR-002 模型快照读（P5-1）**：`PallasTrade::OrderPromotion`
  - 移除 `delegate :name, :description, :code`（保留 `public_metadata`），改为「快照优先」读方法：`name / code / description / kind`；
  - `frozen?` = `frozen_at` 与 `name`、`total_amount` 齐备；
  - `snapshot_payload` 返回只读哈希（供 Admin / 调试 / spec 断言）；
  - `amount` 语义不变（eligible 促销调整求和；批量投影仍为展示权威）。
- **FR-003 冻结服务（P5-2）**：新增 `PallasTrade::Promotions::Snapshot::Freeze`（`call(order, force: false)`）
  - 输入：订单（含 eligible 促销调整）；`force: true` 仅供 `payment_confirmed` 事件使用（跳过状态判定，事件本身即资金确认）；
  - 行为：对每个投影行 upsert `order_promotions` 行并写入快照列 + `definition_digest` + `frozen_at`；
  - 幂等：已冻结行**不覆盖**；
  - 未成交保护：订单无 eligible 促销调整 / 订单为 `cart` 或不传 force 的未支付订单时不写入（返回 `[]`）；
  - 失败：`rescue => e` 记 `Rails.logger.error` 并返回 `[]`（不 raise）。
- **FR-004 冻结点接线（P5-2）**
  - `PallasTrade::Order#freeze_promotion_snapshots`（新方法）→ 调 Freeze；
  - legacy：`after_transition to: :complete, do: :freeze_promotion_snapshots`（与 `record_promotion_redemptions` 并列）；
  - 标准流程：`after_transition to: :paid, do: :freeze_promotion_snapshots`；
  - 兜底：`Promotions::RedemptionSubscriber#handle_payment_confirmed` 内先 `Freeze.call(order)` 再 `FinalizeOrder.call(order)`（顺序：先冻结展示事实，再写核销）。
- **FR-005 展示切换（P5-3）**
  - `DiscountProjection::Line#name / #code / #kind`：`order_promotion&.name.presence || promotion.name`（同 code/kind），保证 API（Store/Admin `discounts[]`、Checkout `discounts`）在冻结后读快照；
  - Admin 订单促销面板 `_order_promotion.html.erb`：名称/类型徽章改读 `order_promotion.name` / `order_promotion.kind`（未冻结时 fallback 实时）；
  - `PallasTrade::Order#promo_code`：优先返回**已冻结**的 `order_promotions.code`（多单多码时取第一条），未冻结时保持现有实时逻辑（CSV / 邮件 / storefront 均受益）。
- **FR-006 存量回填（P5-4 配套）**：rake `pallastrade:promotions:backfill_order_promotion_snapshots`
  - 参数 `[store_id, limit]`（可空）；候选 = 已成交（`completed_at IS NOT NULL` 或 `state IN (complete, paid, processing, shipped, completed)`）且有 eligible 促销调整的订单；
  - **dry-run 默认**（只打印 TSV：order / promotion / name / code / total_amount），`APPLY=1` 才写；
  - 逐单隔离 rescue（单条失败不中断）；幂等（已冻结跳过）；输出 summary（候选数 / 冻结数 / 跳过数 / 失败数）。
- **FR-007 Invariant（P5-4）**：成交后对促销做「改名 + 改 kind + 停用码 + 删除动作 + 修改规则」五连改，订单快照字段与投影输出**逐字段不变**。
- **FR-008 文档同步**：`pallastrade-promotions` SKILL（快照语义与新冻结点）、`pallastrade-data-model` SKILL（`order_promotions` 列）、`pallastrade-admin` SKILL（订单面板读快照）、`harness/scenarios/scenarios.json` 新增 GS-086、`docs/prd/README.md` 索引、本 PRD 状态。

---

## 4. 业务规则与边界（必须逐条实现/测试）

| # | 规则 | 说明 |
|---|---|---|
| R1 | 冻结仅发生在**资金确认后** | `cart / address / … / payment / pending` 状态不写快照；未支付订单继续实时展示；唯一例外是 `commerce_transaction.payment_confirmed` 订阅者路径（`force: true`，事件即资金信号） |
| R2 | 幂等 | 同一 `(order, promotion)` 已有 `frozen_at` → 完全跳过（不覆盖 name/code/金额，保证历史不可变，即使促销在两次触发之间又被改过） |
| R3 | 一码多单 / 多码场景 | 冻结的是**该订单实际使用的码**（`code_for_order` / 已占用 `CouponCode`），后续码重新分配不影响历史 |
| R4 | 删除促销 | 历史订单展示不变（快照兜底），且 `order_promotions` 行存在 → `not_used?` 阻止删除「已用于成交订单」的促销（既有语义强化，不新增硬约束） |
| R5 | 取消订单 | **不清理**快照（历史审计保留）；核销释放走 batch3a/3b（与本批次正交） |
| R6 | 金额一致性 | `total_amount == item_amount + order_amount + shipping_amount`；冻结时 `total_amount` 等于当时投影的 `Line#amount`；冻结后 `SUM(快照 total_amount)` 与 `order.discount_total`（同一批调整）一致 |
| R7 | 币种 | 快照 `currency` = 订单币种（架构 §58：退款/展示一律原订单币种，不做 FX 转换） |
| R8 | 无调整的促销行 | 出现在投影中但金额为 0 的促销：**照常冻结**（保留"本单使用过该促销"的事实）；`order_promotions` 已存在但不在投影（不再 eligible）的行：**不冻结、不改写**，读方法走实时 fallback |
| R9 | 并发 | 冻结写路径用 `find_or_create_by` + 唯一索引 `(promotion_id, order_id)` 兜底（`ActiveRecord::RecordNotUnique` → reload 重试一次），保证不重复行 |
| R10 | 事务安全 | 冻结在 `complete/pay` 的同一事务内执行；订阅者兜底路径自带 rescue，不阻塞支付确认 |

---

## 5. 验收标准（AC，与测试一一映射）

| AC | 对应 | 判定条件 | 映射测试 |
|---|---|---|---|
| AC-001 | FR-001/002 | 迁移后 `pallastrade_order_promotions` 含 11 个快照列、4 个金额列 `default 0.0/null: false`；模型 `frozen?` 对「全空」「部分空」「齐备」三态判定正确；`snapshot_payload` 键集合稳定 | `backend/spec/models/pallastrade/order_promotion_snapshot_spec.rb` |
| AC-002 | FR-003/R2/R6/R8 | `Freeze.call(order)` 对完成订单写入快照：`name/kind/code/description` 与促销一致、`total_amount == item+order+shipping`、`currency == order.currency`、`definition_digest` 64 位 hex；重复调用不改写（第二次调用前后各字段逐一相等）；无调整的促销行也写入；不在投影中的既有行不变 | 同上 + `spec/services/pallastrade/promotions/snapshot/freeze_spec.rb` |
| AC-003 | FR-003/R1 | 购物车 / 未支付（`pending`/`payment`）订单调用 `Freeze.call` 不生效（返回空、`frozen_at` 为 nil）；`Freeze.call(order, force: true)` 在资金确认事件路径下可冻结 | `spec/services/pallastrade/promotions/snapshot/freeze_spec.rb` |
| AC-004 | FR-004/R9 | legacy `order.complete` 后快照齐备；标准流程 `pay` 事件后快照齐备；`commerce_transaction.payment_confirmed` 事件后（跳过状态机）快照齐备；重复触发不新增行（计数不变） | `spec/models/pallastrade/order_checkout_snapshot_freeze_spec.rb` + `spec/jobs/pallastrade/promotions/redemption_subscriber_spec.rb`（扩展） |
| AC-005 | FR-005 | 冻结后：`DiscountProjection` 的 `name/code/kind` 取快照；Store API `GET /api/v3/store/orders/:id?expand=discounts` 与 Checkout `discounts[]` 输出快照；**未冻结购物车**输出实时定义（回归） | `spec/services/pallastrade/promotions/snapshot/freeze_spec.rb` + `spec/requests/api/v3/store/orders_discounts_snapshot_spec.rb` |
| AC-006 | FR-005 | Admin 订单促销面板渲染快照名与类型徽章（改名后页面仍是旧名）；`Order#promo_code` 对冻结订单返回快照码（改名/停用后不变） | `spec/requests/pallastrade/admin/order_promotion_snapshot_spec.rb` |
| AC-007 | FR-007/R4/R5 | 五连改（改名 / 改 kind / 停用码 / 删除动作 / 改规则）后：快照字段、`discounts[]` 输出、`order.discount_total` 逐字段不变；取消订单后快照仍保留 | `spec/models/pallastrade/order_promotion_snapshot_invariant_spec.rb` |
| AC-008 | FR-006 | rake dry-run 不写库（`frozen_at` 仍 nil）且打印候选；`APPLY=1` 冻结存量；二次运行跳过已冻结（summary 跳过数 > 0）；单条异常被隔离 | `spec/lib/pallastrade/tasks/promo_order_promotion_snapshot_backfill_spec.rb` |

验证补充（非 AC，不参与 `prd verify` 的 AC↔测试映射）：

| 编号 | 对应 | 判定 | 证据 |
|---|---|---|---|
| VERIFY-01 | §1.3 | 回归：batch1/2/3a/3b/3c 既有 promotions 相关 spec 全绿（promotions 目录 + jobs + config + 请求规范 + 导航一致性） | 回归批次命令（见 §8）输出 `137+ examples, 0 failures` |
| VERIFY-02 | FR-008 | `pallastrade-promotions` / `pallastrade-data-model` / `pallastrade-admin` SKILL 更新；GS-086 入库；`harness prd verify` 全 AC 覆盖；`doc-impact` 无缺失 | `harness prd verify` / `harness doc-impact` 输出 |

---

## 6. 跨层搜索记录（6 层，2026-09-10 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `OrderPromotion` / `order_promotions` | 无宿主逻辑（batch3b 订阅者实际位于 core gem） | 不涉及 |
| Core | `pallastrade_core/app/` | `order_promotions`, `promotion.name`, `promo_code` | `models/pallastrade/order_promotion.rb`（仅关联 + delegate）、`services/.../discount_projection.rb`（`promotion.name/code`）、`models/pallastrade/order.rb`（`promo_code`, `valid_promotions`）、`models/pallastrade/order/checkout.rb`（状态机 `complete`/`paid`）、`presenters/csv/order_line_item_presenter.rb` | **需扩展**（新增快照列 + 冻结服务 + fallback 读） |
| API | `pallastrade_api/app/` | `discounts`, `OrderPromotion` | `serializers/.../discount_rendering.rb` + `discount_serializer.rb`（batch2 统一投影，无独立 OrderPromotion 序列化器） | 复用投影 → 改投影读快照即可（**无需新端点**） |
| Admin | `pallastrade_admin/app/` | `order_promotions`, `_order_promotion` | `orders/_promotions.html.erb` + `orders/_order_promotion.html.erb` + `orders/order_promotions_controller.rb`（new/create/destroy） | **需改展示**（读快照）；不加写路径 |
| Storefront | `storefront/src/` | `discounts`, `discount_total` | `components/order/OrderTotals.tsx`、`checkout/CouponCode.tsx`、`lib/analytics/gtm.ts`、`lib/webhooks/handlers.ts`（只消费 API 字段） | 不涉及（API 输出稳定即稳定，**无需改动**） |
| Platform | `platform/packages/` | `discounts` | `@pallastrade/sdk` 类型由 typelize 生成；本次 **payload 结构不变** | 不涉及（无 schema 变化 → 不重生成） |

**结论**：能力缺口集中在 **Core（快照列 + 冻结服务 + 读时 fallback）** 与 **Admin（展示读快照）** 两处；
API/Storefront/Platform 因 batch2 已收敛到统一投影，**只需投影内部读快照**，不新增端点、不改契约。

---

## 7. 技术影响

- **数据库**：host 迁移 `backend/db/migrate/20260910000002_add_snapshot_to_pallastrade_order_promotions.rb`（11 列；4 金额列 `null: false, default: 0.0`）。
- **Core**：`OrderPromotion`（读方法 + `frozen?` + `snapshot_payload`）、新增 `Promotions::Snapshot::Freeze`、`Order#freeze_promotion_snapshots`、`order/checkout.rb`（两个 after_transition）、`RedemptionSubscriber`（先冻结后核销）、`DiscountProjection::Line`（读快照）、`Order#promo_code`（优先快照）。
- **Admin**：`orders/_order_promotion.html.erb`（名称 + 类型徽章读快照）。
- **Rake**：`lib/tasks/promotions.rake` 增 `backfill_order_promotion_snapshots`（dry-run 默认）。
- **契约**：**无 API 结构变化**（`discounts[]` 字段集合不变）→ 不重生成 OpenAPI/SDK 类型。
- **不影响**：核销台账（batch3a/3b/3c）、金额计算、退款分摊（批次 4b 另行处理）、Storefront 组件。

---

## 8. 测试计划

| 文件 | 类型 | 覆盖 AC |
|---|---|---|
| `backend/spec/models/pallastrade/order_promotion_snapshot_spec.rb`（新） | model | AC-001/002 |
| `backend/spec/services/pallastrade/promotions/snapshot/freeze_spec.rb`（新） | service | AC-002/003/005 |
| `backend/spec/models/pallastrade/order_checkout_snapshot_freeze_spec.rb`（新） | model/状态机 | AC-004 |
| `backend/spec/jobs/pallastrade/promotions/redemption_subscriber_spec.rb`（扩） | subscriber | AC-004 |
| `backend/spec/requests/api/v3/store/orders_discounts_snapshot_spec.rb`（新） | request | AC-005 |
| `backend/spec/requests/pallastrade/admin/order_promotion_snapshot_spec.rb`（新） | request（Admin） | AC-006 |
| `backend/spec/models/pallastrade/order_promotion_snapshot_invariant_spec.rb`（新） | invariant | AC-007 |
| `backend/spec/lib/pallastrade/tasks/promo_order_promotion_snapshot_backfill_spec.rb`（新） | rake | AC-008 |

运行命令（容器 `pallastrade-web-1`，工作目录 `/rails`）：

```bash
# 新 spec
DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <上表新文件>
# 回归（VERIFY-01）
DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/promotions \
  spec/models/pallastrade/promotion_spec.rb spec/models/pallastrade/promotion_redemption_spec.rb \
  spec/models/pallastrade/order_checkout_redemption_spec.rb spec/jobs/pallastrade/promotions \
  spec/lib/pallastrade/tasks/promo_redemption_backfill_spec.rb spec/config/sidekiq_schedule_spec.rb \
  spec/requests/api/v3/admin/promotion_redemptions_spec.rb \
  spec/requests/pallastrade/admin/promotion_redemptions_spec.rb \
  spec/requests/pallastrade/admin/navigation_consistency_spec.rb
```

---

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-promotions/SKILL.md`：快照语义 + 冻结点（complete/paid/payment_confirmed）+ fallback 规则 + 回填 rake。
- [x] `ai/skills/pallastrade-data-model/SKILL.md`：`pallastrade_order_promotions` 快照列清单。
- [x] `ai/skills/pallastrade-admin/SKILL.md`：订单促销面板读快照（历史不可变）说明。
- [x] `harness/scenarios/scenarios.json`：GS-086（OrderPromotion 快照冻结）。
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态。
- [x] 接口契约：**本轮无 payload 变化** → 不重生成（已评估，无需更新）。
- [x] `pallastrade-testing`：无新增测试规范需求（沿用容器 rspec 约定）。
- [x] 附带修复：`backend/config/locales/admin_nav.zh-CN.yml`（batch3c 导航标签 zh-CN，FR-012）。

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-10 | 0.1 | 初稿（依据任务拆解批次 4 Phase 5 + 架构 §35/§100/§134/§142） | AI |
| 2026-09-10 | 1.0 | 用户「继续」授权实施；D1–D7 决策锁定；AC-001..008 与测试文件映射完成（回归/文档为 VERIFY-01/02） | AI |
| 2026-09-10 | 1.1 | 实施完成：冻结服务落地（含 `force:` 逃生口，仅 `payment_confirmed` 路径使用）；`frozen?` 简化为 `frozen_at + name`（金额列有默认值）；模型/服务/状态机/订阅者/Store API/Admin 页/invariant/回填 rake 全部有 spec；回归绿；PRD/REQ/Skill/场景同步 | AI |

## 11. 实施说明与偏差记录

| 项 | 说明 |
|---|---|
| `force:` 参数 | `payment_confirmed` 订阅者路径使用 `force: true`：事件本身即资金确认信号，此时订单状态机可能尚未推进（如真实回调先于状态流转）。这是唯一绕过状态判定的入口，购物车/未支付订单仍不会冻结。 |
| `frozen?` 判定 | 最终为 `frozen_at.present? && name.present?`——四个金额列 `null: false, default: 0.0`，无法作为「已冻结」信号（默认值看不出差异）。 |
| 码大小写 | 快照存的是 `Promotion#code` / `CouponCode#code` 的**规范化值**（trim + downcase，batch1 规则），与实时展示一致（既有 API 也返回小写）。 |
| 零金额促销 | 未产生 eligible 调整的促销不进投影 → 不冻结（无投影行则无快照）；已产生调整但金额被改为 0 的行照常冻结（spec 已覆盖）。 |
| 既有 rubocop 基线 | `order.rb` / `checkout.rb` / `cart.rb` 等 legacy 文件存在仓库级基线违规（`Layout/EmptyLinesAfterModuleInclusion`、`Style/RedundantSelf` 等）；本批次新增/修改行均为 0 违规（新增文件全部 clean）。 |
| 附带修复（batch3c 遗留） | `harness check --profile quick` 的 nav-validate 插件发现 batch3c 的 Redemptions 导航标签缺 zh-CN 翻译（FR-012 双语必填）→ 已补 `backend/config/locales/admin_nav.zh-CN.yml` 的 `pallastrade.admin.promotions.redemptions: 核销记录`（quick check 复跑 0 warning）。 |
