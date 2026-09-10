# PRD-20260910-promotions-promo-batch3a-redemption-ledger

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-10 |
| 来源 | `豆包梳理业务需求/promotion模块架构-任务拆解.md` 批次3（PR-P4-1/2/4 + PR-P4-8 基础；4b 另行拆分） |
| 分类 | promotions |
| 关联 Skill | pallastrade-promotions、pallastrade-data-model、pallastrade-events-webhooks、pallastrade-payments、pallastrade-testing |
| 关联 PRD | batch1（A0 金额口径 + 契约安全网）、batch2（DiscountProjection 统一投影） |
| 需求类型 | 优化迭代（资金完整性：核销记账与占用语义） |

> **原则**：本批次只做「核销记账 + 占用语义」，**不改动折扣金额计算**（batch1 附录 A 的 `discount_total == eligible 调整之和` 与 batch2 的投影口径保持不动），也不改支付/退款路径。

---

## 1. 背景与目标

### 现状（本轮 6 层搜索已核实）

| # | 现状 | 证据 |
|---|---|---|
| G1 | **多码券在加购物车时即被标记 `used`**，未支付即消耗；弃单需手动 remove 才回退 | `PromotionHandler::Coupon#handle_coupon_code` → `CouponCode#apply_order!`（`promotion_handler/coupon.rb:212`） |
| G2 | **`usage_limit` 无 ledger**：`credits_count` = `Adjustment.eligible.promotion` 的 distinct order 即时统计；`adjusted_credits_count` 再减去本单已计入部分 | `promotion.rb:258-272` |
| G3 | **订单完成时二次占用**：`after_transition to: :complete, do: :use_all_coupon_codes` → `CouponCodesHandler#use_all_codes`，与 G1 职责重叠 | `order/checkout.rb:158`、`order.rb:949` |
| G4 | **取消/支付失败无释放路径**；无 `reserved` 概念，「占用中」与「已核销」不可区分 | `order/checkout.rb:157`（`after_cancel` 不含券释放）；全仓无 redemption 概念 |
| G5 | **无可审计台账**：无法回答「某促销在哪些订单核销、何时、何种码」 | `backend/db/schema.rb` 无 redemption 表；6 层搜索零命中 |

### 目标

新增 `pallastrade_promotion_redemptions` 核销台账（`reserved / committed / released`）+ `Reserve / Commit / Release` 服务，把占用语义从「**apply 即消耗**」迁移到「**下单核销**」，`usage_limit` 改读 ledger，并提供历史回填与不变量测试。

### 成功指标

- 同一 `(promotion, order)` 仅一条 active 核销；同一一次性码不可被两单核销（4a 保证唯一约束层，并发竞争由 4b 压测）。
- `usage_limit_exceeded?` 判定完全来自 ledger（committed 计数），与 `credits_count` 口径差异有测试固化。
- 取消订单 → 对应核销释放、多码回退 `unused`。
- 存量回填幂等（可重复执行、`--dry-run` 不写库）。
- batch1/batch2 全部回归绿（金额与投影行为零变化）。

---

## 2. 用户故事 / 场景

- **顾客**：把码填进购物车试算不消耗码；未支付放弃/取消后码回到可用；达到上限时得到明确提示（不是「神秘失败」）。
- **运营**：能从台账导出某券的核销记录（本期先落数据；Admin 只读页在 4b）。
- **风控/财务**：账实一致 —— 已核销数 = ledger committed 数 = 促销实际使用数。
- 场景覆盖：单码 / 多码 / 自动促销；同订单重复提交；`apply → remove → re-apply`；未支付取消；已支付后取消（4a 只记录事实，释放策略沿既有取消语义）；历史订单回填。

---

## 3. 关键决策（A0-2 / A0-3，待用户确认）

