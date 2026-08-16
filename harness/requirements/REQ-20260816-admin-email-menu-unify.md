# REQ-20260816-admin-email-menu-unify — 管理后台 Email 菜单统一化（参考 Products）

> 任务类型：bugfix | 任务：`TASK-20260816024809-034fc77b` | Gate：`GATE-2026-08-16T02-48-33`
> 分支：`dev`

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | EmailTemplate/EmailLog/ContactMessage/emails_controller | 无 | 无 admin UI，不涉及 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | EmailTemplate/EmailLog/ContactMessage | `models/pallastrade/{email_template,email_log,contact_message}.rb`、`store.rb` 关联、`base_mailer.rb`、`email_log_recorder.rb` | 只有模型/邮件层，无 admin UI |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | email/contact_message | `api/v3/store/contact_messages_controller.rb` + serializers | Store API，无 admin UI |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | emails/email_*/contact_message | 5 个 controller + 视图 + 导航配置 + 表格配置 | **本次要统一化的对象** |
| Storefront | `storefront/src/` | contactMessages | `lib/data/contact.ts`（SDK contactMessages.create） | 仅前台联系表单，不涉及 |
| Platform | `platform/packages/` | contactMessages/email | `packages/sdk/src/store-client.ts` contactMessages | 仅 SDK 客户端，不涉及 |

### 搜索结论

Email 管理后台 UI 全部位于 `pallastrade_admin` gem（符合分层设计），其他层无重复能力。
本次修改范围仅限 admin gem，无跨层重复风险。

---

## Step 1：Skill 文件咨询（已执行）

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | Sidebar 注册模式 `url: :admin_products_path`（symbol → route helper）；"Add a new resource CRUD section" → scaffold；页面统一用 `content_for :page_title`；表格用 `render_table` |

---

## 需求标题：Email 菜单结构与面包屑统一化

### 背景 / Bug 现象

管理后台 **Email** 菜单（Settings / Notification scenarios / Templates / Outbox / Inbox 5 个子项）相比
**Products** 菜单存在三处严重自定义：

1. **页面结构不统一**：Email 各视图只写了 `content_for(:title, ...)`（浏览器标签页标题），
   没有写 `content_for :page_title`（页面头部 h3 标题）。`shared/_content_header.html.erb`
   只在 `page_title` 存在时渲染 header + `page_actions` → **Email 页面没有页面头，且
   `page_actions` 操作按钮（新建模板/返回/标记已解决等）被整体丢弃不显示**。
2. **面包屑不统一**：
   - `emails_controller` / `email_notification_scenarios_controller` 在 action 内手工
     `add_breadcrumb`（无图标、无子页 crumb）；
   - `email_templates` / `email_logs` / `contact_messages` 完全**没有面包屑**；
   - 无 `add_breadcrumb_icon`（products 用 `box`、orders 用 `inbox`、emails 应无 `send`）。
3. **渲染路径不统一**：`emails` / `email_notification_scenarios` 直接继承 `BaseController`
   自绘页面；`email_notification_scenarios#index` 对 8 个 scenario 逐条
   `find_by`（N+1）；导航配置用 lambda URL 而非 symbol。

### 根因定位（为什么没统一）

Email 管理功能是作为**一次性新增需求**（commit `1da1ab7`「需求：邮件管理整合——Email 一级菜单」）
整体从零搭建的：

- **没有复用已有的统一模式**：products/orders/promotions 都有专属 breadcrumb concern
  （`ProductsBreadcrumbConcern` / `OrderBreadcrumbConcern` / `PromotionsBreadcrumbConcern`），
  email 没有建 concern，而是各 action 手工 `add_breadcrumb`；
- **视图按"自包含新页面"思路编写**：只设置浏览器 tab 标题（`:title`），漏掉标准页面头
  （`:page_title`），导致页面头与 page_actions 丢失；
- **控制器基类选择不一致**：settings/scenarios 用 `BaseController` 自绘，templates/outbox/inbox
  用 `ResourceController`，两者都没有统一接入 breadcrumb；
- **导航注册风格不一致**：`url: -> { PallasTrade.admin_emails_path }`（lambda）与统一模式
  `url: :admin_emails_path`（symbol）不同。

### 目标（参考 Products 菜单统一）

| 项 | Products 现状 | Email 现状 | 目标 |
|---|---|---|---|
| 面包屑 | `ProductsBreadcrumbConcern`（icon + 父 crumb）+ 各子页 crumb | 无 concern；部分页面手工 crumb；无 icon | 新建 `EmailsBreadcrumbConcern`，5 个子页全部有「Emails > 子页」面包屑 + send 图标 |
| 页面头 | 各视图 `content_for :page_title` + `page_actions` | 仅 `content_for(:title)` | 补齐 `page_title`，恢复页面头与操作按钮 |
| 渲染 | ResourceController + TableConcern | settings/scenarios 用 BaseController；scenarios N+1 | 消除 scenarios N+1；统一渲染管线 |
| 导航 | `url: :admin_products_path`（symbol） | `url: -> {...}`（lambda） | 改为 symbol 统一 |

### 改动清单

1. **新增** `pallastrade_admin/app/controllers/concerns/pallastrade/admin/emails_breadcrumb_concern.rb`
   （仿 `ProductsBreadcrumbConcern`：`add_breadcrumb_icon 'send'` + `add_breadcrumb :emails`）。
2. **5 个 controller** include `EmailsBreadcrumbConcern` 并加各自子页 crumb：
   - `emails_controller`（Settings）：`admin.emails.settings`
   - `email_notification_scenarios_controller`：`admin.emails.notification_scenarios`
   - `email_templates_controller`：`admin.emails.templates`（show/edit 加对象 crumb）
   - `email_logs_controller`：`admin.emails.outbox`
   - `contact_messages_controller`：`admin.emails.inbox`
   - 移除 action 内手工 `add_breadcrumb`。
3. **视图补 `content_for :page_title`**：`emails/show`、`email_notification_scenarios/index`、
   `email_templates/{index,new,edit,show}`、`email_logs/{index,show}`、`contact_messages/{index,show}`。
4. **性能**：`email_notification_scenarios#index` 批量加载 templates（8 次 find_by → 1 次）。
5. **导航配置**：`pallastrade_admin_navigation.rb` 中 emails 主项与 settings 子项的
   lambda URL 改 symbol。

### 验收标准（AC）

- AC-1：Email 5 个子页面均有「send 图标 + Emails > 子页」面包屑，与 Products 风格一致。
- AC-2：Email 各页面均渲染标准页面头（h3 标题 + page_actions 按钮可见）。
- AC-3：`email_notification_scenarios#index` 只发 1 次 email_templates 查询。
- AC-4：导航配置 URL 全部 symbol；菜单高亮/展开行为不变。
- AC-5：后端测试通过（`harness check --profile quick`），相关 spec 不回归。

### 测试计划

- 现有 spec：`backend/spec/` 中 email 相关（email_log/email_template/contact_message 模型 +
  store contact_messages API spec）。
- 新增/更新 controller 级 breadcrumb 断言（可选，若现有 spec 覆盖渲染则补充页面头断言）。
- 浏览器验证：登录 dev 后台逐页查看 Email 5 个子页结构与面包屑。
