# PRD-20260918-admin-ai-output-validation

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-09-18 |
| 来源 | `实施这项风险优化`（承接 `PRD-20260918-api-deepseek-structured-output` §7.2 残留风险） |
| 分类 | admin（自动判定；改动面跨 `pallastrade_ai` 网关与 `pallastrade_admin` 后台） |
| 关联 Skill | `pallastrade-customization`（已读，决策树判定）、`pallastrade-admin`（已读）、`pallastrade-testing`（已读）、`harness-prd`（已读） |
| 关联 REQ | REQ-20260918-ai-output-validation.md（已建） |
| 关联 PRD | PRD-20260918-api-deepseek-structured-output（同域前序；非重复需求，故新建） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **需求原文**：`实施这项风险优化` —— 即前序 PRD §7.2 登记的残留风险：
  「网关只在 `response.structured_output.present?` 时校验 output schema —— 若模型返回非 JSON，会**静默成功并返回空输出**」。
- **背景**：2026-09-18 修完 DeepSeek 适配器后，四个商品 AI 能力已能真实产出。但**输出侧的质量门是漏的**：
  网关只在"已经拿到结构化输出"时才校验 schema，等于**只校验已经成功的情况**。当模型返回自由文本（真实且常见，尤其在 prompt 未被遵循时），
  网关判 `success`、Run 记 `succeeded`，而能力层 `structured_output(result)` 回退为 `{}` ——
  **商家看到"生成成功"，但预览区是空的，且没有任何错误提示**。这类"成功但无内容"比明确的失败更难排查。
- **目标**：
  1. 声明了 output schema 的能力，拿不到可用结构化输出时**必须判失败**，不得静默成功（同步 + 异步两条路径一致）。
  2. 输出类失败必须报**真实错误码**（`ai_output_invalid`），不得借道 `ai_provider_unavailable` 误导排障方向。
  3. 商家在后台必须**看到失败说明**（当前未映射的错误码会渲染成空白状态）。
- **成功指标**：
  - 模型返回非 JSON 时，四个商品 AI 能力的 `status` 为失败且 `error_code='ai_output_invalid'`（现状：`success` + 空内容）。
  - 后台 AI 助手状态区对**任何**错误码都显示非空文案（现状：未映射码 → 空白）。
  - 相关规格全绿；既有成功路径零回归。

### 1.1 已确认根因（代码走查，非推断）

| # | 缺陷 | 位置与证据 | 严重度 |
|---|---|---|---|
| **D1** | 输出校验被 `structured_output.present?` 短路 → 无结构化输出时**根本不校验**，直接 `success` | `ai/gateway.rb#execute_provider_call`：`if response.structured_output.present? && @capability_entry&.output_schema_class` | **高（静默错误）** |
| **D2** | 异步路径**完全不校验** output schema，且仅在有结构化输出时写 artifact | `ai/execute_run_job.rb#execute!`：先 `succeed!`，再 `if response.structured_output.present?` 写 artifact | **高（同源）** |
| **D3** | `OutputValidationError` 落进 `normalize_error` 的 `else` → 报 `ai_provider_unavailable`（把输出问题说成供应商故障） | `providers/deep_seek.rb` / `providers/open_ai.rb` 的 `case` 无 `OutputValidationError` 分支 | 中（误导） |
| **D4**（实施期重新定性，**比初稿严重得多**） | **五处 AI 助手容器从未接上 Stimulus**：属性哈希直接交给 `tag.attributes`，键名没有 `data-` 前缀 → 渲染成 `controller="ai-assist"` / `ai_assist_endpoint_value="…"` 这类普通属性。`data-controller` 缺失 ⇒ 控制器从未挂载 ⇒ `data-action="click->ai-assist#generate"` 永不派发（**按钮点了没反应**）；`data-ai-assist-*-value` 同理缺失；文案键还要过 dataset 驼峰换算，`Error:<code>` 这类名字活不过去 ⇒ 状态区空白 | 探针实测 `tag.attributes('ai_assist_error:…' => 'X')` → `ai_assist_error:…="X"`（**不是 `data-*`**）；真实页面渲染 `[data-controller~="ai-assist"]` 为空（修复前接线规格 4/4 断言失败）；仓库其余 82 个视图均写 `data-controller="…"`，只有这 5 处例外 | **严重（整块功能在浏览器里是死的）** |
| **D4 旁证** | 已登记 11 个错误码，而 `ai_provider_unavailable` / `ai_output_invalid` / `ai_credentials_invalid` 均未登记 ⇒ 即便控制器挂上也不会显示 | 递归扫描 `pallastrade_admin/app/views/**/*.erb` 的 `ai_assist_error:*_label` 全集 | — |
| **D5** | 异步失败路径被监控上报反噬：`handle_error` 中 `defined?(Sentry)` 为真但 Sentry **未初始化**（无 `SENTRY_DSN`）时，`with_scope` 交出 `nil` → `scope.set_tags` 抛 `NoMethodError`。Run 虽已正确落 `failed`，但作业从此抛异常，Sidekiq 会重试一个确定性失败 | 真实规格实测：`NoMethodError: undefined method 'set_tags' for nil`（`execute_run_job.rb:130`，cause 为 `OutputValidationError`） | 中（失败被放大成重试） |

