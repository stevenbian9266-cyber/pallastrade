# PRD-20260916-catalog-d3-product-merge

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 「继续」→《商品升级方案 V1.0》§十二 第三步 **Merge Product**（D-3 独立专项） |
| 分类 | catalog（商品域 / 数据治理） |
| 关联 Skill | pallastrade-catalog、pallastrade-admin、pallastrade-data-model、pallastrade-security |
| 关联 REQ | `harness/requirements/REQ-20260916-d3-product-merge.md` |
| 关联 PRD | N/A（§十二 第三步；B-2 Catalog Health / D-1 Product History / D-2 Duplicate Detection 已完成，本项收尾该章） |
| 需求类型 | 新功能（高风险：触及商品/variant/review 引用，但**不触及历史交易**） |

> 🔁 **查重**：6 层跨层搜索零命中（仅 `OrderMerger` 订单合并，异域）。
> **范围依据**：方案 §十二 原文 ——「商品合并会牵涉 Variant、Reviews、Redirects 和历史交易关系。审计同样将重复检测和商品合并列为**后置治理能力**」；
> `Products::DuplicateCandidates` 源码注释亦写明 ——「Merging two products has to reconcile variants, reviews, redirects and historical transactions, so it stays a separate project (D-3)」。
> 本批即该独立专项的**切片 1**。

## 1. 背景与目标

- **背景**：D-2 已能让商家**发现**重复商品（barcode / SKU / 名称三信号工作台），但发现之后**没有任何动作**可做 —— 商品重复依然只能靠人工改 SKU、删商品（删了会破坏旧 URL 与评论）。重复商品会分裂库存、评论与搜索权重。
- **目标**：让商家能把一个**重复商品合并进主商品（survivor）**：可迁移的引用迁移过去、旧 URL 301 到主商品、被合并商品软删并保留可追溯记录，**而历史交易零改写**；出错时可**一键撤销**回到合并前（用户 2026-09-16 明确追加）。
- **成功指标**：
  - 预检能回答「合并会发生什么」（逐项计数 + 跳过原因），且**零写入**；
  - 执行合并后：变体/评论/图片/分类/促销规则归到 survivor，被合并商品的旧 slug 301 到 survivor；
  - **历史交易（line_items / orders / payments / transactions）前后逐字节不变**；
  - 重复执行同一合并是 no-op；
  - 冲突项（SKU 重复、同用户同商品评论）**被跳过并在报告中列出**，绝不静默覆盖；
  - **撤销能把引用逐项还原到合并前**，且同样不改写历史交易。

## 2. 用户故事 / 场景

| # | 场景 | 期望 |
|---|---|---|
| S1 | 商家在 Duplicate Detection 组内点「Merge into…」 | 出预检页：可迁移/将跳过逐项计数 + 警告 |
| S2 | 确认执行合并 | 单事务完成迁移 + redirect + 软删 + 审计，页面显示执行报告 |
| S3 | 两个商品有相同 SKU 的变体 | 该变体**跳过**（保留在被合并商品里），报告 `sku_conflict` |
| S4 | 两位顾客各评过两个商品（同 user 两测） | 冲突评论跳过（保留 survivor 既有），报告 `review_conflict` |
| S5 | 合并后访问旧商品 URL | 301 到 survivor URL |
| S6 | 合并后查历史订单 | 订单/行项目/支付**完全未变**（仍指向原 variant/product 快照） |
| S7 | 再次执行同一合并 | no-op，返回「已合并」状态，无新副作用 |
| S8 | 跨店商品 id 混入 | 404/422，拒绝执行 |
| S9 | 无权限的操作者 | 403，且不产生任何写入 |
| S10 | 合并后 survivor 的库存 | = 原库存 + 迁入变体的库存（不合并数量，按行迁移） |
| S11 | 合并后发现选错了 survivor，点「撤销合并」 | 引用逐项回到原absorbed、absorbed 恢复可见、旧 URL redirect 停用、台账标记 undone |
| S12 | 撤销前对象已被删/改（如迁移的变体已被删） | 拒绝并列出阻塞项，**不做部分撤销** |
| S13 | 重复点撤销 | `already_undone`，零写入 |

## 3. 功能需求（FR）

