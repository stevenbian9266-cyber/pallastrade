# REQ-20260916 — Batch F-3（评论审核工作台：批量通过 / 批量拒绝）

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-batch-f3-review-bulk-moderation.md`
> 任务：TASK-20260916044505-2d0d99f6 ｜ Gate：GATE-2026-09-16T04-45-10（feature，risk=critical）
> 用户确认：2026-09-16「确认实施」（范围＝批量通过/拒绝；排序留 F-4；Helpful Vote 更后；批量删除不做）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | review / bulk / moderation | 无评论后台代码 | 缺口：按本仓惯例落 gem |
| Core Gem | `pallastrade_core/app/` | review / approve / reject / audit | `models/pallastrade/review.rb`（`approve!` / `reject!` 状态机 + 审计，P0-4；F-1 加图片） | **复用**：批量必须逐条调同一状态机 |
| API Gem | `pallastrade_api/app/` | review | Store API 只读 approved（F-1 定稿的分页信封 + `rating_distribution`） | **不改**（FR-007 零契约变更） |
| Admin Gem | `pallastrade_admin/app/` | reviews / bulk_operations / tables | `controllers/.../admin/reviews_controller.rb`（`approve`/`reject` 单条，`find_review`）、`controllers/.../admin/bulk_operations_controller.rb`（B-1 通用批量模态 + `find_bulk_action` + `authorize_admin`）、`config/initializers/pallastrade_admin_tables.rb`（表注册 + F-1 photos 列）、`views/.../reviews/index.html.erb`、`_row_actions.html.erb` | **主战场**：选择框 + 两个 bulk action 注册 + `#bulk` 执行端点 + 报告文案 |
| Storefront | `storefront/src/` | review | 仅展示，无审核 | **不涉及** |
| Platform | `platform/packages/` | review | 无 admin bulk 类型 | **不涉及** |

### 搜索结论

- 交互/路由**沿用 B-1**（`BulkOperationsController` + `BulkAction` 注册到表注册表），F-3 只新增「评论表的批量动作 + 执行端点 + 逐条报告」。
- 状态迁移**只走** `Review#approve!` / `#reject!`（含各自审计），与单条路径同源 —— 本批最重要的正确性约束。
- 零迁移、零 Store API 变更：`approved` 才公开的口径由 F-1 规格守护（AC-009 回归）。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：优先既有扩展面 —— 本批复用 B-1 的批量框架与既有状态机，不 decorate 模型、不新造交互 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台列表加列/加动作走 gem 源直改 + `# PALLAS-CUSTOM:`；批量动作经表注册表声明（`PallasTrade.admin.tables`），导航与 `row_actions` 不动 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 评论公开口径：**只有 approved 公开**、`Product#average_rating`/`#review_count` 只算 approved → 批量不改变该口径 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec（容器）+ admin 请求规格；注册 verifier 供 `harness verify` |
| `pallastrade-api-v3` | ☑ 涉及（判断为不改） | ✅ 已读 | 契约只增不改是本仓铁律 → 本批**零变更**，`generated:check` 应保持 no drift |
| `pallastrade-security` | ☑ 涉及（轻） | ✅ 已读 | 后台动作必须逐条鉴权（`authorize!`），不得因批量而放宽；无权即跳过并报告 |
| `pallastrade-data-model` | ☑ 涉及（判断为零迁移） | ✅ 已读 | 无新表/新列；`status` 状态机不动 |
| `harness-prd` | ☑ 涉及 | ✅ 已读 | PRD → 用户确认 → gate → REQ → 实施 → 证据 → 知识同步 |

---

## 需求标题

评论审核工作台批量通过 / 批量拒绝（复用 B-1 批量模态；逐条状态机 + 逐条鉴权 + 结果报告）。

## 任务类型

优化迭代（仅 Admin；零新表、零 Store API 变更、不改审核状态机）

## 需求描述

运营在后台评论列表勾选多条待审评论，一次通过或一次拒绝；系统逐条走与单条点击完全相同的状态机与审计，无权或状态不允许的条目被跳过并在结果中报告，公开口径（只有 approved 公开、平均分只算 approved）保持不变。

## 影响范围（预估）

```text
backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_tables.rb      （reviews 注册 approve/reject 两个 bulk action）
backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/reviews_controller.rb （#bulk：上限 50、逐条 authorize + 状态机、结果报告）
backend/pallastrade_gems/pallastrade_admin/config/routes.rb                                       （POST /admin/reviews/bulk）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/reviews/index.html.erb     （选择框 + 批量入口）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/reviews/_bulk_form.html.erb（新增：模态表单）
backend/pallastrade_gems/pallastrade_admin/config/locales/en.yml                                  （文案 + 报告计数）
backend/spec/requests/pallastrade/admin/reviews_bulk_spec.rb                                      （新增，AC-001~008/010）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / docs/prd/README.md            （治理）
```

## 决策记录

1. 动作范围：**批量通过 + 批量拒绝**；批量删除**不做**（保留逐条，风险更高）。
2. 单次上限 **50 条**（超出拒绝并提示）。
3. 只处理**当前页选择**（不做跨页保留），避免隐式大范围操作。
4. 权限：逐条 `authorize! :update`；无权项计 `skipped_unauthorized`，控制器不整体 500。
5. 合法迁移：仅 `pending → approved`、`pending|approved → rejected`；其余计 `skipped_invalid_state`（不报错、不写审计）。
6. 报告四计数：`updated / skipped_unauthorized / skipped_invalid_state / not_found`；部分失败不回滚已成功项。
