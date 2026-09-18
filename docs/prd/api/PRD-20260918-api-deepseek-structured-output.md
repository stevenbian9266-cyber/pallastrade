# PRD-20260918-api-deepseek-structured-output

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-09-18 |
| 来源 | `实施`（承接「修复：DeepSeek 适配器结构化输出 400 与 test_connection 误导」方案） |
| 分类 | api（自动判定，关键词命中 `schema`；语义上为「AI 供应商 API 适配」） |
| 关联 Skill | `pallastrade-testing`、`pallastrade-deployment`（仓库无 `pallastrade-ai` Skill，见 §9） |
| 关联 REQ | REQ-20260918-deepseek-adapter-structured-output.md |
| 关联 PRD | N/A（`harness prd new` 查重未命中相似 PRD） |
| 需求类型 | Bug 修复 |

## 1. 背景与目标

- **需求原文**：`实施`
- **背景**：dev 环境（`dev.pallastrade.cn`）后台 AI Tools 配置了 DeepSeek 后，四个商品 AI 能力（描述生成 / SEO / 翻译 / Catalog Health 修复建议）**全部无法产出**，Run 一律失败：
  `ai_provider_unavailable` / `the server responded with status 400 for POST https://api.deepseek.com/chat/completions`。
  2026-09-18 的诊断（`harness/reviews/REVIEW-20260918-dev-ai-tools-deepseek-diagnosis.md`）用真实 API 对照矩阵定位出**适配器层**根因，
  并用代码走查发现第二条同源缺陷。本 PRD 收敛该修复。
- **目标**：
  1. 打通 DeepSeek 的结构化输出链路，使四个商品 AI 能力可真实产出（不再 400）。
  2. 消除适配器与 OpenAI 适配器的**行为分歧**（系统指令被静默丢弃）。
  3. 让「测试连接」在 provider 5xx / 网络不可达时**返回结构化失败**而不是抛异常。
  4. 修正目录中**不存在的模型 ID**，并让部署模板登记 AI 总开关与加密密钥，避免新环境静默不可用。
- **成功指标**：
  - 适配器产出的请求体在真实 DeepSeek API 上返回 **HTTP 200 + 合法 JSON**（现状：100% HTTP 400）。
  - 四个商品 AI 能力在 dev 上端到端跑通 ≥1 个真实 Run（`status=success`，`artifacts ≥ 1`）。
  - 新增/更新规格全绿；`deepseek-v4-flash` 在仓库内 0 处残留。

### 1.1 已确认根因（实测证据，非推断）

| # | 缺陷 | 证据 | 严重度 |
|---|---|---|---|
| D1 | `providers/deep_seek.rb#build_request_body` 在 `request.response_schema` 存在时发送 `response_format: {type: 'json_schema', json_schema: …}`，而 DeepSeek Chat Completions **不支持该类型** | 真实 API 对照：纯文本 → 200；`json_object`（提示不含 "json"）→ 400 `Prompt must contain the word 'json'…`；**`json_schema` → 400 `This response_format type is unavailable now`**；`json_object` + 提示含 "json" → 200 且返回合法 JSON | **阻断级** |
| D2 | `build_request_body` 只发送 `messages`，**完全丢弃 `request.system_instructions`**（OpenAI 的 chat-completions 路径会把它注入为 `role: 'system'` 消息） | 代码对比：`open_ai.rb#generate_via_chat_completions` 有注入；`deep_seek.rb#build_request_body` 无 | **阻断级（正确性）** |
| D3 | `test_connection` 的 `status` **硬编码 `'verified'`**；且 5xx / 网络失败**未 rescue** → 异常逃逸，违反 `Base#test_connection` 的 `@return [Hash]` 契约 | `base.rb` 的 `@return` 契约 vs `deep_seek.rb` 的 rescue 分支缺 `Faraday::ServerError` / `ConnectionFailed` | 中（健壮性） |
| D4 | 目录预置 `provider_model_id: 'deepseek-v4-flash'`，**DeepSeek 侧不存在该 ID** | 真实 `GET /models` 只返回 `deepseek-flash` 与 `deepseek-v4-pro` | 中（误导） |
| D5 | `deploy/.env.dev.example` 与 `backend/.env.example` **均未登记 `PALLASTRADE_AI_ENABLED`**（系统总开关，默认 `false`）；`deploy/.env.dev.example` 亦未登记已在使用中的 3 个 `ACTIVE_RECORD_ENCRYPTION_*` | grep 全仓 0 命中于两个模板；`configuration.rb#system_enabled?` 默认 false | 中（新环境静默不可用） |
| **D6** | **目录数据双份，且 `catalogs/deep_seek.rb::MODELS` 是死数据** —— `ProvisionModels` 读的是 provider registry 的内联 `recommended_models`，`catalogs/*::MODELS` 全仓**无任何读取点**（只用了 `SUPPORTED_PARAMETERS`） | `grep 'MODELS\|catalog_class'`：`provider_registry.rb` 只存 `catalog_class` 字符串，从不调用；`provision_models.rb:29/33` 用的是 `entry.recommended_models` | **高（陷阱）** |

