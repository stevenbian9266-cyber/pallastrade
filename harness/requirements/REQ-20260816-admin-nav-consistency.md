# REQ-20260816-admin-nav-consistency — 管理后台导航一致性（两套规范）

> 任务类型：feature | 任务：`TASK-20260816064957-1e7c90f2` | Gate：`GATE-2026-08-16T06-50-20`
> 分支：`dev` | 关联 PRD：`docs/prd/admin/PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一.md`

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | breadcrumb/page_title/SettingsConcern | `ai_controller.rb`（Pattern B 已合规） | 不涉及 |
| Core Gem | `pallastrade_core/app/` | breadcrumb/page_title | 无 | 不涉及 |
| API Gem | `pallastrade_api/app/` | breadcrumb/page_title | 无 | 不涉及 |
| Admin Gem | `pallastrade_admin/app/` | add_breadcrumb/page_title | 92 控制器 + 101 视图（审计清单见 PRD §1） | **本次主要修改对象** |
| Storefront | `storefront/src/` | breadcrumb | `components/navigation/Breadcrumbs.tsx` | storefront 侧，不涉及 |
| Platform | `platform/packages/` | breadcrumb | 无 | 不涉及 |

**结论**：breadcrumb/page_title 仅存在于 admin gem；修改范围 = admin gem 控制器/视图 + skill + scenarios。

## Step 1：Skill 文件咨询（已执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Add a menu item / nav entry to the admin → `PallasTrade.admin.navigation.sidebar.add` → **pallastrade-admin**" |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | "Customizing the sidebar 模式 `url: :admin_brands_path`（symbol → route helper）"；页面统一 `content_for :page_title` |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | "`harness prd new` 自动查重（相似度>0.3 阻止新建）；AC 必须映射测试 `# PRD-xxx AC-x`" |

---

## 需求标题：管理后台导航一致性（主区 Email 模式 + 设置区 Settings 模式）

### 背景

后台两套布局存在不一致：主区 Blog 完全缺失面包屑/页面头；设置区多数页面只有 "Settings" 前缀无页面 crumb；少数视图缺 `page_title`（页面头与操作按钮丢失）。

### 目标

1. 主区每个顶级模块 → breadcrumb concern（icon + 父 crumb）+ 每子页 crumb + 每视图 `page_title`。
2. Blog 新增 `PostsBreadcrumbConcern`（icon news）+ posts 视图补 page_title。
3. 设置区控制器补页面 crumb（"Settings > 页面"），不破坏 SettingsConcern 前缀。
4. 补齐缺失 `page_title` 的视图。
5. 规范沉淀：SKILL.md 两套规范章节 + GS 场景。

### 改动清单

- 新增 `concerns/pallastrade/admin/posts_breadcrumb_concern.rb`；`posts_controller` include + crumb；`posts/{index,new,edit}` 补 page_title。
- 设置区控制器（channels/markets/payment_methods/zones/shipping_*/tax_*/stock_locations/admin_users/policies/storefront/webhook_*/allowed_origins/back_in_stock_subscriptions/redirects/api_keys/roles/invitations 等）补 class-level crumb。
- 视图补 page_title：`allowed_origins/index`、`back_in_stock_subscriptions/index`、`webhook_endpoints/index`、`redirects/index`。
- 规范：`ai/skills/pallastrade-admin/SKILL.md`、`harness/scenarios/scenarios.json`。
- 测试：新增 `spec/requests/pallastrade/admin/navigation_consistency_spec.rb`。

### 验收标准

- AC-001：主区所有顶级模块控制器均有 breadcrumb concern/icon；子页含父 crumb + 子页 crumb。
- AC-002：`/admin/posts` 渲染面包屑「Blog」+ 页面头 h3 + page_actions。
- AC-003：设置区页面面包屑含「Settings > 页面」（抽查 Channels / API Keys / Zones）。
- AC-004：缺失 `page_title` 的视图补全后页面头与操作按钮可见。
- AC-005：SKILL.md 含两套规范章节；scenarios.json 新增/更新 GS 场景并通过 eval-ai。
- AC-006：现有 emails_spec 不回归；新增导航一致性回归 spec。

### 测试计划

- 新增 `navigation_consistency_spec.rb`（主区/设置区面包屑 + page_title 断言，标注 `# PRD-20260816-admin-导航一致性 AC-x`）。
- 运行：容器内 `rspec spec/requests/pallastrade/admin/`；`harness check --profile quick`；`eval-ai --scenarios`。
- 浏览器逐页抽查（用户已确认）。
