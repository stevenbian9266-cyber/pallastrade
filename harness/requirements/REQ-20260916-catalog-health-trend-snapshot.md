# REQ-20260916-catalog-health-trend-snapshot

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-health-trend-snapshot.md`（approved）
> 任务：`TASK-20260916135530-ad3b2d4f` · Gate：`GATE-2026-09-16T13-55-36`
> 来源：商品域审计 G-7（P2）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| **App** | `backend/app/` | `snapshot` / `trend` / `catalog_health` | 无 | ❌ 需新建（gem 侧惯例；Host App 只放净新增模块） |
| **Core** | `pallastrade_core/app/` | `catalog_health` / `snapshot` / `trend` | `catalog_health/issues.rb`（`KEYS` 7 项 + `count(store, key)` = **唯一口径权威**）、`catalog_health/report.rb`、`app/jobs/**/*_sweeper_job.rb`（9 个 sweeper 先例） | ⚠️ 口径已有，**缺快照/趋势** |
| **API** | `pallastrade_api/app/` | `catalog_health` / `report` | 无 | ✅ 不涉及（纯后台 HTML） |
| **Admin** | `pallastrade_admin/app/` | `catalog_health` | `catalog_health_controller.rb`（`Report.call(current_store)`）+ `views/.../catalog_health/index.html.erb`（只有当前计数） | ⚠️ 需加趋势列 |
| **Storefront** | `storefront/src/` | `catalog_health` / `CatalogHealth` | 无（grep 0 命中，已验证） | ✅ 不涉及 |
| **Platform** | `platform/packages/` | `catalog_health` / `snapshot` | 无 | ✅ 不涉及 |

**调度面**：`backend/config/sidekiq_schedule.rb`（16 处 cron 注册；01:00 dispute_deadline_sweep、01:30 dispute_recovery_sweep 已占用 → 本批取 **02:00**）。

**零既有快照能力**（`catalog_health_snapshot|CatalogHealthSnapshot|health_trend` 全仓 grep 0 命中）→ 新增
1 表 + 1 模型 + 2 服务 + 1 job + 1 调度注册 + 控制器注入 + 视图列 + locale；**口径零重复**。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树 **"Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions"**；本批不改核心计算逻辑，只是**给既有权威口径加时间维度**（Admin 一级 + 新数据表），不碰 Decorator/Events |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | §Catalog Health 段落确立"**计数 == 列表条数**"是硬不变量（计数与下钻列表同源）；本批快照必须复用 `Issues.count` 而**不得**另写一套判定 SQL |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台只读页范式：`BaseController` + `model_class = PallasTrade::Product` 锚定权限；改动 Products 下**既有**页面不需要动导航（本批不动导航）；文案走 `PallasTrade.t('admin.catalog_health.*')` |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | 新表惯例：`PallasTrade.base_class`、门店维度列 + 组合唯一索引（如 D15 的 `(order_id, evaluated_at)` 唯一键保证并发只落一行）、**Changelog 段须登记新表**（L474 D-3 为先例） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 验证器注册约定 + "CI 测试库非空（`db:prepare` 会 seed）"gotcha → **必须**（a）显式随机 store code（已知测试卫生问题）、（b）断言限定本用例数据 |
| `pallastrade-deployment` | ⬜ 轻涉及 | ✅ 已读 | 新增 sidekiq-cron 条目由 `config/initializers/pallastrade_sidekiq_cron.rb` 在 **sidekiq 进程**加载 → 部署后需 worker 重启生效（无需 web 侧改动） |
| `pallastrade-i18n` | ⬜ 轻涉及 | — | 新文案进 admin `en.yml`（zh-CN 不在授权 glob 内，另行补） |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 采集是内部快照，**不发事件**（NFR-002） |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 纯后台 HTML，无 v3 契约 |
| `pallastrade-security` | ⬜ 不涉及 | — | 无凭据/权限模型变更（沿用既有 Product read 守卫） |
| `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 不改既有类结构、不替换核心服务 |

---

## 需求标题

Catalog Health 趋势快照：每日增量快照 + 工作台趋势（一表 + 一 job，口径复用 `Issues.count`）

## 任务类型

功能优化（可观测性补全）

## 需求描述

Catalog Health 工作台能告诉你"现在有 37 个待办"，但回答不了"治理在变好还是变差"。本批给每个 issue 每天留一条计数快照，并在工作台上把它读成趋势。

