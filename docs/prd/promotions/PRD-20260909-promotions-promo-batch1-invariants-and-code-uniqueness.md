# PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-09 |
| 确认 | 2026-09-10 用户“认可”（含两决策点：存量重复处置策略、OrderPromotion#amount 偏差留 Phase1/2） |
| 来源 | 实施批次1：口径锁定（A0-1..5）+ Invariant 契约测试（P0-1..7）+ normalized_code/优惠码唯一约束（P3-1..4） |
| 分类 | promotions（自动判定，命中 2 关键词） |
| 关联 Skill | pallastrade-promotions、pallastrade-data-model、pallastrade-testing |
| 关联 REQ | （实施时回填） |
| 关联 PRD | N/A（全新；源自 `豆包梳理业务需求/promotion模块架构.md` 批次1 拆解） |
| 需求类型 | 优化迭代（含资金/模型/迁移，规则多，验收要求详尽） |

> 范围：本文档只覆盖**批次1**。DiscountProjection/Redemption/快照/分摊等为后续批次，不在本 PRD 实施，但其口径在本 PRD 附录 A 中被先行锁定作为基线。

---

## 1. 背景与目标

- **一句话需求原文**：实施促销收敛批次1 —— A0 口径锁定（5 项决策）+ P0 Invariant 契约测试（7 项）+ P3 normalized_code/优惠码唯一约束（4 项），PRD 须完整（逻辑/规则/测试验收详细）。
- **背景**：
  - 审计（`REVIEW-20260908-promotions-module-audit.md`）确认：`Order#discounts`（order_promotions）与 `CheckoutView#discounts`（order 级 adjustments）口径不一致（Finding D）；`promotions.code` 无唯一约束、`with_coupon_code(...).last` 命中序不确定（Finding E）；促销域测试覆盖薄弱（Finding F）。
  - 促销直接改变 payable amount，属资金面；任何金额口径、码唯一性、并发占用必须先有**可执行契约**再动代码。
- **目标**：
  1. 把现状金额/投影口径**显式化并锁定**（形成基线，供后续 Projection/Redemption 批次复用）。
  2. 建立**契约测试安全网**，把架构方案 §24 Invariants 中"当前应成立"的部分固化为回归。
  3. 修 `promotions.code` 重复隐患（单码 store 级唯一）+ 消除 lookup 不确定，并保证不破坏存量数据与多码路径。
- **成功指标**：
  - P0 契约测试全绿并纳入 `harness check --profile quick`（Ruby 变更最小验证）。
  - 单码促销 store 内重复创建被 DB 唯一索引与模型校验双重阻止（返回可读错误）。
  - `with_coupon_code` 对合法数据恒返回唯一确定结果（不再 `.last` 碰运气）。
  - 存量重复数据经一次性迁移处置后可建唯一索引，且**不删除任何被订单使用过的促销**。

---

## 2. 用户故事 / 场景

- 作为**运营**，我希望不能在同一店铺创建两个相同优惠码的促销，以免顾客用码命中不确定。
- 作为**开发者/QA**，我希望金额口径与促销计算有契约测试，避免后续重构悄悄改变优惠金额。
- 作为**顾客**，我希望同一次购物车重算/重复移除优惠码，金额结果稳定一致。

### 场景清单
- 正常：创建单码促销 `SUMMER20` → 再创建同码促销被拒，提示"该优惠码已在本店铺使用"。
- 正常：同码但大小写/空格不同（`summer20 ` / `SUMMER20` / ` Summer20`）视为同一码。
- 正常：多码促销（multi_codes）与自动促销（automatic）不受单码唯一约束影响（code 为空）。
- 边界：历史已存在两个同码促销 → 迁移按策略处置（保留下单用过的，其次保留最新）且不删除使用记录。
- 边界：一个单码与某多码生成的 CouponCode 撞码 → 应用层确定性优先级 + 生成期校验阻止新增撞码。
- 异常：DB 并发同时创建同码 → 唯一索引兜底抛异常（模型校验先行、DB 兜底）。
- 异常：重复调用 remove/apply → 幂等，金额不变（契约测试覆盖）。

