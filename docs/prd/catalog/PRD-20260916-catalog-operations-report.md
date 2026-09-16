# PRD-20260916-catalog-operations-report

> 商品运营报表：批量操作规模与商品维护频次（只读聚合，零新表）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 「你定」→ 商品域审计（`docs/research/RESEARCH-20260916-catalog-domain-audit.md`）的 **G-6（P2）** |
| 分类 | catalog |
| 关联 Skill | pallastrade-catalog、pallastrade-admin、pallastrade-testing |
| 关联 REQ | `harness/requirements/REQ-20260916-catalog-operations-report.md` |
| 关联 PRD | 承接 `PRD-20260915-catalog-batch-d1-product-history`：那一批**写**时间线，本批**读**它 |
| 需求类型 | 优化迭代（可观测性补全） |

## 1. 背景与目标

- **背景（审计 G-6）**：方案 §十六 要求衡量「Bulk operation products / operation」与「Average product maintenance operations」。
  数据**其实已经在库里** —— D-1 的 `ProductHistory::Recorder` 把每次商品写入记进 `pallastrade_audit_logs`
  （含 `action`、`actor_label`、`resource`、`metadata['source'] == 'bulk'`、`metadata['changed']`），
  但**没有任何聚合视图**：商家只能逐商品看时间线，无法回答"这周批量改了多少商品、人均维护多少"。
- **目标**：一个**只读**的后台报表页，把已有的审计流水变成两个可决策的数字。
- **成功指标**：能在页面上一眼看到窗口内的批量操作规模（次数 + 覆盖商品数）与每商品平均维护动作数；
  页面**零写入**，查询数不随数据量增长。

## 2. 用户故事 / 场景

- 作为**商品运营负责人**，我要知道"这周的批量运营做了多少、覆盖多少商品"，才能判断工具是否被用起来。
- 作为**团队管理者**，我要看到"每个商品平均被维护几次"，才能发现维护不足或过度折腾的商品。
- 边界：
  - 窗口内零数据 → 页面显示空态而不是报错或 NaN。
  - 无 actor 的系统写入（如订阅者/同步）不得被算成"人"的维护动作而不加区分 → 单列 `system`。
  - 报表**只读**：不得写任何表、不得触发任何事件。

## 3. 功能需求（FR）

- FR-001：只读聚合服务 `PallasTrade::Catalog::Operations::Report`（`call(window:)`），数据源**仅** `pallastrade_audit_logs`（`resource_type = 'PallasTrade::Product'`），窗口默认近 7 天，可选 30 天。
- FR-002：按 `action` 分组给出**操作次数**（条目数）与**覆盖商品数**（`resource_id` 去重），并区分 `metadata['source'] == 'bulk'` 与否 → `bulk` / `single` 两栏。
- FR-003：给出**每商品平均维护动作数** = 窗口内 `product.updated` 条目数 ÷ 窗口内有任何条目的不同商品数（分母为 0 时返回 0，不得 NaN）。
- FR-004：给出**操作者榜**（`actor_label` 或 `system`）与各自的动作数，用于回答"谁在维护"。
- FR-005：后台只读页 `/admin/catalog_operations`（Products 菜单子项），支持 `?window=7|30` 切换，零写入。
- FR-006：所有聚合在数据库完成（GROUP BY + COUNT DISTINCT），**查询数不随行数增长**。

## 4. 非功能需求（NFR）

