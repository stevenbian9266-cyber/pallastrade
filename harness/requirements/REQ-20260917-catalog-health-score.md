# REQ-20260917-catalog-health-score

> 关联 PRD：`docs/prd/catalog/PRD-20260917-catalog-health-score.md`
> 任务：`TASK-20260917095710-03df0665` / gate `GATE-2026-09-17T09-59-21`（feature，quick）

---

## Step 0：跨层搜索（6 层，强制）

| 层 | 搜索路径 | 搜索关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `catalog_health` / `health_score` | 无 | ❌ 零命中（不涉及 host app） |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ 零命中 |
| Core Gem — models | `pallastrade_gems/pallastrade_core/app/models/` | `health_score` / `def score` | 无 | ❌ 零命中 |
| Core Gem — services | `pallastrade_gems/pallastrade_core/app/services/` | 同上；`catalog_health` | `pallastrade/catalog_health/{issues,report,coverage,snapshot,trend}.rb` | ⚠️ 部分 —— **7 类判定 + 计数 + 趋势 + 2 维覆盖率已就位**；**无 Score** |
| API Gem — controllers/serializers | `pallastrade_gems/pallastrade_api/app/` | `catalog_health` / `health_score` | 无 | ❌ 零命中（本期无 API 变更） |
| Admin Gem — controllers | `pallastrade_gems/pallastrade_admin/app/controllers/` | `health_score` / `score` | 无 | ⚠️ 部分 —— 既有 `catalog_health_controller.rb`（只读，注入 `@report` / `@trend` / `@coverage`） |
| Admin Gem — views | `pallastrade_gems/pallastrade_admin/app/views/` | 同上 | 无 `health_score`；既有 `catalog_health/{index,_products_filter_banner,_product_card}.html.erb` | ⚠️ 部分 —— **本期主战场**：新增总分区块 + 维度明细 |
| Storefront | `storefront/src/` | `catalog_health` / `healthScore` | 无 | ❌ 零命中（不涉及前台） |
| Platform | `platform/packages/` | `catalogHealth` / `healthScore` | 无 | ❌ 零命中 |

### 搜索结论

- **无重复实现**：全仓（6 层）搜索 `health_score` / `HealthScore` **0 命中** → Score 确为未做项。
- **已有能力（不新建判定口径、不新建表）**：① `CatalogHealth::Issues`（7 类 issue 的**唯一判定权威**，`KEYS` / `PRODUCT_FILTER_KEYS` / `translation_slots`）；② `Report`（工作台组装 + `safe_count` 降级）；③ `Snapshot` / `Trend`（趋势）；④ `Coverage`（2 维覆盖率 + 三条铁律 + `covered_ratio` 为 nil 的语义）。**本期全部复用。**
- **需新建**：① `Coverage` 从 2 指标扩展到 7（每 key 分母各自自洽）；② 新 `CatalogHealth::Score`（加权汇总 + 不可计算维度排除）；③ 控制器注入 `@score`；④ 视图区块 + spec。
- **架构层级选择**：按 `pallastrade-customization` 决策树，本需求是「**只读派生 + 只读运维页展示**」——落在 **gem service（core）+ gem 控制器/视图（admin）**，**不需要** Decorator / Events / 新模型 / Host App 改动；沿用 `pallastrade-admin` 的「只读运维页范式」。
- **并发安全**：`Coverage`（PRD-20260917-catalog-health-coverage-ratios）已入库（`b76c5c19`）且该 PRD 为 `done`、工作区对该文件干净 → 可安全扩展其指标集。

---

## Step 1：Skill 文件咨询（强制）

| Skill 文件 | 状态 | 关键结论引用（真实结论） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：Settings → Events → DI → Admin Extensions → Generators → Decorators → Extensions → 直接改 gem。本需求**不需要自定义机制**：规则是「新文档/新展块」，且仓库约定 **gem 为一等公民、允许直接改**（改动加 `# PALLAS-CUSTOM:` 或 PRD 溯源注释）。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | §只读运维页范式（reference: Transactions / Refund Ops / Promotion Redemptions）：① 控制器继承 `ResourceController`、覆写 `model_class` / `scope`（`current_store.<assoc>` 保证店铺隔离）/ `object_name` / `find_object`，**只读页不要定义 new/create/edit/update/destroy**；② 表格经 `pallastrade_admin_tables.rb` 注册 + 视图只写 `render_table`；③ 导航新增/删除子项必须同步 `navigation_consistency_spec.rb` 的断言；④ 权限在 `pallastrade_permission_registry.rb` 注册。→ **本期是「已有只读页上新增一个展示区块」**（不新增资源、不新增导航子项、不新增权限），因此 ②③④ 均不涉及，仅需遵守 ① 的只读约束与既有 CanCan 锚点（`CatalogHealthController` 已 `model_class = PallasTrade::Product`）。 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 目录图：Product → Variant（master + 真实变体）→ Price；**product 的状态字段（`status`: `draft` / `active` / `archived`）与 `not_archived` scope 是商品集合划分的依据** —— 这是本需求「分母必须是各自的子集」的模型层依据（`active_zero_stock` 分母 = active 商品、`old_drafts` 分母 = draft 商品，均**不是**全部商品）。 |

