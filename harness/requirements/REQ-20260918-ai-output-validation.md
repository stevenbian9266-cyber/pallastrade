# REQ-20260918-ai-output-validation

| 项 | 值 |
|---|---|
| 任务类型 | 优化迭代 |
| 关联 PRD | `docs/prd/admin/PRD-20260918-admin-ai-output-validation.md` |
| 关联 Task | TASK-20260918025044-fc936a9e |
| 关联 Gate | GATE-2026-09-18T02-50-53（feature） |
| 需求原文 | `实施这项风险优化`（前序 PRD §7.2 残留风险） |
| 用户确认 | ✅ 已确认（2026-09-18，用户明确选择「确认实施」，含 FR-004 后台提示修复） |

---

## Step 0：跨层搜索（强制 — 无例外）

**关键词**：`structured_output` / `validate_output` / `output_schema` / `ai_output_invalid` / `renderError` / `ai_assist_error`

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App — models/controllers | `backend/app/` | （0 命中）；但 `app/controllers/pallastrade/admin/ai_controller.rb` 是 4 个 AI 助手段点的**宿主**，第 295/359 行把 `result.error_code` 原样放进 `{ error: { code: … } }` | ❌ 无校验逻辑，**但属改动相关方**（错误码取值域变了） |
| App — views/decorators | `backend/app/views/`、`backend/app/decorators/` | （0 命中） | ❌ |
| Core Gem — models | `pallastrade_core/app/models/` | （0 命中） | ❌ |
| Core Gem — services | `pallastrade_core/app/services/` | （0 命中） | ❌ |
| API Gem — controllers | `pallastrade_api/app/controllers/` | （0 命中）；AI 管理端点实为 `pallastrade_ai` 自带 `api/v3/admin/ai/**`，其中 `runs_controller` 支持按 `error_code` 筛选（新码可直接筛选） | ❌ |
| Admin Gem — controllers/JS | `pallastrade_admin/app/` | `javascript/pallastrade/admin/controllers/ai_assist_controller.js`（**D4 所在**） | ✅ **需改** |
| Admin Gem — views | `pallastrade_admin/app/views/` | 4 个文件的 `ai_assist_error:*_label` 映射；递归扫描得已登记 11 个码 | ✅ **需改** |
| Storefront | `storefront/src/` | （0 命中） | ❌ 前台不消费 AI |
| Platform | `platform/packages/` | （0 命中） | ❌ |

### 搜索结论

1. 输出校验的**唯一实现**在 `pallastrade_ai`（`Gateway` 同步 + `ExecuteRunJob` 异步 + 两个适配器的 `normalize_error`），其他层无重复 → **改既有文件，不新建实现**。
2. 错误展示的**唯一实现**在 `pallastrade_admin`（1 个 Stimulus 控制器 + 4 个视图 + locale）→ 同样改既有文件。
3. **新增文件仅限规格**：3 个 RSpec + 1 个仓库级 node 守卫（测试资产，非实现重复）。
4. 后台 `backend/` **无 JS 测试设施**（无 `backend/package.json`、无任何 `*.test.js|*.spec.ts`）→ UI 层以「服务端渲染契约（request spec）+ 仓库级 JS 契约守卫（node:test）」覆盖，**不新建 JS 测试栈**（明确记为范围边界）。

---

## Step 1：Skill 文件咨询（强制 — 每格填真实结论）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「**Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions**」，并强调「Decorators are reserved for *structural* changes… for behavioral changes use Events instead」。本次属**gem 内既有服务的逻辑修正 + 后台既有视图/控制器修正**，不适用任何定制层（非设置开关、非事件副作用、非 DI 替换、非新资源、非装饰既有类）→ 直接改源文件，符合 R0「能改已有却新建 = 违规」 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | §5 REQ 简版规范：**「改动 ≤5 文件且无逻辑变更 → 简版；否则完整版」**。本次 >5 文件且含逻辑变更 → **必须完整版 REQ**（本文档）；「核心监督（跨层搜索 + 验证 + 确认）任何版本都保留」 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台是 Rails engine：「server-rendered ERB views, **Stimulus + Turbo** for interactivity」；`app/javascript/pallastrade/admin/` 放 Stimulus 控制器、`app/views/pallastrade/admin/<resource>/` 放视图；宿主 `backend/app/` 同名路径可覆盖 gem 文件，但**本仓库为自有产品，gem 文件直接改**（与本次前序任务一致） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | 「Always use factories — never call `Model.create` directly in tests」「Prefer `build` over `create`」；RSpec + Factory Bot + `pallastrade_dev_tools`。CI **不注入** `PALLASTRADE_AI_ENABLED`（可用性 Gate 1 会拦）与 `ACTIVE_RECORD_ENCRYPTION_*`（`ProviderSecret` fail-closed）→ 本次规格需在规格内显式打开系统开关或用替身，且**不打真实 API** |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已评估 | 新增 locale 键必须 en ↔ zh-CN **双向键集相等**（仓库有 `admin-i18n-rspec` 校验与顶级键批次约定） |
| `pallastrade-api-v3` | ☐ 不涉及 | ✅ 已评估 | 无 OpenAPI/契约变更：响应结构 `{ error: { code } }` 不变，仅 `code` 的取值域新增一个值 |
| `pallastrade-decorators` | ☐ 不涉及 | ✅ 已评估 | 不装饰既有类，直接改 gem 源文件 |
| `pallastrade-storefront` | ☐ 不涉及 | ✅ 已评估 | 前台不消费 AI（0 命中） |