- **只读**：仅 SELECT；不得写审计、不得发事件、不得触发 Sidekiq。
- **性能**：3 个聚合查询（按 action / 按 actor / 维护比率），与窗口内行数无关。
- **多店**：`product.updated` 等条目不带 store 维度（`pallastrade_audit_logs` 无 store_id 时）→ 若无法按店收敛，**必须在 PRD 与页面上明确标注"全局口径"**，不得假装按店隔离。
- **i18n**：文案进 admin locale（en + zh-CN）。
- **可维护性**：口径集中在服务内一处，视图只渲染。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件 |
|---|---|---|
| AC-001 | FR-001 | 服务只读：调用后 `AuditLog.count` 与调用前一致（零写入） |
| AC-002 | FR-002 | 批量写入（`record_bulk` 造 3 个商品）→ `bulk` 栏操作次数=3、覆盖商品数=3 |
| AC-003 | FR-002 | 单条写入与批量写入分别落在 `single` / `bulk` 两栏，互不污染 |
| AC-004 | FR-003 | 5 个更新条目覆盖 2 个商品 → 平均 2.5；窗口内无条目 → 0（非 NaN） |
| AC-005 | FR-004 | 操作者榜包含 `actor_label` 与 `system`（无 actor 的条目） |
| AC-006 | FR-001 | 窗口过滤生效：窗口外的旧条目不计入 |
| AC-007 | FR-005 | `GET /admin/catalog_operations` 200 并渲染指标；`?window=30` 生效；未知 window 回落默认 |
| AC-008 | FR-006 | 渲染页面的查询数不随审计行数增长（10 行 vs 60 行差值 ≤ 3） |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `product_history` / `audit` | 无（能力在 gem 侧） | ❌ 需新建 |
| Core — 服务 | `pallastrade_core/app/services/` | `product_history` / `Report` | **`product_history/recorder.rb`**（写 audit_logs，含 bulk 标记）、`product_history/timeline.rb`（读单商品时间线）、**`catalog_health/report.rb`**、**`payments/costs/report.rb`**（同构的只读聚合报表先例） | ✅ 数据源就绪，**缺聚合视图** |
| Core — 模型 | `pallastrade_core/app/models/` | `AuditLog` / `Report` | `pallastrade/audit_log.rb`（`for_resource`）、`pallastrade/report.rb`（**生成型**报表 STI，不适用） | ⚠️ 用 AuditLog，不用 Report STI |
| API Gem | `pallastrade_api/app/` | `report` | 无 | ✅ 不涉及（报表仅后台） |
| Admin | `pallastrade_admin/app/` | `reports` | `reports_controller.rb`（生成型报表的展示页）、`product_history` 侧栏 partial | ⚠️ 需新建只读页 + 导航子项 |
| Storefront | `storefront/src/` | `report` | 无 | ✅ 不涉及 |
| Platform | `platform/packages/` | `report` | 无 | ✅ 不涉及 |

**结论**：**零新表、零新模型**；新增 1 个只读聚合服务 + 1 个后台控制器/视图 + 1 个导航子项 + 路由；
**不改任何写入路径**（D-1 已在写日志）。

## 7. 技术影响

| 组件 | 文件 | 变更 |
|---|---|---|
| 服务 | `pallastrade_core/app/services/pallastrade/catalog/operations/report.rb` | 新增（只读聚合） |
| 控制器 | `pallastrade_admin/app/controllers/pallastrade/admin/catalog_operations_controller.rb` | 新增 |
| 视图 | `pallastrade_admin/app/views/pallastrade/admin/catalog_operations/index.html.erb` | 新增 |
| 路由 | `pallastrade_admin/config/routes.rb` | 1 行 |
| 导航 | `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb` | Products 下新增子项 |
| 导航回归 | `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb` | 子项数组同步 |
| locale | admin `en.yml` + 宿主 zh-CN | 新增文案 |

**接口契约**：无 Store/Admin API 变更（纯后台 HTML）。

## 8. 测试计划

| 文件 | 覆盖 AC |
|---|---|
| `backend/spec/services/pallastrade/catalog/operations/report_spec.rb` | AC-001~006 |
| `backend/spec/requests/pallastrade/admin/catalog_operations_spec.rb` | AC-007/008 |

**验证器**：新增 `catalog-operations-rspec`。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（运营报表口径：数据源、bulk/single 判定、平均维护数定义、**全局口径声明**）
- [ ] `ai/skills/pallastrade-admin/SKILL.md`（新导航子项 + 只读页约定）
- [ ] `harness/scenarios/scenarios.json`（新场景：运营报表只读且口径诚实）
- [ ] `docs/research/RESEARCH-20260916-catalog-domain-audit.md`（G-6 状态更新）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引

## 10. 关键决策

| # | 决策 | 取值 | 理由 |
|---|---|---|---|
| D1 | 是否复用 `PallasTrade::Report` STI | **不复用** | 那套是**生成型**（要跑 Job 产出并存库），而这里要的是**实时只读聚合**；同构先例是 `CatalogHealth::Report` / `Payments::Costs::Report` |
| D2 | 批量"次数"的口径 | **审计条目数**（每个被操作商品一条），并单列**覆盖商品数**（去重） | `record_bulk` 按商品各写一条，批次本身没有 id；不引入"批次表"就能给出两个诚实的数字 |
| D3 | 多店口径 | 若 `audit_logs` 无 store 维度则**明确标注"全局"** | 宁可写清口径，也不要假装按店隔离（审计 G-8 同源问题，但本批不扩范围） |
| D4 | 窗口切换 | `?window=7|30`，未知值回落 7 | 最小可用；不做自定义区间（避免引入日期选择器与额外校验） |

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿：由审计 G-6 提炼（读 D-1 已写的审计流水，零新表） | AI |
| 2026-09-16 | 1.0 | 用户「你定」授权推进；补 D1~D4、AC 表、测试与同步清单 → 状态 approved | AI |
