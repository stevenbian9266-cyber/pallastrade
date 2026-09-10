# PRD-20260910-promotions-promo-batch3b-redemption-hardening

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-10 |
| 来源 | `豆包梳理业务需求/promotion模块架构-任务拆解.md` 批次3 后半（PR-P4-3/5/6/7/8 的运行时与观测部分）；承接 batch3a（PRD-20260910-promotions-promo-batch3a-redemption-ledger） |
| 分类 | promotions |
| 关联 Skill | pallastrade-promotions、pallastrade-events-webhooks、pallastrade-payments、pallastrade-data-model、pallastrade-testing（若选 Phase B 另含 pallastrade-api-v3 / pallastrade-admin） |
| 关联 PRD | batch3a（ledger 建模与下单内事务，已 done） |
| 需求类型 | 优化迭代（资金完整性：并发/超时/事件/退款释放） |

> **原则**：batch3a 已把「占用语义」迁到 ledger；本批次只补 **运行时健壮性**（并发、超时、支付/退款事件挂接）与（可选）**只读可观测面**。不改折扣金额计算，不改 API payload（Phase B 为纯新增只读端点）。

---

## 1. 背景与现状（batch3a 遗留）

| # | 遗留点 | 现状证据 |
|---|---|---|
| G1 | **并发未加固**：`Reserve/Commit` 只靠 `(promotion_id, order_id)` 唯一约束兜底；`usage_limit` 判定与占用之间无锁，两单可同时通过校验 | `promotion_redemption.rb`（唯一索引）+ `promotion.rb#usage_limit_exceeded?`（读 committed 计数，无锁） |
| G2 | **`reserved` 无出口**：batch3a 只建模了 `reserved_until`，没有 sweeper；一旦 4b/未来产生悬挂 reserved 行，`usage_limit` 会永久占用 | `PromotionRedemption::ACTIVE_STATES` 含 reserved；无对应 Job |
| G3 | **支付确认未显式挂接**：Commit 只在 `order.complete` 状态机内完成；若订单经 `commerce_transaction.payment_confirmed` 路径（组合支付/异步回调）而未走 order.complete，则该单核销缺失 | `commerce_transaction.rb`（`confirm_payment` 事件 + `publishes_lifecycle_events`）；无订阅者 |
| G4 | **退款不释放**：`refund.succeeded` 事件已存在（`refund_succeeded_subscriber.rb`），但核销行保持 committed → 退款后 usage 仍被占用 | 现有 `Refund` 事件发布点（`publish_event('refund.succeeded')`） |
| G5（可选 Phase B） | **无只读观测面**：运营无法查看核销台账（Rails Admin / Admin API 均无入口） | `pallastrade_admin` coupon_codes 只读页可作模板；`api/v3/admin/coupon_codes_controller`（ResourceController 只读）可作模板 |

---

## 2. 目标与成功指标

- 并发下**同一码/同一名额只被核销一次**（先到先得），失败方得到确定性结果（回滚/明确错误码），无半占用。
- `reserved_until` 过期行可被周期性安全释放（幂等、保守：有支付证据的订单不释放）。
- 支付确认路径（`commerce_transaction.payment_confirmed`）**幂等兜底**核销，消除「收了钱没记核销」。
- 全额退款释放核销（部分退款策略显式定义），usage 口径随释放回落。
- Phase B（可选）：Admin API `GET /api/v3/admin/promotion_redemptions` + Rails Admin 只读列表，受现有权限体系约束。

---

## 3. 范围决策（已确认：选项 A）

> ✅ 2026-09-10 用户连续确认「继续」→ 按推荐选项 **A**（FR-001..006 运行时加固，不含只读 UI）+ 退款释放策略「**仅全额退款释放**」实施。Phase B（FR-007/008）保留在本 PRD 但标记为 **未实施**，留待后续批次。

| 选项 | 内容 | 适用 |
|---|---|---|
| **A（已选）** | Phase A 全部：FR-001..006（并发、sweeper、支付事件兜底、退款释放、注册与观测）| 资金完整性优先，UI 另行排期 |
| B | Phase A + Phase B（FR-007 Admin API 只读端点、FR-008 Admin 只读页 + 权限/导航）— **本期未做** | 需要运营可见性 |
| C | 仅 FR-001/002/003（并发 + 超时 + 支付兜底） | 最小改动 |

---

## 4. 功能需求（FR）

### Phase A — 运行时健壮性（选项 A/B/C 共同部分）

- **FR-001 并发加固（占用原子化）**
  - `FinalizeOrder` 对每个促销：`promotion.with_lock` 内**重新判定** `usage_limit_exceeded?`（基于 ledger），超限则跳过该促销并记录（不产生行）；
  - 多码：`coupon_code.with_lock` 内校验 `state == 'unused' || order_id == 本单`，再 `apply_order!`；
  - `Reserve` 遇 `RecordNotUnique` 时：重读既有行；若既有行为 `released`（竞争后释放）→ 重试一次创建；
  - 任何失败**整单回滚**（下单失败优于半占用），错误统一为可读原因（复用 `coupon_code_max_usage` 语义）。
