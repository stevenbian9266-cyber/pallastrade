# PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-13 |
| 来源 | 需求：管理后台，菜单栏中有个 integrations，去掉这个菜单以及相关的业务逻辑、代码逻辑，不影响其它逻辑（后经用户确认：AI 模块与通用 Integration 解耦） |
| 分类 | admin（自动判定） |
| 关联 Skill | pallastrade-admin / pallastrade-data-model |
| 关联 REQ | 实施时回填 |
| 关联 PRD | N/A（查重命中 PRD-20260808-admin-remove-enterprise-edition-notice，功能不同，确属全新需求 --force 新建） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：管理后台，菜单栏中有个 integrations，去掉这个菜单以及相关的业务逻辑、代码逻辑，不影响其它逻辑
- **追加诉求**：AI 模块（DeepSeek/OpenAI providers）不应寄生在通用 `PallasTrade::Integration`（STI）上，两个模块需要解耦
- **背景**：
  1. 管理后台侧边栏有 Integrations 菜单（第三方服务连接管理页），当前部署不需要
  2. AI 模块（`pallastrade_ai` gem）建设时选择复用 `PallasTrade::Integration` 作为 provider 的 STI 基类（每店每类型唯一 + store 作用域 + 前缀 ID + preferences），导致 AI 数据（含 `provider_secrets`/`ai_models`/`ai_runs` 外键）寄生于 `pallastrade_integrations` 表 → 两模块耦合
- **目标**：
  1. AI 模块建立**独立 provider 模型与数据表**，彻底切断对 `PallasTrade::Integration` 的依赖
  2. 通用 integrations（菜单/路由/控制器/视图/helper/模型/数据表）整体移除
- **成功指标**：AI 模块测试全绿且零 `PallasTrade::Integration` 引用；`git grep -i integration` 在 admin/core 无业务残留；侧边栏无 Integrations 菜单

## 2. 用户故事 / 场景

- 作为后台管理员，登录管理后台 → 侧边栏**不再出现** Integrations 菜单
- 访问旧 `/admin/integrations` 路径 → 404（路由已移除）
- 作为管理员，配置 AI（DeepSeek/OpenAI）→ **功能不变**，数据存于独立的 `pallastrade_ai_providers` 表
- 已有 AI provider 配置（若有密钥）→ 迁移后不丢失
- 其它后台页面（商品、订单、设置等）→ 正常渲染，无报错

## 3. 功能需求（FR）

### 阶段 A：AI 解耦

- FR-001：新建 `PallasTrade::AI::Provider < PallasTrade.base_class` 独立 STI 基类，`DeepSeek`/`OpenAI` 子类迁移至 `PallasTrade::AI::Provider::DeepSeek` / `PallasTrade::AI::Provider::OpenAI`（命名空间避开已占用的 service 层 `PallasTrade::AI::Providers::*`）
- FR-002：新建数据表 `pallastrade_ai_providers`（store_id / type / active / preferences），迁移现有 AI integration 记录（dev 2 条、prod 2 条，均 inactive 无密钥）
- FR-003：外键重指向：`pallastrade_ai_provider_secrets.integration_id` → 新 `provider_id`；`pallastrade_ai_models.provider_id`、`pallastrade_ai_runs.provider_id` 改指新表（关联数据均 0 条，零数据风险）
- FR-004：`Store` 增加 `has_many :ai_providers`；AI 模块全部 `current_store.integrations` 改 `current_store.ai_providers`
- FR-005：`ProviderSecret` / `AI::Model` / `AI::Run` 的 `belongs_to` 改指 `PallasTrade::AI::Provider`
- FR-006：AI controllers（providers/credentials/models/connection_tests）、services（providers/deep_seek|open_ai|base、provision_providers、provision_models、availability_service）、serializer、permission_sets、`provider_registry`（`integration_class` → `provider_class`）全部改用新模型
- FR-007：`app/controllers/pallastrade/admin/ai_controller.rb`（宿主 app）改用 `PallasTrade::AI::Provider` 查询

### 阶段 B：移除通用 Integrations