- **FR-001 预检（read model，零写入）**：`Products::MergePreview.call(store:, survivor:, absorbed:)` 返回
  `variants{movable,conflicts[reason]}`、`reviews{movable,conflicts}`、`media{movable}`、`classifications{movable}`、
  `promotions{movable}`、`historical_references{line_items,orders}`（**仅计数**）、`redirect{from,to}`、`warnings[]`。
- **FR-002 执行合并（单事务）**：`Products::Merge.call(store:, survivor:, absorbed:, actor:)`
  ① 迁移 variants（含 stock_items/prices，冲突跳过）② 迁移 media（Asset viewable 指向 survivor）
  ③ 迁移 classifications（taxon 去重）④ 迁移 product_promotion_rules（去重）⑤ 迁移 reviews（冲突跳过）
  ⑥ upsert `Redirect(from_path → survivor.path, active)` ⑦ 被合并商品：`archived` + 软删 + `private_metadata['merged_into'] = survivor.prefixed_id`
  ⑧ 写 `Audit`（动作 `product_merged`，payload = 计数 + 跳过明细）⑨ 返回与预检同口径的报告。
- **FR-003 历史交易零改写（硬不变量）**：不得触碰 `line_items` / `orders` / `payments` / `commerce_transactions` /
  `financial_ledger_entries`；合并前后这些表**逐字节不变**（测试断言全表校验和）。
- **FR-004 作用域与校验**：survivor 与 absorbed 必须属于 `current_store`、二者不同、absorbed 未被合并过；违反 → 404/422。
- **FR-005 幂等**：absorbed 已是 `merged_into: survivor` → 返回 `already_merged`，不产生新写入。
- **FR-006 权限**：仅具备商品管理权限（`can? :manage, PallasTrade::Product`）可执行；无权限 → 403 且零写入。
- **FR-007 后台入口**：Duplicate Detection 工作台组内新增「合并到…」动作 + 确认页（展示预检结果）+ 执行；
  执行结果以报告形式回显（含跳过明细与计数）。
- **FR-008 前台**：旧商品 URL 301 到 survivor（复用既有 `PallasTrade::Redirect` 解析链路，零新中间件）。
- **FR-009 合并台账**：每次合并写 1 行 `pallastrade_product_merges`
  （`store_id` / `survivor_id` / `absorbed_id` / actor / `moved`（逐条 id：variants / reviews / media / classifications / promotions）/ `counts` / `skips` / `redirect_id` / `undone_at` + `undone_by`），
  并以 partial unique（`WHERE undone_at IS NULL`）保证同一 absorbed 商品同时只有一条未撤销的合并。
- **FR-010 撤销合并**：`Products::UndoMerge.call(store:, merge:, actor:)` —— ① 按台账把每条 `moved` 记录改回 absorbed
  ② 恢复 absorbed（取消软删与 archived、清 `merged_into`）③ 停用合并建立的 redirect ④ 台账标记 `undone_at`/`undone_by`
  ⑤ 写审计 `product_merge_undone`。撤销后可重新合并（新台账行）。
- **FR-011 撤销前置条件（零写入拒绝）**：台账已 undone → `already_undone`；任一清单项已不存在或已被改动
  → 拒绝并返回 `blocking_items`，**不做部分撤销**（避免半途状态）。

**本批边界（不做）**：
- 不做批量合并（一次多组）、不做跨店合并；
- 不迁移/改写历史交易与快照；
- 不合并库存**数量**（只迁移库存行）；
- 不做自动选择 survivor 的启发式（由商家显式指定）；
- 不做「撤销后再撤销」（撤销后重新合并会产生新台账行，属正常流程）；
- 不改 Duplicate Detection 的信号口径（D-2 冻结）。

## 4. 非功能需求（NFR）