- **FR-002 `reserved` 过期 sweeper**
  - 新增 `PallasTrade::Promotions::Redemption::ExpireSweeperJob`（`PallasTrade::BaseJob`）；
  - 处理条件：`state = reserved AND reserved_until < now`，且**订单无支付证据/无进行中会话**（复用 `StockReservations::ExpireJob` 的 guarded 订单判定思路：`payment_total > 0 / completed_at / state in paid|complete / active PaymentSession / active CommerceTransaction`）；
  - 逐行 `with_lock` + 服务 Release（`reason: 'reserved_timeout'`），幂等；
  - 注册到 `backend/config/sidekiq_schedule.rb`（`*/5 * * * *`，默认保守）。
- **FR-003 支付确认兜底（事件挂接）**
  - 新增订阅者 `PallasTrade::PromotionRedemptionSubscriber`（gem `app/subscribers/`，注册进 `pallastrade_core/lib/pallastrade/core.rb` 的订阅者列表）；
  - 订阅 `commerce_transaction.payment_confirmed`：对 txn 关联订单执行 `FinalizeOrder`（幂等，已核销则无操作）；
  - 异步默认（`async: true`）——核销不是资金前置条件，失败可重放；如实现发现时序要求则改为同步并记录理由。
- **FR-004 退款释放**
  - 订阅 `refund.succeeded`：定位 Refund 对应的 Order（及其成员订单，若为组合退款），对 active redemption 执行 Release（`reason: 'refunded'`）；
  - 策略（需在实现中显式）：**默认仅当该订单被全额退款**（`order.payment_total - refunded_total <= 0` 或退款覆盖订单总额）才释放；部分退款保留 committed 并记录（避免滥发/滥用）；
  - 幂等：重复事件不产生副作用。
- **FR-005 观测与审计**
  - 核销事件 payload 补充 `state`/`release_reason` 已有；新增 sweeper 每次运行输出统计日志（扫描/释放数）；
  - `PromotionRedemption` 暴露 `active`/`committed`/`reserved` scope 供运维查询（已有）。
- **FR-006 存量 reserved 行的窗口补齐**
  - 不新增迁移/回填：sweeper 对 `reserved_until IS NULL` 的旧行使用**宽限窗口**（自 `reserved_at` 起 `ExpireSweeperJob::DEFAULT_GRACE = 2.hours`），防止历史悬挂行永久占用；
  - `Reserve` 新建行统一写入 `reserved_until = now + Reserve::DEFAULT_RESERVED_WINDOW`（2h），使 TTL 语义可预期。

### Phase B — 只读可观测面（选项 B，**本期未实施**）

> 以下 FR 仅作后续批次输入，本批次不落地、也无对应 AC。

- **FR-007 Admin API 只读端点**：`GET /api/v3/admin/promotion_redemptions`（列表，支持 `order_id`/`promotion_id`/`state` 过滤 + 分页），`GET /api/v3/admin/promotion_redemptions/:id`；沿用 `ResourceController` 只读子类模式（参考 `admin/coupon_codes_controller`）；新增 serializer（typelize）；权限沿用 promotions 读取能力。
- **FR-008 Rails Admin 只读页**：`pallastrade_admin` 下 `promotion_redemptions#index`（表格：订单/促销/码/状态/金额/时间），导航项与面包屑遵循 admin 规范；权限注册进现有 promotions 能力集（不新起 registry）；`nav-validate` 通过。

---

## 5. 非功能需求

- **幂等**：sweeper/订阅者/服务全部可重放。
- **保守自动化**（对齐现有 RecoverSweeper 风格）：只做确定性释放，不做金额回滚。
- **性能**：sweeper 批量处理（batch_size 1_000）；`FinalizeOrder` 仍为有界查询（batch3a 已保证）。
- **兼容**：不改 API payload（Phase B 仅新增）；不改金额/支付/退款计算。
- **安全**：管理员仅可见本 store 数据（store-scoped）。

---

## 6. 验收标准（AC）

| AC | 对应 | 判定 |
|---|---|---|
| AC-001 | FR-001 | 并发/超限场景：`usage_limit=1` 时第二单 `FinalizeOrder` 不产生核销行且给出确定性结果；多码被占时第二单失败且不落半占用 |
| AC-002 | FR-001 | `RecordNotUnique` 竞争路径：模拟“读到 released 既有行”→ 重试创建成功（一次） |
| AC-003 | FR-002 | sweeper：过期 reserved → released(reserved_timeout)；未过期不动；有支付证据订单不释放；重复执行幂等 |
| AC-004 | FR-002 | sweeper 注册在 `sidekiq_schedule.rb` 且可被 railtie 加载（配置断言） |
| AC-005 | FR-003 | `commerce_transaction.payment_confirmed` → 订单补写 committed（幂等：重复事件仍 1 行） |
| AC-006 | FR-004 | 全额退款释放（reason=refunded）；部分退款不释放；重复事件幂等 |
| AC-007 | FR-005 | sweeper 统计日志输出（`output(...).to_stdout` 断言） |
| AC-008 | FR-006 | `reserved_until` 历史行为空/补齐逻辑有测试 |
| PHASE-B-1（未实施） | FR-007 | Admin API 列表/过滤/分页 + 权限拒绝场景 |
| PHASE-B-2（未实施） | FR-008 | Admin 页可渲染 + 导航/权限 + `nav-validate` 通过 |
| AC-011 | §5 回归 | batch3a（22 例）与 batch1/2（46 例）全绿；本批次新增 17 例全绿；未改动金额计算 |

