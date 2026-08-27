# PRD-20260826-checkout-实施-p2-统一拆单引擎-orders-splitter-策略分组-调整分摊-幂等

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-08-26 |
| 来源 | 需求：实施 P2 统一拆单引擎（Orders::Splitter 策略分组/调整分摊/幂等） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-checkout、pallastrade-data-model、pallastrade-payments、pallastrade-decorators、pallastrade-testing |
| 关联 REQ | REQ-20260826-order-lifecycle-p2.md（实施时回填） |
| 关联 PRD | N/A（全新；上游方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md` §P2） |
| 需求类型 | 新功能（能力层服务，默认不接入任何流程） |

---

## 1. 背景与目标

- **一句话需求原文**：需求：实施 P2 统一拆单引擎（Orders::Splitter 策略分组/调整分摊/幂等）
- **背景**：P1 已建数据地基（`orders.parent_id` / `split_from_id` / `payment_combination_id` + `PaymentCombination`/`PaymentSplit`）。P2 实现**统一拆单引擎**，为 P5 自动拆单 / P6 手动拆单提供可复用能力。
- **目标**：
  1. `PallasTrade::Orders::Splitter` 统一入口 `split(order:, groups:, options:)`；
  2. 策略分组 helpers（按商品仓库地址 / 按店铺 / 扩展点）；
  3. 行项目迁移 + 调整项分摊（promo/tax/shipping 按行项目金额比例）+ 金额重算；
  4. 已付金额按比例分摊到 `PaymentSplit`；
  5. 幂等 + `order.splitted` 事件。
- **成功指标**：引擎独立可测（不接入流程）；拆单前后**总额守恒**断言通过；默认关闭零行为变化。

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

> P2 是能力层服务，无直接用户故事；以下为技术场景（供测试与验收映射）。

- **S1（按仓库地址拆）**：订单行项目分属 2 个商品仓库地址 → 拆成 2 个子订单，父订单保留。
- **S2（按店铺拆/手动跨店）**：手动指定目标店铺/仓库拆分。
- **S3（已支付订单拆）**：源订单已付款 → 已付金额按行项目金额比例分摊到各子订单 `PaymentSplit`。
- **S4（幂等）**：对同一订单重复调用 split → 不重复创建子订单。
- **S5（异常）**：行项目已在别的组 / 目标店铺无该商品 / 源订单不可拆 → 明确业务错误，事务回滚。
- **S6（空父容器）**：全部分出后源订单无行项目 → 成为空父订单（容器语义，P3 起派生金额）。

## 3. 功能需求（FR）

- **FR-001**：`PallasTrade::Orders::Splitter#split(order:, groups:, options:)`——`groups = { group_key => [line_item_id, ...] }`，`options` 支持 `parent_order` / `target_store` / `target_stock_location`；返回 `ServiceResult<Array<Order>>`。
- **FR-002**：前置校验：源订单存在/非取消/非空；行项目不跨组；目标店铺商品可用（publication/价格/税/配送）。
- **FR-003**：创建子订单（复制 store/user/channel/market/currency/email/地址 + `parent_id`/`split_from_id`），迁移行项目（含其 line_item 级 `Adjustment` 的 `order_id` 同步更新）。
- **FR-004**：order 级非税 eligible 调整（promo 等）按行项目金额比例分摊创建到各子订单（新 `Adjustment`，保留原 `source`）。
- **FR-005**：子订单税额重算（`create_tax_charge!`）+ `OrderUpdater` 金额重算（item/shipment/adjustment/total）。
- **FR-006**：源订单存在 completed 支付时，按行项目金额比例创建 `PaymentSplit`（已付分摊）。
- **FR-007**：幂等：同一源订单重复拆分不重复创建（`split_from_id` + 状态守卫 + 唯一性校验）。
- **FR-008**：发布 `order.splitted` 事件（父/子订单）。
- **FR-009**：策略分组 helpers：`SplitStrategies::ByStockLocation`（按商品仓库地址）、`SplitStrategies::ByStore`（按店铺）；`PallasTrade.orders_split_strategies` 扩展注册点。
- **FR-010**：源订单保留未分组行项目；全部分出时成为空父订单（P3 起容器语义）。

## 4. 非功能需求（NFR）