> **为什么 D1/D2 是"优化"而非"修复"**：它不产生 crash 也不产生 400，而是**把失败伪装成成功**。按前序 PRD §7.2 的约定单独立项。

### 1.2 端到端链路（本次改动点）

```
能力服务 (ProductCopy / ProductTranslation / HealthFixSuggestion)
  └─ 读 structured_output(result) → 取不到就回退 {} → 组装 Result(status: success, 字段为空)   ← 症状出口
       ▲
Gateway#call ── execute_provider_call ── validate_output!（← 被 .present? 短路，D1）        ← 改动点 ①
       ▲
       └─ 异常经 provider.normalize_error → else 分支 = ai_provider_unavailable（D3）        ← 改动点 ②
手工「AI 助手」按钮 ─→ POST /admin/ai/* ─→ render json { error: { code: <原样透传> } }
       └─ ai_assist_controller.js#renderError → dataset 查不到 → ''（D4）                     ← 改动点 ③
异步（ExecuteRunJob）── 先 succeed! 再条件写 artifact（D2）                                    ← 改动点 ④
```

## 2. 用户故事 / 场景

- 作为**店铺运营**，当 AI 没能返回可用内容时，我希望看到明确的失败原因，而不是"成功"加一个空预览框 —— 否则我会反复点击、以为是自己没操作对。
- 作为**排障者（我/工程）**，我希望 Run 的 `error_code` 能区分"供应商不可用"与"模型输出不合格"，因为两者的处置完全不同。
- 作为**店铺管理员**，我希望后台 AI 助手的状态区**永远不空**，即使遇到我配置之外的错误。

| 类型 | 场景 |
|---|---|
| 正常流 | 模型返回合规 JSON → 校验通过 → `success` + 内容（**不得回归**） |
| 边界 | 能力**未**声明 output schema（纯文本能力）→ 无结构化输出也必须成功（**不得误伤**） |
| 边界 | `structured_output` 是合法 JSON 但**字段不符合 schema** → 判失败（现状会失败，但错误码错） |
| 异常 | 模型返回自由文本（非 JSON）→ **判失败** + `ai_output_invalid`（现状：静默成功） |
| 异常 | 异步路径同一场景 → Run `failed` + **不写 artifact**（现状：`succeeded`） |
| 异常 | 未映射的错误码到达后台 → 显示通用兜底文案而非空白 |

## 3. 功能需求（FR）