- FR-008：管理后台侧边栏移除 Integrations 菜单项
- FR-009：移除 `/admin/integrations` 路由 + 删除 `IntegrationsController` 及全部 integrations 视图
- FR-010：删除 admin engine 的 `integrations_actions_partials`/`integrations_header_partials` 注册与 base_controller 的 `helper 'pallastrade/integrations'`
- FR-011：删除 core gem 的 `integrations_helper.rb`
- FR-012：删除 admin locale 中 `admin.integrations.*` 文案（保留 `integrations_directory`，payment_methods 视图仍引用）
- FR-013：删除 `PallasTrade::Integration` 模型、`Store#has_many :integrations`、`IntegrationsConcern` 及其在 `base.rb`/`shipment_handler.rb` 的 include、`PallasTrade.integrations` 注册机制（core.rb/engine.rb）——AI 解耦后已无使用者
- FR-014：删除 `pallastrade_integrations` 数据表（迁移脚本 drop，解耦后无引用）

## 4. 非功能需求（NFR）

- 兼容性：AI 模块行为不变（API 响应结构、权限 subject、provision 流程）；后台其余页面正常渲染
- 数据安全：迁移前确认 AI integration 记录数与密钥存在性；迁移失败可回滚（up/down）
- 可维护性：解耦后 AI 与 integrations 零相互引用
- 数据表：`pallastrade_ai_providers` 保留原 `preferences` YAML 序列化结构

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`PallasTrade::AI::Provider`（含 DeepSeek/OpenAI 子类）存在，且继承链不含 `PallasTrade::Integration`（模型断言）
- AC-002 ← FR-002/003：`pallastrade_ai_providers` 表存在，含迁移后的 2 条记录；`provider_secrets`/`ai_models`/`ai_runs` 外键指向新表（DB 断言）
- AC-003 ← FR-004/005/006：AI 模块代码无 `PallasTrade::Integration` 或 `current_store.integrations` 引用（grep 断言）
- AC-004 ← FR-007：宿主 app `ai_controller.rb` 使用 `PallasTrade::AI::Provider`（grep 断言）
- AC-005 ← FR-008：登录管理后台侧边栏无 Integrations 菜单（浏览器验证）
- AC-006 ← FR-009：`GET /admin/integrations` 返回 404（路由断言）
- AC-007 ← FR-010/011/012：engine 无 `integrations_*_partials`；base_controller 无 helper；locale 无 `admin.integrations.*` 残留（grep 断言）
- AC-008 ← FR-013/014：`integration.rb`/`integrations_concern.rb`/`integrations_helper.rb` 已删；`pallastrade_integrations` 表已 drop（grep + DB 断言）
- AC-009 ← NFR：AI 模块全量测试全绿（`spec/services/pallastrade/ai/*`、`spec/requests/pallastrade/admin/ai_models_spec.rb`、`ai_providers_spec` 等）
- AC-010 ← NFR：后台基础页面正常 200；AI 设置页浏览器可用

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | integration | `controllers/pallastrade/admin/ai_controller.rb`（用 `current_store.integrations` + AI::Integrations::DeepSeek/OpenAI）、`views/pallastrade/admin/ai/*.html.erb` | **改造**：改用 `PallasTrade::AI::Provider` |
| Core | `pallastrade_gems/pallastrade_core/app/` | integration | `models/pallastrade/integration.rb`、`concerns/integrations_concern.rb`、`helpers/integrations_helper.rb`、`store.rb:117 has_many :integrations`、`base.rb`/`shipment_handler.rb` include、`core.rb`/`engine.rb`（PallasTrade.integrations） | **删除**（AI 解耦后无使用者） |
| API | `pallastrade_gems/pallastrade_api/app/` | integration | 仅 2 处注释（admin_authentication.rb、store_credits_controller.rb） | 无需改动 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | integration | `integrations_controller.rb`、`views/pallastrade/admin/integrations/*`（4 文件）、`base_controller.rb:17 helper`、`engine.rb:33-34 partials`、`routes.rb:244 resources :integrations`、`pallastrade_admin_navigation.rb:185-191 菜单`、`locales/en.yml:229-232` | **全部删除** |
| AI | `pallastrade_gems/pallastrade_ai/` | integration | 模型（integrations/deep_seek|open_ai）、model.rb/provider_secret.rb/run.rb、controllers（providers/credentials/models/connection_tests）、services（providers/*、provision_*、availability_service）、serializer、permission_sets、provider_registry、migrations（2026072400000*） | **改造为独立 Provider**（阶段 A） |
| Storefront | `storefront/src/` | integration | 仅 4 处注释 | 无需改动 |
| Platform | `platform/packages/` | integration | 仅 docs/dist 生成文档 + 注释 | 无需改动 |

**结论**：
- 阶段 A 改造 `pallastrade_ai` 全模块（模型/表/控制器/service/权限/注册）到独立 `PallasTrade::AI::Provider`
- 阶段 B 删除 core + admin 的通用 integrations（模型/表/菜单/路由/控制器/视图/helper/文案）
- AI 是 `PallasTrade::Integration` 唯一消费方，解耦后通用 integrations 可彻底移除（防重复判定通过）

## 7. 技术影响

- **新增**：`PallasTrade::AI::Provider` 基类 + `Provider::DeepSeek`/`Provider::OpenAI` 子类（`pallastrade_ai`）；migration `create_pallastrade_ai_providers` + 数据迁移 + 外键重指向 + drop `pallastrade_integrations`
- **修改**（约 20 文件，`pallastrade_ai`/`pallastrade_core`/`pallastrade_admin`/宿主 app）：
  - `pallastrade_ai`：models（deep_seek/open_ai/model/provider_secret/run）、lib（ai.rb、provider.rb、provider_registry.rb）、config/initializers/provider_registry.rb、controllers（4）、services（6）、serializer、permission_sets、migrations（改外键）
  - `pallastrade_core`：`store.rb`（加 `has_many :ai_providers`、删 `has_many :integrations`）、`base.rb`/`shipment_handler.rb`（删 concern include）、删 `integration.rb`/`integrations_concern.rb`/`integrations_helper.rb`、`core.rb`/`engine.rb`（删 PallasTrade.integrations 机制）
  - `pallastrade_admin`：删 controller/views/nav 菜单/routes/engine partials/base_controller helper/locale
  - 宿主 app：`ai_controller.rb` 改新模型
- **数据库变更**：新增 `pallastrade_ai_providers`；`provider_secrets`/`ai_models`/`ai_runs` 外键改指；drop `pallastrade_integrations`
- **无 API 变更、无前端变更**
- 影响面：`pallastrade_ai` 全部 + `pallastrade_core` integrations 相关 + `pallastrade_admin` integrations 资源

## 8. 测试计划

- **新增测试**：`spec/models/pallastrade/ai/provider_spec.rb`（STI + 唯一性 + preferences）；`spec/requests/pallastrade/api/v3/admin/ai/*`（providers/credentials/models/connection_tests 改用新模型后回归）；数据迁移 spec（`spec/migrations/` 或 seed 断言）
- **更新测试**：`spec/services/pallastrade/ai/provision_providers_spec.rb`、`provision_models_spec.rb`、`spec/requests/pallastrade/admin/ai_models_spec.rb`（改用 `PallasTrade::AI::Provider` factory）
- **回归**：`bundle exec rspec spec/services/pallastrade/ai/ spec/requests/pallastrade/admin/ spec/models/pallastrade/ai/`；`harness check --profile quick`
- **AC 映射**：AC-001/002/009 → rspec；AC-003/004/007/008 → grep 断言；AC-005/006/010 → 浏览器 + route 断言
- **数据迁移验证**：migrate up/down 各跑一次，确认 2 条 AI 记录迁移正确、外键指向正确

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-admin/SKILL.md`（若描述 integrations 资源则更新）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`（若描述 Integration/Store 关联则更新）
- [ ] `ai/skills/pallastrade-ai/SKILL.md`（若存在；新 Provider 模型说明）
- [ ] `docs/prd/README.md` 索引（新 PRD）
- [ ] 本 PRD 状态更新
- [ ] 反模式/任务规则/场景库：如涉及才更新

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-13 | 0.1 | 初稿（删菜单，保留 Integration） | AI |
| 2026-08-13 | 0.2 | 用户确认 AI 解耦方案：扩展为 AI 独立 Provider + 移除通用 integrations | AI |
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射（AC-xxx → 测试文件）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |
