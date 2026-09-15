# PRD-20260915-catalog-batch-d1-product-history

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》§十二「治理第二步：商品级 Product History」（用户授权原话：「继续」，2026-09-15） |
| 分类 | catalog（商品域 / 运营治理） |
| 关联 Skill | pallastrade-admin / pallastrade-data-model / pallastrade-customization |
| 关联 REQ | REQ-20260915-batch-d1-product-history.md |
| 关联 PRD | 同计划：B-1 = `PRD-20260915-admin-bulk-operations-2`；B-2 = `PRD-20260915-admin-catalog-health-v1`；C-1 = `PRD-20260915-catalog-batch-c1-discovery`；C-2 = `PRD-20260915-catalog-batch-c2-sku-back-in-stock` |
| 需求类型 | 新功能（运营可观测性，零迁移） |

> 🔁 **查重**：`harness prd new` 通过。切片划分：D-1 = 商品级时间线（本 PRD）；D-2 = 重复商品检测（另行立项）。

## 1. 背景与目标

- **背景**（《商品升级方案》§十二）：B-1 的批量运营、B-2 的健康待办都让「批量改了什么」变得容易发生，但**改完看不见**——商品编辑页只有当前值，没有「谁、什么时候、把哪个字段从什么改成什么」。审计表 `pallastrade_audit_logs` 已经在记录快照，`PriceHistory` 也在记录改价，但没有任何界面把它们拼成一条可读的时间线。
- **目标**：在商品编辑页提供**只读时间线**——① 字段变更（名称/slug/状态/描述/SEO/上架时间）逐条可读；② 批量动作（改价/库存/渠道/状态）按商品归属并显示本批影响面；③ 改价历史合并进同一时间线并显示前后金额；④ **零迁移**（复用审计表，不新增历史表）。
- **成功指标**：① 一次只改名称的保存 → 时间线只出现 `name` 一行（不是把全部字段刷一遍）；② 无变化保存 → 不产生噪音条目；③ 一次批量改价 → 每个受影响商品各一条，条目标注 `source=bulk` 与本批 `updated_count`；④ 价格条目能看到「从 10 → 15」。

## 2. 用户故事 / 场景

- 作为**运营**，我打开商品编辑页，右栏就能看到这个商品最近的变更时间线（谁改的、改了哪个字段、前后值）。
- 作为**运营**，我批量调价后回到某个商品，能看到「批量改价（本批 12 个商品）」这条记录，知道这次改动不是我一个人手动改的。
- 作为**客服/店主**，我能确认某个商品的价格是何时从 10 变成 15 的（与改价历史同源，不会两套数字打架）。
- 边界：只改变体/媒体/分类（不落在受跟踪列）→ 时间线出现一条带「区块」标注的记录，而不是消失。
- 异常：actor 缺失（控制台/导入）→ 显示 `system`；商品完全没有历史 → 显示空态文案。

## 3. 功能需求（FR）

- **FR-001 存储复用（零迁移）**：`PallasTrade::ProductHistory::Recorder` 写入 `pallastrade_audit_logs`（`resource_type='PallasTrade::Product'`），不新增表/迁移；受跟踪字段集合显式声明（`name/slug/status/description/meta_title/meta_description/available_on/discontinue_on`）。
- **FR-002 只记变化**：`snapshot(product)` 在更新前取快照；`record_product` 只保留**真正变化的字段**；`update` 无变化且无 `metadata` → **不写记录**（避免空保存污染时间线）。
- **FR-003 批量归属**：`record_bulk` 为**每个受影响商品各写一条**（`metadata['source']='bulk'` + `updated_count`/`skipped_count`）；接入 4 个入口：批量改价、批量库存、批量渠道、批量状态。
- **FR-004 嵌套区块标注**：表单里改变体/媒体/分类以 `metadata['sections']`（`variants`/`media`/`categories`）标注，不伪造列级差异。
- **FR-005 actor 归一**：actor 一律归一为 `{type, id, label}`（label 取 email/name/full_name，回退 `#id`）；`nil` → `'system'`。
- **FR-006 读侧合并**：`Timeline.call(product:, limit: 20)` 合并审计条目与 `PriceHistory`（按变体），按 `occurred_at` 倒序截断；价格条目的**before 由同一 `price_id` 的下一条更旧记录推导**；`metadata` 携带 `variant_sku`/`variant_id`。
- **FR-007 注入与渲染**：面板通过 `product_form_sidebar_partials` 注入（`PallasTrade.admin.partials.product_form_sidebar << 'pallastrade/admin/products/history'`），**不覆盖 gem 表单**；i18n 集中于 `admin.product_history.*`（含 `kinds`/`fields`/`system_actor`/`sku`/`empty`）。
- **FR-008 兼容与边界**：时间线只读、只含传入商品（不做全局扫描）；批量入口的返回值契约不变（仍 `result.updated_count`/`skipped_count`）；无 API/契约变更。

## 4. 非功能需求（NFR）

