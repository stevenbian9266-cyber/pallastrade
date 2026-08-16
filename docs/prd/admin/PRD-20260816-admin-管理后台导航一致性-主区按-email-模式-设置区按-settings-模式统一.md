# PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-16 |
| 来源 | 优化：管理后台导航一致性——主区按 Email 模式、设置区按 Settings 模式统一 |
| 分类 | admin（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260816-admin-管理后台导航一致性

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-16 |
| 来源 | 优化：管理后台导航一致性——主区按 Email 模式、设置区按 Settings 模式统一（用户已确认方向/范围/验收） |
| 分类 | admin |
| 关联 Skill | pallastrade-admin |
| 关联 REQ | REQ-20260816-admin-nav-consistency.md |
| 关联 PRD | N/A（全新需求，查重未命中） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：整个管理后台菜单结构的 UI 有问题，此前没有一致性规范：有的二级菜单有面包屑导航、有的没有。建议以 Email 菜单及相关子菜单的 UI、面包屑导航为标准，形成整个统一规范，将其它导航按 Email 优化，同时更新相关规范、skills。
- **背景**：
  - 后台存在**两套布局**：主侧边栏区（`admin` 布局）与设置/Developers 区（`admin_settings` 布局，自动带 "Settings" 面包屑前缀 + 分区 banner + tabs）。
  - 主区：Orders/Products/Customers/Promotions/Reports/Emails 均有 breadcrumb concern（icon + 父 crumb），但 **Blog（posts）完全缺失**（空面包屑 + 无页面头）；host app 的 AI 模块已用同类 Pattern B。
  - 设置区：多数页面只有 "Settings" 前缀、无页面 crumb；少数视图缺 `page_title`（页面头/操作按钮丢失）：`allowed_origins/index`、`back_in_stock_subscriptions/index`、`webhook_endpoints/index`、`redirects/index`。
- **目标**：形成**两套统一规范**（主区=Email 模式、设置区=Settings 模式）并落地，消除不一致；沉淀为 `pallastrade-admin/SKILL.md` 权威章节 + GS 场景。
- **成功指标**：主区所有顶级模块均有 breadcrumb concern + 每子页 crumb + 每视图 page_title；设置区所有页面均有页面 crumb + page_title；新增回归 spec 断言；浏览器逐页抽查通过。

## 2. 用户故事 / 场景

- 作为管理员，我希望后台每个页面都有一致的面包屑与页面头，以便快速定位层级并找到操作按钮。
- 主区场景：进入 Blog → 面包屑「Blog」+ 页面头 + New Post 按钮（同 Email 的「Emails > Templates」）。
- 设置区场景：进入 Channels → 面包屑「Settings > Channels」+ 分区 banner。
- 边界：登录/密码页（user_sessions/user_passwords）属 auth 页，不套用（保持 minimal layout）。
- 异常：settings 页自动前缀与页面 crumb 叠加时不得重复显示。

## 3. 功能需求（FR）

- FR-001：主区每个带子菜单的顶级模块必须有专属 breadcrumb concern（`add_breadcrumb_icon` + 父 `add_breadcrumb`），每子页控制器 class-level crumb + 对象 crumb（如需要）。
- FR-002：主区 Blog（posts）新增 `PostsBreadcrumbConcern`（icon `news` + Blog 父 crumb），posts 视图补 `content_for :page_title`。
- FR-003：设置区各控制器补页面 crumb（面包屑 = "Settings > 页面"），不破坏 `SettingsConcern` 自动前缀机制。
- FR-004：补齐缺失 `page_title` 的视图（allowed_origins/index、back_in_stock_subscriptions/index、webhook_endpoints/index、redirects/index 等），恢复页面头与 page_actions。
- FR-005：规范沉淀：更新 `ai/skills/pallastrade-admin/SKILL.md`（两套规范权威章节）；更新/新增 GS 场景。

## 4. 非功能需求（NFR）

- 兼容：不破坏现有 `settings_area?` 布局切换、`SettingsConcern`、`breadcrumbs_on_rails` 机制。
- 可维护性：复用 concern 模式，禁止在 action 内手写 breadcrumb。
- 一致性：与已统一的 Email 模式完全一致（图标/层级/页面头）。
- 性能：无新增查询（breadcrumb 均为常量/类级声明）。

## 5. 验收标准（AC）