> **更正说明（诚实标注）**：诊断初稿称「密钥无效也会显示 Connection verified」。经复核 `base.rb#build_connection` 启用了 `conn.response :raise_error`，
> 401 会抛 `Faraday::UnauthorizedError` 并被既有 rescue 捕获为 `invalid_credentials` —— 因此**该指控不成立**。
> D3 的真实问题收敛为：(a) `status` 硬编码属不可达死代码/契约不实；(b) 5xx 与网络失败**未按契约返回 Hash**。

## 2. 用户故事 / 场景

- 作为**店铺运营**，我希望在商品编辑页点「Generate」就能拿到 AI 草稿，以便我只需审阅与微调，而不是对着 400 报错无计可施。
- 作为**店铺管理员**，我希望「测试连接」按钮的结果与真实生成结果一致，以便我能用它排障。
- 作为**运维/新环境搭建者**，我希望部署模板列全 AI 与加密所需变量，以便新环境不会静默地「AI 永远不可用」。

**场景**

| 类型 | 场景 |
|---|---|
| 正常流 | 运营在商品页点 Generate → 适配器发 `json_object` + 系统指令 → DeepSeek 返回 JSON → 网关校验 output schema → 前端预览草稿 |
| 边界 | 能力未声明 output schema（无 `response_schema`）→ 不发 `response_format`，也不注入 schema 指令，保持纯文本路径 |
| 边界 | `system_instructions` 为空 → 不插入空的 system 消息（避免污染 messages） |
| 边界 | 提示未含字面 "json" 的能力 → 由适配器注入的指令保证 "json" 出现（满足 DeepSeek 前置条件） |
| 边界 | 能力通过 `system_instructions` 表达领域约束（如「不得编造规格」）→ 该约束必须真正到达模型 |
| 异常 | DeepSeek 返回 5xx → `test_connection` 返回 `{success:false, status:'error'}`，不抛异常 |
| 异常 | 网络/DNS 不可达 → 同上，返回结构化失败 |
| 异常 | 凭据无效（401）→ 仍返回 `invalid_credentials`（不回归） |
| 异常 | 模型 ID 不存在 → 修正目录后不再出现该 400 |

## 3. 功能需求（FR）

- **FR-001**：`PallasTrade::AI::Providers::DeepSeek#build_request_body` 在 `request.response_schema` 存在时，改为发送
  `response_format: { type: 'json_object' }`（**不得**再发送 `json_schema`），并在消息中注入系统级指令，
  该指令必须包含字面词 `json` 且包含目标 schema 的 JSON 表示（DeepSeek 的 `json_object` 前置条件 + 字段可被模型看到）。
- **FR-002**：同一方法必须把 `request.system_instructions` 作为 `role: 'system'` 消息注入到 messages 首位
  （与 `providers/open_ai.rb#generate_via_chat_completions` 对齐）；为空时不得注入空 system 消息。
- **FR-003**：`#test_connection` 的 `status` 必须由响应派生（`response.success? ? 'verified' : 'error'`），不得硬编码；
  并补齐 `Faraday::ServerError` 与 `Faraday::ConnectionFailed` 的 rescue，返回 `{success:false, status:'error', error:<非空>, latency_ms:nil}`。
