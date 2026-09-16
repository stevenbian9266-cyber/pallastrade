# PRD-20260916-catalog-health-trend-snapshot

> Catalog Health 趋势快照：每日增量快照 + 工作台趋势（一表 + 一 job，口径复用 `Issues.count`）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 「继续」→ 商品域审计（`docs/research/RESEARCH-20260916-catalog-domain-audit.md`）的 **G-7（P2）** |
| 分类 | catalog |
| 关联 Skill | pallastrade-catalog、pallastrade-admin、pallastrade-data-model、pallastrade-testing |
| 关联 REQ | `harness/requirements/REQ-20260916-catalog-health-trend-snapshot.md` |
| 关联 PRD | 承接 `PRD-20260915-admin-catalog-health-v1`（那一批只给**当前**计数，本批给它**时间维度**） |
| 需求类型 | 优化迭代（可观测性补全） |

## 1. 背景与目标

- **背景（审计 G-7）**：Catalog Health 工作台（`/admin/catalog_health`）只有**当前**计数 —— 它是一张"待办清单"，不是一条"趋势线"。方案 §十六 的指标「Unresolved Catalog Health Issues」因此**缺时间维度**：商家能看到"现在有 37 个待办"，但回答不了"治理在变好还是变差"。
- **目标**：给每个 issue 留下**每日一条**的计数快照，并在工作台上把它读成趋势（方向 + 变化量），使"治理是否有效"成为可观测的事实。
- **非目标**：不做图表库/BI 面板；不做自定义时间区间；不改变既有 7 类 issue 的**判定口径**（那是 `CatalogHealth::Issues` 的权威）。

## 2. 用户故事 / 场景

- **US-1**：作为店主，我想在工作台上看到每类待办的「近 30 天变化」，好判断上一轮治理（批量补描述、批量补翻译）到底有没有让数字下降。
- **US-2**：作为店主，我希望数字变差时能立刻看出来（而不是靠记忆对比），以便及时止损。
- **US-3**：作为运维，我希望快照是**幂等**的 —— 同一天重跑不会产生重复行、不会把当天数字写乱。
- **场景**：某店周一有 40 个 `missing_description`，周三做了批量补全后降到 12。周一的商家看到趋势列显示 `-28 较 30 天前`，方向为**改善**。

## 3. 功能需求（FR）

| ID | 需求 | 说明 |
|---|---|---|
| FR-001 | 每日快照表 | `pallastrade_catalog_health_snapshots`：`store_id` × `issue_key` × `captured_on`（date）+ `count`（int）；唯一索引 `(store_id, issue_key, captured_on)` |
| FR-002 | 采集服务 | `CatalogHealth::Snapshot.capture(store, on:)` —— 对 7 个 key 各调**既有** `Issues.count(store, key)`，同日重复采集**幂等**（更新而不新增） |
| FR-003 | 采集作业 | `CatalogHealth::SnapshotSweeperJob`（sidekiq-cron 每日 02:00）遍历所有店铺；**单店失败不阻断其他店** |
| FR-004 | 趋势读取 | `CatalogHealth::Trend.call(store, days: 30)` —— 每个 issue 给出序列、与**窗口内最早可用快照**的差值、方向（`improving` / `worsening` / `flat` / `unknown`） |
| FR-005 | 工作台趋势列 | `/admin/catalog_health` 每行新增趋势列（方向 + 差值 + 迷你条）；顶部汇总显示待办总数趋势 |
| FR-006 | 空态诚实 | 无任何快照（新店/首日）时显示"暂无趋势"，**不得**把缺失当成 0 或持平 |

## 4. 非功能需求（NFR）

