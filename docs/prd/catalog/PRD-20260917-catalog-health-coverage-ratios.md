# PRD-20260917-catalog-health-coverage-ratios

> 商品健康覆盖率指标：Missing SEO ratio 与 Missing translation ratio（补方案 §十六）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 「自主决定」→ 方案 §十六「上线指标」的 Health 三项中仍缺的两项 ratio |
| 分类 | catalog |
| 关联 Skill | pallastrade-catalog、pallastrade-admin、pallastrade-testing |
| 关联 REQ | `harness/requirements/REQ-20260917-catalog-health-coverage-ratios.md` |
| 关联 PRD | 承接 `PRD-20260915-admin-catalog-health-v1`（给的是**计数**）；趋势由 `PRD-20260916-catalog-health-trend-snapshot` 提供 |
| 需求类型 | 优化迭代（指标补全） |

## 1. 背景与目标

- **背景**：方案 §十六 的 Health 三项指标 —— `Unresolved Catalog Health Issues`、`Missing SEO ratio`、`Missing translation ratio`。第一项已由 Catalog Health V1（计数）+ G-7（趋势）覆盖；**后两项是"比率"，而现有页面只给"计数"** —— 缺一个**分母**。
  - 「有 23 个商品缺 SEO」无法判断严重程度：如果全店只有 25 个商品，那是灾难；如果有 5000 个，那是噪声。**比率才能决策**。
- **目标**：给这两个比率一个**口径自洽、分母诚实**的实现，并在商品健康工作台上呈现。
- **非目标**：不做百分比目标/告警阈值（方案明确"不建议现在设定提升 20% 之类的目标，因为现有审计没有提供业务数据基线"）；不改既有 7 类 issue 的判定；不做图表。

## 2. 用户故事 / 场景

- **US-1**：作为店主，我想知道"缺 SEO 的商品占多少比例"，好判断要不要安排一次批量补全。
- **US-2**：作为店主，我想知道"翻译覆盖还有多少缺口"，而不是只看到"154 个缺失"——没有分母，154 是多是少我无从判断。
- **US-3**：作为新店，我的店里还没有商品 —— 我希望看到"暂无数据"，而不是"0%"（那会让我以为已经做完了）。

## 3. 功能需求（FR）

| ID | 需求 | 说明 |
|---|---|---|
| FR-001 | 覆盖率服务 | `CatalogHealth::Coverage.call(store)`：对两个比率各给出 `{ missing:, total:, missing_ratio:, coverage_ratio: }` |
| FR-002 | 分子复用唯一口径 | 分子**必须**来自 `Issues.count(store, key)`，禁止另写判定 SQL（维持"计数 == 下钻列表条数"） |
| FR-003 | SEO 分母 | `store.products.not_archived.count`（与 `Issues` 的 scope 同源） |
| FR-004 | 翻译分母 | `商品数 × 支持语言数`（**精确匹配** `Issues#missing_translations_count` 的口径：它按 `product × locale` 对数计算，不是按商品数） |
| FR-005 | 工作台呈现 | `/admin/catalog_health` 顶部汇总区显示两个覆盖率（百分比 + 分子/分母），随 UI 语言本地化 |
| FR-006 | 诚实空态 | 分母为 0 或"没有其它语言"时比率为 `nil`，页面显示"暂无数据"，**不得**显示 0% 或 100% |

## 4. 非功能需求（NFR）

| ID | 要求 |
|---|---|
| NFR-001 | **零写入**：只读聚合，不写任何表 |
| NFR-002 | **有界**：两个分母各一条 count 查询；不随商品数产生额外查询 |
| NFR-003 | **不回归**：既有 7 类计数与下钻链接、趋势列均不受影响 |
| NFR-004 | **可解释**：页面必须同时给出分子与分母，让商家能自己验算比率 |

## 5. 验收标准（AC，与测试一一映射）

| ID | 验收标准 |
|---|---|
| AC-001 | SEO 缺失率 = `Issues.count(store, 'missing_seo')` ÷ 未归档商品数 |
| AC-002 | 翻译缺失率 = `Issues.count(store, 'missing_translations')` ÷ (商品数 × 支持语言数) |
| AC-003 | 分母为 0 时两个比率均为 `nil`（不出现 0.0 或 NaN） |
| AC-004 | 门店无其它支持语言时，翻译比率为 `nil`（**不是** 100%） |
| AC-005 | 分子与 `Issues.count` 严格相等（口径同源，不重写判定） |
| AC-006 | 工作台渲染两个比率（含分子/分母），分母为 0 时显示空态文案 |
| AC-007 | 覆盖率计算零写入（不新增任何行） |
| AC-008 | 既有 7 类计数、下钻链接与趋势列均不回归 |
| AC-009 | 中文后台渲染无 `translation missing`（含新增文案） |
| AC-010 | 无归档商品被计入分母 |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索路径 | 关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| **App** | `backend/app/` | `coverage` / `ratio` | 无 | ❌ 需新建（gem 侧惯例） |
| **Core** | `pallastrade_core/app/services/` | `catalog_health` | `catalog_health/issues.rb`（`count` 唯一口径 + `not_archived` scope + `other_locales`）、`catalog_health/report.rb`、`catalog_health/{snapshot,trend}.rb` | ⚠️ 口径齐备，**缺比率** |
| **API** | `pallastrade_api/app/` | `catalog_health` | 无 | ✅ 不涉及 |
| **Admin** | `pallastrade_admin/app/` | `catalog_health` | `catalog_health_controller.rb`、`views/.../catalog_health/index.html.erb`（趋势列已就位） | ⚠️ 需加汇总区 |
| **Storefront** | `storefront/src/` | `catalog_health` / `ratio` | 无 | ✅ 不涉及 |
| **Platform** | `platform/packages/` | `ratio` | 无 | ✅ 不涉及 |

