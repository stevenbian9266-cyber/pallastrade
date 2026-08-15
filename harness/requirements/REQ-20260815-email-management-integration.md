# REQ-20260815-email-management-integration

> 关联 PRD：PRD-20260815-catalog-邮件管理整合-email-一级菜单-配置-模板-记录-分类-回复开关
> 关联 Task：TASK-20260815102607-39551e3b
> 关联 Gate：GATE-2026-08-15T10-26-19

---

## Step 0：跨层搜索（6 层，已完成）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | mailer/email | `app/mailers/application_mailer.rb`（空壳） | ❌ 无邮件管理 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | mailer/notification/back_in_stock | `mailers/`（BaseMailer/BackInStockMailer 等 7 个）、`subscribers/`（5 个）、`store.rb`（email preferences） | ⚠️ 有基础设施，无统一管理 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | email/back_in_stock | `api/v3/store/back_in_stock_subscriptions_controller.rb`、`admin/store_controller.rb`（customer_support_email）、newsletter | ⚠️ 有订阅/字段，无模板/记录/反馈接口 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | email/navigation | `pallastrade_admin_navigation.rb`（settings_nav emails + back_in_stock_subscriptions）、`views/stores/form/_emails.html.erb` | ⚠️ 有设置入口，无一级菜单/模板/记录/反馈 |
| Storefront | `storefront/src/` | email/contact/feedback | `src/lib/emails/`（4 模板 + send.ts Resend）、`src/lib/webhooks/handlers.ts`、`NewsletterSignup.tsx` | ⚠️ 有发送通道，无投诉/反馈表单 |
| Platform | `platform/packages/` | email | 无相关 | ❌ 无 |

**搜索结论**：邮件发送基础设施已存在（core + emails gem + storefront React Email 双通道）。本需求是**新增管理后台统一管理壳**：Email 一级菜单 + 二级子项（配置/通知场景/模板/发送记录/收件与反馈）+ 新模型（邮件模板、发送记录、收件反馈）+ storefront 投诉/反馈表单 + 相关 API。与现有发送通道正交，无重复实现。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：加管理后台菜单项用 `PallasTrade.admin.navigation.sidebar.add`；React to events 用 subscriber；优先级 Settings→Events→Admin→Generators→Decorators。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | Sidebar 用 `sidebar.add :key, label:, url:, icon:, position:`；`settings_nav` 二级注册模式；Developer resources 用 SettingsConcern controller + 表注册 + v3 Admin API + serializer。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 完整闭环：一句话需求 → PRD → gate → REQ → 实施 → 测试 → 知识同步；每个 AC 必须测试覆盖；API 变更须同步 store/admin.yaml + generated:check。 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | API v3 路由 `/api/v3/admin/`；ID 前缀；current_store 作用域；list 返回 `{data, meta}`。 |
| `pallastrade-data-model` | ✅ | ✅ 已读 | Back-in-stock 订阅模型/状态机/事件已存在；Store has_many back_in_stock_subscriptions；新模型（模板/记录/反馈）挂 Store。 |
| `pallastrade-events-webhooks` | ⬜ | （实施时按需读取） | — |
| `pallastrade-storefront` | ✅ | （实施时读取） | — |
| `pallastrade-testing` | ⬜ | （实施时按需读取） | — |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 翻译放 gem locale；导航 key 需 `pallastrade.admin.*` 前缀（此前修复经验）。 |

---

## 需求标题

管理后台 Email 一级菜单整合：邮件配置 / 通知场景 / 邮件模板 / 发送记录 / 收件与反馈 / 回复开关

## 任务类型

新功能（功能升级）

## 需求描述

用户要求把散落各处的邮件功能整合到管理后台统一的 **Email 一级菜单** 下管理：
1. 邮件配置（发件地址/SMTP/回复开关）
2. 邮件通知场景（支付成功、待支付提醒、订单状态提醒、补货提醒、其它）管理
3. 邮件内容编辑模板（CRUD + 预览 + 占位符）
4. 邮件发送记录、收件记录
5. 投诉邮件、意见反馈邮件归类
6. 邮件回复功能开关（方案 A：Reply-To 头 + inbound webhook → 收件与反馈）

## 影响范围

- `pallastrade_admin`：导航（一级菜单 + 二级子项）、controllers、views、tables
- `pallastrade_core`：新模型（EmailTemplate/EmailLog/ContactMessage）+ store preference（SMTP/回复开关）
- `pallastrade_api`：新增 admin API（模板/记录/反馈）+ store API（投诉反馈提交）
- `storefront`：投诉/反馈表单
- 数据库：3 张新表迁移
- API 文档：`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`

## 技术方案（初步）

按决策树：
- **导航**：`PallasTrade.admin.navigation.sidebar.add :emails`（一级）+ 二级子项（类似 settings_nav / developers_tabs_nav 模式）→ `pallastrade-admin` skill
- **模型**：`PallasTrade::EmailTemplate`、`PallasTrade::EmailLog`、`PallasTrade::ContactMessage`，均 `belongs_to :store` → `pallastrade:model` 生成器路径
- **偏好**：`store.rb` preference 声明 SMTP 配置 + 回复开关（`allow_email_replies`）
- **通知场景**：基于现有事件（payment.paid/order.completed/back_in_stock 等）+ 新场景注册表
- **模板渲染**：DB 模板（占位符替换）优先，无则回退代码 mailer 模板（方案 A）
- **发送记录**：ActionMailer `delivered_email` 回调 / interceptor 写入 EmailLog
- **反馈**：storefront 表单 → store API → ContactMessage（kind: complaint/feedback）
- **回复开关**：控制 `reply_to` 头 + inbound webhook 处理（方案 A）

## 风险点

- 大范围改动（跨 5 层）→ risk critical，需 supervise plan/diff + 完整测试
- 现有双通道（core gem + storefront React Email）不能破坏 → 发送记录以 core ActionMailer 为主，storefront 通道不拦截
- SMTP 密码不能明文入库 → 加密存储
- 新表迁移需与现有 schema 兼容（prefix ID、store 作用域）

## 实施步骤（分阶段）

- **P1**：模型 + 迁移（EmailTemplate/EmailLog/ContactMessage）+ store preference
- **P2**：Admin 导航（Email 一级菜单 + 5 个二级子项）+ 各页面骨架
- **P3**：邮件配置页（整合现有字段 + SMTP + 回复开关）
- **P4**：通知场景页（场景注册 + 启停 + 测试发送）
- **P5**：邮件模板 CRUD + 预览 + 占位符渲染接入
- **P6**：发送记录（拦截器/回调写入 + 列表页）
- **P7**：收件与反馈（ContactMessage 列表 + 状态流转）+ storefront 表单 + store API
- **P8**：API 文档同步 + 测试补齐 + 知识同步
