# REVIEW-20260918 — AI 输出校验缺口修复 + 后台 AI 助手接线修复

| 项 | 值 |
|---|---|
| 日期 | 2026-09-18 |
| 任务 | `TASK-20260918025044-fc936a9e` · gate `GATE-2026-09-18T02-50-53`（feature） |
| PRD | `docs/prd/admin/PRD-20260918-admin-ai-output-validation.md` |
| REQ | `harness/requirements/REQ-20260918-ai-output-validation.md` |
| 用户确认 | ✅ 两次：立项时「确认实施」；发现接线缺陷后「扩围：接线修复并入本次」 |
| 结论 | 四组缺陷全部修复并验证；**实施中把原 D4 重新定性为更严重的缺陷** |

---

## 一、起点与实施中的重大修订

原立项只针对前序 PRD §7.2 登记的**残留风险**：网关用 `structured_output.present?` 短路输出校验。
实施期间走查与实测把范围扩大了两处，均已回报用户并获批准：

| # | 缺陷 | 定性变化 |
|---|---|---|
| D1 | 网关只在「已拿到结构化输出」时才校验 → 模型答自由文本时判 `success`，能力层回退 `{}` | 立项时的原目标 |
| D2 | 异步路径 `ExecuteRunJob` **完全不校验**，且仅在有结构化输出时写 artifact | 立项时新增 |
| D3 | `OutputValidationError` 落进 `normalize_error` 的 `else` → 报 `ai_provider_unavailable` | 立项时新增 |
| **D4** | **五处 AI 助手容器从未接上 Stimulus**：属性哈希直接交给 `tag.attributes`，键名没有 `data-` 前缀 → 渲染成 `controller="ai-assist"` / `ai_assist_endpoint_value="…"` 这类普通属性 | **由「某些码显示空白」重新定性为「整块功能在浏览器里是死的」**（用户同意扩围） |
| **D5** | 异步失败路径被监控上报反噬：`defined?(Sentry)` 为真但未初始化时 `with_scope` 交出 `nil`，`scope.set_tags` 抛 `NoMethodError` | 实施期新增（写 AC-007 规格时暴露） |

### D4 的决定性证据（非推断）

| 手段 | 结果 |
|---|---|
| 独立探针跑 `tag.attributes('ai_assist_error:ai_disabled_label' => 'X')` | 渲染为 `ai_assist_error:ai_disabled_label="X"` —— **不是 `data-*` 属性**，`element.dataset` 取不到 |
| 真实页面渲染（修复前） | `[data-controller~="ai-assist"]` 在 `/admin/products/:id/edit` 与 `/admin/catalog_health` 上**均为空**；接线规格 4/4 断言失败 |
| 仓库惯例对照 | 其余 **82 个视图**都写 `data-controller="…"` 或 `data: { controller: … }`，只有这 5 处例外 |

**后果**：Stimulus 只认 `data-controller` ⇒ 控制器从未挂载 ⇒ `data-action="click->ai-assist#generate"` 永不派发（**按钮点了没反应**）；`data-ai-assist-*-value` 同理缺失；文案键还得经 dataset 驼峰换算，`Error:<code>` 这类名字活不过去 ⇒ 状态区空白。

> **为什么此前的验证没发现**：既有规格断言的是 `data-ai-assist-target="preview"` 与按钮 `disabled`，**从未断言 `data-controller`** —— 而启用 AI 的产品页那一行 `AIController` 的 spec 也只覆盖 HTTP 层。服务层通过、HTTP 层通过、浏览器里是死的。

## 二、交付内容（FR ↔ 落地）

| FR | 内容 | 落地位置 |
|---|---|---|
| FR-001 | 声明了 output schema 却拿不到可用结构化输出 → **判失败** | `ai/gateway.rb#validate_output!`（改为接收 response，先判「有没有」再判「合不合」） |
| FR-002 | 异步路径同一判定，且失败**不写 artifact** | `ai/execute_run_job.rb#validate_output!`（在 `succeed!` 之前） |
| FR-003 | 输出类失败统一报 `ai_output_invalid`；两个适配器一致 | `providers/{deep_seek,open_ai}.rb#normalize_error` 新增 `OutputValidationError` 分支（`retryable: false`） |
| FR-004 | 后台助手真正可用且失败可见 | 新增 `ai_assist_helper.rb#ai_assist_attributes / ai_assist_labels / catalog_health_ai_labels`；**5 个视图**改为走 helper（`data:` 前缀 + 单一 JSON 文案属性）；`ai_assist_controller.js` 改按 JSON 取名并保留 `ErrorFallback` 兜底 |
| FR-005 | 失败可排障 | `validate_output!` 的异常信息含能力键与 `finish_reason` |
| FR-006 | 失败路径零副作用 | 校验在写库之前抛错；规格断言商品属性不变 |
| FR-007 | 上报不得反噬 | `execute_run_job.rb#handle_error` 加 `Sentry.initialized?` 守卫；`output_error?` + 修饰符返回 |

**i18n**：`pallastrade.admin.products.ai.errors` 新增 5 键（`ai_provider_unavailable` / `ai_output_invalid` / `ai_credentials_invalid` / `ai_credentials_missing` / `ai_unavailable`），en 与 zh-CN **双向齐备**。

## 三、验证证据

| 层次 | 验证器 / 命令 | 结果 |
|---|---|---|
| 输出校验（网关 + 作业 + 适配器） | `harness verify ai-output-validation-rspec` | ✅ **19 examples, 0 failures**（AC-001..009、013..015、017） |
| 后台接线（真实页面渲染） | 同上（含 `ai_assist_wiring_spec.rb`） | ✅ `data-controller="ai-assist"` + `data-ai-assist-*-value` + 文案 JSON 齐备；`ErrorFallback` 非空；三个新码有文案 |
| 接线静态契约（另三处视图 + JS 兜底） | `harness verify repo-guards-test` → `tests/ai-assist-wiring.test.mjs` | ✅ **5/5**（AI-ASSIST-01..05） |
| AI 部署模板契约（前序任务） | `harness verify repo-guards-test` → `tests/ai-env-template.test.mjs` | ✅ **4/4** |
| 受影响 AI 请求规格（回归） | `spec/requests/admin/{products_ai_copilot,products_ai_translation,ai_assist_edited_source,ai_acceptances}` | ✅ **27 examples, 0 failures** |
| 代码风格 | `rubocop --except Layout/EndOfLine`（本次改动文件） | ✅ **0 新增违规**；剩余 2 处为基线（`execute_run_job.rb` 的两条既有 `&.` 链） |
| i18n 键集 | `harness verify admin-i18n-rspec` | 见收尾记录（新增键 en/zh-CN 同批） |

### 已知的本地环境噪音（与本改动无关，已单独证实）

本地 test 库存在**泄漏**：同一套规格**连跑第二遍**会因 `stores.code='pallastrade_1'` 唯一约束失败。
已用**未改动**的 `provision_models_spec` + `provision_providers_spec` 复现（PASS1 0 failures / PASS2 1 failure），
证明与本次改动无关；跑前 `db:test:purge && db:test:prepare` 即可（已写入仓库记忆）。

## 四、知识同步

- `harness.config.mjs`：注册 `ai-output-validation-rspec`；`repo-guards-test` 扩入 `tests/ai-assist-wiring.test.mjs`
- `AGENTS.md` §6：新增「AI 输出校验 / 后台 AI 助手接线」行，并更新 repo-guards 行描述
- 场景库：见收尾（本轮新增 GS-179 —— 后台接线契约）
- PRD 与 REQ：D4 重新定性、D5 新增、FR-004 扩写、FR-007 与 AC-016/017 回填

## 五、残留与后续建议

1. **`catalog_health` 页面的 AI 错误文案口径变化**：原先该页把所有 AI 错误码统一映射为同一句 `admin.catalog_health.ai.errors.default`，
   现在走共享文案表（按码给具体说明）。这是**有意的改进**（更可诊断），但属用户可见文案变化，记录在此。
2. **后台 JS 仍无测试设施**：`backend/` 无 `package.json`、无任何 `*.test.js|*.spec.ts`。
   本次以「服务端渲染契约 + 仓库级静态契约」覆盖，**明确标注为契约守卫而非行为测试**。
   若要真正覆盖 Stimulus 行为，需要为后台引入 JS 测试栈 —— 建议另立任务。
3. **`Entry:` 键大小写在旧代码里是错的**（视图写 `entry:`，控制器查 `Entry:`）——本次统一为控制器的 `Entry:`，属顺带修正。