**按需 Skill（本次涉及）**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ | ⬜ 未读 | 本期计划扩展现有 Catalog Health spec 与请求 spec（对应已登记的 verifier `admin-catalog-health-rspec`），不新建测试基础设施。若实施中发现需要新范式，再补读。 |
| `pallastrade-data-model` | ❌ | — | 零迁移、零模型改动 |
| `pallastrade-api-v3` | ❌ | — | 无契约变更 |
| `pallastrade-i18n` | ✅ | ⬜ 未读 | 页面新增文案（分数标签、维度名、未计入原因）**需要 en + zh-CN 双语键** —— 实施时按 `pallastrade-i18n` 与 `admin-i18n-rspec` 门禁补齐；本期 AC 不直接覆盖 i18n，但实现必须过该门。 |
| `pallastrade-decorators` / `pallastrade-dependencies` / `pallastrade-events-webhooks` | ❌ | — | 无副作用、无行为替换 |

---

## 需求标题

Catalog Health 工作台新增「可解释健康分」（0-100，分维度可见）

## 任务类型

功能优化（优化迭代）

## 需求描述

工作台已有 7 类 issue 的**计数**、**趋势**与 **2 维覆盖率**，但没有一个能一眼看懂的总分。方案 §6.1 把 0–100 Score 列为 Catalog Health V2，本期做掉。

**但总分必须是「可解释」的**：一旦页面出现数字，商家会拿它当 KPI；分数若不能由页面上可见的数字**手工复算**，就会退化成扯皮。因此本期做三件事：

1. **覆盖率从 2 维扩展到 7 维**，每个 key 的分母**与自身单位同源**（内容三维 = 未归档商品数；库存维 = active 商品数；草稿维 = draft 商品数；翻译维 = 商品 × 其它语言槽位；URL 维 = URL 变更总条数）。**这五个分母互不相同，绝不能共用一个**。
2. **0–100 总分** = 可计算维度的加权平均（默认等权，权重集中为常量且页面可见）。
3. **不可计算的维度必须排除**：分母为 0（新店 / 单语言门店 / 无 URL 变更）时该维「不可计算」，**既不按 0 也不按 1 计入**，并在页面标注原因。

**两条必须守住的旧账**（继承 `PRD-20260917-catalog-health-coverage-ratios` 的三条铁律）：
- 所有**分子一律取自 `Issues.count`**，不得新写判定 SQL（维持「计数 == 下钻列表条数」不变量）；
- 某一维计数**抛错**时（`Report#safe_count` 既有降级返回 0）必须按**不可计算**处理 —— 否则会拿这个 0 当分子，凭空得到「该维满分」并抬高总分。

## 影响范围（`harness affected` 输出）

- 实施前基线（仅两份 PRD 文档）：`filesChanged: 2`、`affectedComponents: []`、`estimatedTests: 6` → **尚无代码变更**，实施后需重跑。
- 计划改动清单（详见 PRD §7）：
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/catalog_health/coverage.rb`（2 → 7 维，保留既有签名与语义）
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/catalog_health/score.rb`（**新建**，只读）
  - `backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/catalog_health_controller.rb`（注入 `@score`）
  - `backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/catalog_health/index.html.erb`（总分区块 + 维度明细）
  - Catalog Health spec（service）+ 工作台请求 spec（AC 映射）
- **零数据库迁移、零 API 契约变更、零权限改动、零导航子项变更。**

## 技术方案（初步）