---

## 3. 功能需求（FR）

### 3.1 A0 口径与决策（产物=规范性定义与决策记录，写入附录 A/B）

- **FR-A0-1**：锁定"优惠金额事实口径"：`Order#discount_total == Order#promo_total` 的精确定义（三档聚合 + eligible 规则 + tie-break），写入 PRD 附录 A 并作为 P0 契约测试的规范来源。
- **FR-A0-2**：锁定 `DiscountProjection` 输出必须满足的契约：`SUM(discounts[].amount) == discount_total`、含 `breakdown{item,order,shipping}`；并**记录现状偏差**：`OrderPromotion#amount` 未过滤 `eligible`（当同 adjustable 存在多个竞争促销时可能 ≠ discount_total）——本批次不修（Phase 1/2 修），仅以测试暴露。
- **FR-A0-3**：锁定 Coupon 模式×所有权×核销键矩阵（single_code / multi_codes / 预留 user_grant）；明确单码唯一性范围 = store 内；多码 `CouponCode` 维持全局唯一（单店部署，跨店撞码无现实路径）；user_grant 属后续批次。
- **FR-A0-4**：锁定 Redemption 相关边界（不实施）：购物车不消耗 usage；commit 点=订单成交/支付完成状态（Phase 4 细化）；本批次仅记录，不在迁移中引入 reserved 语义。
- **FR-A0-5**：锁定迁移语义：促销码归一化= trim + 全小写（`normalizes :code` 已做 squish/presence，`downcase_code` 已做 downcase.strip）；唯一性用 **DB 函数索引** 表达 `UNIQUE(store_id, lower(btrim(code)))`（不加新列、不动既有读取路径）。

### 3.2 P0 Invariant 契约测试（测试套件）

- **FR-P0-1**：建立促销契约测试目录约定与基架（复用 core testing_support 的 promotion factories；`# PRD-... AC-...` 标注）。
- **FR-P0-2（I1）**：`discount_total == Σ eligible 促销调整金额（order+line+shipment 三档，open 且 eligible:true）` —— 在 recalc 后对 coupon/automatic/FreeShipping/行级/整单/组合场景断言。
- **FR-P0-3（I2）**：重算确定性：相同输入（同 line items/码/规则）连续两次 `update_with_updater!`/Recalculate 结果（item/discount/tax/total）一致。
- **FR-P0-4（I3）**：优惠码移除幂等：连续两次 remove 同一码，金额/order_promotions/调整与一次移除一致且不报错。
- **FR-P0-5（I4/best-per-adjustable）**：每个 adjustable（order/line_item/shipment）最多一条 `eligible:true` 的促销调整；两条等额促销并存时择优 tie-break = 最新（created_at DESC, id DESC）。
- **FR-P0-6（I5）**：usage/调整不把订单打折为负：CreateAdjustment 金额封顶于 `order_total`（compute_amount min 逻辑）场景断言。
- **FR-P0-7（I6/暴露型）**：契约测试记录 Cart discounts 口径现状（order_promotions#amount 未过滤 eligible 的行为），当与 discount_total 不一致时**显式断言差异存在或不存在**并打标，作为 Phase 1/2 修复基线（允许用 `pending`/tag 管理，避免 CI 假绿假红）。

### 3.3 P3 优惠码唯一约束与确定性查找