- **性能**：单商品读取最多 2 次查询（审计 + 价格历史），各带 `limit`；面板渲染不阻塞编辑页（同请求内完成，无 N+1 文案查询）。
- **可维护**：写侧/读侧各一个服务类；视图零业务逻辑（只做格式化与 i18n 查表）。
- **可测试性**：写侧、读侧、后台渲染三类规格；verifier `product-history-rspec` 注册到 `harness.config.mjs`。
- **合规**：沿用审计表即沿用其权限与保留策略；本批不新增数据保留面。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-002：只改名称+slug → 审计行 `before`/`after` **只含这两个键**。`recorder_spec.rb` "stores only the attributes that changed…"
- AC-002 ← FR-002：无变化且无 metadata → 不写记录。`recorder_spec.rb` "skips an update that changed nothing…"
- AC-003 ← FR-004：只有嵌套区块变化 → 记录一条且 `metadata['sections'] == ['media']`。`recorder_spec.rb` "keeps an update that only touched nested form sections"
- AC-004 ← FR-001/FR-005：create 记录全部受跟踪字段且 `actor_label == 'system'`。`recorder_spec.rb` "records a create with every tracked attribute…"
- AC-005 ← FR-003：批量 → 每商品一条、`source=bulk`、带计数。`recorder_spec.rb` ".record_bulk records one entry per affected product…"
- AC-006 ← FR-006：审计 + 改价合并倒序；改价的 before 由更旧行推导；`variant_sku` 存在。`timeline_spec.rb`（前 3 例）
- AC-007 ← FR-006：`limit` 截断、不串其他商品、无历史时为空数组。`timeline_spec.rb`（后 2 例）
- AC-008 ← FR-007：PATCH 更新 → 记录 + 编辑页渲染标题/条目；批量渠道 → 每商品一条；无历史 → 空态。`product_history_spec.rb`（4 例）

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | history / audit | 无商品历史实现（宿主 app 无相关服务/视图） | 缺口：需新增（Framework 产品线，落 core/admin） |
| Core | `pallastrade_core/app/` | audit / price history | `models/pallastrade/audit_log.rb`（`for_resource` + before/after JSONB）、`services/pallastrade/audit.rb`（`record`）、`models/pallastrade/price_history.rb`（`recorded_at` + `price_id`）、`models/pallastrade/product.rb`（受跟踪列） | **数据源齐备**（审计 + 改价历史）→ 只缺「写侧归属 + 读侧合并」 |
| API | `pallastrade_api/app/` | history | 无（本批不动 API，无契约变更） | ✅ 无需改动 |
| Admin | `pallastrade_admin/app/` | partials / product form | `config/initializers/pallastrade_admin_partials.rb`（`products_header` 已被 B-2 占用）、`app/views/.../products/_form.html.erb`（含 `product_form_sidebar_partials` 渲染点）、`controllers/.../products_controller.rb`（update + 4 个批量入口） | **注入点与写入点都存在** → 可直接接线，零视图覆盖 |
| Storefront | `storefront/src/` | history | 无（本批不动前台） | ✅ 无需改动 |
| Platform | `platform/packages/` | history | 无（本批不动 SDK/CLI） | ✅ 无需改动 |

**结论**：能力缺口只有两块——**写侧把批量/单商品动作归属到商品**、**读侧把审计与改价合并成时间线**；存储、注入点、i18n 惯例、控制器写入点全部已存在，因此本批**零迁移、零契约变更**。

## 7. 技术影响

- **Core（新增）**：`app/services/pallastrade/product_history/recorder.rb`（写侧）、`app/services/pallastrade/product_history/timeline.rb`（读侧）。
- **Admin（新增/改动）**：`app/views/pallastrade/admin/products/_history.html.erb`（面板）；`config/initializers/pallastrade_admin_partials.rb`（注册 `product_form_sidebar`）；`config/locales/en.yml`（`admin.product_history.*`）；`app/controllers/.../products_controller.rb`（update 快照 + 记录；`bulk_status_update`；`run_bulk_operation(..., history_action:)` + 3 个批量入口；3 个私有辅助方法）。
- **数据库**：**无迁移**（复用 `pallastrade_audit_logs`）。
- **契约**：无 API 变更，无 `generated:check` 影响。
- **测试（新增）**：`spec/services/pallastrade/product_history/recorder_spec.rb`、`.../timeline_spec.rb`、`spec/requests/pallastrade/admin/product_history_spec.rb`（15 例）。
- **风险**：写侧在 `update` 事务外记录（失败不阻塞保存，符合可观测性定位）；批量入口仅新增可选参数，返回契约不变。

## 8. 测试计划

- `spec/services/pallastrade/product_history/recorder_spec.rb`：AC-001~005（5 例）。
- `spec/services/pallastrade/product_history/timeline_spec.rb`：AC-006/007（5 例）。
- `spec/requests/pallastrade/admin/product_history_spec.rb`：AC-008（4 例）+ 编辑页渲染/空态。
- 回归：`spec/requests/pallastrade/admin/products_bulk_operations_spec.rb`（B-1，17 例）——控制器改动不得破坏既有批量语义。
- 注册 verifier：`product-history-rspec`（3 个 spec 文件）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`（新增「Product History —— 商品级时间线」章节：审计表即时间线 + 写/读/注入/回归定式）
- [x] `harness/scenarios/scenarios.json`（GS-134：时间线复用审计表而非新表；`harness eval-ai --scenarios` → **135/135 valid**）
- [x] `harness.config.mjs`（verifier `product-history-rspec`）+ `AGENTS.md` §6 行
- [x] 本 PRD 状态（done）+ `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）
- [x] `pallastrade-customization`（无需更新：本次走的是已登记的分页注入点惯例）／`pallastrade-data-model`（无需更新：零迁移）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch D-1：FR-001~008 / AC-001~008） | AI |
| 2026-09-15 | 1.0 | 实施完成：Recorder + Timeline + 侧栏面板 + 控制器 5 处接线；定向 15 例绿 + B-1 回归 17 例绿；知识同步（admin Skill / GS-134 / verifier / AGENTS §6） | AI |