- **FR-001**：能力声明了 output schema 时，若供应商响应**没有可用的结构化输出**（`structured_output` 为空/非 Hash），
  `Gateway#call` 必须判**失败**（`status: :failure`）并把 Run 置为 `failed`，**不得**返回 `status: :success`。
- **FR-002**：同一判定在**异步路径**（`ExecuteRunJob#execute!`）必须一致：Run `failed`，且**不得**创建 `structured_output` artifact。
- **FR-003**：输出类失败的错误码必须是 **`ai_output_invalid`**，覆盖两种情形（无可解析结构化输出 / 不符合 schema）；
  两个供应商适配器的 `normalize_error` 必须一致地把 `OutputValidationError` 映射为该码（现状：`ai_provider_unavailable`）。
- **FR-004**：后台「AI 助手」必须真正可用，且失败必然可见：
  (a) 五处容器一律经 `ai_assist_attributes` 接线 —— `data-controller="ai-assist"` + `data-ai-assist-*-value`（Stimulus 只认 `data-*`，裸属性名等于没接）；
  (b) 文案作为**单一 JSON 属性** `data-ai-assist-labels` 下发，键名与控制器查找名**逐字一致**（`Error:<code>`、`Entry:<key>`）
      —— 属性名会被小写化并折叠成 dataset 驼峰键，逐键下发无法保真；
  (c) 控制器在具体码无文案时回退到 `ErrorFallback`，**兜底永不为空**；
  (d) `ai_provider_unavailable` / `ai_output_invalid` / `ai_credentials_invalid` 必须有专门文案（en + zh-CN）。
- **FR-007**：异步失败路径不得被监控上报反噬 —— Sentry 未初始化时跳过上报；作业**不得因上报本身抛异常**（Run 记录才是事实来源）。
- **FR-005**：输出类失败必须**可排障**：失败的 Run 其 `error_message` 非空，且至少包含以下之一 —— 能力键、预期 schema 标识、供应商 `finish_reason`。
- **FR-006**（零副作用，约束性）：失败路径**不得**修改任何业务数据（商品、翻译、媒体等），只允许写 Run 及其错误字段。

## 4. 非功能需求（NFR）

- **兼容性**：成功路径行为**完全不变**；未声明 output schema 的能力行为**完全不变**；不新增依赖、不改方法签名。
- **可测试性**：网关/作业层用替身（不打真实 API）；UI 层以**服务端渲染契约**（request spec）+ **仓库级 node 守卫**（JS 契约）覆盖 ——
  因为 `backend/` **不存在 JS 测试设施**（无 `backend/package.json`、无任何 `*.test.js|*.spec.ts`）。