| # | 决策项 | 建议方案 | 备选 / 备注 |
|---|---|---|---|
| D1 | 核销唯一键 | `UNIQUE(promotion_id, order_id)`；多码附加 `UNIQUE(coupon_code_id) WHERE state <> 'released'` | 备选：以 `(promotion_id, order_id, coupon_code_id)` 三列唯一（弱，释放后无法复用同码） |
| D2 | 状态机 | `reserved → committed`；`reserved/committed → released`；带 `release_reason`、`reserved_until`、`committed_at`、`released_at` | `committed` 的自动释放（退款）留待 4b/退款域，本期不做 |
| D3 | **4a 运行时刻** | **下单完成（`order.complete`）短事务内 `Reserve + Commit` 原子完成**；`Release` 挂 `order.canceled`；`reserved` 态建模但 4a 不产生悬挂行（超时/并发留给 4b） | 备选 B：4a 只 Reserve，Commit 由 `commerce_transaction.payment_confirmed` 订阅者（4b）→ 会出现长期 reserved 悬挂，需 4b 的 sweeper 才安全；备选 C：apply 时 Reserve（**拒绝**：违背「购物车不落 reserved」且放大弃单占用） |
| D4 | `usage_limit` 读口径 | 改读 `committed` 计数（`Promotion#usage_limit_exceeded?`）；`credits_count` 保留但标注 deprecated（值改为委托 ledger） | 兼容：外部调用 `credits_count` 不报错，语义由「调整统计」变为「已核销计数」 |
| D5 | 多码占用时机 | `CouponCode#apply_order!` 不再由购物车 apply 触发；改由核销服务在 `order.complete` 时原子占用；购物车 remove 不再回退 state（因为未提前占用） | `CouponCode#remove_from_order` 保留，供释放路径调用 |
| D6 | 存量回填 | rake `pallastrade:promotions:backfill_redemptions`（幂等，`dry_run=true` 默认）；来源：`coupon_codes.used` 关联订单 + 有 eligible 促销调整的订单 | 回填只写 ledger，不改任何历史金额 |
| D7 | 4b 范围（明确不在本期） | 并发抢最后名额（锁/NOWAIT/重试）、`reserved_until` 过期 sweeper、显式 `commerce_transaction.*` 事件挂接、Admin 只读核销页、退款释放 | 本期先保证 4a 闭环与不变量 |

---

## 4. 功能需求（FR）

### A. 模型与迁移
- FR-001 新表 `pallastrade_promotion_redemptions`：`store_id`、`promotion_id`、`order_id`、`user_id?`、`coupon_code_id?`、`state`、`amount?`、`currency?`、`reserved_at`、`committed_at?`、`released_at?`、`release_reason?`、`reserved_until?`、timestamps；索引：唯一 `(promotion_id, order_id)`、部分唯一 `(coupon_code_id) WHERE state <> 'released'`、查询索引 `(order_id)`、`(promotion_id, state)`、`(store_id, state)`。
- FR-002 `PallasTrade::PromotionRedemption` 模型：`belongs_to :promotion/:order/:store/:user(optional)/:coupon_code(optional)`；`enum state: reserved/committed/released`；业务校验；`has_prefix_id :redemption`（为 4b 只读 API 预留）；scope `active`（reserved+committed）。
- FR-003 关联：`Store has_many :promotion_redemptions`、`Promotion has_many :promotion_redemptions`（+ `has_many :redemption_orders, through: :promotion_redemptions, source: :order`）、`Order has_many :promotion_redemptions`。

### B. 服务层（`PallasTrade::Promotions::Redemption::*`）
- FR-004 `Reserve.call(order:, promotion:, coupon_code: nil)`：单订单内幂等创建 `reserved` 行；已存在 active 行 → 返回既有行；唯一约束冲突 → 抛出并回滚整笔事务。
- FR-005 `Commit.call(redemption)`：`reserved → committed`（幂等；已 committed 直接返回；released 行抛错）。
- FR-006 `Release.call(redemption, reason:)`：`reserved|committed → released`（幂等；写 `released_at` + `release_reason`）。
- FR-007 `FinalizeOrder.call(order)`（下单核销入口）：对订单上每个促销 `Reserve + Commit`（同事务），多码促销同时原子占用 `CouponCode`（`unused → used` + 关联 order）；重复调用幂等；发布 `promotion.redemption_committed` 事件。
- FR-008 `ReleaseOrder.call(order, reason:)`：释放订单全部 active 核销；多码释放 `CouponCode`（`used → unused`、解除 order 关联）；发布 `promotion.redemption_released` 事件。

### C. 口径与调用点切换
- FR-009 `Promotion#usage_limit_exceeded?` 改读 committed 计数（`promotion_redemptions.committed.where(promotion_id:).count >= usage_limit`），不再依赖 `Adjustment` 统计；`credits_count` 保留为委托方法并标注 deprecated 注释。
- FR-010 `CouponCode#apply_order! / remove_from_order` 语义调整：不再由 `PromotionHandler::Coupon` 的 apply/remove 触发（删除提前占用）；由 FR-007/FR-008 调用。`PromotionHandler::Coupon` 保留「码已被核销/已达上限」的校验与错误码。
- FR-011 `Order::Checkout`：`after_transition to: :complete` 的 `use_all_coupon_codes` 替换为 `record_promotion_redemptions`（调用 FR-007）；`Order#use_all_coupon_codes` 保留为兼容包装（内部走 FinalizeOrder）。
- FR-012 `Order` 取消路径挂载 FR-008（`after_cancel` 内调用，或在 `after_transition to: :canceled` 增加 tick）。

