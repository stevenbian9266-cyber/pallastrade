# REQ-20260917-catalog-health-coverage-ratios

> 关联 PRD：`docs/prd/catalog/PRD-20260917-catalog-health-coverage-ratios.md`（approved）
> 任务：`TASK-20260917011408-da073d9d` · Gate：`GATE-2026-09-17T01-14-14`
> 来源：「自主决定」→ 方案 §十六 Health 三项中仍缺的两个 ratio

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| **App** | `backend/app/` | `coverage` / `ratio` | 无 | ❌ 需新建（gem 侧惯例） |
| **Core** | `pallastrade_core/app/services/` | `catalog_health` | `issues.rb`（`count` 唯一口径 + `not_archived` + `other_locales`）、`report.rb`、`{snapshot,trend}.rb` | ⚠️ 口径齐备，**缺比率** |
| **API** | `pallastrade_api/app/` | `catalog_health` / `ratio` | 无 | ✅ 不涉及（不镜像到 v3） |
| **Admin** | `pallastrade_admin/app/` | `catalog_health` | `catalog_health_controller.rb`、`views/.../catalog_health/index.html.erb`（趋势列已就位） | ⚠️ 需加汇总区 |
| **Storefront** | `storefront/src/` | `catalog_health` / `ratio` | 无 | ✅ 不涉及 |
| **Platform** | `platform/packages/` | `ratio` | 无 | ✅ 不涉及 |

**全仓 grep `missing_seo_ratio|missing_translation_ratio|seo_ratio` = 0 命中** → 全新指标，无既有实现可复用。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树 **"Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions"**；本批是**只读派生指标**（不改核心计算、不加订阅者）→ 落在领域服务 + Admin 展示，不碰 Decorator/Events |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | §Catalog Health 确立「**计数 == 下钻列表条数**」是硬不变量、且判定口径唯一权威是 `Issues`；比率是**同一批计数的派生**，分子必须复用 `Issues.count` 而非重写判定 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台只读页范式：`BaseController` + `model_class = PallasTrade::Product` 锚定权限；**改既有页面不动导航**（故 `navigation_consistency_spec` 无需同步）；文案走 `PallasTrade.t('admin.catalog_health.*')` |
| `ai/skills/pallastrade-i18n/SKILL.md` | ✅ 已读 | 新键必须**同步**补宿主 zh-CN（`admin_catalog_health.zh-CN.yml` 已有该域），否则中文门店静默 `Translation missing`；**进 HTML 属性**的文案须用 `I18n.t` + 纯文本兜底 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 验证器注册约定 + "CI 测试库由 `db:prepare` 种入数据"gotcha → 断言必须**自建夹具并限定范围**，且显式随机 store code（已知测试卫生问题） |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 零新表、零新列（纯读取） |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 纯后台展示，不镜像到 v3（D7） |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 只读派生，不发事件 |
| `pallastrade-security` | ⬜ 不涉及 | — | 无凭据/权限模型变更（沿用 Product read 守卫） |
| `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 不改既有类结构、不替换核心服务 |

---

## 需求标题

商品健康覆盖率指标：Missing SEO ratio 与 Missing translation ratio（补方案 §十六）

## 任务类型

功能优化（指标补全）

## 需求描述

方案 §十六 要 `Missing SEO ratio` 与 `Missing translation ratio`，而工作台只给计数。「23 个商品缺 SEO」在 25 个商品的店里是灾难、在 5000 个的店里是噪声 —— **缺的是分母**。

## 影响范围

| 变更文件 | 说明 |
|---|---|
| `pallastrade_core/app/services/pallastrade/catalog_health/coverage.rb` | 新服务（只读） |
| `pallastrade_admin/app/controllers/.../catalog_health_controller.rb` | 注入 `@coverage` |
| `pallastrade_admin/app/views/.../catalog_health/index.html.erb` | 顶部汇总区 |
| admin `en.yml` + 宿主 `admin_catalog_health.zh-CN.yml` | 文案（en/zh-CN 双向一致） |
| specs × 2 | 服务 + 页面 |

**不可触碰**：`Issues` 的判定 SQL、`Report` / `Trend` 既有行为、导航、v3 契约。

## 技术方案（初步）

- **服务** `CatalogHealth::Coverage.call(store)` → 两个比率，各带 `missing` / `total` / `missing_ratio` / `coverage_ratio`。
- **分子**：`Issues.count(store, 'missing_seo')` / `Issues.count(store, 'missing_translations')`（唯一口径）。
- **分母（必须分别定义，不可共用）**：
  - SEO → `store.products.not_archived.count`
  - 翻译 → `商品数 × 支持语言数`（`Issues#missing_translations_count` 是按 `product × locale` 对数计数的）
- **分母 0 / 无其它语言** → `nil`（页面显示空态，不显示 0% 或 100%）。

## 不变量（不得破坏）

1. **分子唯一来源**：必须来自 `Issues.count`，禁止另写判定 SQL（否则与"计数==列表"漂移）。
2. **分母各自自洽**：两个比率**不得共用**分母（D1）。
3. **零写入**：只 SELECT。
4. **分母 0 或无其它语言 → `nil`**：不编造 0% / 100%。
5. **零新表/零新列**。
6. **既有不回归**：7 类计数、下钻链接、趋势列。
7. **文案双语**：新增键必须同时有 en 与 zh-CN（键集断言会守）。

## 文件级实施计划

1. `Coverage` 服务（两个比率 + 诚实空态）。
2. 控制器注入 + 视图汇总区（比率 + 分子/分母，可自行验算）。
3. 文案：gem `en.yml` + 宿主 `admin_catalog_health.zh-CN.yml`。
4. Specs：服务（AC-001~005/007/010）+ 页面（AC-006/009）。
5. 知识同步：catalog Skill（覆盖率口径）、admin Skill（汇总区）、场景、PRD 索引。

## 证据计划

| 改动类型 | 证据 |
|---|---|
| 后端派生指标 | `harness verify catalog-health-coverage-rspec` |
| 后台页面（UI） | 同上 + **浏览器真实渲染**（前两批证明 spec 看不见渲染缺陷） |
| 文档 | `doc-impact` |

## 用户确认

用户 2026-09-17 回复「**自主决定**」，授权我按判断选批次。本批选择理由：方案 §十六 明确要求、审计报告已列为缺口、成本小，且能补齐 Health 三项中的最后两项。