- **可维护性**：错误码集合应可枚举（避免"魔法字符串"散落）；已知码与兜底的关系应在 PRD/测试中明示。
- **i18n**：新增文案必须 en + zh-CN 双语键齐备（仓库有 i18n 双向键集校验）。
- **可观测性**：`ai_output_invalid` 必须可从后台 Run 列表按 `error_code` 筛选到（该能力已存在）。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 可验证判定条件 |
|---|---|---|
| AC-001 | FR-001 | 能力声明 schema + provider 返回 `structured_output=nil` → Gateway `status == :failure` |
| AC-002 | FR-003 | 同场景 `error_code == 'ai_output_invalid'`（且 `!= 'ai_provider_unavailable'`） |
| AC-003 | FR-001 | 同场景 Run `status == 'failed'`（不再是 `succeeded`） |
| AC-004 | FR-001 | `structured_output` 为 Hash 但缺必填字段 → 同样 `:failure` + `ai_output_invalid` |
| AC-005 | FR-001 | `structured_output` 合法且符合 schema → `status == :success`（**不回归**） |
| AC-006 | FR-001 | 能力**未**声明 output schema → 无结构化输出仍 `:success`（**不误伤**） |
| AC-007 | FR-002 | `ExecuteRunJob` 同场景 → Run `failed` 且 artifact 数 **= 0** |
| AC-008 | FR-002 | `ExecuteRunJob` 正常场景 → Run `succeeded` 且 artifact 数 == 1（**不回归**） |
| AC-009 | FR-003 | 对 `OutputValidationError`，DeepSeek 与 OpenAI 两个适配器 `normalize_error` 均返回 `ai_output_invalid` |
| AC-010 | FR-004 | 4 个含 AI 助手的视图渲染后均含通用兜底标签属性（非空文案） |
| AC-011 | FR-004 | 视图渲染后含 `ai_output_invalid` / `ai_provider_unavailable` / `ai_credentials_invalid` 的专门标签 |
| AC-012 | FR-004 | `ai_assist_controller.js#renderError` 在具体码标签缺失时回退到通用标签（契约守卫） |
| AC-013 | FR-005 | 输出类失败的 Run `error_message` 非空且含能力键 |
| AC-014 | FR-006 | 输出类失败后商品未被修改（`updated_at` 不变、无翻译写入） |
| AC-015 | FR-001/002 | 四个 catalog 能力在 provider 返回非 JSON 时，能力层 `Result.status` 均为失败且 `error_code == 'ai_output_invalid'` |
| AC-016 | FR-004 | 助手容器接线：`data-controller="ai-assist"` + `data-ai-assist-*-value` + `data-ai-assist-labels`（JSON 含 `ErrorFallback`、`Idle`/`Generating`/`Review`/`Accepted`）——商品页与 `catalog_health` 走**渲染**断言，另三处视图走仓库级静态契约 |
| AC-017 | FR-007 | Sentry 未初始化时 `ExecuteRunJob` 在记录失败后**不抛异常**（`perform_now` 正常返回） |

### 5.1 明确的范围边界

- **不含**：让模型"更听话"（prompt 工程）、自动重试、把自由文本兜底当作有效输出。
- **不含**：重构 `structured_output` 的解析逻辑（适配器侧 `JSON.parse` 兜底保持不变）。
- **不含**：为后台引入 JS 测试基础设施（另立任务；本次以契约守卫覆盖并如实标注）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `structured_output\|validate_output\|output_schema\|ai_output_invalid` | （0 命中）；但 `app/controllers/pallastrade/admin/ai_controller.rb` 是 4 个 AI 助手段点的**宿主**（295/359 行原样透传 `error.code`） | ❌ 无校验逻辑，**是改动相关方** |
| Core | `pallastrade_gems/pallastrade_core/app/` | 同上 | （0 命中） | ❌ |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | （0 命中） | ❌ |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `structured_output\|output_schema\|renderError\|ai_assist_error` | `javascript/.../ai_assist_controller.js`（D4 所在）+ 4 个视图的 `ai_assist_error:*_label` 映射 | ✅ **需改**（FR-004） |
| Storefront | `storefront/src/` | `structured_output\|ai_output_invalid\|ai_assist` | （0 命中） | ❌ 前台不消费 AI |
| Platform | `platform/packages/` | `structured_output\|ai_output_invalid` | （0 命中） | ❌ |

**结论**：校验缺口在 `pallastrade_ai`（**唯一实现**，无重复），展示缺口在 `pallastrade_admin`。
两侧都是本仓库自有 gem，**直接改既有文件**（不新建实现，符合 R0）；本次新增文件仅限**规格**与文档。

## 7. 技术影响

- **涉及组件**：
  - `backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/gateway.rb`（FR-001/003/005）
  - `backend/pallastrade_gems/pallastrade_ai/app/jobs/pallastrade/ai/execute_run_job.rb`（FR-002）
  - `backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/providers/{deep_seek,open_ai}.rb`（FR-003）
  - `backend/pallastrade_gems/pallastrade_admin/app/javascript/pallastrade/admin/controllers/ai_assist_controller.js`（FR-004a）
  - 4 个视图：`admin/shared/_seo.html.erb`、`admin/products/form/_base.html.erb`、`admin/translations/products/_form.html.erb`、`admin/catalog_health/{index,_product_card}.html.erb`（FR-004b/c）
  - `backend/config/locales/admin_products_ai.zh-CN.yml` + `pallastrade_admin/config/locales/en.yml`（FR-004c，i18n 双向）