- **FR-P3-1**：单码促销唯一性：Promotion 模型新增 store 级 code 唯一校验（`coupon_code? && !multi_codes?` 时），错误信息 i18n 可读；DB 增加函数唯一索引 `(store_id, lower(btrim(code))) WHERE code IS NOT NULL`。
- **FR-P3-2**：存量重复处置迁移：数据检查任务列出重复（按 store+normalize(code) 分组）；处置策略：优先保留"被订单使用过(order_promotions>0)"者；其次保留最新(created_at DESC,id DESC)；多余重复者：若未使用 → 软处置（改名加后缀 `-dup-<n>` 使可重建唯一索引）；若被使用 → 阻断迁移并输出清单由人工决策。**绝不 delete 使用过的促销。**
- **FR-P3-3**：`with_coupon_code` 确定性：单码命中优先于多码 CouponCode 命中；同一来源命中多条（仅应发生在历史脏数据/不同 store）时按 store 已隔离 + 同 store 内唯一索引保证唯一；移除 `.last` 依赖，命中 0 → nil、命中唯一 → 返回、命中 >1（异常数据）→ 记 warning 并返回确定策略值（created_at DESC,id DESC 最新）。返回前按调用方 store 作用域（现状调用已 scope）。
- **FR-P3-4**：撞码预防（单码 ↔ 多码 CouponCode 同 namespace）：CouponCode 创建/生成前校验其 code 不与同 store 任一单码促销 code 冲突；单码促销保存时校验 code 不与同 store 已有多码 CouponCode 冲突（后者成本高，做"存在性快速查询"即可）。错误均 i18n。
- **FR-P3-5**：自动促销/多码不受影响回归：automatic 与 multi_codes 保存、多码生成、用码、CSV 导出路径全部照常。

---

## 4. 非功能需求（NFR）

- **NFR-1 资金安全**：本批次不改金额计算公式（除唯一约束/校验外零行为变更）；所有金额断言只读验证。
- **NFR-2 兼容**：不新增/删除列（用函数索引）；不改变 Store/Admin API 载荷；存量订单与历史促销展示不变。
- **NFR-3 性能**：新增校验走已有索引/前缀查询；`with_coupon_code` 保持单条 SQL；避免为撞码校验引入全表扫描（限 `promotion_id`/`store` 作用域）。
- **NFR-4 可维护性**：契约测试目录集中、命名 `_contract_spec.rb`/`promotion_spec.rb`；迁移可重复（幂等）；i18n key 进核心 locale。
- **NFR-5 迁移安全**：唯一索引迁移必须先跑数据检查；被使用促销不可删除（沿用 `before_destroy :not_used?` 语义）。

---

## 5. 验收标准（AC，与测试一一映射）

> AC 编号为数字（AC-001…AC-017，供 `harness prd verify` 追溯）；分组别名见括号。

### A0（文档/决策，由 P0 契约测试与迁移锁定）
- AC-001 ← FR-A0-1（A0-1）：附录 A 口径定义与 `order_updater.rb`/`adjuster/promotion.rb` 真实行为一致；契约测试 I1 全场景断言 `discount_total == Σ eligible 促销调整`。
- AC-002 ← FR-A0-2（A0-2）：`OrderPromotion#amount` 未过滤 eligible 的偏差被记录且由 AC-012（I6）暴露。
- AC-003 ← FR-A0-3（A0-3）：决策矩阵记录于附录 B；单码唯一性 = store 级、多码 CouponCode 全局唯一。
- AC-004 ← FR-A0-4（A0-4）：Redemption 边界记录于附录 B（本批次不实施）。
- AC-005 ← FR-A0-5（A0-5）：唯一性用函数索引表达（不加列）；迁移在真实 DB 执行成功（dev 已跑通 + rake 检查器验证）。

### P0（契约测试，测试文件：promotion_contract_spec.rb）
- AC-006 ← FR-P0-1：契约测试目录/文件建立，factories 引用可用。
- AC-007 ← FR-P0-2（I1）：order/line/shipment 三档及并存场景 `discount_total == Σ eligible`（5 用例）。
- AC-008 ← FR-P0-3（I2）：重复 recalc 金额一致。
- AC-009 ← FR-P0-4（I3）：重复 remove 幂等。
- AC-010 ← FR-P0-5（I4）：每 adjustable 至多一条 eligible 促销调整，取最大折扣。
- AC-011 ← FR-P0-6（I5）：高折扣不打负。
- AC-012 ← FR-P0-7（I6）：暴露型用例记录 OrderPromotion#amount 口径差（tag known_gap，Phase1/2 修）。

