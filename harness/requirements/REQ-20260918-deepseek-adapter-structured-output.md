# REQ-20260918-deepseek-adapter-structured-output

| 项 | 值 |
|---|---|
| 任务类型 | Bug 修复 |
| 关联 PRD | `docs/prd/api/PRD-20260918-api-deepseek-structured-output.md` |
| 关联 Task | TASK-20260918020017-217247b3 |
| 关联 Gate | GATE-2026-09-18T02-00-37（bugfix / quick） |
| 需求原文 | `实施`（承接诊断方案：DeepSeek 适配器结构化输出 400 + 系统指令丢失 + 模型 ID + 环境模板） |

---

## Step 0：跨层搜索（强制 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `deep_seek\|DeepSeek\|response_format\|system_instructions\|json_schema` | `controllers/pallastrade/admin/ai_controller.rb`（供应商预置与总览页） | ❌ 无适配器逻辑 |
| App — views/decorators | `backend/app/views/`、`backend/app/decorators/` | 同上 | （0 命中） | ❌ |
| Core Gem — models | `pallastrade_core/app/models/` | `deep_seek\|DeepSeek\|response_format\|system_instructions` | （0 命中） | ❌ |
| Core Gem — services | `pallastrade_core/app/services/` | 同上 | （0 命中） | ❌ |
| API Gem — controllers | `pallastrade_api/app/controllers/` | 同上 | （0 命中） | ❌ |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | `deep_seek\|test_connection\|ai_provider` | 命中均为**支付渠道** `payment_methods#test_connection` | ❌ 无关 |
| Admin Gem — views | `pallastrade_admin/app/views/` | 同上 | `catalog_health/*`、`products/form/*`、`translations/*` 的 `ai_assist` 文案 | ❌ 仅文案，无供应商逻辑 |
| Storefront | `storefront/src/` | `deep_seek\|DeepSeek\|response_format\|ai_provider` | （0 命中） | ❌ |
| Platform | `platform/packages/` | `deep_seek\|DeepSeek\|response_format` | （0 命中） | ❌ |

### 搜索结论

- AI 供应商适配器（`providers/*.rb`）与模型目录（`catalogs/*.rb`）的**唯一实现**位于 `backend/pallastrade_gems/pallastrade_ai/`（本仓库自有 gem，AGENTS.md §1 允许直接修改）。
- 其余 5 层**均无重复实现** → 修复**改既有文件**即可，**不新建实现文件**（R0：能改已有却新建 = 违规）。
- 本次新增文件仅限：RSpec 规格（测试资产）与本 PRD/REQ 文档（流程资产）。
- 供应流程 `PallasTrade::AI::ProvisionModels` 按目录常量产模型，故 FR-004 需同步两处既有规格的模型 ID 断言。

---

## Step 1：Skill 文件咨询（强制 — 每格填真实结论）

**必读 Skill：** 无（仓库不存在 `pallastrade-ai` Skill；本需求不涉及 customization/admin/catalog 的定制决策）

**按需 Skill（本次涉及）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | 「Always use factories — never call `Model.create` directly in tests」；「**Prefer `build` over `create`** when persistence isn't needed」；栈为 RSpec + Factory Bot + `pallastrade_dev_tools`（非 Minitest）。本批规格用 Faraday 替身测请求体，不落库、不打真实 API |
| `pallastrade-deployment` | ☑ 涉及 | ✅ 已读 | 环境变量为「**must be set on every PallasTrade deployment**」的权威表（`SECRET_KEY_BASE`/`DATABASE_URL`/`REDIS_URL`…），并强调「**The key is a secret — set it only in the server `.env` (e.g. `deploy/.env.dev`), never commit it**」→ FR-005 只在模板写**空值 + 说明**，不写真实密钥 |
| `pallastrade-api-v3` | ☐ 不涉及 | ✅ 已评估 | 无 API 契约变更（`test_connection` 响应字段名/类型不变，仅取值更诚实）→ §9 API 文档项判定无需更新 |
| `pallastrade-catalog` | ☐ 不涉及 | ✅ 已评估 | 四个能力虽属商品域，但本次不改能力/schema/端点，只改底层供应商适配器 |
| `pallastrade-customization` | ☐ 不涉及 | ✅ 已评估 | 改动位于自有 gem 内部实现，非定制决策树选型问题 |
| `pallastrade-decorators` | ☐ 不涉及 | ✅ 已评估 | 不装饰既有类，直接改 gem 源文件（仓库为自有产品，git 追踪合并） |

> **CI 环境差异教训（来自既有 REQ-E1/E2）**：CI 不注入 `PALLASTRADE_AI_ENABLED`（Gate 1 拦截）与 `ACTIVE_RECORD_ENCRYPTION_*`（`ProviderSecret` fail-closed）。
> 本批规格**只测适配器层**（不触发可用性闸门、不造 `ProviderSecret`），故不受该差异影响。

---

## 需求标题

修复 DeepSeek 供应商适配器：结构化输出改用受支持的 `json_object`、恢复被丢弃的系统指令、`test_connection` 返回真实状态、修正目录模型 ID、补齐部署模板的 AI 开关

## 任务类型

Bug 修复（其中 D3 为健壮性修复）

## 需求描述

dev 环境后台已正确配置 DeepSeek（密钥有效、连通 104ms），但四个商品 AI 能力全部失败（HTTP 400）。经真实 API 对照矩阵 + 代码走查定位：

