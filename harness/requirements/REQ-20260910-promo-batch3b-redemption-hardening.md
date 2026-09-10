# REQ-20260910-promo-batch3b-redemption-hardening

| 元数据 | 值 |
|---|---|
| 状态 | done（范围 A 已实施；Phase B 明确未做） |
| 任务类型 | 功能优化（资金完整性：并发/超时/事件/退款释放） |
| 关联 PRD | `docs/prd/promotions/PRD-20260910-promotions-promo-batch3b-redemption-hardening.md` |
| 关联任务 | TASK-20260910083915-f3cdd2d7 / GATE-2026-09-10T08-39-22 |
| 前置 | batch3a（PRD-20260910-promotions-promo-batch3a-redemption-ledger，已 done，commit eaffa286） |

---

## Step 0：跨层搜索（本轮实测）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | subscriber / redemption | 不存在 `backend/app/subscribers`（订阅者均在 gem 内）；无宿主核销逻辑 | 无需改动 |
| App — views/decorators | `backend/app/` | redemption | 无 | 无需改动 |
| Core Gem — models | `pallastrade_core/app/models/` | PromotionRedemption / commerce_transaction | `promotion_redemption.rb`（batch3a）、`commerce_transaction.rb`（state machine + `confirm_payment` 事件 + `publishes_lifecycle_events`） | 部分：缺并发/超时/事件挂接 |
| Core Gem — services | `pallastrade_core/app/services/` | redemption / sweeper | batch3a `promotions/redemption/*`（Reserve/Commit/Release/FinalizeOrder/ReleaseOrder）；无 sweeper service | ❌ 需新增 Job + 并发加固 |
| Core Gem — jobs | `pallastrade_core/app/jobs/` | ExpireJob / RecoverSweeperJob | `stock_reservations/expire_job.rb`（保守 sweeper 模板，含 guarded 订单判定）、`transactions/recover_sweeper_job.rb`、`refunds/recover_sweeper_job.rb` | ✅ 有模板可循 |
| Core Gem — subscribers | `pallastrade_core/app/subscribers/` | payment_confirmed / refund.succeeded | `payment_paid_subscriber.rb`、`refund_succeeded_subscriber.rb`、`payment_session_reservation_subscriber.rb` 等；注册表在 `pallastrade_core/lib/pallastrade/core.rb` | ❌ 缺核销订阅者 |
| API Gem — controllers | `pallastrade_api/app/controllers/` | admin read-only | `admin/coupon_codes_controller.rb`（ResourceController 只读：`model_class`/`serializer_class`/`parent_association`）| Phase B 模板 |
| Admin Gem — controllers/views | `pallastrade_admin/app/` | read-only index / nav | `admin/coupon_codes_controller.rb` + `views/.../coupon_codes/index.html.erb`；权限：`config/initializers/pallastrade_permission_registry.rb` + `PermissionSets::PromotionManagement` | Phase B 模板 |
| Storefront | `storefront/src/` | redemption | 无消费点 | 无改动 |
| Platform | `platform/packages/` | redemption | 无相关类型 | Phase B 需再生契约 |

### 搜索结论

- batch3a 已建 ledger 与下单内闭环；本批次的**全部缺口**都在 core gem：并发加固（服务层）、过期 sweeper（新 Job + 调度）、支付确认兜底（新订阅者 + 注册）、退款释放（新订阅者）。
- 现有实现范式可直接复用：`StockReservations::ExpireJob`（保守 sweeper + guarded 订单）、`core.rb` 订阅者注册列表、`config/sidekiq_schedule.rb`（sidekiq-cron 调度）。
- Phase B（只读面）在 API/Admin 层，均有现成只读模板，可独立交付。

---