- **FR-004**：DeepSeek Flash 的 `provider_model_id` 由 `deepseek-v4-flash` 改为 `deepseek-flash`，**必须同时改两处**：
  `PallasTrade::AI::Catalogs::DeepSeek::MODELS`（可读目录）**与** `config/initializers/provider_registry.rb` 的 `recommended_models`（**实际供应来源**，见 D6）；
  `deepseek-v4-pro` 保持不变（实测有效）。两处必须由规格强制同步。
- **FR-005**：`deploy/.env.dev.example` 登记 `PALLASTRADE_AI_ENABLED` 与 3 个 `ACTIVE_RECORD_ENCRYPTION_*`（含说明）；
  `backend/.env.example` 登记 `PALLASTRADE_AI_ENABLED`。

> **明确不在本次范围（记录以免误判为遗漏）**：
> - `capabilities: %w[text structured_output]` 的声明**保留**。理由：改用 `json_object` 后「服务端保证 JSON 语法 + prompt/schema 约定形状」是真实的（弱）结构化输出；
>   且 `required_model_capabilities` 对四个能力均为 `%i[text]`（见 `config/initializers/catalog_capabilities.rb`），该声明不参与任何门禁。移除反而会削弱表达力。
> - `body[:thinking] = { type: reasoning_effort }` 未经验证，**不猜**、不改。
> - `DEPRECATED_MODEL_IDS` 含 `deepseek-chat` 但实测仍可用：仅记录，不改（改它会改变既有供应语义）。
> - 网关在 `structured_output` 为空时跳过 output schema 校验（可能导致「成功但空输出」）：属既有设计，本次仅记录为后续风险（§7）。> - **D6 的「死目录」不重构**：只让两处保持一致并由规格锁住。合并到单一数据源属重构，需另立任务（否则会把本次 bugfix 撑成跨文件重构）。
## 4. 非功能需求（NFR）

- **兼容性**：OpenAI 适配器**零改动**（其 `json_schema` 受支持）；改动仅限 DeepSeek 适配器 + DeepSeek 目录 + 两个 `.env.example`。
- **可测试性**：新增规格**不得打真实 API**（仓库既有约定），用 Faraday 测试替身断言请求体；真实 API 验证在 dev 上另行执行并留证。
- **安全**：`.env.example` 只放**空值/示例值**与说明，**绝不写入真实密钥**（AGENTS.md §8）。
- **可维护性**：不改方法签名、不改 `Request`/`Response` 结构、不新增依赖；保持 Ruby 风格与既有注释风格一致。
- **可观测性**：`test_connection` 的失败必须带非空 `error`，便于后台 flash 展示。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 可验证判定条件 |
|---|---|---|
| AC-001 | FR-001 | 有 `response_schema` 时，请求体 `response_format == {type: 'json_object'}`，且**不含** `json_schema` 键 |
| AC-002 | FR-001 | 有 `response_schema` 时，注入的指令文本同时包含字面词 `json` 与 schema 的属性名（如 `meta_title`） |
| AC-003 | FR-001 | **无** `response_schema` 时，请求体**不含** `response_format`（纯文本路径不回归） |
| AC-004 | FR-002 | `system_instructions` 存在时，messages[0] 为 `{role: 'system', content: <原指令>}`，且原 user 消息顺序与内容不变 |
| AC-005 | FR-002 | `system_instructions` 为 nil 时，messages 中**不存在** `role: 'system'` 的条目 |
| AC-006 | FR-003 | 2xx 响应 → `status == 'verified'`、`success == true`（`status` 由响应派生） |
| AC-007 | FR-003 | `Faraday::ServerError` → 不抛异常，返回 `success:false, status:'error'`，`error` 非空 |
| AC-008 | FR-003 | `Faraday::ConnectionFailed` → 不抛异常，返回 `success:false, status:'error'`，`error` 非空 |
| AC-009 | FR-003 | `Faraday::UnauthorizedError` → `status == 'invalid_credentials'`（不回归） |
| AC-010 | FR-004 | `MODELS` 中 Flash 的 `provider_model_id == 'deepseek-flash'`；Pro 仍为 `deepseek-v4-pro` |
| AC-011 | FR-004 | 供应流程（`ProvisionModels`）为 DeepSeek provider 产出 `deepseek-flash`（既有规格同步更新后仍绿） |
| AC-012 | FR-005 | `deploy/.env.dev.example` 与 `backend/.env.example` 均含 `PALLASTRADE_AI_ENABLED`；`deploy/.env.dev.example` 含 3 个 `ACTIVE_RECORD_ENCRYPTION_*` |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `deep_seek\|DeepSeek\|response_format\|system_instructions\|json_schema` | `controllers/pallastrade/admin/ai_controller.rb`（DeepSeek 供应商预置/总览） | ❌ 无适配器或请求体逻辑 |
| Core | `pallastrade_gems/pallastrade_core/app/` | 同上 | （0 命中） | ❌ 核心层不含 AI 适配器 |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | （0 命中）；AI 管理端点实为 `pallastrade_ai` 自带 `api/v3/admin/ai/**` | ❌ |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `deep_seek\|test_connection\|ai_provider` | 命中均为**支付渠道** `test_connection` 与商品表单 `ai_assist` 文案 | ❌ 与本需求无关 |
| Storefront | `storefront/src/` | `deep_seek\|DeepSeek\|response_format\|ai_provider` | （0 命中） | ❌ 前台不消费 AI 供应商 |
| Platform | `platform/packages/` | `deep_seek\|DeepSeek\|response_format` | （0 命中） | ❌ SDK/Dashboard 无 AI 供应商逻辑 |