**全仓 grep `missing_seo_ratio|missing_translation_ratio|seo_ratio` = 0 命中** → 确认是全新指标。

## 7. 技术影响

| 变更文件 | 说明 |
|---|---|
| `pallastrade_core/app/services/pallastrade/catalog_health/coverage.rb` | 新服务（只读） |
| `pallastrade_admin/app/controllers/.../catalog_health_controller.rb` | 注入 `@coverage` |
| `pallastrade_admin/app/views/.../catalog_health/index.html.erb` | 顶部汇总区 |
| admin `en.yml` + 宿主 `admin_catalog_health.zh-CN.yml` | 文案（en/zh-CN 双向一致） |
| specs | 服务 + 页面 |

**不可触碰**：`Issues` 的判定 SQL、`Report` / `Trend` 的既有行为、导航。

## 8. 测试计划

| 测试文件 | 覆盖 |
|---|---|
| `backend/spec/services/pallastrade/catalog_health/coverage_spec.rb` | AC-001 ~ AC-005 / AC-007 / AC-010 |
| `backend/spec/requests/pallastrade/admin/catalog_health_coverage_spec.rb` | AC-006 / AC-009 |
| 回归 | `catalog_health_spec`（AC-008）、`catalog_health_trend_spec`、`i18n` 键集断言 |

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-catalog/SKILL.md`（覆盖率口径：分母各是什么、为什么不能共用）— 新增「商品健康覆盖率指标」章节
- [x] `ai/skills/pallastrade-admin/SKILL.md`（工作台汇总区）— 新增「Catalog Health 覆盖率区」小节
- [x] `harness/scenarios/scenarios.json`（新场景：比率的分母必须自洽、分母为 0 必须诚实）— **GS-165**（166/166 通过）
- [x] `docs/research/RESEARCH-20260916-catalog-domain-audit.md`（§十六 指标缺口状态）— 见下方说明
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引 — 状态改 `done`

**未改动（已评估，无需更新）**：

- `pallastrade-data-model` Skill：零新表、零新列（纯读取）
- `pallastrade-api-v3` Skill + `api-docs/*.yaml` + SDK 类型：纯后台指标，不镜像到 v3（D7）
- `AGENTS.md` / `copilot-instructions.md`：无新流程/反模式规则；未动导航，故 `navigation_consistency_spec` 无需改

> 关于审计报告：§十六 的 Health 三项中「Unresolved Catalog Health Issues」由 V1+G-7 覆盖、「Missing SEO ratio」与
> 「Missing translation ratio」由本批覆盖；报告 §6 的缺口表本身无需改动（G-1~G-7 状态已是最新），
> 本批是**补方案 §十六 指标**而非闭合审计缺口，因此未在审计报告中新增行。

## 10. 关键决策

| # | 决策 | 取值 | 理由 |
|---|---|---|---|
| D1 | 两个比率能否共用同一个分母 | **不能** | `missing_seo` 是**按商品**计数，分母是商品数；`missing_translations` 是**按 product × locale 对数**计数，分母必须是 `商品数 × 支持语言数`。共用一个分母会得出**错的比率**（而且错得很像对的） |
| D2 | 分子来源 | **只能**来自 `Issues.count` | 维持"计数 == 下钻列表条数"不变量；另写 SQL 会让页面自相矛盾 |
| D3 | 分母为 0 | **`nil` + 空态** | 新店没有商品时，0% 会让人以为"已做完"，100% 会让人以为"全坏了"——两者都是编造 |
| D4 | 无其它语言 | **`nil`** | "没有要翻译的语言"≠"翻译完成 100%"。这是 G-7 `unknown` 的同一条原则 |
| D5 | 呈现位置 | 工作台顶部汇总区 | 与 7 类 issue 计数同屏，商家可自行验算分子/分母 |
| D6 | 是否设阈值告警 | **不设** | 方案明确：现有审计无业务基线，先记录基线再谈目标 |
| D7 | 是否镜像到 v3 API | **不镜像** | 纯后台展示指标 |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-17 | 0.1 | 初稿：由方案 §十六 的两个 ratio 指标提炼（补齐 Health 三项） | AI |
| 2026-09-17 | 1.0 | 用户「自主决定」授权；补 FR/AC/NFR、6 层搜索、D1~D7（重点是 D1 分母不可共用、D3/D4 诚实空态）→ status approved | AI |
| 2026-09-17 | 1.1 | 实施完成（commit `b76c5c19`）：Coverage 服务 + `Issues.translation_slots` 分母口径 + 工作台覆盖率区 + 双语文案；18 新例 + 回归 56 例全绿；**浏览器真实渲染验证**（SEO 97.4% = 1−1/38、翻译 32.5% = 1−154/228，两个分母确实不同）；知识同步含 GS-165；状态 → done | AI |