- **数据库**：无 migration。
- **接口**：**无** OpenAPI/契约变更（响应字段名与类型不变，仅 `error.code` 的**取值域**新增 `ai_output_invalid`）→ §9 API 文档项预判「已评估，无需更新」。
- **风险与缓解**：

| 风险 | 缓解 |
|---|---|
| 误伤"合法但宽松"的输出（如模型多返回一个字段） | 只在**缺失/非 Hash**时判失败；schema 校验沿用既有 `OutputSchema.valid?` 语义，不新增严格性 |
| 把失败变成"空白提示"（比静默成功更糟） | 同批修 FR-004，使失败必然可见；AC-010/011/012 锁住 |
| 异步任务重试语义 | `OutputValidationError` 属确定性失败；不加入 `retry_on`（沿用既有 `discard_on` 之外的默认 = 不重试） |
| 影响既有 AI 规格 | 成功路径 AC-005/008 明确回归断言 |

**回滚难度**：低 —— 纯逻辑 + 视图/文案，`git revert` 即可。

## 8. 测试计划

| AC | 测试文件 | 断言方式 |
|---|---|---|
| AC-001..AC-006、AC-013、AC-014、AC-015 | `backend/spec/services/pallastrade/ai/gateway_output_validation_spec.rb`（新增） | 替身 provider + 真实 Gateway/Run |
| AC-007、AC-008 | `backend/spec/jobs/pallastrade/ai/execute_run_job_spec.rb`（新增；若已存在同名则更新） | 替身 adapter |
| AC-009 | `backend/spec/services/pallastrade/ai/providers/normalize_error_spec.rb`（新增） | 纯单元，两个适配器 |
| AC-010、AC-011 | `backend/spec/requests/pallastrade/admin/ai_assist_error_labels_spec.rb`（新增） | 渲染 4 个页面，解析 `data-ai-assist-error:*` 属性 |
| AC-012 | `tests/ai-assist-error-fallback.test.mjs`（新增，仓库级 node 守卫） | 静态契约断言（**明确标注为契约守卫，非行为测试**） |

- 新增验证器：`ai-output-validation-rspec`（网关 + 作业 + 错误码三文件），并注册到 `harness.config.mjs`；
  node 守卫追加进既有 `repo-guards-test`。
- **i18n 校验**：新增 locale 键必须过 `harness verify admin-i18n-rspec`（en ↔ zh-CN 双向键集相等）。
- 不做真实 API 调用（供应商行为已在前序任务验证）。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：预判**无需更新**（无契约变更），收尾以 `doc-impact` 实测为准
- [ ] Skill 文档：改动位于 `pallastrade_ai` / `pallastrade_admin` gem —— `doc-impact` 规则按实测判定；
      若触及 `ai/skills/**` 则同步 `harness/scenarios/scenarios.json`
- [ ] `harness.config.mjs` 变更 → 至少同步 `AGENTS.md` §6（新增验证器行）
- [ ] 反模式库 / 任务规则：预判无需更新
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-18 | 0.1 | 初稿：由前序 PRD §7.2 残留风险立项；实施前走查新增 D2/D3/D4 三项同源缺陷 | AI |
| 2026-09-18 | 0.2 | **实施期重大修订（用户已同意扩围）**：D4 由「某些码显示空白」重新定性为「**五处容器从未接上 Stimulus**」——属性缺 `data-` 前缀，按钮点了没反应；新增 D5（异步失败被 Sentry 未初始化反噬）；FR-004 扩为四款（接线/文案下发/兜底/新码文案），新增 FR-007 与 AC-016/017 | AI |