| ID | 要求 |
|---|---|
| NFR-001 | **不变量**：快照计数必须与工作台/列表**同源**（复用 `Issues.count`，禁止另写一套 SQL） |
| NFR-002 | **零副作用**：采集只写快照表；不触碰商品/媒体/翻译/redirect，不发事件 |
| NFR-003 | **幂等**：同日重跑不新增行、计数覆盖为当次值 |
| NFR-004 | **有界**：采集按店铺遍历且有上限；趋势读取只取窗口内行，查询数不随快照天数增长 |
| NFR-005 | **隔离**：快照按 `store_id` 隔离，跨店不可见 |
| NFR-006 | **容错**：单店采集异常被捕获并记录，不影响其余店铺与作业本身 |

## 5. 验收标准（AC，与测试一一映射）

| ID | 验收标准 |
|---|---|
| AC-001 | 采集结果逐项等于 `Issues.count(store, key)`（口径同源） |
| AC-002 | 同日重复采集不新增行，且计数被更新为最新值（幂等） |
| AC-003 | 不同店铺的快照互不可见（跨店隔离） |
| AC-004 | 趋势差值 = 当前计数 − 窗口内最早可用快照计数；方向按差值符号映射 |
| AC-005 | 无快照时趋势方向为 `unknown`、差值为 `nil`（不编造 0） |
| AC-006 | 工作台渲染趋势列，且既有 7 类计数与下钻链接**不变**（回归"计数==列表") |
| AC-007 | 采集作业单店失败被捕获，其他店铺仍被采集；作业不抛出 |
| AC-008 | 页面需要 Product read 权限（沿用既有守卫） |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索路径 | 关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| **App** | `backend/app/` | `snapshot` / `trend` / `catalog_health` | 无 | ❌ 需新建（gem 侧惯例） |
| **Core** | `pallastrade_core/app/` | `catalog_health` / `snapshot` / `trend` | `catalog_health/issues.rb`（`KEYS` + `count`：**唯一口径权威**）、`catalog_health/report.rb`（`Issue` struct）、`app/jobs/**/*_sweeper_job.rb`（9 个 sweeper 先例） | ⚠️ 口径已有，**缺快照与趋势** |
| **API** | `pallastrade_api/app/` | `catalog_health` / `report` | 无 | ✅ 不涉及（纯后台 HTML） |
| **Admin** | `pallastrade_admin/app/` | `catalog_health` | `catalog_health_controller.rb`（`Report.call(current_store)`）、`views/.../catalog_health/index.html.erb`（只有当前计数） | ⚠️ 需加趋势列 |
| **Storefront** | `storefront/src/` | `catalog_health` / `CatalogHealth` | 无（已验证 0 命中） | ✅ 不涉及 |
| **Platform** | `platform/packages/` | `catalog_health` / `snapshot` | 无 | ✅ 不涉及 |

**调度面**：`backend/config/sidekiq_schedule.rb`（既有 16 处 cron 注册；01:00 / 01:30 已被 dispute sweeper 占用 → 本批取 **02:00**）。

**结论**：零既有快照能力（搜索 0 命中）→ 新增 1 表 + 2 服务 + 1 job + 1 调度注册 + 1 视图改动 + locale；**口径零重复**（复用 `Issues.count`）。

## 7. 技术影响

| 变更文件 | 说明 |
|---|---|
| `backend/db/migrate/20260916xxxxxx_create_pallastrade_catalog_health_snapshots.rb` + gem 侧同名迁移 | 新表 + 唯一索引 + store 外键 |
| `pallastrade_core/app/models/pallastrade/catalog_health_snapshot.rb` | 模型（校验 issue_key ∈ `Issues::KEYS`、count ≥ 0） |
| `pallastrade_core/app/services/pallastrade/catalog_health/snapshot.rb` | 采集（幂等） |
| `pallastrade_core/app/services/pallastrade/catalog_health/trend.rb` | 趋势读取 |
| `pallastrade_core/app/jobs/pallastrade/catalog_health/snapshot_sweeper_job.rb` | 每日采集 |
| `backend/config/sidekiq_schedule.rb` | +1 条 cron（02:00） |
| `pallastrade_admin/app/controllers/.../catalog_health_controller.rb` | 注入 `@trend` |
| `pallastrade_admin/app/views/.../catalog_health/index.html.erb` | +趋势列 + 空态 |
| admin `en.yml` | 文案 |