---

## 7. 跨层搜索记录（6 层，本轮实测）

| 层 | 路径 | 关键词 | 找到 | 满足？ |
|---|---|---|---|---|
| App | `backend/app/` | subscriber | 无 `app/subscribers`（订阅者在 gem 内） | 无需改 |
| Core | `pallastrade_core/app/`、`lib/` | redemption / sweeper / payment_confirmed / refund.succeeded / subscribers | batch3a 的 `PromotionRedemption` + 5 服务；`StockReservations::ExpireJob`（sweeper 模板）；`Transactions::RecoverSweeperJob`；`core.rb` 订阅者注册列表；`refund.succeeded` 发布点 | **主改动区**（新增 Job/订阅者 + 并发加固） |
| API | `pallastrade_api/app/controllers/` | admin read-only | `admin/coupon_codes_controller`（ResourceController 只读模板）+ routes | Phase B 参考 |
| Admin | `pallastrade_admin/app/` | index/nav/权限 | `coupon_codes` 只读页；`PermissionRegistry`（`config/initializers/pallastrade_permission_registry.rb`）+ `PermissionSets::PromotionManagement` | Phase B 参考 |
| Storefront | `storefront/src/` | redemption | 无消费点 | 无改动 |
| Platform | `platform/packages/` | redemption | 无类型/端点 | Phase B 若加 API 需再生契约 |

---

## 8. 技术影响

- **新增**：`app/jobs/pallastrade/promotions/redemption/expire_sweeper_job.rb`、`app/subscribers/promotion_redemption_subscriber.rb`（+ core.rb 注册）、`config/sidekiq_schedule.rb` 条目、（Phase B）API controller/serializer/routes + Admin controller/views/nav。
- **修改**：`promotions/redemption/finalize_order.rb`（锁与重查）、`reserve.rb`（重试）、`promotion.rb`（如需锁内判定辅助）、`promotion_redemption.rb`（scope/工具方法）。
- **不涉及**：金额计算、支付执行、退款计算、storefront。
- **风险**：并发改动影响下单路径 → 用「锁 + 唯一约束 + 整单回滚」三重兜底，且以幂等测试覆盖；退款释放策略若拿捏不当会错放名额 → 默认仅全额退款释放并可配置。

---

## 9. 测试计划

| 文件 | 覆盖 |
|---|---|
| `backend/spec/services/pallastrade/promotions/redemption_concurrency_spec.rb`（新） | AC-001/002 |
| `backend/spec/jobs/pallastrade/promotions/redemption_expire_sweeper_job_spec.rb`（新） | AC-003/004/007 |
| `backend/spec/subscribers/pallastrade/promotion_redemption_subscriber_spec.rb`（新） | AC-005/006 |
| `backend/spec/lib/pallastrade/sidekiq_schedule_spec.rb` 或既有等价 spec | AC-004 |
| Phase B（未实施）`spec/requests/api/v3/admin/promotion_redemptions_spec.rb`、`spec/requests/pallastrade/admin/promotion_redemptions_spec.rb` | PHASE-B-1/2 |
| 回归：batch3a 4 个 spec + batch1/2 契约与 parity | AC-011 |

运行：容器 rspec；`harness check --profile quick`；（Phase B）`nav-validate` + `generated:check`。

---

## 10. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-promotions/SKILL.md`：并发/超时/事件/退款释放语义（含「仅全额退款释放」策略）。
- [x] `harness/scenarios/scenarios.json`：GS-084（核销加固）。
- [x] `docs/prd/README.md` + 本 PRD 状态（done）。
- [x] `ai/skills/pallastrade-events-webhooks/SKILL.md`：无需更新（沿用既有订阅者注册与 `on` 路由模式，未引入新模式）—— 已评估。
- [x] Phase B：本期未实施 → 无 API/Admin 文档改动。

---

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-10 | 0.1 | 初稿（批次3b：并发/超时/支付兜底/退款释放 + 可选只读面；含范围选项 A/B/C 待确认） | AI |
| 2026-09-10 | 1.0 | done：范围 A 落地（FR-001..006）；新 spec 17 例全绿，batch1/2/3a 回归共 85 例 0 失败；Phase B 未实施 | AI |