### P3（唯一约束/确定性，测试文件：promotion_spec.rb + coupon_code）
- AC-013 ← FR-P3-1：单码 store 级唯一（模型校验 + 函数唯一索引）。
- AC-014 ← FR-P3-2：迁移处置策略与 rake 检查器验证（重复被处置、被使用促销保留）。
- AC-015 ← FR-P3-3：`with_coupon_code` 确定性（归一化/单码优先/回退多码/无命中 nil）。
- AC-016 ← FR-P3-4：新增 CouponCode 撞单码被拒；非撞码放行。
- AC-017 ← FR-P3-5：automatic / multi_codes 不受影响回归。

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件（关键） | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | promotion/decorator | 仅生成 TS serializers 类型；无业务覆盖 | 否（无需宿主代码） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | promotion/discount_total/promo_total/adjuster/coupon | `order.rb`(alias discount_total→promo_total)、`order_updater.rb`(三档聚合公式)、`adjustable/adjuster/promotion.rb`(best-per-adjustable + tie-break)、`promotion.rb`(normalizes/downcase/with_coupon_code/validations)、`adjustment.rb`(eligible/promotion scopes)、`order_promotion.rb`(amount 未过滤 eligible) | 是（改动主区） |
| API | `pallastrade_gems/pallastrade_api/app/` | promotions/coupon/discounts | `admin/promotions_controller.rb`、`store/carts/discount_codes_controller.rb`、`discount_serializer.rb` | 本批次无 API 载荷变化（仅内部校验/lookup） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | promotions views/forms | `promotion_actions/.../calculator_fields`、`promotions/form/kind`（code 输入 uppercase） | 本批次不改 UI（唯一约束报错由错误渲染通用呈现） |
| Storefront | `storefront/src/` | coupon/discount | `/api/checkout/coupon` BFF、CouponCode 组件 | 本批次不改（lookup 行为不变则前端无感） |
| Platform | `platform/packages/` | promotion/coupon types | sdk Discount/Promotion 生成类型 | 无 API 变化，无需再生 |

**结论**：能力已存在于 core；本批次为 core 模型/测试/迁移增强，不新建 API/页面；宿主层无自定义促销代码需同步。防重复：无既有 PRD 命中（查重已通过）。

---

## 7. 技术影响

- **模型**：`pallastrade_core` `Promotion`（校验 + lookup + 可能 helper）、`CouponCode`（撞码校验，若实现于模型层）；`OrderPromotion#amount` **不改**（记录偏差）。
- **数据库**：新增函数唯一索引（PG）：`CREATE UNIQUE INDEX ... ON pallastrade_promotions (store_id, lower(btrim(code))) WHERE code IS NOT NULL;`；一次性数据检查/处置（新 migration 或 rake task + 在 CI 前本地执行）。
- **Locale**：core `en.yml` 新增错误 key（如 `coupon_code_already_used_by_promotion` 之类）。
- **测试**：新增契约 spec 目录 + promotion_spec（若不存在）；更新涉及现有 factory 使用处无破坏。
- **接口**：无（Store/Admin API/SDK/OpenAPI 不变）。
- **影响面**：`harness affected` 预计 core models + spec + migration；`harness check --profile quick` 纳入。

## 8. 测试计划

### 新增测试文件
| 文件 | 覆盖 AC |
|---|---|
| `backend/spec/services/pallastrade/promotions/totals_contract_spec.rb` | AC-P0-2/3/5/6 |
| `backend/spec/services/pallastrade/promotions/coupon_remove_idempotency_spec.rb` | AC-P0-4 |
| `backend/spec/services/pallastrade/promotions/discount_projection_gap_spec.rb` | AC-P0-7（暴露型，tag `:known_gap`） |
| `backend/spec/models/pallastrade/promotion_spec.rb`（若不存在则新建） | AC-P3-1/3/5 |
| `backend/spec/models/pallastrade/coupon_code_spec.rb`（补充） | AC-P3-4 |
| `backend/spec/migrations/promo_code_unique_migration_spec.rb`（或 rake task spec） | AC-P3-2 |

### 更新测试
- 涉及 `promotion_code`/`with_coupon_code` 既有用例的断言对齐（确定性返回）。