### D. 回填与可观测
- FR-013 rake `pallastrade:promotions:backfill_redemptions[dry_run]`：幂等；统计「将创建 / 已存在 / 跳过」；`dry_run=true` 不写库。
- FR-014 核销事件发布：`promotion.redemption_committed` / `promotion.redemption_released`（4b 接 webhook/审计；本期先发布并测试 payload）。

---

## 5. 非功能需求

- **资金安全**：不触碰折扣金额、支付、退款计算；只新增占用与记账。
- **幂等**：四个服务与 rake 均可重复执行且结果稳定。
- **兼容**：`credits_count`、`use_all_coupon_codes`、`CouponCode#apply_order!` 方法签名不变（语义变更点写入 SKILL 与 PRD §11）。
- **性能**：FinalizeOrder 走批量查询（`order.adjustments.promotion` 一次加载）；单订单新增写 ≤ `促销数 + 1`。
- **迁移安全**：迁移仅建表/索引，不删数据；回填单独执行（默认 dry-run）。

---

## 6. 验收标准（AC）

| AC | 对应 | 判定 |
|---|---|---|
| AC-001 | FR-001/002 | 迁移建表成功；唯一约束 `(promotion_id, order_id)` 与部分唯一 `(coupon_code_id)` 生效（违反时抛错） |
| AC-002 | FR-004 | 同一订单+促销重复 Reserve 仅一行（幂等） |
| AC-003 | FR-005/006 | Commit/Release 状态流转正确；非法流转抛错；重复调用幂等 |
| AC-004 | FR-007/G1 | **购物车 apply 不再消耗多码**：apply 后 `CouponCode` 仍 `unused`、无 redemption 行 |
| AC-005 | FR-007/G3 | `order.complete` 后：每个促销一行 committed；多码变为 `used` 且关联本单；无重复行 |
| AC-006 | FR-008/G4 | `order.canceled` 后：active 核销全部 released（含 reason）；多码回退 `unused` 且解除关联 |
| AC-007 | FR-009/G2 | `usage_limit_exceeded?` 与 ledger 一致：N 张已核销订单后第 N+1 单被拒；与 `credits_count` 差值有测试说明 |
| AC-008 | FR-013 | 回填 dry-run 不写库；实跑幂等（二次执行为 0 新增）；回填后 usage_limit 判定与回填前**历史事实**一致 |
| AC-009 | FR-011/012 | `Order::Checkout` 完成/取消路径挂接正确（模型层 spec 覆盖 state machine 过渡） |
| AC-010 | FR-014 | 事件 `promotion.redemption_committed/released` 发布一次且 payload 含 order/promotion/amount |
| AC-011 | §5 兼容 | 批次1 契约（I1..I6）与批次2 投影 parity 全绿（金额/投影零变化） |
| AC-012 | §5 幂等 | `apply → remove → re-apply → complete` 全流程无重复核销、金额与核销均正确 |

---

## 7. 跨层搜索记录（6 层，本轮实测）

| 层 | 路径 | 关键词 | 找到 | 满足？ |
|---|---|---|---|---|
| App | `backend/app/` | redemption / coupon / promotion | 仅生成的 TS 类型（`app/javascript/types/serializers/*`） | 无宿主逻辑，不需改 |
| Core | `pallastrade_core/app/` | redemption / credits_count / usage_limit / apply_order! / use_all_codes | `Promotion#credits_count/adjusted_credits_count/usage_limit_exceeded?`、`CouponCode#apply_order!/remove_from_order`、`PromotionHandler::Coupon#apply/remove`、`Order#use_all_coupon_codes`、`Order::Checkout` 状态机、`CouponCodes::CouponCodesHandler` | **主改动区**（新增 ledger + 服务 + 口径切换） |
| API | `pallastrade_api/app/` | coupon / usage_limit | admin `coupon_codes_controller`（只读列表）、store `carts/discount_codes_controller`（apply/remove）、`admin/promotion_serializer`（usage 统计字段） | 4a 不改 payload；4b 加只读核销端点 |
| Admin | `pallastrade_admin/app/` | coupon / credits / usage_limit | `coupon_codes` 视图、`orders/order_promotions_controller`（后台手动加券）、`promotions/_usage_limit.html.erb`（`coupon_codes.used.count`） | 4a 不改 UI；4b 评估读数口径 |
| Storefront | `storefront/src/` | coupon / redemption | `app/api/checkout/coupon/route.ts`、`components/checkout/CouponCode.tsx`、`UnifiedCheckout.tsx` | 无核销概念；行为变化（apply 不再消耗）对前端透明 |
| Platform | `platform/packages/` | coupon / promotion | SDK 类型与文档（`Promotion`、`discountCodes.apply`） | 无改动 |

**结论**：能力全部落在 core gem；本批次新建迁移 + 模型 + 4 个服务 + rake + specs，改动 5 个既有文件（`promotion.rb`、`coupon_code.rb`、`promotion_handler/coupon.rb`、`order/checkout.rb`、`order.rb`）。

