# PRD-20260917-catalog-health-score

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-09-17 |
| 来源 | 一句话需求「实施 B3 Catalog Health 可解释健康分」← `豆包梳理业务需求/商品升级方案.md` §6.1 |
| 分类 | catalog |
| 关联 Skill | pallastrade-admin、pallastrade-catalog |
| 关联 REQ | REQ-20260917-catalog-health-score.md（实施时回填） |
| 关联 PRD | PRD-20260915-admin-catalog-health-v1（7 类 issue 判定口径）、PRD-20260916-catalog-health-trend-snapshot（趋势）、PRD-20260917-catalog-health-coverage-ratios（覆盖率口径与三条铁律） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：「实施 B3 Catalog Health 可解释健康分（0-100）」
- **背景**：方案 §6.1 把 **0–100 Score** 列为 Catalog Health V2。工作台现状已具备：① 7 类 issue 的**计数**（`CatalogHealth::Issues` / `Report`）；② **趋势**（`Snapshot` / `Trend`，只读快照）；③ **覆盖率**（`Coverage`，目前 2 个指标：`missing_seo` / `missing_translations`）。Score 未做。
- **为什么必须是「可解释」**：一旦页面出现一个总分，商家会把它当 KPI。分数若不能由页面上可见的数字**手工复算**，就会立刻退化成扯皮（「72 分怎么来的」）。`PRD-20260917-catalog-health-coverage-ratios` 已经写下三条铁律（分子唯一来源、分母各自自洽、分母为 0 不编造），Score 必须**继承**它们。
- **目标**：
  1. 把覆盖率从 2 个指标扩展到**全部 7 类 issue**，每个 key 的分母**与自身单位同源**；
  2. 在页面上给出 0–100 总分，**并同时展示每个维度的 `缺失/总数`、覆盖率、以及「是否计入总分」**——分数可被逐项复算；
  3. **不可计算的维度不得以 0 分或满分参与**（会系统性抬高或压低总分）。
- **成功指标**：
  1. 页面上的总分可由页面上的 7 行明细**手工复算**得到同一数值；
  2. 每个维度的分子**严格等于** `Issues.count(store, key)`（不新增任何判定 SQL）；
  3. 缺数据（分母为 0）时该维度标注「不可计算（已排除）」，总分按剩余维度权重归一化。

## 2. 用户故事 / 场景

- 作为**运营负责人**，我希望一眼看到一个总分（我在变好还是变差），并且能展开看到**是哪一维在拖后腿**，以便决定这周的整改重点。
- 作为**只信任数字的人**，我希望总分的算法与权重在页面上写得清清楚楚，我能拿计算器复算一遍，而不是被告知「这是系统算的」。
- 场景：
  - **正常流**：有商品、有支持语言、有 URL 变更 → 7 维全部可计算 → 展示总分 + 7 行明细。
  - **新店**：0 个商品 → 内容三维与库存 / 草稿维分母为 0 → 全部标注「不可计算」→ 页面**不显示一个凭空的分数**，而是提示尚无足够数据。
  - **单语言门店**：`translation_slots == 0` → 翻译维「不可计算（门店未启用其它语言）」≠「翻译完成 100%」。
  - **无 URL 变更**：`redirect_unresolved` 分母为 0 → 该维不可计算（不是「100 分」）。
  - **异常**：某一维计数抛错（`Report#safe_count` 既有降级返回 0）→ 该维必须按「**不可计算**」处理并排除，**绝不能拿这个 0 当分子**（否则会凭空得到满分，把总分抬高）。

## 3. 功能需求（FR）

- **FR-001 覆盖率扩展到 7 个 key**：`CatalogHealth::Coverage` 为 `Issues::KEYS` 的每一类提供指标，分母定义如下（**每个 key 的分母与其分子的单位必须同源**）：

  | key | 分子（唯一来源） | 分母 |
  |---|---|---|
  | `missing_media` | `Issues.count` | 未归档商品数 |
  | `missing_description` | `Issues.count` | 未归档商品数 |
  | `missing_seo` | `Issues.count` | 未归档商品数 |
  | `missing_translations` | `Issues.count` | `Issues.translation_slots`（商品 × 其它语言） |
  | `active_zero_stock` | `Issues.count` | 未归档**且 `status=active`** 的商品数 |
  | `old_drafts` | `Issues.count` | 未归档**且 `status=draft`** 的商品数 |
  | `redirect_unresolved` | `Issues.count` | `ProductUrlChange.call(store)` 总条数 |

