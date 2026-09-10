# REQ-20260910-promo-batch4a-orderpromotion-snapshot

| 元数据 | 值 |
|---|---|
| 状态 | done（成交快照已实施并验证） |
| 任务类型 | 优化迭代（OrderPromotion 成交快照化；不改金额/核销语义） |
| 关联 PRD | `docs/prd/promotions/PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot.md` |
| 关联任务 | TASK-20260910121422-5721aa28 / GATE-2026-09-10T12-14-39 |
| 前置 | batch1（invariants）、batch2（DiscountProjection）、batch3a/3b/3c（核销台账 + 加固 + 观测） |
| 风险等级 | standard（requiredEvidence: test / review / knowledge） |

---

## Step 0：跨层搜索（本轮实测，2026-09-10）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | `OrderPromotion` / `order_promotions` / `discount snapshot` | 无宿主实现（仅 batch3b 订阅者在 core gem 内） | 不涉及 |
| Core — models | `pallastrade_core/app/models/` | order_promotions / delegate | `order_promotion.rb`（**仅有 4 列 + `delegate :name,:description,:code → promotion`**）、`order.rb`（`discounts` 别名、`promo_code`、`valid_promotions`）、`order/checkout.rb`（状态机 `complete`/`paid`） | ❌ 需扩展（快照列 + 冻结服务 + fallback 读） |
| Core — services/jobs/subscribers | `pallastrade_core/app/{services,jobs,subscribers}` | discount projection / redemption subscriber / snapshot | `promotions/projection/discount_projection.rb`（batch2 统一投影，读 `promotion.name/code`）、`promotions/redemption_subscriber.rb`（batch3b payment_confirmed/refund.succeeded 兜底） | ⚠️ 需改造（投影读快照；订阅者增加冻结步骤） |
| Core — presenters/tasks | `pallastrade_core/{app/presenters,lib/tasks}` | promo_code / promotions rake | `csv/order_line_item_presenter.rb`（`order.promo_code` 实时）、`lib/tasks/promotions.rake`（batch3a 回填任务模板） | ⚠️ 需扩展（CSV 走快照；新增回填任务） |
| API | `pallastrade_api/app/` | discounts / OrderPromotion serializer | `serializers/.../discount_rendering.rb` + `discount_serializer.rb`（无独立 OrderPromotion 序列化器，全部经统一投影） | ✅ 复用（改投影即改 API 输出，**无新端点/无契约变化**） |
| Admin | `pallastrade_admin/app/` | `_order_promotion` / order_promotions | `orders/_promotions.html.erb`、`orders/_order_promotion.html.erb`（读 `order_promotion.promotion.name` 与 `promotion.coupon_code?`）、`orders/order_promotions_controller.rb`（new/create/destroy 写路径，本批次不动） | ❌ 需改展示（读快照；不加写路径） |
| Storefront | `storefront/src/` | discounts / discount_total | `components/order/OrderTotals.tsx`、`checkout/CouponCode.tsx`、`lib/analytics/gtm.ts#coupon`（`order.discounts[].code`）、`lib/webhooks/handlers.ts` | 不涉及（字段集合不变，展示自动受益） |
| Platform | `platform/packages/` | discounts | `@pallastrade/sdk` 类型由 typelizer 生成 | 不涉及（payload 结构不变 → 不重生成） |

### 搜索结论

- 「历史订单折扣展示漂移」的根因集中在 **Core 的 3 个读点 + Admin 的 1 个视图**：`OrderPromotion` delegate、`DiscountProjection::Line`、`Order#promo_code`、`_order_promotion.html.erb`。
- 写点（冻结点）无需新建机制：**batch3a 的 `order.complete` 钩子与 batch3b 的 `payment_confirmed` 订阅者已经是「成交事实」的权威时点**，本批次在同点追加快照写入即可，避免双轨。
- API / Storefront / Platform 因 batch2 已统一到 `DiscountProjection`，**不需要新增端点或改契约**（`discounts[]` 字段集合不变）。

---

