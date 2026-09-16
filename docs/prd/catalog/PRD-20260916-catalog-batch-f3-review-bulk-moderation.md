# PRD-20260916-catalog-batch-f3-review-bulk-moderation

| 元数据 | 值 |
|---|---|
| 状态 | reviewing |
| 创建日期 | 2026-09-16 |
| 来源 | 《商品升级方案 V1.0》§十「评论系统升级」剩余项之一 —— **Admin Bulk Approve / Reject**（用户授权原话「自主决定」，2026-09-16） |
| 分类 | catalog（商品域 / 评论，沿用 Batch A~F 系列目录） |
| 关联 Skill | pallastrade-admin / pallastrade-api-v3（只读口径）/ pallastrade-testing / pallastrade-data-model（零迁移） |
| 关联 REQ | REQ-20260916-batch-f3-review-bulk-moderation.md（实施时回填） |
| 关联 PRD | 上游：`PRD-20260818-catalog-p0-4-产品评论`（审核基础）+ `PRD-20260916-catalog-batch-f1-reviews`（评分分布/分页/图片）；平行复用：Batch B-1 批量运营（`BulkOperationsController`） |
| 需求类型 | 优化迭代（Admin 工作台；**零 Store API 变更**、零新表、不改审核状态机） |

> 🔁 **查重**：`harness prd new` 通过。
> **为什么自主选它**：§十 剩余三项中，排序会改 Store API 契约、Helpful Vote 需新表 + 反滥用机制（成本与风险都更高）；批量审核**只动后台**、复用 B-1 既有机制，是「商家价值 ÷ 风险」最高的一片。

## 1. 背景与目标

- **一句话需求原文**：「自主决定」。
- **背景**（6 层复核）：评论审核目前**只能逐条点击**——`PallasTrade::Admin::ReviewsController#approve` / `#reject` 是单个资源动作（`@review.approve!` / `reject!`）；F-1 之后评论带图片、列表有分页，待审量一旦上来，运营要一条一条点。B-1（`PRD-20260915-admin-bulk-operations-2`）已经建成**通用批量操作框架**（`BulkOperationsController` + 表注册表 `PallasTrade.admin.tables` 的 `find_bulk_action`，商品批量价格/库存/渠道都在用），评论表却还没接。
- **目标**：
  1. 审核工作台支持**批量通过 / 批量拒绝**，复用既有批量模态（不新造交互）；
  2. 每条评论仍走**同一个状态机**（`approve!` / `reject!`）并各自留审计 —— 绝不 `update_all` 直改状态；
  3. 结果**逐条报告**（成功 / 无权跳过 / 状态不允许），部分失败不影响其余；
  4. **零 Store API 变更**：只有 approved 公开、平均分与评论数只算 approved 的口径完全不动。
- **成功指标**：一次操作可处理 ≥50 条（上限内）；混合状态下只迁移合法项且计数与审计条数一一对应；无权用户提交后**0 条**被改动；Store API 快照无新增字段。

## 2. 用户故事 / 场景

- 作为**运营**，大促后一次导入 80 条待审评论，希望一次勾选、一次通过，而不是点 80 次。
- 作为**运营**，在一堆好评里看到几条明显违规的，希望勾选后一次拒绝，保留删除作为逐条动作。
- 作为**店铺管理员**（无权改评论），误提交批量通过时希望系统**明确告诉我 0 条被改**，而不是静默失败或整体报错。
- 作为**已审核过的评论**，再次被批量通过时不应报错、不应重复写审计。

## 3. 功能需求（FR）

- **FR-001 多选与入口**：`pallastrade/admin/reviews/index` 列表加「行选择 + 当前页全选」，并接入**既有** `BulkOperationsController`（`GET /admin/bulk_operations/new?kind=…&table_key=reviews`）打开批量确认模态；不在页面里另写一套 JS 弹窗。
- **FR-002 动作**：`approve` / `reject` 两个批量动作，通过**表注册表**声明（`PallasTrade.admin.tables.<reviews>.add_bulk_action`），模态文案与按钮走 i18n。
- **FR-003 执行路径**：服务端逐条 `authorize! :update, review` → 校验状态允许 → 调用**既有状态机** `approve!` / `reject!`（每条各自写审计，与单条路径完全一致）。**禁止** `update_all` / `update_columns` / 直接改 `status` 列。
- **FR-004 结果报告**：返回并展示 `updated / skipped_unauthorized / skipped_invalid_state / not_found` 计数；部分失败不回滚已成功项；无任何变更时也给出明确反馈（0 条）。
- **FR-005 幂等与合法迁移**：仅允许 `pending → approved`、`pending|approved → rejected`（与既有状态机一致）；已处于目标态或非法迁移计入 `skipped_invalid_state`，不报错、不写审计。
- **FR-006 规模保护**：单次上限 **50 条**；超出 → 拒绝并提示（防误操作与长事务）。空选择 → 不动作 + 提示。
- **FR-007 不改公开口径**：Store API 不新增/不改字段；未审核评论（及其图片）仍不外泄；`Product#average_rating` / `#review_count` 仍只算 approved（回归断言）。
- **FR-008 权限**：批量入口与执行都经后台鉴权；无权限的用户提交后 0 条改动（逐条 `authorize!` 捕获 `CanCan::AccessDenied` 计 `skipped_unauthorized`，控制器层不整体 500）。

## 4. 非功能需求（NFR）