- **FR-002 不可计算即排除**：分母为 0 → 该维 `coverage_ratio` 为 `nil`，标记为不可计算，**不参与总分**（既不按 0 也不按 1 计入）。
- **FR-003 总分**：`CatalogHealth::Score` 计算 `Σ(权重 × 覆盖率) / Σ(权重)`，只对**可计算**维度求和；权重集中定义在一个常量中，**页面可见**；默认各维等权（理由：权重越复杂越难解释，等权意味着「平均每类问题的完成度」，可手工复算）。
- **FR-004 可解释呈现**：工作台必须同时展示：① 总分；② 计入的维度数与总数（如「由 5/7 个维度计算」）；③ 每个维度的 `缺失/总数`、覆盖率百分比、是否计入、未计入的原因。
- **FR-005 分子唯一来源**：所有分子一律取自 `Issues.count`，**不得新增判定 SQL**（维持「计数 == 下钻列表条数」这条不变量）。
- **FR-006 降级不冒充分数**：某一维计数失败时该维按**不可计算**处理（区别于「真实为 0」），总分不得因此抬高。
- **FR-007 只读零写入**：Score 不新增表、不写审计、不改变任何既有写路径（沿用只读运维页范式）。

## 4. 非功能需求（NFR）

- **性能**：7 个分母查询复用 `Issues` / `Coverage` 既有口径；页面查询数不随商品数增长（全部为 `COUNT`），与现状同阶。
- **安全**：只读；沿用 `CatalogHealthController` 既有的 CanCan 锚点（`model_class = PallasTrade::Product`），**不引入新的权限面**。
- **可维护**：分母定义与分子定义**同处一文件**（`Coverage`），避免「分子在这、分母在那」的漂移；权重集中为常量并附注释说明理由。
- **向后兼容**：`Coverage#seo` / `#translations` / `metric_for` / `empty?` 等既有方法签名与返回语义不变（既有 catalog health spec 不回归）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：7 个 key 都有 coverage 指标；`missing_media` / `missing_description` / `missing_seo` 三者分母**相等且等于**未归档商品数。
- **AC-002 ← FR-001**：`active_zero_stock` 的分母等于未归档且 `active` 的商品数（**不等于**未归档商品总数）；`old_drafts` 的分母等于未归档且 `draft` 的商品数。
- **AC-003 ← FR-001**：`redirect_unresolved` 的分母等于 `ProductUrlChange` 的总条数；`missing_translations` 的分母等于 `Issues.translation_slots`。
- **AC-004 ← FR-002**：任一维分母为 0 时 `coverage_ratio` 为 `nil`，且该维**不计入**总分。
- **AC-005 ← FR-003**：给定一组维度值，总分等于按权重手工复算的结果；当所有维度都不可计算时，总分为 `nil`（页面不显示数字分数）。
- **AC-006 ← FR-004**：页面同时渲染总分、计入维度数 / 总数、以及每维的分子 / 分母 / 覆盖率 / 是否计入。
- **AC-007 ← FR-005**：逐 key 断言每个指标的分子**等于** `Issues.count(store, key)`。
- **AC-008 ← FR-006**：让某一维计数抛错 → 该维被标记为不可计算，总分排除它，**且不会出现「该维 100%」的虚高**。
- **AC-009 ← FR-007**：计算过程零写入（无新增表、无写操作）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `catalog_health` / `health_score` | **无（ABSENT）** | 不适用 —— 不涉及 host app |
| Core | `pallastrade_gems/pallastrade_core/app/` | `health_score` / `HealthScore` / `def score` | **无（`health_score` 0 命中）**；相关既有：`services/pallastrade/catalog_health/{issues,report,coverage,snapshot,trend}.rb` | **缺口** —— 需新增 `Score`，并扩展 `Coverage` |
| API | `pallastrade_gems/pallastrade_api/app/` | `catalog_health` / `health_score` | **无（ABSENT）** | 不适用 —— 本需求无 API 变更 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `health_score` / `score` | **无（ABSENT）**；相关既有：`controllers/pallastrade/admin/catalog_health_controller.rb`、`views/pallastrade/admin/catalog_health/{index,_products_filter_banner,_product_card}.html.erb` | **本期主战场** —— 控制器注入 `@score` + 视图新增区块 |
| Storefront | `storefront/src/` | `catalog_health` / `healthScore` | **无（ABSENT）** | 不适用 |
| Platform | `platform/packages/` | `catalogHealth` / `healthScore` | **无（ABSENT）** | 不适用 |