## Step 1：Skill 文件咨询（真实结论）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：**Events/Subscribers 优先于 Decorator**；结构性变更（新列/新服务）落 Gem 源（本项目 git 跟踪、允许直接改）。→ 冻结点接线走 `Order` 钩子 + 既有订阅者，符合"行为用事件、结构改源"原则。 |
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已读 | batch2 投影是唯一展示权威（`DiscountedProjection::Line`，`SUM==discount_total`）；batch3a/3b 的成交点是 `order.complete` 与 `commerce_transaction.payment_confirmed`。→ 快照必须**复用投影**取金额（D6），冻结点与核销 commit 对齐（D2）。 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | `pallastrade_order_promotions` 为纯关联表（无 store_id），改列须 **host `backend/db/migrate/` 新迁移**（gem 内迁移为旧引擎）；列变更后需 docker `db:migrate`（dev + test）。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 订单促销面板属既有页面局部视图；只改读取来源（快照优先），不新增导航/表格/权限（无导航一致性影响）。 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec + FactoryBot（`create(:order_with_line_items)` 等）；新 spec 头部标注 `# PRD-xxx AC-xxx`；容器内 `DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec`。 |
| `ai/skills/harness-prd/SKILL.md` + `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 流程：PRD → 用户确认 → task/gate → REQ（含跨层搜索 + Skill 表）→ 实施 → AC↔测试 → `prd verify` → 知识同步门 → evidence → finish。本 REQ 采用**完整版**（改动 > 5 文件且有逻辑变更）。 |

---

## 需求标题

Promotion 批次 4a：OrderPromotion 成交快照化（PR-P5-1..4）——历史订单折扣展示不再随当前促销定义漂移。

## 需求描述

为 `pallastrade_order_promotions` 增加成交快照列（name/kind/code/description/definition_digest/三分项金额/总额/币种/冻结时间），
在订单资金确认（legacy `complete`、标准流程 `paid`、`payment_confirmed` 兜底）时以 batch2 统一投影为源写入快照；
展示层（API `discounts[]`、Admin 订单促销面板、订单 CSV）冻结后只读快照、未冻结回退实时；
提供存量回填 rake（dry-run 默认）与 invariant 测试（促销改名/改 kind/停用码/删动作/改规则后历史输出 0 变化）。

## 影响范围

- **新增**：迁移 `20260910000002_add_snapshot_to_pallastrade_order_promotions.rb`；服务 `Promotions::Snapshot::Freeze`；8 个 spec（模型/服务/状态机/订阅者/Store 请求/Admin 请求/invariant/rake）。
- **修改**：`order_promotion.rb`（快照读方法）、`order.rb`（`freeze_promotion_snapshots` + `promo_code` 快照优先）、`order/checkout.rb`（两个 after_transition）、`redemption_subscriber.rb`（先冻结后核销）、`discount_projection.rb`（读快照）、`promotions.rake`（回填）、`_order_promotion.html.erb`（读快照）、3 个 Skill + scenarios + PRD 索引。
- **不改**：金额计算、核销台账语义、API 契约、storefront 组件。

## 技术方案

1. **迁移（P5-1）**：11 列（4 金额列 `precision: 10, scale: 2, default: 0.0, null: false`）。
2. **模型（P5-1）**：快照优先读方法 + `frozen?` + `snapshot_payload`；`amount` 语义不变。
3. **服务（P5-2）**：`Promotions::Snapshot::Freeze.call(order)` —— 投影驱动、幂等、未成交不写、rescue 不阻断。
4. **接线（P5-2）**：`Order#freeze_promotion_snapshots` 挂 `complete` / `paid`；订阅者 `payment_confirmed` 先 Freeze 后 FinalizeOrder。
5. **展示（P5-3）**：投影 `Line#name/code/kind` 快照优先；Admin 视图读 `order_promotion.name/kind`；`Order#promo_code` 快照优先。
6. **回填（P5-4）**：rake `pallastrade:promotions:backfill_order_promotion_snapshots[store_id,limit]`（dry-run 默认，`APPLY=1` 落库）。
7. **Invariant（P5-4）**：五连改后逐字段比对。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 新增列后 `delegate :name/:code` 残留导致读列失败 | 中 | 移除对应 delegate，读方法显式 `self[:name].presence || promotion...`；模型 spec 覆盖三态 |
| 冻结点过晚（未支付就展示快照）/过早导致购物车冻结 | 中 | 仅在 `complete`/`paid`/`payment_confirmed` 触发；服务内再校验订单已成交；AC-003 覆盖 |
| 冻结失败阻断资金链路 | 中 | 服务整体 rescue + 日志；订阅者保持兜底语义；`complete` 钩子内失败不 raise |
| 快照 `total_amount` 与 `order.discount_total` 偏差 | 中 | 金额直接取 batch2 投影；AC-002/007 断言 `total == item+order+shipping` 且与投影一致 |
| 回填误写存量订单 | 低 | dry-run 默认 + `APPLY=1` 显式；幂等跳过已冻结；逐条隔离 |
| 契约漂移 | 低 | 无 payload 变化 → 不重生成；跑 `generated:check` 确认无漂移 |

## 决策节点

> ✅ 2026-09-10 用户「继续」（承接上一条消息的「说继续我就按 R8 开批次 4 的 PRD/REQ 并走完整流程」）=
> 授权按 PRD §2 D1–D7 推荐方案实施批次 4a（P5-1..4）；无额外决策点。

## 验证方案（AC → 命令）

| AC | 命令 |
|---|---|
| AC-001/002/007 | `rspec spec/models/pallastrade/order_promotion_snapshot_spec.rb spec/models/pallastrade/order_promotion_snapshot_invariant_spec.rb` |
| AC-002/003/005 | `rspec spec/services/pallastrade/promotions/snapshot/freeze_spec.rb` |
| AC-004 | `rspec spec/models/pallastrade/order_checkout_snapshot_freeze_spec.rb spec/jobs/pallastrade/promotions/redemption_subscriber_spec.rb` |
| AC-005 | `rspec spec/requests/api/v3/store/orders_discounts_snapshot_spec.rb` |
| AC-006 | `rspec spec/requests/pallastrade/admin/order_promotion_snapshot_spec.rb` |
| AC-008 | `rspec spec/lib/pallastrade/tasks/promo_order_promotion_snapshot_backfill_spec.rb` |
| AC-009 | 回归批次（见 PRD §8） |
| AC-010 | `harness prd verify --id PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot` + `harness doc-impact --base origin/dev` |