- **NFR-001 性能**：50 条上限内不产生 N+1（列表已有分页；执行按 id 批量取一次再逐条迁移）。
- **NFR-002 可观测**：每条的审计与单条路径一致（`audit` 事件名不变），便于「谁批量改了什么」倒查。
- **NFR-003 兼容**：单条 approve/reject 路由与行为不变；既有 `row_actions` 不动。
- **NFR-004 a11y**：选择框有可读 label、批量提交按钮有明确文案（沿用 B-1 组件的既有实现）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-002/003：3 条 pending 批量通过 → 3 条变 approved，且每条各写 1 条审计（后台请求规格）。
- AC-002 ← FR-002/003：批量拒绝同理（3 条 → rejected + 3 条审计）。
- AC-003 ← FR-008：无权限用户提交 → 0 条改动、报告 `skipped_unauthorized = 3`、HTTP 非 500。
- AC-004 ← FR-005：混合态（1 pending + 1 approved）批量通过 → 仅 pending 迁移；approved 计 `skipped_invalid_state`。
- AC-005 ← FR-006：空选择 → 无变更 + 提示；51 条 → 拒绝且 0 条改动。
- AC-006 ← FR-003：断言**逐条状态机**（审计条数 == 成功条数；不得出现 `update_all` 语义的「1 条 SQL 改多行」）。
- AC-007 ← FR-004：报告计数与实际状态变化一一对应（含 not_found 分支）。
- AC-008 ← FR-001/002：批量动作已在 reviews 表注册（表注册表可查到 `approve`/`reject`），模态路由可打开（admin 请求规格）。
- AC-009 ← FR-007：回归——批量通过后 Store API 列表才出现该评论；平均分/评论数只算 approved（请求 + 模型规格）。
- AC-010 ← NFR-004/FR-001：列表渲染选择框与批量入口（admin feature/请求规格断言 DOM 关键节点与 i18n 文案键）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| **App** `backend/app/` | review / bulk | 无评论后台代码 | 缺口：按本仓惯例落 gem |
| **Core** `.../pallastrade_core/app/` | review / approve / audit | `models/pallastrade/review.rb`（`approve!` / `reject!` 状态机，P0-4；F-1 图片） | **复用**：批量必须调同一状态机 |
| **API** `.../pallastrade_api/app/` | review | Store API 只读 approved（F-1 已定口径） | **不改**（FR-007） |
| **Admin** `.../pallastrade_admin/app/` | reviews / bulk_operations / tables | `controllers/.../admin/reviews_controller.rb`（`approve` / `reject` 单条）、`controllers/.../admin/bulk_operations_controller.rb`（B-1 通用批量模态 + `authorize_admin`）、`config/initializers/pallastrade_admin_tables.rb`（表注册 + F-1 的 photos 列）、`views/.../reviews/index.html.erb` + `_row_actions.html.erb` | **主战场**：加选择框 + 注册两个 bulk action + 新 bulk 执行端点 |
| **Storefront** `storefront/src/` | review | 无审核相关（前台只展示） | **不涉及** |
| **Platform** `platform/packages/` | review | 无 admin bulk 类型 | **不涉及** |

### 搜索结论

- 交互与路由**沿用 B-1**（`BulkOperationsController` + `BulkAction` 注册），F-3 只新增「评论表的两个批量动作 + 执行端点 + 报告」，不新造框架。
- 状态迁移**只走 `Review#approve!` / `#reject!`**（含各自审计），与单条路径同源 —— 这是本批最重要的正确性约束。
- 零迁移、零 Store API 变更：`approved` 才公开的口径由 F-1 既有规格守护（AC-009 回归）。

## 7. 技术影响

```text
backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_tables.rb    （reviews 表注册 2 个 bulk action）
backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/reviews_controller.rb （#bulk 端点：上限/逐条 authorize/状态机/报告）
backend/pallastrade_gems/pallastrade_admin/config/routes.rb                                    （POST /admin/reviews/bulk）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/reviews/index.html.erb   （选择框 + 批量入口）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/reviews/_bulk_form.html.erb（模态表单：动作 + 结果提示；【新增】）
backend/pallastrade_gems/pallastrade_admin/config/locales/en.yml                                （bulk 文案/报告计数）
backend/spec/requests/pallastrade/admin/reviews_bulk_spec.rb                                    （【新增】AC-001~008/010）
backend/spec/requests/pallastrade/admin/reviews_spec.rb                                         （回归）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / docs/prd/README.md          （治理）
```

## 8. 测试计划

- **后端规格**：`spec/requests/pallastrade/admin/reviews_bulk_spec.rb`（AC-001~008、AC-010）；`reviews_spec.rb` 回归（AC-009 的 Store API 侧）。
- **注册 verifier**：`f3-review-bulk-rspec`。
- **门禁**：本批**不涉前台** → 无需 `pnpm build`；`harness generated:check` 应保持 no drift（无契约变更）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-admin/SKILL.md`（评论批量动作 + 复用 BulkOperationsController 的约定 + 「批量必须逐条走状态机」铁律）
- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（评论审核工作台段补一句：批量入口与公开口径不变）
- [ ] `ai/skills/pallastrade-api-v3/SKILL.md`（**已评估，无需更新**：零契约变更）
- [ ] `harness/scenarios/scenarios.json`（新增 GS：批量审核逐条走状态机、部分失败可解释、公开口径不变；编号 GS-147）
- [ ] `harness.config.mjs`（verifier `f3-review-bulk-rspec`）+ `AGENTS.md` §6 行
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（Batch F-3：FR-001~008 / AC-001~010；范围 = §十 剩余项「Admin Bulk Approve / Reject」；已复刻 B-1 机制与 F-1 审核口径） | AI |