1. **`Coverage` 扩展**：新增 5 个分母方法（active 商品数、draft 商品数、URL 变更总数等），全部与分子同处一文件以保「分子/分母同源」；`Metric` 结构不变，`coverage_ratio` 为 nil 即「不可计算」。
2. **`Score` 新建**（只读）：输入 `Coverage` + `Report`，输出「总分 + 维度列表（含计入/未计入与原因）+ 计入维度数/总数」；权重为常量并注释理由（默认等权）；`safe_count` 降级的维度按不可计算处理。
3. **控制器/视图**：`@score = Score.call(current_store)`；视图在现有区块下方新增「健康分」卡片（分数 + `缺失/总数` + 覆盖率 + 计入标记 + 页面可见的权重说明）。
4. **i18n**：新增文案键走 en + zh-CN 双语（受 `admin-i18n-rspec` 门禁）。

## 风险点

- **最高风险**：**分母用错**（例如拿「全部商品数」当 `active_zero_stock` / `old_drafts` 的分母）—— 会算出一个**很像对的**错误比率。缓解：AC-002 显式断言这两个分母等于各自的**子集**计数，且断言**不等于**未归档商品总数。
- **次高**：把 `safe_count` 降级返回的 `0` 当真实分子 → 该维虚高满分并抬高总分。缓解：AC-008 构造单维抛错场景，断言该维被排除且总分不被抬高。
- **均分陷阱**：7 维中内容三维共用同一分母（未归档商品数），等权意味着内容占 3/7 权重 —— 这是**有意**的（三类内容问题各自独立），但必须在页面上写清权重，避免「为什么改一张图分涨这么多」的疑问。
- **回滚难度**：低 —— 只读、零迁移、零写路径；回滚 revert commit 即可。

## 决策节点

> 1. **权重**：默认**等权**（每维 1.0，理由：越简单越可解释）。若你希望给某维更高权重（如翻译/库存），请指出，我改一个常量并同步页面说明。
> 2. **分数分级**：本期**不做**「良好/需关注」之类阈值标签（阈值同样是魔数，且会强化 KPI 化）。若你要，请给出阈值与理由。

> ⏸️ **请确认以上理解是否正确。确认后 AI 将进入阶段②输出详细方案文档。**

---

## 阶段②：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core service | `catalog_health/coverage.rb` | Catalog Health spec | 2 → 7 维；`DENOMINATORS` 五套分母均已断言（含「库存/草稿分母 ≠ 商品总数」） | ✅ |
| Core service（新建） | `catalog_health/score.rb` | Catalog Health spec | 总分 == 手工复算；等权；分母为 0 与计数报错分别按 `:no_denominator` / `:count_failed` 排除 | ✅ |
| Admin 控制器/视图 | `catalog_health_controller.rb` + `index.html.erb` | `harness verify admin-catalog-health-rspec` + 渲染取证 | 92 例 0 失败（含新增 18 例）；页面渲染总分/权重说明/逐维行/未计入原因/中文 | ✅ |
| i18n | `admin_catalog_health.zh-CN.yml` + gem `en.yml` | `harness verify admin-i18n-rspec` | 键集 66 = 66 双向相等；门禁绿 | ✅ |
| 选择器加固 | `index.html.erb` + `catalog_health_ai_suggestion_spec.rb` | 全套 catalog health 回归 | issue 清单表加 `data-testid="catalog-health-issues"`，收窄原本过宽的 `doc.css('tbody')` | ✅ |
| 整体 | — | `harness check --profile quick` | 无反模式 / AP-009 干净 / nav-validate 0 警告 | ✅ |

### 验证结论

全绿。实施中有两处需要记录的发现：

1. **既存口径不一致（未擅自改动）**：`Issues.translation_slots` 走 `store.product_ids`（**含已归档**），
   而内容三类走 `not_archived`。所以「翻译维分母 == 未归档商品数」这个假设是**错的** ——
   但分子与分母**同一套集合**，比率本身是对的。已如实写进 spec 断言与 Skill，未改动 `Issues`。
2. **我自己的改动撞坏了别人的断言**：健康分表新增的 `<tbody>` 让 AI 建议 spec 的
   全页 `doc.css('tbody')` 统计从 3 变 4。根因是那个选择器**过宽**（现在页面有两张表），
   已给 issue 清单表加 `data-testid` 并把选择器限定到该表内 —— 断言原意（“每个 issue 一个 tbody，
   只有计数 > 0 的行才有按钮”）完整保留。

另：dev 环境实测 5/7 维计入、总分 85 且手工复算一致；
`ACTIVE_TOTAL_NE_PRODUCTS=false`（dev 店全部商品都是 active）说明**手工验证无法证明两个分母真的不同**，
该断言已在 spec 中用三种状态的数据补上。
