# REQ-20260916-catalog-operations-report

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-operations-report.md`（approved）
> 任务：`TASK-20260916132646-1b201e1e` · Gate：`GATE-2026-09-16T13-26-57`
> 来源：商品域审计 G-6（P2）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — controllers | `backend/app/` | `report` / `catalog_operations` | 无 | ❌ 需新建（报表在 gem 侧惯例） |
| App — views | `backend/app/` | `report` | 无 | ❌ |
| Core Gem — models | `pallastrade_core/app/models/` | `AuditLog` / `Report` | `pallastrade/audit_log.rb`、`pallastrade/report.rb`（**生成型** STI，不适用） | ⚠️ 用 AuditLog |
| Core Gem — services | `.../app/services/` | `product_history` / `Report` | `product_history/recorder.rb`（写 audit_logs，`metadata['source']='bulk'`）、`product_history/timeline.rb`（单商品时间线）、`catalog_health/report.rb`、`payments/costs/report.rb`（**同构只读聚合先例**） | ✅ 数据源就绪，**缺聚合视图** |
| API Gem — controllers | `pallastrade_api/app/controllers/` | `report` | 无 | ✅ 不涉及 |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | `reports` | `reports_controller.rb`（生成型报表展示页） | ⚠️ 需新建只读页 |
| Admin Gem — views | `pallastrade_admin/app/views/` | `reports` / `_history` | `reports/`、`products/_history.html.erb` | ⚠️ 需新建视图 |
| Admin Gem — 初始化 | `pallastrade_admin/config/initializers/` | `navigation` | `pallastrade_admin_navigation.rb`（Products 子项数组） | ⚠️ 需加子项 |
| Storefront | `storefront/src/` | `report` | 无 | ✅ 不涉及 |
| Platform | `platform/packages/` | `report` | 无 | ✅ 不涉及 |

### 搜索结论

**零新表、零新模型、零写入路径改动**（D-1 已在写 `pallastrade_audit_logs`）。
新增：1 个只读聚合服务 + 1 个后台控制器/视图 + 1 个路由 + 1 个导航子项 + locale + 2 个 spec。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树 **"Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → Generators → Decorators → Extensions"**；本批是**只读报表**（不改核心计算、不加订阅者）→ 落在 Admin 一级（新增后台页 + 导航），不碰 Decorator/Events |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台约定：`tables.register` + 逐列 `.add`、导航改动**必须同步** `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb` 子项数组（该 spec 会断言导航与路由同源）；只读页沿用既有 layout/面包屑 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | §Product History（D-1）确立了"审计流水即时间线"的口径（`ProductHistory::Recorder` 写 `audit_logs`）；本批是**同一数据源的聚合读**，口径必须复用而非另建 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 验证器注册约定 + "CI 测试库非空（`db:prepare` 会 seed）"gotcha → 聚合断言必须**限定窗口与夹具**，不能假设表里只有本用例的数据 |
| `pallastrade-i18n` | ✅ 涉及（轻） | — | 新页面文案进 admin locale（en + zh-CN 双补） |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 零新表零新列 |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 纯后台 HTML，无 v3 契约 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 只读报表不发事件 |
| `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 不改既有类结构、不替换核心服务 |

---

## 需求标题

商品运营报表：批量操作规模与商品维护频次（只读聚合，零新表）

## 任务类型

功能优化（可观测性补全）

## 需求描述

D-1 已经把每次商品写入记进了审计流水，但没人能把这些流水变成"本周批量改了多少商品""每个商品平均维护几次"。本批加一个**只读**后台页，把已有数据聚合成这两个数字。

## 影响范围

| 变更文件 | 说明 |
|---|---|
| `pallastrade_core/app/services/pallastrade/catalog/operations/report.rb` | 新增只读聚合服务 |
| `pallastrade_admin/app/controllers/pallastrade/admin/catalog_operations_controller.rb` | 新增 |
| `pallastrade_admin/app/views/pallastrade/admin/catalog_operations/index.html.erb` | 新增 |
| `pallastrade_admin/config/routes.rb` | 1 行 |
| `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb` | Products 下新增子项 |
| `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb` | 子项数组同步（硬要求） |
| admin `en.yml` + 宿主 zh-CN locale | 文案 |

**不可触碰**：`ProductHistory::Recorder` 与任何写入路径、`PallasTrade::Report` STI 框架、v3 契约。

## 技术方案（初步）

- **服务**：`Catalog::Operations::Report.call(window: 7.days)` →
  - `action_rows`：`group(:action)` → `count` + `count(distinct resource_id)`，并 `split { |r| bulk?(r) }`
  - `maintenance`：`product.updated` 条目数 ÷ 有任一条目的不同商品数（分母 0 → 0）
  - `actors`：`group(:actor_label)` → `count`（`nil` → `system`）
  - 三个查询都带 `occurred_at >= window_start` 与 `resource_type = 'PallasTrade::Product'`
- **控制器**：`window` 白名单 `%w[7 30]`，未知回落 `7`；只读 `@report`。
- **视图**：三段（批量 vs 单条 / 维护比率 / 操作者榜）+ 窗口切换 + 空态 + **全局口径声明**。

## 不变量（不得破坏）

1. **零写入**：服务只 SELECT。
2. **零新表/零新列**。
3. 窗口过滤必须生效（窗口外条目不计入）。
4. 分母 0 时比率为 `0`，**不得** NaN/Infinity。
5. 聚合在 DB 完成：查询数与窗口内行数**无关**。
6. 导航与路由同源（`navigation_consistency_spec` 必须一起改）。

## 文件级实施计划

1. 服务（含 bulk 判定与比率计算）。
2. 控制器 + 路由 + 导航子项 + `navigation_consistency_spec` 同步。
3. 视图（三段 + 窗口切换 + 空态 + 全局口径声明）。
4. locale（en + zh-CN）。
5. Specs：服务（AC-001~006）+ 请求（AC-007/008）；注册 `catalog-operations-rspec`。
6. 知识同步：catalog Skill（报表口径）、admin Skill（导航子项 + 只读页）、场景、审计报告 G-6 状态。

## 证据计划

| 改动类型 | 证据 |
|---|---|
| 后端聚合 | `harness verify catalog-operations-rspec` |
| 导航一致性 | 同上（含 `navigation_consistency_spec`） |
| 文档 | `doc-impact` + `sync-check` |

## 用户确认

用户 2026-09-16 回复「**你定**」，授权我按审计 ROI 选择并推进（本批选 G-6，理由：零新表、成本最低、直接补齐方案 §16 的两项 Admin 指标）。
