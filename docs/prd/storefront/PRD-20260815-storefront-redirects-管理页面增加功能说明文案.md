# PRD-20260815-storefront-redirects-管理页面增加功能说明文案

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-08-15 已实施并部署验证） |
| 创建日期 | 2026-08-15 |
| 来源 | 优化：redirects 管理页面增加功能说明文案 |
| 分类 | storefront（自动判定） |
| 关联 Skill | pallastrade-admin |
| 关联 REQ | REQ-20260815-redirects-intro-copy.md（实施时回填） |
| 关联 PRD | N/A（全新小需求；能力本体见 PRD-20260814-catalog-seo-...） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：优化：redirects 选项卡页面和 new redirect、add one 页面内增加文案说明，文案是表述这个功能的作用，要通俗易懂
- **背景**：redirects（SEO 301/302 重定向）是 2026-08 新增功能，管理端目前只有字段级 help 提示（from_help/to_help/status_help），**页面级没有"这个功能是干什么的"说明**。作为开发者都难以理解其用途，非技术运营/店主更看不懂——需要页面级通俗文案降低理解门槛。
- **目标**：在 redirects 的 index、new、edit 页面顶部显示通俗易懂的功能说明，让任何用户一眼明白"旧链接自动跳新链接、防止 404、保住搜索引擎排名"。
- **成功指标**：redirects 三个页面（index/new/edit）均可见说明文案；文案无技术黑话。

## 2. 用户故事 / 场景

- 作为店主/运营，我希望打开 Developers → Redirects 就看到"这是什么、有什么用"，以便决定是否使用。
- 作为运营，我希望在新建重定向时看到"每格填什么"的说明，以便正确配置（旧路径→新路径）。
- 场景：第一次打开 redirects 页面（index）；点击 New Redirect / Add One（new）；编辑已有规则（edit）。

## 3. 功能需求（FR）

- FR-001：`/admin/redirects` index 页顶部显示功能说明（信息提示框样式，参照 `admin.option_types.intro_help` 的 `page_alerts` 先例）
- FR-002：`/admin/redirects/new` 与 `/admin/redirects/:id/edit` 表单页顶部显示"填写说明"（From Path / To Path / 状态码通俗解释）
- FR-003：文案通俗易懂，无技术黑话；复用现有 `PallasTrade.t` locale 机制，不硬编码

## 4. 非功能需求（NFR）

- 兼容现有 `alert-info` 样式与布局，不破坏表格/表单
- 文案集中放 `en.yml`（`admin.redirects.intro_help` / `admin.redirects.form_intro`），便于多语言扩展
- 不引入新依赖、不改后端逻辑/API

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：GET `/admin/redirects` 响应 body 包含 intro 文案（`alert-info` 块）
- AC-002 ← FR-002：GET `/admin/redirects/new` 与 edit 响应 body 包含表单填写说明
- AC-003 ← FR-003：文案经用户确认（本 PRD approved），不含技术黑话

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | redirects/intro/说明 | 无（仅 AI controller redirect_to） | 否，无需新建 |
| Core | `pallastrade_gems/pallastrade_core/app/` | redirect | `redirect.rb`（模型已存在） | 否，文案属 Admin 层 |
| API | `pallastrade_gems/pallastrade_api/app/` | redirect | `redirects_controller.rb` x2 | 否，文案属 Admin 层 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | intro/说明/redirects | `redirects/index.html.erb`、`new.html.erb`、`_form.html.erb`；**先例**：`option_types/index.html.erb` 的 `page_alerts` + `intro_help` | ✅ 复用先例实现 |
| Storefront | `storefront/src/` | redirect | `lib/pallastrade/middleware.ts`（消费方） | 否，本次只改 Admin 文案 |
| Platform | `platform/packages/` | redirect | 仅文档 | 否 |

**结论**：Admin 层已有 `option_types` 的 `page_alerts` + `intro_help` 先例可复用；本次仅改 `redirects` 的 index/new/edit 视图 + `en.yml` locale，无跨层重复风险。

## 7. 技术影响

- 涉及文件：
  - `pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/redirects/index.html.erb`（+ `page_alerts`）
  - `.../redirects/_form.html.erb`（顶部 + 填写说明）
  - `.../redirects/new.html.erb` / `edit.html.erb`（如需要容器）
  - `pallastrade_gems/pallastrade_admin/config/locales/en.yml`（+ `admin.redirects.intro_help` / `form_intro`）
- 无数据库变更、无 API 变更、无 storefront 变更

## 8. 测试计划

- 扩展 `backend/spec/requests/pallastrade/admin/redirects_spec.rb`：
  - index 断言 body 包含 intro 文案
  - new 断言 body 包含填写说明
- 本地 `docker compose exec web env DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec ...` 全绿

## 9. 文档同步清单

- `ai/skills/pallastrade-admin/SKILL.md`：记录"settings 列表页可用 `page_alerts` + `intro_help` 提供功能说明"约定（已存在 option_types 先例，补充 redirects 作为范例）
- 无需 scenarios.json 变更（无新能力/场景，仅文案）

## 10. 变更记录

- 2026-08-15：创建 PRD（reviewing），待用户确认