- AC-001 ← FR-001：主区所有顶级模块控制器均有 breadcrumb concern/icon；子页面包屑含父 crumb + 子页 crumb。
- AC-002 ← FR-002：`/admin/posts` 渲染面包屑「Blog」+ 页面头 h3 + page_actions。
- AC-003 ← FR-003：设置区页面面包屑含「Settings > 页面」（抽查 Channels / API Keys / Zones）。
- AC-004 ← FR-004：缺失 `page_title` 的视图补全后页面头与操作按钮可见。
- AC-005 ← FR-005：`pallastrade-admin/SKILL.md` 含两套规范章节；`scenarios.json` 新增/更新 GS 场景并通过 `eval-ai`。
- AC-006：`emails_spec` 等现有 spec 不回归；新增导航一致性回归 spec。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | breadcrumb/page_title/SettingsConcern | `app/controllers/pallastrade/admin/ai_controller.rb`（已用 Pattern B） | AI 模块已符合主区规范 |
| Core | `pallastrade_core/app/` | breadcrumb/page_title | 无 | 无 admin UI，不涉及 |
| API | `pallastrade_api/app/` | breadcrumb/page_title | 无 | 无 admin UI，不涉及 |
| Admin | `pallastrade_admin/app/` | add_breadcrumb/page_title/controller | 92 个控制器 + 101 个视图 | 本次主要修改对象 |
| Storefront | `storefront/src/` | breadcrumb | `components/navigation/Breadcrumbs.tsx` | storefront 侧组件，与 admin 无关 |
| Platform | `platform/packages/` | breadcrumb | 无 | 不涉及 |

**结论**：breadcrumb/page_title 机制仅存在于 admin gem（+ host app AI controller 已合规）；无跨层重复。本次修改范围 = admin gem 控制器/视图 + `pallastrade-admin` skill + `scenarios.json`。

## 7. 技术影响

- 主区：新增 `PostsBreadcrumbConcern`；`posts_controller` include + 子 crumb；`posts/*` 视图补 page_title。
- 设置区：`channels`/`markets`/`payment_methods`/`zones`/`shipping_categories`/`shipping_methods`/`tax_categories`/`tax_rates`/`stock_locations`/`admin_users`/`policies`/`storefront`/`webhook_*`/`allowed_origins`/`back_in_stock_subscriptions`/`redirects`/`api_keys`/`roles`/`invitations` 等补 class-level crumb。
- 视图：`allowed_origins/index`、`back_in_stock_subscriptions/index`、`webhook_endpoints/index`、`redirects/index` 补 `page_title`。
- 规范：`ai/skills/pallastrade-admin/SKILL.md`、`harness/scenarios/scenarios.json`。
- 无 DB/接口变更；无新依赖。

## 8. 测试计划

- 新增 `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb`：主区抽查（Blog 面包屑+页面头）、设置区抽查（Settings 前缀 + 页面 crumb + page_title）。（AC-001~004）
- 更新 `backend/spec/requests/pallastrade/admin/emails_spec.rb`：保持通过。（AC-006）
- 运行：容器内 `rspec spec/requests/pallastrade/admin/`；`harness check --profile quick`；`harness eval-ai --scenarios`。

## 9. 文档同步清单（知识同步门）

- [x] Skill 文档：`ai/skills/pallastrade-admin/SKILL.md`（两套规范权威章节「两套布局的统一规范」）
- [x] 场景库：`harness/scenarios/scenarios.json`（新增 GS-032，33/33 通过 eval-ai）
- [x] 反模式库/任务规则：不涉及（已评估）
- [x] 本 PRD 状态更新（done）+ `docs/prd/README.md` 索引
- [x] `harness sync-check` 结论：pallastrade-security（仅面包屑改动，无安全影响）、AGENTS.md §8（未涉及危险操作）、pallastrade-deployment/.env.example/部署 README（无部署改动）、pallastrade-prd（skill 未改）、AGENTS.md/copilot-instructions（未改）、scenarios.json（updated：GS-032）—— 均已记录为知识评估 9/9

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-16 | v0.1 | 初稿（审计 + 两套规范 + 范围确认） | AI（用户已确认方向/范围/验收方式） |
| 2026-08-16 | v0.2 | 实施完成：Blog PostsBreadcrumbConcern + posts 视图 page_title；25 个设置控制器补 class-level crumb；admin_settings 布局补面包屑渲染；back_in_stock_subscriptions 表格 new_resource:false 修复；SKILL.md 两套规范章节 + GS-032 场景；navigation_consistency_spec（6 examples）+ emails_spec（20 examples）全过；gate GATE-2026-08-16T06-50-20 finished；task TASK-20260816064957-1e7c90f2 completed | AI |