**结论**：
- **已有能力（防重复判定）**：7 类 issue 的判定口径（`Issues`）、工作台组装（`Report`）、快照与趋势（`Snapshot` / `Trend`）、两个覆盖率指标（`Coverage`）**均已存在且已 `done` 交付**；本期**不新建判定口径、不新建表**。
- **需新建**：① `Coverage` 从 2 指标扩展到 7；② 新 `CatalogHealth::Score`（加权汇总 + 不可计算排除）；③ 控制器注入 + 视图区块；④ spec。
- **轮子检查**：全仓（6 层）搜索 `health_score` / `HealthScore` 均为 0 命中 → 确认无重复实现。
- **并发安全**：`Coverage`（PRD-20260917-catalog-health-coverage-ratios）已入库（`b76c5c19`）且该 PRD 状态为 `done`，工作区对该文件干净 → 可安全扩展。

## 7. 技术影响

涉及文件：
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/catalog_health/coverage.rb` —— 从 2 指标扩展到 7；保留既有 `seo` / `translations` / `metric_for` / `empty?` 的签名与语义。
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/catalog_health/score.rb` —— **新建**（只读）：维度收集（含不可计算排除）、权重常量、总分与「计入 / 未计入」元数据。
- `backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/catalog_health_controller.rb` —— `@score = PallasTrade::CatalogHealth::Score.call(current_store)`。
- `backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/catalog_health/index.html.erb` —— 总分区块 + 维度明细表（`缺失/总数`、覆盖率、计入与否、未计入原因）。

不涉及：数据库迁移（**零 schema 变更**）、API 契约、SDK、前台、权限注册、导航（无新子项）。

影响面：Catalog Health 工作台为**只读运维页**，本期仅新增展示区块；既有 7 类计数与其下钻链接**不变**。

## 8. 测试计划

- **更新**：Catalog Health 既有 service spec（扩展 `harness verify admin-catalog-health-rspec` 覆盖的用例）
  - AC-001 ~ AC-003（逐 key 分母口径）
  - AC-004（分母为 0 → `nil` + 不计入）
  - AC-005（总分 == 手工复算；全不可计算 → `nil`）
  - AC-007（分子 == `Issues.count`，逐 key）
  - AC-008（单维抛错 → 不可计算而非满分）
- **新建 / 更新**：工作台请求 spec
  - AC-006（页面渲染总分 + 明细 + 计入标记）
  - AC-009（零写入断言）
- **门禁**：`harness verify admin-catalog-health-rspec`（AGENTS.md §6 已登记的 verifier，本次扩展其 spec 覆盖）。
- **渲染取证**：工作台页面实际 HTML 片段（总分 + 明细行）。

AC 映射：AC-001~AC-005 / AC-007 / AC-008 → service spec；AC-006 / AC-009 → 请求 spec。

## 9. 文档同步清单（知识同步门）

- [ ] **API 文档**：不涉及（无契约变更）
- [ ] **Skill 文档**：`ai/skills/pallastrade-admin/SKILL.md`（只读运维页范式 / Catalog Health 章节补「健康分与可解释口径」）—— 按 `sync-check` 判定
- [ ] **场景库**：若改动 Skill 文件，则同步 `harness/scenarios/scenarios.json`（doc-impact 硬要求）
- [ ] **反模式库 / 任务规则**：预计不涉及
- [ ] **本 PRD 状态** + `docs/prd/README.md` 索引
- [ ] `AGENTS.md` §6 —— 若 verifier 的 spec 范围发生变化则同步该行

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-17 | 0.1 | 初稿（B3：7 维覆盖率 + 可解释加权总分 + 不可计算排除） | AI |