**不可触碰**：`CatalogHealth::Issues` 的 7 类判定 SQL（口径权威）、`CatalogHealth::Report` 的既有行为、v3 契约。

## 8. 测试计划

| 测试文件 | 覆盖 |
|---|---|
| `backend/spec/services/pallastrade/catalog_health/snapshot_spec.rb` | AC-001 / AC-002 / AC-003 |
| `backend/spec/services/pallastrade/catalog_health/trend_spec.rb` | AC-004 / AC-005 |
| `backend/spec/jobs/pallastrade/catalog_health/snapshot_sweeper_job_spec.rb` | AC-007 |
| `backend/spec/requests/pallastrade/admin/catalog_health_trend_spec.rb` | AC-006 / AC-008 |
| 回归 | 既有 `admin-catalog-health-rspec`（AC-006 的"计数==列表"不变量） |

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-catalog/SKILL.md`（快照口径：复用 `Issues.count`、幂等、趋势语义）— 新增「Catalog Health 趋势快照」章节
- [x] `ai/skills/pallastrade-admin/SKILL.md`（工作台趋势列 + 空态）— 新增「Catalog Health 趋势列」小节
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（新表）— changelog 登记 `pallastrade_catalog_health_snapshots`
- [x] `harness/scenarios/scenarios.json`（新场景：趋势快照口径同源 + 幂等 + 空态诚实）— **GS-161**
- [x] `docs/research/RESEARCH-20260916-catalog-domain-audit.md`（G-7 状态更新）— G-7 段补「已实施 + 两处比建议更严的口径」，优先级表改 ✅
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引 — 状态改 `done`

**未改动（已评估，无需更新）**：

- `pallastrade-api-v3` Skill + `backend/public/api-docs/{store,admin}.yaml` + SDK 类型：纯后台 HTML，无 v3 契约
- `AGENTS.md` / `.github/copilot-instructions.md`：无新流程/反模式规则（未改动 Products 导航，故不动 `navigation_consistency_spec`）
- `pallastrade-prd` Skill：PRD 流程未变
- `pallastrade-deployment` Skill：新 cron 由既有 `config/initializers/pallastrade_sidekiq_cron.rb` 加载（worker 侧生效），无新部署步骤

## 10. 关键决策

| # | 决策 | 取值 | 理由 |
|---|---|---|---|
| D1 | 快照 vs 实时重算 | **每日增量快照** | 判定口径会随代码演进（如 `old_drafts` 阈值调整）；历史必须按**当日口径**保存，事后重算会篡改历史 |
| D2 | 幂等实现 | **唯一索引 + 同日覆盖** | 重复采集（重跑、补跑）不得产生重复行；DB 约束比应用层判断更可靠 |
| D3 | 趋势基准点 | **窗口内最早可用快照** | 与"前一日"比会放大人为日内噪音；与窗口起点比才回答"这轮治理有没有效果" |
| D4 | 趋势窗口 | **固定 30 天** | 与快照表规模（30 × 7 × 店数）一起保持有界；不做自定义区间 |
| D5 | 调度时间 | **每日 02:00** | 错开 01:00（争议期限）/ 01:30（争议收敛） |
| D6 | 是否新增 v3 端点 | **不新增** | 纯后台展示；趋势不是外部契约 |
| D7 | 缺失数据的表达 | **`unknown` + `nil`** | 新店首日没有快照是真事实，"持平"是编造 |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿：由审计 G-7 提炼（复用 `Issues.count` 口径，只加快照与趋势） | AI |
| 2026-09-16 | 1.0 | 用户「继续」授权推进；补 FR/AC/NFR、6 层搜索、D1~D7 → 状态 approved | AI |
| 2026-09-16 | 1.1 | 实施完成：新表 + Snapshot/Trend 服务 + SweeperJob + 工作台趋势列；29 新例全绿 + 既有 17 例回归全绿；知识同步全部落地（含 GS-161）；状态 → done | AI |
