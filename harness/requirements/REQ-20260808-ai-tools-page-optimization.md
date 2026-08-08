# REQ-20260808-ai-tools-page-optimization — AI Tools 页面优化

> 关联 PRD：`docs/prd/admin/PRD-20260808-admin-ai-tools-page-optimization.md`
> 任务类型：feature（优化：）

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — controllers | `backend/app/controllers/pallastrade/admin/` | ai, update_model | `ai_controller.rb`（index/providers/provider/models/capabilities/runs/update_model/test_connection） | ✅ 目标层 |
| App — views | `backend/app/views/pallastrade/admin/ai/` | providers/models/capabilities/runs/provider | 6 个视图 | ✅ 目标层 |
| Core Gem | `pallastrade_core/` | back_button/turbo | 无直接 | — |
| API Gem | `pallastrade_api/` | ai | 无（AI API 在 gem 独立 controller） | — |
| Admin Gem — helpers | `pallastrade_admin/app/helpers/` | page_header_back_button | `navigation_helper.rb:242` | ✅ 复用返回按钮 |
| Admin Gem — CSS | `pallastrade_admin/app/assets/tailwind/` | custom-switch | `_forms.css:209` `.custom-switch` | ✅ 复用开关样式 |
| Admin Gem — JS | `pallastrade_admin/app/javascript/` | auto-submit | `application.js` 注册 `@stimulus-components/auto-submit` | ✅ 复用自动提交 |
| Admin Gem — views | `pallastrade_admin/app/views/` | custom-switch | `payment_methods/_payment_method.html.erb`（开关示例） | ✅ 参考模式 |
| Admin Gem — controller | `pallastrade_admin/app/controllers/` | turbo_stream | `resource_controller.rb`（update turbo_stream）、`users_controller.rb:36` | ✅ 参考模式 |
| Storefront | `storefront/src/` | ai | 无 | — |
| Platform | `platform/packages/` | ai | 无 | — |

### 搜索结论

返回按钮复用 admin 官方 helper `page_header_back_button`；开关复用 `custom-switch`（CSS）+ `auto-submit`（Stimulus）+ Turbo Stream 响应模式。全部能力已存在于 admin 层，**0 新组件**，仅需在 AI 视图/controller 应用既有模式。

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "Admin / Ransack APIs" 层适配后台 UI 定制；本任务属 host app 视图 + 控制器微调，走决策树 Admin 层 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | §View helpers：「`page_header_back_button`」为官方返回按钮；「For Turbo Streams … render `turbo_stream.*` from the controller, target frames by ID」；admin = ERB + Stimulus + Turbo |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §4 gate+REQ 流程；§5 测试位置约定（requests → `backend/spec/requests/`） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 否 | — | 无接口变更（update_model 已存在，仅扩展响应格式） |
| `pallastrade-decorators` | ⬜ 否 | — | 直接改 host app controller |
| `pallastrade-dependencies` | ⬜ 否 | — | — |
| `pallastrade-events-webhooks` | ⬜ 否 | — | — |
| `pallastrade-storefront` | ⬜ 否 | — | 不涉及 storefront |
| `pallastrade-testing` | ✅ 是 | 已评估 | 沿用 request spec（RSpec + Factory Bot）模式，见 §8 测试计划 |
| `pallastrade-i18n` | ⬜ 否 | — | 返回按钮用 icon 无文案；开关无文案 → 预计无新增 locale key |

---

## 需求标题

AI Tools 页面优化：详情页返回按钮 + models active 列开关

## 需求描述

1. **返回按钮**：AI Tools 4 个子页面（providers/models/capabilities/runs）+ provider 详情页标题区增加返回按钮（复用 `page_header_back_button`），分别指向 `/admin/ai` 与 `/admin/ai/providers`
2. **models active 开关**：active 列从 On/Off 文本按钮改为 `custom-switch` 开关；切换时 PATCH `/admin/ai/models/:id`，`update_model` 响应 Turbo Stream 局部替换该行，**无整页刷新**

## 验收标准（映射 PRD AC）

- AC-001：4 个子页面标题区可见返回按钮 → `/admin/ai`
- AC-002：provider 详情页返回按钮 → `/admin/ai/providers`
- AC-003：models active 列为开关（非 On/Off 文本）
- AC-004：开关切换即时生效且 URL 不变（无整页刷新）
- AC-005：刷新后状态与服务端一致

## 技术方案

1. **返回按钮**：5 个视图 `content_for :page_title` 内加 `page_header_back_button(<path>)`
2. **开关**：`models.html.erb` active 列改：
   ```erb
   <%= form_tag PallasTrade.admin_ai_update_model_path(model), method: :patch, data: { controller: 'auto-submit' } do %>
     <div class="custom-control custom-switch">
       <%= check_box_tag :active, '1', model.active?, class: 'custom-control-input', data: { action: 'auto-submit#submit' }, id: "ai_model_active_#{model.id}" %>
       <%= label_tag "ai_model_active_#{model.id}", '&nbsp;'.html_safe, class: 'custom-control-label' %>
     </div>
   <% end %>
   ```
   行抽成 `_model_row.html.erb` partial（id=`ai_model_row_<id>`），供 Turbo Stream 替换
3. **controller**：`update_model` 增加 `respond_to` turbo_stream（替换行 + flash.now）与 html（redirect_back 兜底）
4. **turbo_stream 视图**：`update_model.turbo_stream.erb` 用 `turbo_stream.replace "ai_model_row_#{@model.id}"` 渲染 `_model_row` partial

## 影响文件

- 修改：`ai_controller.rb`、`{providers,models,capabilities,runs,provider}.html.erb`
- 新增：`_model_row.html.erb`、`update_model.turbo_stream.erb`
- 测试：`spec/requests/pallastrade/admin/ai_models_spec.rb`（新增/更新）

## 测试计划

- `ai_models_spec.rb`：PATCH update_model → turbo_stream 响应（200 text/vnd.turbo-stream.html）+ active 持久化；HTML 兜底重定向
- 浏览器验证：子页面返回按钮；models 开关无刷新
