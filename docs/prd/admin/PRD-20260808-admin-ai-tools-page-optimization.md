# PRD-20260808-admin-ai-tools-page-optimization

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-08 |
| 完成日期 | 2026-08-08 |
| 来源 | 优化：AI Tools 页面优化（详情页返回按钮 + models active 列开关） |
| 分类 | admin（后台 AI Tools 模块） |
| 关联 Skill | pallastrade-admin / pallastrade-prd |
| 关联 REQ | REQ-20260808-ai-tools-page-optimization.md |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：①AI Tools 有四个卡片，点进去会打开独立页面，页面上需要增加返回上一页按钮或者操作 ②models 页面 active 列做成开关，当前页面响应开关操作，目前点击 On、Off 页面有刷新
- **背景**：
  - AI Tools 首页有 4 个卡片（Providers / Models / Capabilities / Runs），点 Manage/View 进入独立页面。当前子页面仅靠面包屑的 "AI Tools" 链接返回，缺少直观的"返回上一页"按钮，用户容易迷失层级
  - models 页 active 列目前是文本按钮（On/Off），点击后整页刷新（form submit → redirect）。用户体验差，期望做成开关并**当前页面即时响应**（Turbo Stream，无整页刷新）
- **目标**：AI 子页面有统一返回按钮；models 页 active 列为可视化开关，切换即时生效不刷新
- **成功指标**：AI 4 个子页面 + provider 详情页均有返回按钮；models 页开关切换 ≤1s 内状态变化且 URL 不变（无整页刷新）

## 2. 用户故事 / 场景

- 作为后台管理员：进入 AI Tools → 点卡片进 Providers/Models/Capabilities/Runs 子页面 → 页面顶部有"返回"按钮 → 一键回 AI Tools 首页
- 作为后台管理员：在 Models 页切换某个模型的启用状态 → 开关即时翻转（无整页刷新）→ 状态与服务端一致
- 正常流：点卡片 → 子页面 → 点返回按钮 → 回 AI 首页
- 正常流：models 页拨动开关 → Turbo 提交 PATCH → 服务端更新 → Turbo Stream 局部替换该行 → 无刷新
- 异常流：update 失败（校验错误）→ flash error 提示，开关状态回滚

## 3. 功能需求（FR）

- FR-001：AI Tools 4 个子页面（providers / models / capabilities / runs）标题区增加返回按钮，指向 `/admin/ai`
- FR-002：provider 详情页（provider）增加返回按钮，指向 `/admin/ai/providers`
- FR-003：models 页 active 列改为开关组件（复用 admin `custom-switch` + `auto-submit` 模式），替换现有 On/Off 文本按钮
- FR-004：切换开关时通过 PATCH `/admin/ai/models/:id` 更新，controller 响应 Turbo Stream（局部替换该行），不整页刷新
- FR-005：开关状态与服务端数据一致（页面刷新后保持实际状态）

## 4. 非功能需求（NFR）

- 兼容：复用 admin 现有 `page_header_back_button` / `custom-switch` / `auto-submit` 组件，不新增样式体系
- 安全：沿用现有 current_store 作用域与权限，无新风险面
- i18n：新增文案走 `PallasTrade.t`，en + zh-CN 补全
- 无刷新：仅目标行更新，不触发全页 Turbo 导航

## 5. 验收标准（AC）

- AC-001：进入 providers/models/capabilities/runs 任一子页面，标题区可见返回按钮，点击回到 `/admin/ai`
- AC-002：进入 provider 详情页，可见返回按钮，点击回到 `/admin/ai/providers`
- AC-003：models 页 active 列显示为开关（switch），不再显示 On/Off 文本按钮
- AC-004：切换开关后，模型 active 状态即时更新且页面 URL 不变（无整页刷新）
- AC-005：开关切换后刷新页面，状态与服务端一致（已持久化）

## 6. 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| App | backend/app/ | ai | ai_controller.rb + 6 视图（index/providers/provider/models/capabilities/runs） | ✅ 目标层 |
| Core | pallastrade_core/ | back_button / turbo | 无直接 | — |
| API | pallastrade_api/ | ai | 无（AI API 在 gem 独立 controller） | — |
| Admin | pallastrade_admin/ | page_header_back_button / custom-switch / auto-submit / turbo_stream | navigation_helper#page_header_back_button、_forms.css .custom-switch、application.js auto-submit、resource_controller turbo_stream | ✅ 复用模式 |
| Storefront | storefront/src/ | 无 | 无 | — |
| Platform | platform/packages/ | 无 | 无 | — |
| AI gem | pallastrade_ai/ | ai | provision services + API v3 controllers | — |