---

## 8. 技术影响

- **新增**：`db/migrate/*_create_pallastrade_promotion_redemptions.rb`、`app/models/pallastrade/promotion_redemption.rb`、`app/services/pallastrade/promotions/redemption/{reserve,commit,release,finalize_order,release_order}.rb`、`lib/tasks/promotions.rake`（追加回填任务）、specs。
- **修改**：`promotion.rb`（usage 口径）、`coupon_code.rb`（占用调用点）、`promotion_handler/coupon.rb`（删除提前占用）、`order/checkout.rb`（complete/cancel 挂接）、`order.rb`（`use_all_coupon_codes` 兼容包装）。
- **不涉及**：金额计算（Calculator/Adjuster）、API payload、Admin UI、支付/退款、storefront。
- **风险**：历史数据口径变化（`credits_count` 语义迁移）→ 用回填 + 测试固化；下单路径新增写入 → 幂等 + 唯一约束兜底。

---

## 9. 测试计划

| 文件 | 覆盖 |
|---|---|
| `backend/spec/models/pallastrade/promotion_redemption_spec.rb`（新） | AC-001/002/003（模型校验、唯一约束、状态流转） |
| `backend/spec/services/pallastrade/promotions/redemption_spec.rb`（新） | AC-004..007、AC-012（apply 不消耗 / complete 核销 / cancel 释放 / usage_limit 口径 / 全流程幂等） |
| `backend/spec/lib/pallastrade/tasks/backfill_redemptions_spec.rb`（新） | AC-008（dry-run、幂等） |
| `backend/spec/models/pallastrade/order_checkout_redemption_spec.rb`（新） | AC-009（state machine 挂接） |
| `backend/spec/services/pallastrade/promotions/promotion_contract_spec.rb`（回归） | AC-011（批次1 I1..I6） |
| `backend/spec/services/pallastrade/promotions/projection_parity_spec.rb`（回归） | AC-011（批次2 parity） |

运行：容器内 rspec（`docker exec pallastrade-web-1 ... bundle exec rspec <files>`）；`harness check --profile quick`；迁移在 dev 容器执行并核对 `schema.rb`。

---

## 10. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-promotions/SKILL.md`：新增「Redemption ledger」条目（apply 不消耗 / complete 核销 / cancel 释放 / usage_limit 读 ledger / 回填命令）。
- [x] `ai/skills/pallastrade-data-model/SKILL.md`：新增「Promotion redemptions (ledger)」关系与状态说明。
- [x] `harness/scenarios/scenarios.json`：新增 GS-083（redemption ledger 不变量）。
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态（done）。
- [x] 接口文档：本期无 API 变化 → 无需 `generated:check`（4b 加只读端点时再同步）。

---

## 11. 兼容与迁移说明（消费方必读）

| 变化 | 变更前 | 变更后 | 影响 |
|---|---|---|---|
| 多码占用时机 | 购物车 apply 即 `unused → used` | `order.complete` 核销时占用 | 弃单不再消耗码；前端无感（码在 apply 时仍可用于试算） |
| `Promotion#credits_count` | eligible 调整的 distinct order 数 | 委托 ledger `committed` 计数（deprecated 注释） | 内部/外部读取语义变化：旧口径只统计「有 eligible 调整的订单」，新口径统计「已核销记录」；回填保证历史一致 |
| `CouponCode#apply_order!` | apply 时调用 | 仅核销服务调用 | 直接调用方（若有）行为不变，但不应再由购物车路径触发 |
| `Order#use_all_coupon_codes` | 直接标记全部码 used | 兼容包装 → `FinalizeOrder`（幂等） | 重复调用不再产生副作用 |
| 新增表/事件 | — | `pallastrade_promotion_redemptions` + `promotion.redemption_*` 事件 | additive |
| `CouponCode#remove_from_order` | batch1 提交误将方法名写成 `remove_from_orde`（缺 `r`）→ 多码券移除 NoMethodError | 已修正为 `remove_from_order`（本批次 AC-013 回归拦住） | bugfix：调用方无需改动 |

---

## 12. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-10 | 0.1 | 初稿（批次3a：redemption ledger 建模 + 单订单内事务；含 D1..D7 决策待确认） | AI |
| 2026-09-10 | 0.2 | approved：用户确认 D1..D7 全部建议方案；核销触发点为 `order.complete` 短事务内 Reserve+Commit（D3 建议项） | AI |
| 2026-09-10 | 1.0 | done：迁移+模型+4 服务+回填 rake 落地；4 个新 spec（22 例）全绿；批次1/2 回归 68 例 0 失败；顺带修复 batch1 遗留 `remove_from_orde` 拼写缺陷；Skill/场景库/PRD 索引同步 | AI |