- **事务一致性**：拆分在单个事务内完成，任一步失败整体回滚（源/子订单均不残留半拆状态）。
- **总额守恒**：`Σ(子订单金额) + 源订单剩余 = 原订单拆分前总额`（有 spec 断言）。
- **零行为变化**：不接入任何流程/端点/前端，默认关闭。
- **可回滚**：服务文件独立，删除即退；无迁移。
- **幂等**：重复调用/并发调用安全。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`split` 返回子订单数组；子订单 `parent_id`/`split_from_id` 正确（service spec）。
- **AC-002 ← FR-002**：非法分组/不可拆/跨店无商品 → 明确业务错误且无残留（service spec）。
- **AC-003 ← FR-003**：行项目迁移正确（子订单持有、源订单剩余）；line_item 级调整 `order_id` 同步（service spec）。
- **AC-004 ← FR-004**：order 级 promo 按行项目金额比例分摊，金额守恒断言（service spec）。
- **AC-005 ← FR-005**：子订单金额/税额重算正确（`OrderUpdater`）。
- **AC-006 ← FR-006**：已付金额 `PaymentSplit` 创建且守恒（service spec）。
- **AC-007 ← FR-007**：重复调用不重复拆（service spec）。
- **AC-008 ← FR-008**：`order.splitted` 事件触发（service/event spec）。
- **AC-009 ← FR-009**：`ByStockLocation` / `ByStore` 分组正确（strategy spec）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | split / 拆单 | 无 | ⛔ 需新建（core） |
| Core | `pallastrade_gems/pallastrade_core/app/` | class Splitter / def split | 仅 `stock/splitter/*`（按仓库拆 shipment，非订单级） | ⛔ 需新建 `Orders::Splitter` |
| API | `pallastrade_gems/pallastrade_api/app/` | split | `admin/orders/fulfillments_controller#split`（shipment 级） | ⛔ P2 不涉及（P6 起） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | split | `shipments_controller#split`（shipment 拆分） | ⛔ P2 不涉及 |
| Storefront | `storefront/src/` | splitOrder / split | 无 | ⛔ P2 不涉及 |
| Platform | `platform/packages/` | split / Splitter | 无 | ⛔ P2 不涉及 |

**结论**：全仓库无订单级拆单实现；现有 `split` 均为 shipment 级（发货单拆分），与 P2 不冲突。`Orders::Splitter` 全新创建。

## 7. 技术影响

- **新增**（`pallastrade_core`）：
  - `app/services/pallastrade/orders/splitter.rb`（统一拆单引擎）
  - `app/services/pallastrade/orders/split_strategies/base.rb`、`by_stock_location.rb`、`by_store.rb`（策略分组）
  - `order.rb`：发布 `order.splitted` 事件（若需，复用 `publishes_lifecycle_events`）
- **测试**：`backend/spec/services/pallastrade/orders/splitter_spec.rb` + `split_strategies_spec.rb`
- **无迁移 / 无 API / 无前端改动**；引擎不接入 `Carts::Complete`（P5 才接）。

## 8. 测试计划

- **新增**（`backend/spec/services/pallastrade/orders/`）：
  - `splitter_spec.rb`（AC-001~008：基础拆分/跨店/分摊/幂等/事件/异常）
  - `split_strategies_spec.rb`（AC-009：ByStockLocation / ByStore）
- 运行：`harness check --profile quick` + 相关 rspec（docker exec）
- 无既有测试更新（P2 不接入流程）

## 9. 文档同步清单（知识同步门）

- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`（拆单引擎与父子模型联动）
- [ ] `ai/skills/pallastrade-checkout/SKILL.md`（统一拆单引擎）
- [ ] 场景库 `harness/scenarios/scenarios.json`（如涉及新场景）
- [ ] API 文档：P2 无新端点，不涉及

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-26 | 0.1 | 初稿：P2 统一拆单引擎（Orders::Splitter 策略分组/调整分摊/幂等） | AI |
| 2026-08-26 | 0.2 | 实施完成：Splitter + SplitStrategies(3) + 迁移（payment_splits.combination 可空）+ PaymentSplit optional；13 spec 全绿 + P1/回归 26 spec 全绿 + harness quick + 回滚演练通过；知识同步（checkout/data-model SKILL） | AI |