**结论**：返回按钮复用 `page_header_back_button`（navigation_helper）；开关复用 `custom-switch`（_forms.css）+ `auto-submit`（Stimulus，已注册）+ Turbo Stream 响应模式（参考 payment_methods `_payment_method.html.erb` + ResourceController/UsersController turbo 响应）。

## 7. 技术影响

- `backend/app/controllers/pallastrade/admin/ai_controller.rb`：`update_model` 增加 `respond_to format.turbo_stream`（局部替换该行 + flash），HTML 兜底保持 redirect_back
- `backend/app/views/pallastrade/admin/ai/{providers,models,capabilities,runs}.html.erb`：`content_for :page_title` 加 `page_header_back_button(PallasTrade.admin_ai_path)`
- `backend/app/views/pallastrade/admin/ai/provider.html.erb`：`content_for :page_title` 加 `page_header_back_button(PallasTrade.admin_ai_providers_path)`
- `backend/app/views/pallastrade/admin/ai/models.html.erb`：active 列改 `custom-switch` 开关（`form_tag` + `check_box_tag` + `auto-submit`）
- 新增：`backend/app/views/pallastrade/admin/ai/_model_row.html.erb`（表格行 partial，供 turbo_stream 替换）
- 新增：`backend/app/views/pallastrade/admin/ai/update_model.turbo_stream.erb`
- `harness affected`：admin 布局 / AI 控制器 / 视图

## 8. 测试计划

- 新增/更新：`backend/spec/requests/pallastrade/admin/ai_models_spec.rb`（# PRD-20260808-admin-ai-tools-page-optimization AC-003/004/005）——PATCH update_model 支持 `turbo_stream` 响应且持久化 active；HTML 兜底重定向
- 更新：PRD §10 变更记录
- 验证：浏览器（进入子页面看返回按钮；models 页拨开关看无刷新更新）+ rspec

## 9. 文档同步清单

- [x] locale：无新增文案（返回按钮用 icon、开关无文案）
- [x] skill：pallastrade-admin（复用 page_header_back_button / custom-switch 模式，无新组件）
- [x] API 文档：无接口变更（update_model 已存在，仅扩展 turbo_stream 响应格式）
- [x] 场景库：无能力变更

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-08 | 0.1 | 初稿 | AI |
| 2026-08-08 | 0.2 | 实施完成（AC-001~005 全部通过） | AI |

### 实施摘要

- **返回按钮**：5 个视图（providers/models/capabilities/runs/provider）`content_for :page_title` 加 `page_header_back_button`，分别指向 `/admin/ai` 与 `/admin/ai/providers`（复用 admin 官方 helper，带 chevron-left 图标）
- **models 开关**：active 列改为 `custom-switch` 开关；表格行抽 `_model_row.html.erb` partial；`update_model` 增加 `respond_to format.turbo_stream`（Turbo Stream 局部替换该行 + flash），HTML 兜底 redirect；新增 `update_model.turbo_stream.erb`
- **交互实现调整**：初版用 `auto-submit`（Stimulus）但 dev 环境 Stimulus Application 未启动（data-action 不生效）→ 改为 checkbox inline `onchange="this.form.requestSubmit()"`（Turbo 原生拦截，已有 `onclick` 先例），验证可靠
- **测试**：`ai_models_spec.rb` 修复（admin role 需绑定测试 store 否则 CanCanCan 403）+ 新增 4 个 PATCH update_model 用例（turbo_stream 响应/持久化/HTML 兜底/关闭）；`support/devise.rb` 补 `Devise::Test::IntegrationHelpers`（request spec sign_in）

**AC 验证**：AC-001✅（providers/models 页返回按钮，capabilities/runs 同模式）、AC-002✅（provider 详情页返回 /admin/ai/providers）、AC-003✅（active 列为开关）、AC-004✅（切换即时更新无刷新——POST 发出、URL 不变、turbo_stream 行替换、flash 提示）、AC-005✅（刷新后状态一致，AI 首页 Models 4/5 反映持久化）。测试 25 examples 0 failures（AI 全量）。