**结论**：AI 供应商适配器与目录的**唯一实现**位于 `backend/pallastrade_gems/pallastrade_ai/`（本仓库自有 gem，可直接改）。
其他 5 层均无重复实现，**无需 Decorator / 无需新建文件替代既有实现** → 修复应**改既有文件**，符合 R0「能改已有却新建 = 违规」。
新增文件仅限**规格**与本文档（RSpec 规格属测试资产，非实现重复）。

## 7. 技术影响

- **涉及组件**（最终落地清单）：
  - `backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/providers/deep_seek.rb`（FR-001/002/003）
  - `backend/pallastrade_gems/pallastrade_ai/app/services/pallastrade/ai/catalogs/deep_seek.rb`（FR-004，可读目录）
  - `backend/pallastrade_gems/pallastrade_ai/config/initializers/provider_registry.rb`（FR-004，**实际供应来源**）
  - `deploy/.env.dev.example`、`backend/.env.example`（FR-005）
  - 规格新增：`backend/spec/services/pallastrade/ai/providers/deep_seek_spec.rb`（AC-001..AC-009）、
    `backend/spec/services/pallastrade/ai/catalogs/deep_seek_spec.rb`（AC-010，含两处来源同步）、
    **`tests/ai-env-template.test.mjs`**（AC-012，仓库级 node:test）
  - 规格更新：`backend/spec/services/pallastrade/ai/provision_models_spec.rb`、`backend/spec/requests/pallastrade/admin/ai_models_spec.rb`（模型 ID）
  - 验证器注册：`harness.config.mjs` 新增 `ai-provider-rspec`，并把 AI 环境模板守卫并入 `repo-guards-test`
  - 知识同步：`AGENTS.md` §6（新增「AI 供应商适配器 / 模型目录」行 + 更新 `repo-guards-test` 行描述）
- **AC-012 为何不写成 RSpec**：Rails 容器只绑定 `backend/`，`Rails.root.join('..')` 在容器内解析为 `/`，
  `deploy/.env.dev.example` 不可达（实测 `Errno::ENOENT - /deploy/.env.dev.example`）。
  仓库根文件契约断言必须跑在仓库根 → 改用 node:test；本地 node 可用，**不用 Ruby 环境**。
- **数据库**：无 migration，无 schema 变更。
- **接口**：**无** controller/routes/serializer/OpenAPI 契约变更（`test_connection` 的响应字段名与类型不变，仅取值更诚实）
  → §9 API 文档项判定为「已评估，无需更新」。
- **影响面**（`harness affected`）：见 REQ 记录。
- **运行期影响**：DeepSeek 适配器行为改变 → 需在 dev 用真实 API 复验四个能力（见 §8 + §10 证据）。

### 7.1 风险与缓解

