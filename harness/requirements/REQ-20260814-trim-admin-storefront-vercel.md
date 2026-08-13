# 需求文档：裁剪 admin storefront 页面 Vercel 集成 UI 并优化已连接 origins 展示

> 关联 PRD：`docs/prd/storefront/PRD-20260813-storefront-裁剪-admin-storefront-页面-vercel-集成-ui-并优化已连接-origins-展示.md`
> 关联 Task：TASK-20260813160553-b1ed8185 | Gate：GATE-2026-08-13T16-06-23

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | vercel/storefront | 无 | 不涉及 |
| App — views/decorators | `backend/app/` | vercel | 无 | 不涉及 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | vercel/storefront | allowed_origin.rb、stores/setup.rb（仅注释提及 Vercel） | 仅注释，无需改 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | vercel | 无 | 不涉及 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | vercel | 无 | 不涉及 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | vercel/storefront | storefront_controller.rb | 需删 `vercel_dashboard_url` |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | vercel/deploy-button | storefront/show.html.erb | 需删 Vercel 卡片/按钮 |
| Storefront | `storefront/src/` | vercel | 无 | 不涉及 |
| Platform | `platform/packages/` | vercel | 无 | 不涉及 |

### 搜索结论

Vercel 集成代码**全部集中在 pallastrade_admin gem 的 storefront 资源**（controller/helper/view/locales，共 4 文件）。无其他层引用，无重复能力。`backend/spec` 无 storefront 页面测试，需新增。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Admin views/partials 使用 admin 自身 UI 词汇（`link_to_with_icon`、`external_link_to`、`button` 等）"；自定义优先顺序 Settings→...→Direct Gem Modification（本次为删除框架 UI，属 gem 直接修改） |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | "admin sidebar 渲染 navigation + user menu；写 admin views 用 admin UI 词汇"；视图/partial 规范章节 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD 生成（查重→扩充→用户确认→gate→实施→测试→知识同步）完整闭环；优化迭代需"定位已有测试→新增/修改覆盖变更后 AC" |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 否 | — | 无接口变更 |
| `pallastrade-decorators` | ⬜ 否 | — | 非结构性修改 |
| `pallastrade-dependencies` | ⬜ 否 | — | — |
| `pallastrade-events-webhooks` | ⬜ 否 | — | — |
| `pallastrade-storefront` | ⬜ 否 | — | storefront 前台不受影响 |
| `pallastrade-testing` | ✅ 是 | ✅ 已读（既有知识） | RSpec + Factory Bot；`spec/requests` 写 admin 页面回归 |
| `pallastrade-i18n` | ⬜ 否 | — | 仅删 en.yml keys，不新增 |

---

## 需求详情

### 背景

本项目 storefront 与 backend 同域部署（dev.pallastrade.cn / pallastrade.cn），部署走自有 pull-deploy（docker+ghcr），**不使用 Vercel**。`/admin/storefront` 仍展示 Vercel 一键部署卡片与 "View on Vercel" 按钮，属无效/误导性 UI + 死代码。

### 改动清单（均在 `backend/pallastrade_gems/pallastrade_admin/`）

| 文件 | 变更 |
|---|---|
| `app/views/pallastrade/admin/storefront/show.html.erb` | 删 Vercel 部署卡片（deploy_title 卡片 + loopback 分支 + vercel-deploy-button + finish hint + local_installation_instructions）；删 "View on Vercel" 按钮（`@vercel_dashboard_url` 分支） |
| `app/controllers/pallastrade/admin/storefront_controller.rb` | 删 `@vercel_dashboard_url` 赋值 + `vercel_dashboard_url` 方法 |
| `app/helpers/pallastrade/admin/storefront_helper.rb` | 删 `vercel_deploy_url` / `store_url_loopback?` / `STOREFRONT_REPOSITORY_URL` |
| `config/locales/en.yml` | 删 `deploy_button` / `deploy_copy` / `deploy_finish_hint` / `deploy_title` / `loopback_warning` / `view_on_vercel` |
| `backend/spec/requests/pallastrade/admin/storefront_spec.rb`（新增） | 页面回归：渲染 Setup Storefront / API URL / key；不含 Vercel 文案；Connected storefronts 展示 |

### 保留项（不回归）

- Storefront URL 保存（`PATCH /admin/storefront`）与 allowed_origins 自动添加
- `allow_origin`（POST /admin/storefront/allow_origin）
- `@deployment_origin` deployment 确认卡片（非 Vercel 专用）
- Connected storefronts 列表（含空态不渲染保护）
- publishable key 生成/展示

### 验收

见 PRD §5（AC-001~AC-005）。