## Step 1：Skill 文件咨询（真实结论）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-promotions/SKILL.md` | ✅ 已读 | batch3a 条目：占用/核销语义在 `PromotionRedemption`，`usage_limit`/`credits_count` 读 ledger committed，`use_all_coupon_codes` 为兼容包装 → 本批次**只加固并发与出口**，不得回退这些口径。 |
| `ai/skills/pallastrade-events-webhooks/SKILL.md` | ✅ 已读 | 订阅者**不会自动发现**，必须在注册表注册；`publish_event` 在调用点派发（可能在事务内），异步订阅者经 `SubscriberJob`；核销兜底订阅者按 async 默认 + 幂等设计。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | 支付状态机与事件（`payment.completed` 等）；`commerce_transaction.payment_confirmed` 是资金确认点 → 作为核销兜底触发；退款域事件 `refund.succeeded` 用于释放。 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | 新增模型需 store-scoped + 唯一约束（batch3a 已落）；本批次只读查询需沿用 store 作用域。 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec + FactoryBot；sweeper/订阅者测试用 job spec 与 subscriber spec 惯例（`perform_now` / `SubscriberJob`）。 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ⬜（Phase B 才需要） | 只读端点需 typelize + 契约再生 `generated:check`。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ⬜（Phase B 才需要） | 只读页需导航/面包屑三要素 + 权限矩阵 + `nav-validate`（历史教训：`skip_breadcrumb_derivation` 控制器需手写面包屑）。 |
| `pallastrade-customization` | ✅ 已读 | 决策树优先级：Events（订阅者）用于副作用；结构性改动直接改 core gem 源（本仓库约定）。 |

---

## 需求标题

核销台账运行时加固：并发占用原子化、`reserved` 过期释放、支付确认兜底、退款释放（可选：Admin 只读观测面）。

## 任务类型

功能优化（资金完整性 / 数据一致性）；不改金额与支付执行。

## 需求描述

batch3a 建立了核销台账，但仍有四个运行时缺口：①并发时 `usage_limit` 校验与占用之间无锁，可能超额；②`reserved` 状态没有过期出口；③走 `commerce_transaction.payment_confirmed` 而不走 `order.complete` 的订单不会核销；④退款成功后核销行仍为 committed，名额不回落。本批次把这四处补齐，并（可选）提供运营只读观测面。

## 影响范围（预估）

- 新增：sweeper Job、订阅者、调度条目、（Phase B）API + Admin 只读面。
- 修改：`promotions/redemption/{finalize_order,reserve}.rb`、`promotion_redemption.rb`、`core.rb`（注册）、`sidekiq_schedule.rb`。
- 不改：金额计算、支付/退款执行、storefront。

## 技术方案（初步）

1. `FinalizeOrder` 内 `promotion.with_lock` 中重查 `usage_limit_exceeded?`，多码 `coupon_code.with_lock` 校验；`Reserve` 对 `RecordNotUnique` 重读并支持 released 重试；失败整单回滚。
2. `ExpireSweeperJob`：`state=reserved AND reserved_until < now` 且订单无支付证据/无进行中会话 → `Release(reason: reserved_timeout)`；注册 `*/5 * * * *`。
3. `PromotionRedemptionSubscriber`：订阅 `commerce_transaction.payment_confirmed` → `FinalizeOrder`（幂等）；注册进 `core.rb`。
4. 同订阅者（或独立）订阅 `refund.succeeded` → 全额退款才 Release（`reason: refunded`）。

## 风险点

| 风险 | 等级 | 缓解 |
|---|---|---|
| 并发改动影响下单主链路 | 中 | 三重兜底（行锁 + 唯一约束 + 整单回滚）；幂等测试 + 回归 |
| sweeper 误放有效占用 | 中 | 保守 guarded 判定（复用 StockReservations 思路）+ 只释放无支付证据订单 |
| 退款释放策略不符合财务预期 | 中 | 默认仅全额退款释放，策略写入 PRD/Skill 并可配置 |
| Phase B 引入权限/导航遗漏 | 低 | 复用只读模板 + `nav-validate` + 权限矩阵回归 |

## 决策节点

> ✅ **已确认（2026-09-10，用户「继续」）**：实施范围 **A**（FR-001..006 运行时加固）+ 退款释放策略「**仅全额退款释放**」；Phase B（Admin API/页面只读观测面）不做。
>
> 实施产物：`ExpireSweeperJob`（+ `sidekiq_schedule` 注册）、`Promotions::RedemptionSubscriber`（`commerce_transaction.payment_confirmed` + `refund.succeeded`，注册进 `core/engine.rb`）、`FinalizeOrder` 行锁与限额重查（overshoot 事件）、`Reserve` 复用 released 行（`revive!`）；3 个新 spec + 调度 spec 扩展。