### 运行方式
- Ruby 变更最小验证：`npx harness check --profile quick`；契约/模型 spec 在 backend 测试环境（docker `pallastrade-web-1` 内 `bundle exec rspec <files>`）执行并留证据。

## 9. 文档同步清单（知识同步门）

- [x] `pallastrade-promotions` SKILL：已补充“Code uniqueness & lookup + contract tests”小节（PRD-20260909-promo-batch1）。
- [x] `pallastrade-data-model` SKILL：已评估无需更新（core gem 模型行为已由 promotions Skill 覆盖；迁移为函数索引，无新列/新模型）。
- [x] `docs/prd/README.md` 索引：本 PRD 已登记，状态 done。
- [x] 场景库 `harness/scenarios/scenarios.json`：新增 GS-081（促销码唯一/金额契约场景，配合 Skill 变更）。
- [x] 测试：新增 `promotion_spec.rb` + `promotion_contract_spec.rb`（AC-001…017 全覆盖，`prd verify` ✅）。
- [x] API 文档：无 API 载荷变化（内部校验/lookup），无需更新。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-09 | 0.1 | 初稿（批次1：A0 口径+决策 / P0 契约测试 / P3 唯一约束） | AI |
| 2026-09-10 | 0.2 | approved（用户认可）；实施完成：P3（唯一校验+函数索引+确定性 lookup+BulkGenerate 防撞）、P0 契约测试全绿（75 examples 0 failures）、A0 口径附录固化、迁移/rake/Skill/场景库同步 | AI |

---

## 附录 A（规范性）：优惠金额口径定义（FR-A0-1，代码核实版）

> 依据：`order_updater.rb`、`adjustable/adjuster/promotion.rb`、`adjustment.rb`、`order.rb` 实际行为（2026-09-09 核对）。

1. `Order#discount_total` ≡ `Order#promo_total`（`alias_attribute`；持久化列，负值表优惠）。
2. `order.promo_total = Σ line_items.promo_total + Σ shipments.promo_total + Σ order 级 eligible 促销调整金额`（updater 三档求和）。
3. 每 adjustable（Order/LineItem/Shipment）的 `promo_total` 由 `Adjustable::Adjuster::Promotion` 设置 = 该 adjustable 上**唯一 eligible** 的 competing promo adjustment 金额；无则 0。
4. 择优规则：`amount ASC, created_at DESC, id DESC` 取首条（折扣最大；并列取最新）；其余 competing promo 调整置 `eligible:false`（金额保留但**不参与求和**）。
5. "计入 discount_total 的促销调整" = `source_type='PallasTrade::PromotionAction' AND eligible=true` 且属于 open 可重算交易（closed 冻结订单属 Phase 5 范围）。
6. **已记录偏差（不移除，供 Phase 1/2 修复）**：`OrderPromotion#amount` 使用 `all_adjustments.promotion` **未过滤 eligible**；当某 adjustable 存在多个竞争促销时，`order_promotions` 汇总金额可能比 `discount_total` 更负 → Cart/Order API `discounts[]` 与 `discount_total` 可能不一致（Finding D 同源）。本批次仅用暴露型测试锁定现状。

## 附录 B（规范性）：决策记录（FR-A0-3/4/5）

- 码唯一性范围 = **store 级**（函数索引 `(store_id, lower(btrim(code)))`）；多码 `CouponCode` 维持**全局唯一**（单店部署无跨店现实冲突，避免加列迁移）。
- 归一化 = **trim + 全小写**（复用现有 `normalizes`/`downcase_code` 语义，不加 `normalized_code` 列，用函数索引表达，避免读取路径/序列化器改动）。
- 撞码 namespace：单码促销 code 与多码 CouponCode code 属同一"顾客输入空间"，本批次做**新增侧防撞**（创建时校验），存量撞码在 with_coupon_code 层用"单码优先"确定性处理（不承诺合并清理，属后续/产品决策）。
- Redemption/user_grant/组合策略：本批次**不实施**，仅锁定边界与决策占位（见 §3.1）。