## 影响范围

| 变更文件 | 说明 |
|---|---|
| `backend/db/migrate/20260916xxxxxx_create_pallastrade_catalog_health_snapshots.rb` + gem 侧同名 | 新表 + 唯一索引 |
| `pallastrade_core/app/models/pallastrade/catalog_health_snapshot.rb` | 新模型 |
| `pallastrade_core/app/services/pallastrade/catalog_health/{snapshot,trend}.rb` | 采集（幂等）+ 趋势读取 |
| `pallastrade_core/app/jobs/pallastrade/catalog_health/snapshot_sweeper_job.rb` | 每日采集作业 |
| `backend/config/sidekiq_schedule.rb` | +1 条 cron（02:00） |
| `pallastrade_admin/app/controllers/.../catalog_health_controller.rb` | 注入趋势 |
| `pallastrade_admin/app/views/.../catalog_health/index.html.erb` | +趋势列 + 空态 |
| admin `en.yml` | 文案 |

**不可触碰**：`CatalogHealth::Issues` 的 7 类判定 SQL（口径权威）、`CatalogHealth::Report` 既有行为、v3 契约、导航（本批不改菜单）。

## 技术方案（初步）

- **表**：`pallastrade_catalog_health_snapshots`：`store_id`、`issue_key`(string)、`captured_on`(date)、`count`(integer, default 0) + timestamps；唯一索引 `(store_id, issue_key, captured_on)`。
- **采集** `Snapshot.capture(store, on: Date.current)`：对 `Issues::KEYS` 逐个调 `Issues.count(store, key)`，用 `upsert`/`find_or_initialize_by` 同日覆盖（幂等）。
- **趋势** `Trend.call(store, days: 30)`：一次查询取窗口内行 → 内存分组；每个 issue 给 `current`（最新快照）、`baseline`（窗口内最早）、`delta`、`direction`（improving/worsening/flat/unknown）。
- **作业** `SnapshotSweeperJob`：遍历 `PallasTrade::Store`（有上限），**逐店 rescue**，异常记录后继续。

## 不变量（不得破坏）

1. **口径同源**：快照计数必须来自 `Issues.count`，禁止另写判定 SQL（否则"计数==列表"会漂移）。
2. **幂等**：同店同日同 key 只有一行；重跑覆盖当日计数。
3. **只写快照表**：不触碰商品/媒体/翻译/redirect，不发事件。
4. **缺失即 `unknown`**：无快照时不得显示 0 或"持平"。
5. **按店隔离**：`store_id` 过滤；跨店不可见。
6. **有界**：趋势读取只取窗口内行；采集按店铺遍历有上限、单店失败不阻断。
7. **既有 AC 不回归**：工作台 7 类计数与下钻链接保持不变。

## 文件级实施计划

1. 迁移（宿主 `backend/db/migrate/` + gem 侧 `pallastrade_core/db/migrate/`），类名遵循既有 inflection。
2. 模型（校验 `issue_key ∈ Issues::KEYS`、`count >= 0`，唯一性）。
3. `Snapshot` 采集服务（幂等）。
4. `Trend` 趋势服务（delta/direction/unknown）。
5. `SnapshotSweeperJob` + `sidekiq_schedule.rb` 注册。
6. 控制器注入 + 视图趋势列（方向 + 差值 + 迷你条）+ 空态 + locale。
7. Specs：采集 / 趋势 / 作业 / 页面请求；注册验证器 `catalog-health-trend-rspec`。
8. 知识同步：catalog Skill（快照与趋势口径）、admin Skill（趋势列）、data-model Skill（新表 + changelog）、场景、审计报告 G-7。

## 证据计划

| 改动类型 | 证据 |
|---|---|
| Model / DB / migration | `harness check --profile full` 不适用（时间），改：新 spec 全绿 + 既有 catalog-health 回归全绿 |
| 后端聚合 | `harness verify catalog-health-trend-rspec` |
| 后台页面 | 同上（含请求 spec） |
| 文档 | `doc-impact` + `sync-check` |

## 用户确认

用户 2026-09-16 回复「**继续**」，在我上轮提问（"G-7 要现在开，还是先停一下等你定方向？"）之后 —— 即授权推进 G-7（P2，审计剩余缺口中的高优先项）。