---

## 需求标题

修复 AI 输出校验缺口：声明了 output schema 的能力拿不到可用结构化输出时必须判失败（含异步路径），并让失败在后台可见、错误码真实

## 任务类型

优化迭代（消除"把失败伪装成成功"的静默错误 + 修正误导性错误码 + 修复后台空白提示）

## 需求描述

见 PRD §1.1：**D1** 网关用 `structured_output.present?` 短路输出校验（只在已成功时才校验）；
**D2** 异步路径完全不校验；**D3** `OutputValidationError` 被映射成 `ai_provider_unavailable`；
**D4（实施期重新定性）** 五处 AI 助手容器的属性缺 `data-` 前缀 → **Stimulus 从未挂载**（按钮点了没反应），
文案还会被 dataset 驼峰换算搞丢 —— 比初稿的「某些码显示空白」严重得多；
**D5（实施期新增）** 异步失败路径被 Sentry 上报反噬：未初始化时 `with_scope` 交 nil → `set_tags` 抛 `NoMethodError`，
Run 已落 `failed` 但作业抛异常，Sidekiq 重试确定性失败。

> 用户已于 2026-09-18 二次确认将 **D4 接线修复并入本次**（选项：扩围）。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 1,
  "affectedComponents": [],
  "errors": [],
  "estimatedTests": 3
}
```

（实施前基线：仅 PRD 新增；实施后预计 3 个受影响测试目标：网关规格、作业规格、error-code 规格）

**改动文件清单**

| 文件 | 动作 | FR |
|---|---|---|
| `pallastrade_ai/app/services/pallastrade/ai/gateway.rb` | 改 | FR-001/003/005 |
| `pallastrade_ai/app/jobs/pallastrade/ai/execute_run_job.rb` | 改 | FR-002/007 |
| `pallastrade_ai/app/services/pallastrade/ai/providers/deep_seek.rb` | 改 | FR-003 |
| `pallastrade_ai/app/services/pallastrade/ai/providers/open_ai.rb` | 改 | FR-003 |
| `pallastrade_admin/app/javascript/.../ai_assist_controller.js` | 改 | FR-004a/c |
| `pallastrade_admin/app/helpers/pallastrade/admin/ai_assist_helper.rb` | 改 | FR-004a/b（新增 `ai_assist_attributes` / `ai_assist_labels` / `catalog_health_ai_labels`） |
| `pallastrade_admin/app/views/.../_seo.html.erb` 等 **5** 个视图 | 改 | FR-004a/b |
| `backend/config/locales/admin_products_ai.zh-CN.yml` + `pallastrade_admin/config/locales/en.yml` | 改 | FR-004d（i18n 双向） |
| `backend/spec/services/pallastrade/ai/gateway_output_validation_spec.rb` | 新增 | AC-001..006、013、014、015 |
| `backend/spec/jobs/pallastrade/ai/execute_run_job_spec.rb` | 新增 | AC-007、008、017 |
| `backend/spec/services/pallastrade/ai/providers/normalize_error_spec.rb` | 新增 | AC-009 |
| `backend/spec/requests/pallastrade/admin/ai_assist_wiring_spec.rb` | 新增 | AC-010、011、016（渲染断言） |
| `tests/ai-assist-wiring.test.mjs` | 新增 | AC-016（另三处视图 + JS 兜底的静态契约） |
| `harness.config.mjs` | 改 | 注册 `ai-output-validation-rspec` + 扩 `repo-guards-test` |
| `AGENTS.md` §6 | 改 | docImpact |

## 技术方案（初步）

- **校验判定**：把「有 schema 就必须有可用结构化输出」作为**前置判定**，而不是挂在 `.present?` 之后。
  取不到 `structured_output` 时抛/构造 `OutputValidationError`，由既有 rescue 路径落为 `:failure`。
- **错误码**：在**两个适配器**的 `normalize_error` 增加 `OutputValidationError → ai_output_invalid`（`retryable: false`）。
  ⚠️ 不用 `discard_on`，保持"确定性失败不重试"的既有语义。
- **异步路径**：`ExecuteRunJob#execute!` 在 `succeed!` **之前**做同一判定；失败走 `handle_error` → Run `failed`，且**不创建** artifact。
- **后台**：`renderError` 在具体码标签缺失时回退到通用兜底标签；4 个视图提供兜底 + 3 个新码文案。
- **验证**：容器内 RSpec 覆盖 AC-001..AC-011/013..015；node 守卫覆盖 AC-012（契约守卫，如实标注）。

## 风险点

| 风险 | 等级 | 缓解 / 回滚 |
|---|---|---|
| 误伤"合法但宽松"的输出 | 中 | 仅在**缺失/非 Hash**时判失败；schema 严格性沿用既有语义，不新增 |
| 把静默成功换成静默空白 | 中 | 同批修 FR-004（AC-010/011/012 锁住） |
| 既有 AI 规格回归 | 中 | AC-005/008 显式回归断言；跑 AI 域整套 |
| i18n 双向键集失衡 | 低 | 新增键同时补 en + zh-CN，并跑 `admin-i18n-rspec` |

**回滚难度**：低 —— 纯逻辑 + 视图/文案，无 migration，`git revert` 即可。

## 决策节点

> ⏸️ 用户已于 2026-09-18 明确确认「确认实施」（含 FR-004）。实施期间如发现方案需偏离 PRD，先回报再改。