- **安全**：跨店隔离（`current_store`）；权限门（403）；历史交易不可变；审计留痕（actor + 计数 + 跳过原因）。
- **性能**：预检对单组商品（≤5 商品）为常数级查询；执行合并单事务、无外部调用、无长锁（不锁 order/payment 表）。
- **兼容**：零 API 契约变更（纯后台动作 + 模型内元数据）；不新增公开端点。
- **可维护性**：预检与执行**共用同一份影响面计算**（计数不可能不一致）；跳过原因枚举化。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：预检返回逐项计数且**零写入**（前后全表校验和相等）。
- **AC-002 ← FR-001**：预检与执行报告的计数口径一致（同一份计算）。
- **AC-003 ← FR-002**：合并后 variants/reviews/media/classifications/promotions 归属 survivor，且数量守恒（迁移数 + 跳过数 = 原数）。
- **AC-004 ← FR-002**：旧 slug 建立 301 redirect（active）；重复执行不产生第二条。
- **AC-005 ← FR-002**：被合并商品 archived + 软删 + `merged_into` 标记。
- **AC-006 ← FR-003**：合并前后 `line_items`/`orders`/`payments`/`commerce_transactions` 校验和不变。
- **AC-007 ← FR-002**：同 SKU 变体跳过并报告 `sku_conflict`，其仍归属被合并商品。
- **AC-008 ← FR-002**：同用户同商品评论冲突跳过并报告，survivor 既有评论保留。
- **AC-009 ← FR-004/FR-005**：跨店/自身/已合并 → 拒绝且零写入；重复执行返回 `already_merged`。
- **AC-010 ← FR-006**：无权限 → 403 且零写入。
- **AC-011 ← FR-007**：后台确认页展示预检结果；执行后回显报告（含跳过明细）。
- **AC-012 ← FR-008**：前台旧 URL 301 到 survivor（redirect 解析链路口径）。
- **AC-013 ← FR-002**：审计写入 1 条，含 actor、survivor/absorbed、计数与跳过原因。
- **AC-014 ← FR-009**：合并后台账 1 行，`moved` 逐条 id 与执行报告一致；同一 absorbed 不能出现第二条未撤销记录（唯一约束）。
- **AC-015 ← FR-010**：撤销后 survivor 与 absorbed 的引用分布**逐项回到合并前**（变体/评论/媒体/分类/促销），absorbed 恢复可见且 `merged_into` 清空。
- **AC-016 ← FR-010**：撤销后与本次合并关联的 redirect 停用；再次撤销 → `already_undone`，零写入。
- **AC-017 ← FR-011**：清单项缺失/已被改动 → 拒绝且零写入（前后全表校验和相等），并返回 `blocking_items`。
- **AC-018 ← FR-003（扩展）**：撤销同样不改写历史交易（订单/行项目/支付/交易表校验和不变）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `merge_product` / `product_merge` / `consolidat` | 无 | ❌ |
| Core | `pallastrade_core/app/` | `merge_product` / `def merge` / `DuplicateCandidates` | `order_merger.rb`（**订单**合并，异域）、`services/products/duplicate_candidates.rb`（检测，D-2，注释明确把合并留给 D-3） | ❌ 需新建 |
| API | `pallastrade_api/app/` | `merge` / `consolidat` | 仅 `Hash#merge` 等用法（`reviews_controller` 的 `serializer_params.merge`） | ❌ 无端点 |
| Admin | `pallastrade_admin/app/` | `merge` / `duplicate_products` | `duplicate_products_controller.rb`（检测工作台，本批挂载入口） | ⚠️ 有入口，无动作 |
| Storefront | `storefront/src/` | `merge` | 仅 `tailwind-merge` 与文案 | ❌ 无 |
| Platform | `platform/packages/**/src` | `merge` | 仅通用 JSON merge 注释 | ❌ 无 |
| 依赖能力 | `Redirect` 模型 / `Product` 关联 | — | `PallasTrade::Redirect`（store 作用域 + from_path 唯一 + active）= 可复用做 301；`Product` `acts_as_paranoid` + variants/reviews/media/classifications/promotions 关联齐备 | ✅ 可复用，零新表 |

**结论**：需**新建 1 张台账表 + 3 个服务（预检 / 合并 / 撤销）+ 1 个后台动作 + 1 个确认页**；
**零公开契约变更**（复用 `Redirect` 做 301、`acts_as_paranoid` 做软删）。用户追加撤销能力后，
必须持久化「逐条迁移清单」才能反迁移，因此需要合并台账表（仅新增表，不改任何既有列）。

## 7. 关键决策（本 PRD 推荐值，需用户确认）

