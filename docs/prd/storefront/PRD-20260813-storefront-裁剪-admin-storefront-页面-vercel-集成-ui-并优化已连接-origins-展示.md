# PRD-20260813-storefront-裁剪-admin-storefront-页面-vercel-集成-ui-并优化已连接-origins-展示

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-08-13 |
| 来源 | 优化：裁剪 admin storefront 页面 Vercel 集成 UI 并优化已连接 origins 展示 |
| 分类 | storefront（自动判定） |
| 关联 Skill | pallastrade-admin |
| 关联 REQ | REQ-20260814-trim-admin-storefront-vercel.md（实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 优化迭代 |

---

## 1. 背景与目标

- **一句话需求原文**：优化：裁剪 admin storefront 页面 Vercel 集成 UI 并优化已连接 origins 展示
- **背景**：本项目的 storefront 与 backend **同域部署**（dev.pallastrade.cn / pallastrade.cn），部署走自有 pull-deploy（docker + ghcr），**不使用 Vercel**。但 `/admin/storefront` 页面仍展示：
  1. **Vercel 一键部署卡片**（"Recommended: deploy the official Next.js storefront" + Deploy to Vercel 按钮 + loopback 警告 + finish hint）——对本项目无价值，且可能误导用户误点
  2. **"View on Vercel" 回调按钮**（`@vercel_dashboard_url`，仅 Vercel 部署回调带参时显示）
  3. 相应 helper 方法（`vercel_deploy_url` / `store_url_loopback?`）与 i18n keys 成为死代码
- **目标**：
  - 移除 Vercel 集成 UI（部署卡片 + View on Vercel 按钮），让页面聚焦"API URL + Key + Storefront URL"三件套
  - 清理死代码（helper 方法 + i18n keys）
  - 保留并确认 "Connected storefronts"（allowed origins）列表：有数据正常显示、无数据不渲染空白
- **成功指标**：
  - `/admin/storefront` 页面无任何 "Vercel" / "Deploy to Vercel" / vercel-deploy-button 渲染
  - `storefront_helper.rb` 无 `vercel_deploy_url` / `store_url_loopback?`；`en.yml` 无残留 Vercel keys
  - 页面功能（保存 storefront URL / 展示 key / Connected storefronts）不回归

## 2. 用户故事 / 场景

- 作为管理员，我希望 storefront 配置页只显示本项目真正使用的配置（API URL、publishable key、storefront URL），以便不被无关的 Vercel 部署选项干扰。
- 场景列表：
  - 正常：打开 `/admin/storefront`，看到 "Setup Storefront" + Connect your storefront（三件套）+ Connected storefronts（含 dev.pallastrade.cn）
  - 正常：页面**不出现** Deploy to Vercel 按钮 / "View on Vercel" / vercel-deploy-button
  - 边界：store 无 allowed_origins（除 loopback）时，Connected storefronts 卡片不渲染（不出现空白块）
  - 边界：带 `deployment-url` 参数访问页面时，deployment 确认卡片仍正常（非 Vercel 专用，保留）
  - 异常：无（纯 UI 裁剪，不改业务逻辑）

## 3. 功能需求（FR）

- FR-001：移除 Vercel 一键部署卡片（deploy_title/deploy_copy/deploy_button/deploy_finish_hint + loopback 警告 + local_installation_instructions 链接）
- FR-002：移除 "View on Vercel" 回调按钮（view 的 `@vercel_dashboard_url` 分支 + controller 的 `vercel_dashboard_url` 方法 + `@vercel_dashboard_url` 赋值）
- FR-003：清理 `storefront_helper.rb` 死代码（`vercel_deploy_url` / `store_url_loopback?` / `STOREFRONT_REPOSITORY_URL`）
- FR-004：清理 `en.yml` 中不再使用的 Vercel i18n keys（deploy_button/deploy_copy/deploy_finish_hint/deploy_title/loopback_warning/view_on_vercel）
- FR-005：保留 "Connect your storefront"（API URL / publishable key / Storefront URL 表单）与 "Connected storefronts"（allowed origins 列表）能力，确认空态不渲染

## 4. 非功能需求（NFR）