1. **D1（阻断级）** 适配器发送 `response_format: {type: 'json_schema'}`，DeepSeek 明确回 `This response_format type is unavailable now`。四个能力均声明 output schema → **必然 400，无一例外**。
2. **D2（阻断级·正确性）** 适配器**完全丢弃** `request.system_instructions`（OpenAI 的 chat-completions 路径会注入为 system 消息）→ 领域约束（如「不得编造规格」）从未到达模型。
3. **D3（健壮性）** `test_connection` 的 `status` 硬编码 `'verified'`；且 5xx / 网络失败未 rescue，异常逃逸，违反 `Base#test_connection` 的 `@return [Hash]` 契约。
4. **D4（误导）** 目录预置 `deepseek-v4-flash`，DeepSeek 侧不存在（实测为 `deepseek-flash`）。
5. **D5（新环境静默不可用）** 两个 `.env.example` 均未登记 `PALLASTRADE_AI_ENABLED`（系统总开关，默认 false）。
6. **D6（实施期发现，高陷阱）** 模型目录**双份**：`catalogs/deep_seek.rb::MODELS` 全仓**无任何读取点**（仅 `SUPPORTED_PARAMETERS` 被用），
   `ProvisionModels` 读的是 `provider_registry.rb` 的内联 `recommended_models`。
   → 只改目录**完全无效**（实施中差点如此）；FR-004 修正为**两处同改**，并由规格强制同步。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 1,
  "affectedComponents": [],
  "errors": [],
  "estimatedTests": 3
}
```

（`filesChanged=1` 为本 PRD 新增；实施后预计 3 个受影响测试目标：新增 providers 规格、新增 catalogs 规格、更新的 provision_models 规格）

**改动文件清单**

| 文件 | 动作 | FR |
|---|---|---|
| `backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/providers/deep_seek.rb` | 改 | FR-001/002/003 |
| `backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/catalogs/deep_seek.rb` | 改 | FR-004（可读目录） |
| `backend/pallastrade_gems/pallastrade_ai/config/initializers/provider_registry.rb` | 改 | FR-004（**实际供应来源**） |
| `deploy/.env.dev.example` | 改 | FR-005 |
| `backend/.env.example` | 改 | FR-005 |
| `backend/spec/services/pallastrade/ai/providers/deep_seek_spec.rb` | 新增 | AC-001..AC-009 |
| `backend/spec/services/pallastrade/ai/catalogs/deep_seek_spec.rb` | 新增 | AC-010（含两处来源同步） |
| `tests/ai-env-template.test.mjs` | 新增 | AC-012（仓库级 node:test） |
| `harness.config.mjs` | 改 | 注册 `ai-provider-rspec` + 扩 `repo-guards-test` |
| `AGENTS.md` §6 | 改 | docImpact（harness.config.mjs 变更） |
| `backend/spec/services/pallastrade/ai/provision_models_spec.rb` | 改 | AC-011 |
| `backend/spec/requests/pallastrade/admin/ai_models_spec.rb` | 改 | AC-011 |

## 技术方案（初步）

- **层级选择**：直接修改 `pallastrade_ai` gem 源文件。
  理由：适配器与目录是 gem 内部实现，无对应定制扩展点（决策树优先级 1–7 均不适用：非设置开关、非事件副作用、非 DI 替换、非 admin UI、非新资源、非装饰既有类、非跨 app 共享扩展）。
  按 AGENTS.md §1，本仓库为 PallasTrade 团队自有产品，gem 文件可直接修改并由 git 追踪。
- **FR-001/002 实现要点**：
  - `build_request_body` 中 `response_format` 改为 `{type: 'json_object'}`。
  - 新增私有方法组装 messages：先收集 `system_instructions`（若有），再追加「只返回 JSON + 目标 schema JSON」的指令（保证字面词 `json` 出现，满足 DeepSeek 前置条件），合并为**单条** `role: 'system'` 消息置于首位。
  - 无 `response_schema` 时不注入 schema 指令、不发 `response_format`（纯文本路径不回归）。
  - `parse_response` 既有 `JSON.parse` 兜底保持不变（`json_object` 模式已保证合法 JSON）。
- **FR-003 实现要点**：`status: response.success? ? 'verified' : 'error'`；新增 `Faraday::ServerError`、`Faraday::ConnectionFailed` rescue 分支返回结构化失败。
- **FR-004**：仅改 `MODELS[0][:provider_model_id]`。
- **FR-005**：模板补变量与中文/英文说明，值留空（**不含真实密钥**）。
- **验证**：容器内 RSpec 覆盖 AC-001..AC-012；dev 上用真实 DeepSeek API 跑四个能力并留存 Run/artifact 证据。

## 风险点

| 风险 | 等级 | 缓解 / 回滚 |
|---|---|---|
| 适配器行为变更影响其他 provider 路径 | 低 | OpenAI 适配器零改动；改动限于 `Providers::DeepSeek` |
| 模型 ID 变更导致既有库中 `deepseek-v4-flash` 行成为孤儿 | 低 | 供应流程按新 ID 匹配；dev 上该行已由人工改为 `deepseek-flash`，不受影响 |
| `json_object` 只保证 JSON 语法、不保证字段形状 | 中 | 网关 output schema 校验仍在；缺口记入 PRD §7.2 后续风险 |
| 规格更新遗漏导致 CI 红 | 低 | 全仓 grep `deepseek-v4-flash` 清零后再提交 |

**回滚难度**：低 —— 纯代码 + 文档，无 migration、无数据变更；`git revert` 即可还原。

## 决策节点

> 用户已下达 `实施` 指令（承接上一轮「4 项修复方案」），且本任务为 bugfix gate（无 `user-confirmed` check）。
> 实施期间发现并对诊断做了**诚实更正**（D3 的 401 指控不成立，见 PRD §1.1），已在 PRD 中显式标注。