| # | 决策 | 推荐值 | 理由 |
|---|---|---|---|
| D1 | survivor 选择方式 | **商家显式指定**（不做自动启发式） | 合并不可逆，自动选错代价高 |
| D2 | 评论是否迁移 | **迁移**（同用户冲突则跳过） | 评论是商品的社会证明，丢弃可惜；冲突静默覆盖会污染 |
| D3 | 图片是否迁移 | **迁移**（Asset 改指向 survivor） | 图片是内容资产；不复制二进制，只改归属 |
| D4 | 被合并商品处置 | **软删 + archived + `merged_into` 标记**（不物理删除） | 可追溯；物理删除会破坏历史引用与审计 |
| D5 | 是否本批做撤销 | **本批做**（用户 2026-09-16 确认追加） | 撤销靠台账逐条清单反迁移；前置条件校验防「半途状态」 |
| D6 | 前台 URL 处理 | **301 到 survivor**（复用 Redirect） | 保住 SEO 与外部链接 |

## 8. 测试计划

- `spec/services/pallastrade/products/merge_preview_spec.rb`（AC-001/002：零写入 + 计数口径）
- `spec/services/pallastrade/products/merge_spec.rb`（AC-003~009/013/014：迁移守恒、redirect、软删、交易不变、冲突跳过、幂等/拒绝、审计、台账）
- `spec/services/pallastrade/products/undo_merge_spec.rb`（AC-015~018：逐项还原、redirect 停用、已撤回幂等、阻塞项拒绝、交易不变）
- `spec/requests/pallastrade/admin/product_merges_spec.rb`（AC-010~012：权限 403、确认页、执行报告、撤销入口、redirect 解析）
- **AC → 测试映射**：AC-001/002 → preview；AC-003~009/013/014 → merge；AC-015~018 → undo_merge；AC-010~012 → admin request。
- **注册验证器**：`d3-product-merge-rspec`。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-catalog/SKILL.md`（合并口径与不变量：预检只读、迁移守恒、冲突跳过、历史零改写、纯软删 + `merged_into`、按语言 301、撤销逐条还原）
- [x] `ai/skills/pallastrade-admin/SKILL.md`（Duplicate Detection → Merge 入口 / 预检页 / 最近合并 + 撤销 / helper 前缀 / 权限）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（`pallastrade_product_merges` 表 + 前缀 `pmg` + partial unique + `absorbed_status_before` + 软删口径）
- [x] `harness/scenarios/scenarios.json`（新增 **GS-154**：合并可迁移引用，绝不改写历史交易；GS-153 已被并行会话占用故顺延）
- [x] `AGENTS.md` §6（验证器 `d3-product-merge-rspec`，≤3 min）
- [x] `harness.config.mjs`（注册验证器）
- [x] `docs/prd/README.md` 索引（由 `prd-status-sync.mjs --fix` 刷新）

**sync-check 其余项评估（2026-09-16）**：

| 触发项 | 结论 |
|---|---|
| API 端点变更（`pallastrade_admin/config/routes.rb`） | **无需更新** `backend/public/api-docs/{store,admin}.yaml` / `pallastrade-api-v3` Skill / SDK 类型 —— 本次仅新增 3 条 **admin HTML** 路由（`duplicate_products/{merge,undo_merge}`），不动 `/api/v3/**` 契约；`generated:check` 无 diff |
| Skill / PRD 机制 | `pallastrade-prd` Skill **无需更新**（流程未变）；`copilot-instructions.md` **无需更新**（R0–R9 未变）；知识同步矩阵未新增文件类型 |
| 测试 / 场景库 | `harness verify d3-product-merge-rspec`（19 例）+ `eval-ai --scenarios` 155/155 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（D-3 切片1：预检 + 执行 + 审计 + 后台入口；6 个决策点 待用户确认） | AI |
| 2026-09-16 | 1.0 | 用户确认「**确认实施切片1**」，并追加要求「**本批也要撤销能力**」→ D5 改为做：新增 FR-009~011（台账 / 撤销 / 前置条件）与 AC-014~018，范围 由 2 个服务扩为 3 个服务 + 1 张台账表 → 状态 approved | AI |
| 2026-09-16 | 1.1 | 实施完成：19 例 spec 全绿、AC 27/27 覆盖、场景 GS-154 通过（155/155）、验证器 `d3-product-merge-rspec` 注册 → 状态 **done** | AI |