- 兼容：不改变任何路由/接口/数据库结构；不改变 storefront URL 保存与 allowed_origins 逻辑
- 可维护性：清理死代码，避免误导性 UI
- 安全：删除 `vercel_dashboard_url`（原已防任意 URL 反射，删除后无此暴露面）

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：GET /admin/storefront 返回的 HTML 不含 "Deploy to Vercel"、"vercel-deploy-button.svg"、"View on Vercel"、"loopback_warning" 文案
- AC-002 ← FR-001：页面仍显示 "Setup Storefront" 标题、API URL、Publishable API key、Storefront URL 表单
- AC-003 ← FR-003：`storefront_helper.rb` 中无 `vercel_deploy_url` / `store_url_loopback?` / `STOREFRONT_REPOSITORY_URL`（grep 断言）
- AC-004 ← FR-004：`en.yml` 中 storefront_setup 下无 deploy_button/deploy_copy/deploy_finish_hint/deploy_title/loopback_warning/view_on_vercel（grep 断言）
- AC-005 ← FR-005：store 有非 loopback allowed_origin 时页面渲染 Connected storefronts 列表；无时该卡片不渲染（页面无空卡片）

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | vercel/storefront | 无 storefront/Vercel 相关 | 不涉及 |
| Core | `pallastrade_gems/pallastrade_core/app/` | vercel/storefront | allowed_origin.rb / stores/setup.rb（仅注释提及 Vercel） | 无需改（注释保留） |
| API | `pallastrade_gems/pallastrade_api/app/` | vercel/storefront | 无 | 不涉及 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | vercel/storefront/deploy-button | storefront_controller.rb / storefront_helper.rb / views/admin/storefront/show.html.erb / locales/en.yml | **改动核心（4 文件）** |
| Storefront | `storefront/src/` | vercel | 无 | 不涉及 |
| Platform | `platform/packages/` | vercel | 无 | 不涉及 |

**结论**：Vercel 集成代码全部集中在 pallastrade_admin gem 的 storefront 资源；无重复能力、无其他层引用；`backend/spec` 无 storefront 页面测试（需新增）。`setup.rb`/`allowed_origin.rb` 仅注释提及 Vercel，保留（不影响行为）。

## 7. 技术影响

- 涉及文件（均在 `backend/pallastrade_gems/pallastrade_admin/`）：
  - `app/views/pallastrade/admin/storefront/show.html.erb`（删 Vercel 卡片 + View on Vercel 按钮）
  - `app/controllers/pallastrade/admin/storefront_controller.rb`（删 `@vercel_dashboard_url` + `vercel_dashboard_url`）
  - `app/helpers/pallastrade/admin/storefront_helper.rb`（删 `vercel_deploy_url`/`store_url_loopback?`/常量）
  - `config/locales/en.yml`（删 6 个 Vercel keys）
  - 新增：`backend/spec/requests/pallastrade/admin/storefront_spec.rb`（页面回归测试）
- 无数据库变更、无 API 变更、无路由变更
- 影响面：仅 admin storefront 页面渲染，不影响 storefront 前台与 API

## 8. 测试计划

- 新增测试：`backend/spec/requests/pallastrade/admin/storefront_spec.rb`
  - GET /admin/storefront 渲染成功且含 "Setup Storefront" / API URL / publishable key
  - 页面不含 "Deploy to Vercel" / "vercel-deploy-button" / "View on Vercel"（AC-001）
  - 有 allowed_origin 时渲染 Connected storefronts（AC-005）
- 覆盖 AC 映射：AC-001/002/005 → storefront_spec.rb；AC-003/004 → grep 断言（在 spec 中 grep helper/en.yml 或独立断言）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：无接口变更，不涉及
- [x] Skill 文档：`pallastrade-admin` Skill 不描述 storefront 页面细节，**无需更新**
- [ ] README / Agent 文件 / 样式规范：不涉及
- [ ] 反模式库 / 任务规则 / 场景库：不涉及（无新反模式）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-14 | 0.1 | 初稿（Vercel 集成 UI 裁剪 + origins 展示优化） | AI |
| 2026-08-14 | 0.2 | 用户确认实施，明确要求相关代码逻辑一并清理干净（helper/controller/i18n 死代码），不影响现有业务 | 用户 + AI |
| YYYY-MM-DD | 0.1 | 初稿 | AI |
