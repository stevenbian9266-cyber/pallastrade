# 需求文档：移除管理后台 integrations 菜单及相关逻辑

> 任务：`TASK-20260813124300-02e5072d` | Gate：`GATE-2026-08-13T12-44-48` | 类型：feature（需求）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | integration | `controllers/pallastrade/admin/ai_controller.rb`（AI 模块用 `current_store.integrations` + `AI::Integrations::DeepSeek/OpenAI`） | AI 依赖 Integration 关联 → 保留，不属本次删除 |
| Core Gem — models | `pallastrade_core/app/models/` | integration | `integration.rb`（AI STI 基类）、`integrations_concern.rb`、`store.rb:117 has_many`、`base.rb`/`shipment_handler.rb` include | 模型/关联/concern 保留；仅删 `helpers/integrations_helper.rb` |
| API Gem — controllers | `pallastrade_api/app/controllers/` | integration | 仅 2 处注释 | 无 endpoints，无需改动 |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | integration | `integrations_controller.rb`、`base_controller.rb:17 helper` | **删除**（本次目标） |
| Admin Gem — views | `pallastrade_admin/app/views/` | integration | `views/pallastrade/admin/integrations/`（4 文件）、`engine.rb` partials、`routes.rb:244`、nav 菜单、`locales/en.yml` | **删除**（本次目标） |
| Storefront | `storefront/src/` | integration | 仅 4 处注释 | 无相关功能 |
| Platform | `platform/packages/` | integration | 仅 docs/dist 生成文档 + 注释 | 无相关功能 |

### 搜索结论

- 本次删除范围：**admin gem 的 Integrations 资源**（菜单/路由/控制器/视图/helper 引用/partials 注册/i18n）+ core 的 `integrations_helper.rb`
- **严禁删除**：`PallasTrade::Integration` 模型、`Store#integrations` 关联、`IntegrationsConcern`、`PallasTrade.integrations` 注册机制、AI 模块、`pallastrade_integrations` 数据表
- AI 模块（DeepSeek/OpenAI）通过 `PallasTrade::AI.providers` 独立注册，不依赖通用 integrations 管理 UI

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | admin 是 Rails engine，挂载于 `/admin`；资源页面由 controller + views + nav 注册组成；nav 在 `config/initializers/pallastrade_admin_navigation.rb` 通过 `sidebar_nav.add` 注册；本任务即删除 `:integrations` nav 项 + `resources :integrations` 路由 + controller + views |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD → 查重（`prd new` 自动，>0.3 阻止）→ 用户确认 → gate → 实施 → 知识同步；本次已走查重（命中 enterprise-edition-notice PRD，功能不同，`--force` 新建） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | 否 | — | 无 API 变更 |
| `pallastrade-decorators` | 否 | — | 无 decorator 变更 |
| `pallastrade-testing` | 是 | ✅ 已读 | 最小验证矩阵：Ruby 变更 → `harness check --profile quick`；AI 模块回归跑 `spec/services/pallastrade/ai/` |
| `pallastrade-i18n` | 是 | 已评估 | locale 删除 `admin.integrations.*` keys，保留 `integrations_directory`（payment_methods 视图仍引用） |

---

## 需求标题

AI 模块解耦 + 移除管理后台 integrations 菜单及相关逻辑（不影响其它逻辑）

## 需求描述

### 阶段 A：AI 解耦（pallastrade_ai 独立）
1. **新建** `PallasTrade::AI::Provider < PallasTrade.base_class` 独立 STI 基类；DeepSeek/OpenAI 子类迁至 `PallasTrade::AI::Provider::DeepSeek` / `Provider::OpenAI`
2. **新建表** `pallastrade_ai_providers`；迁移现有 AI integration 记录（dev/prod 各 2 条，inactive 无密钥）
3. **外键重指向**：`provider_secrets.integration_id` → `provider_id`；`ai_models.provider_id`、`ai_runs.provider_id` 改指新表（关联数据 0 条）
4. `Store` 加 `has_many :ai_providers`；AI 全部 `current_store.integrations` → `current_store.ai_providers`
5. `ProviderSecret`/`AI::Model`/`AI::Run` belongs_to 改指新模型
6. AI controllers/services/serializer/permission_sets/provider_registry 全部改用新模型
7. 宿主 app `ai_controller.rb` 改用新模型

### 阶段 B：移除通用 Integrations
8. 删除 admin 侧边栏 Integrations 菜单、`/admin/integrations` 路由、`IntegrationsController`、全部视图
9. 删除 admin engine partials 注册、base_controller helper、locale `admin.integrations.*`
10. 删除 core `integrations_helper.rb`、`integration.rb` 模型、`integrations_concern.rb` 及 base.rb/shipment_handler include、`Store#has_many :integrations`、`PallasTrade.integrations` 机制
11. drop `pallastrade_integrations` 数据表

## 验收标准

- AC-001：`PallasTrade::AI::Provider`（含子类）继承链不含 `PallasTrade::Integration`
- AC-002：`pallastrade_ai_providers` 表含迁移后的 2 条记录；外键指向新表
- AC-003：AI 模块代码无 `PallasTrade::Integration` / `current_store.integrations` 引用
- AC-004：宿主 app ai_controller 用新模型
- AC-005：侧边栏无 Integrations 菜单
- AC-006：`GET /admin/integrations` → 404
- AC-007：engine/base_controller/locale 无残留
- AC-008：`integration.rb`/`integrations_concern.rb`/`integrations_helper.rb` 已删；`pallastrade_integrations` 表已 drop
- AC-009：AI 模块全量测试全绿
- AC-010：后台基础页面 200；AI 设置页浏览器可用