| 风险 | 缓解 |
|---|---|
| 改用 `json_object` 后模型仍可能返回非 JSON（服务端只保证语法，不保证字段） | 网关侧 output schema 校验仍在（`validate_output!`）；本次**不改**该逻辑，仅在 §7.2 记录缺口 |
| 注入 schema 指令会增大 prompt token 消耗 | schema 体积极小（1–3 个字段）；成本影响可忽略 |
| `deepseek-flash` 在 DeepSeek 侧改名 | 该 ID 来自实测 `GET /models`；若未来变更，属外部 API 演进，需另立任务 |
| dev 上已有 `deepseek-v4-flash` 旧行（已由人工改为 `deepseek-flash`） | 供应流程按 `provider_model_id` 匹配；新 ID 命中既有行，不产生重复 |

### 7.2 后续风险（本次不修，仅登记）

- 网关 `execute_provider_call` 仅在 `response.structured_output.present?` 时校验 output schema；
  若模型返回非 JSON 文本，将**成功返回空输出**（`ProductCopy#structured_output` 回退 `{}`）。
  建议后续任务：能力声明 output schema 却拿不到结构化输出时，应判失败而非静默成功。

## 8. 测试计划

| AC | 测试文件 | 断言位置 |
|---|---|---|
| AC-001 / AC-003 | `backend/spec/services/pallastrade/ai/providers/deep_seek_spec.rb` | `#build_request_body` via `#generate` 的请求体 |
| AC-002 | 同上 | 注入的 system 指令文本 |
| AC-004 / AC-005 | 同上 | `messages` 结构 |
| AC-006 / AC-007 / AC-008 / AC-009 | 同上 | `#test_connection` |
| AC-010 | `backend/spec/services/pallastrade/ai/catalogs/deep_seek_spec.rb` | `MODELS` 常量 |
| AC-012 | `tests/ai-env-template.test.mjs`（node:test，AI-ENV-01..04） | 读取两个 `.env.example` 做契约断言 |
| AC-011 | `backend/spec/services/pallastrade/ai/provision_models_spec.rb`（更新）+ `backend/spec/requests/pallastrade/admin/ai_models_spec.rb`（更新） | 既有断言改为 `deepseek-flash` |

- **规格约定**（依 `pallastrade-testing` Skill）：RSpec + Factory Bot；`build` 优于 `create`；**绝不打真实 API**（Faraday 替身）；
  注意 CI 不注入 `PALLASTRADE_AI_ENABLED` 与 `ACTIVE_RECORD_ENCRYPTION_*`（本批规格只测适配器层，不触发可用性闸门，故不受影响）。
- **真实 API 验证**：dev 容器内跑四个能力的真实调用，留 Run/artifact 证据（不写入规格）。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：**无需更新** —— 无 controller/routes/serializer/OpenAPI 契约变更（`test_connection` 响应字段名与类型不变）
- [x] Skill 文档：**无需更新** —— `doc-impact` 规则未匹配任何变更路径（改动位于 `pallastrade_ai` gem、`deploy/`、`backend/.env.example`、`tests/`）；
      仓库**不存在** `pallastrade-ai` Skill，本需求不改动其他 Skill 的既有描述
- [x] **`AGENTS.md` §6 已同步** —— 改 `harness.config.mjs`（注册 `ai-provider-rspec` / 扩 `repo-guards-test`）命中 docImpact 规则，
      已新增「AI 供应商适配器 / 模型目录」行并更新仓库级守卫行描述
- [x] README / 样式规范 / 技术规范：**无需更新**（非架构/选型变更）
- [x] 反模式库 / 任务规则 / 场景库：**无需更新**（未新增反模式，未改任务规则）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

> 注：D5 的教训（新环境缺 `PALLASTRADE_AI_ENABLED` 导致 AI 静默不可用）已由 FR-005 在**模板层**消除；
> 是否需要在 `pallastrade-deployment` Skill 的环境变量表中补一条，留待收尾时按 `sync-check` 逐项判定。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-18 | 0.1 | 初稿：由 dev DeepSeek 实测诊断（D1–D5）收敛为 5 条 FR / 12 条 AC | AI |
| 2026-09-18 | 0.2 | 更正 D3 表述（`raise_error` 中间件使 401 已被正确捕获），并登记 §7.2 后续风险 | AI |
| 2026-09-18 | 0.3 | 实施期发现 D6（`catalogs/*::MODELS` 是死数据，真正供应源为 provider registry）→ FR-004 改为两处同改并由规格锁住；AC-012 从 RSpec 改为仓库级 node:test（容器内仓库根不可达）；补充验证器注册与 AGENTS.md §6 同步 | AI |
