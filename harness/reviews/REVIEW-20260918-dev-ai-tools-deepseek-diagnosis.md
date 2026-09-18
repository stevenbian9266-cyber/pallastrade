# dev 后台 AI Tools（DeepSeek）测试与场景应用 — 诊断记录

| 项 | 值 |
|---|---|
| 日期 | 2026-09-18 |
| 环境 | dev（`dev.pallastrade.cn`） |
| 任务 | `TASK-20260918014845-53ac1356` · gate `GATE-2026-09-18T01-48-57`（test / quick） |
| 结论 | **AI 链路打通但无法产出**：定位到 **2 个真实缺陷**（含 1 个阻断级代码缺陷），未修改产品代码 |

---

## 一、起点：用户已配置的部分

| 项 | 状态 |
|---|---|
| Provider | ✅ DeepSeek（id 1，active，`base_url=https://api.deepseek.com`） |
| API Key | ✅ 已加密存储（35 字符，hint `sk-e9••••……68cb`） |
| 模型 | ✅ DeepSeek V4 Flash（id 1，active） |
| 连接测试 | ✅ `{success: true, status: "verified", latency_ms: 104}` |

---

## 二、发现：4 层配置只配了 1 层

AI 可用性由 `PallasTrade::AI::AvailabilityService` 的 **8 道闸门**串行把关。用户只完成了「Provider + Key + Model」，另外 **3 层缺失**，且**每一层缺失都只表现为同一个笼统的 `ai_disabled`**，没有任何提示指向缺哪一层。

| 闸门 | 检查内容 | 配置前 |
|---|---|---|
| Gate 0 | 能力已注册 | ✅ |
| **Gate 1** | **全局 kill switch `ENV['PALLASTRADE_AI_ENABLED']`**（默认 **false**） | ❌ **缺失** |
| **Gate 2** | **store 级总开关 `PallasTrade::AI::Setting#active`** | ❌ **表为空** |
| **Gate 3** | **能力→模型绑定 `CapabilitySetting`** | ❌ **0 条** |
| Gate 4–7 | primary_model / provider active / model active / 凭据已配 | ✅ |

### 已补齐（dev 侧）
1. **Gate 2**：创建 `AI::Setting(store: shop, active: true, default_model: DeepSeek V4 Flash)`
2. **Gate 3**：为 4 个 catalog 能力分别建 `CapabilitySetting` 绑定到 DeepSeek V4 Flash
3. **Gate 1**：在服务器 `deploy/.env.dev` 追加 `PALLASTRADE_AI_ENABLED=true`（该文件被 `deploy/.gitignore` 忽略，属服务器侧配置），并 `docker compose up -d --no-deps --no-build web worker` 重建 → 容器内已读到 `true`，服务 200/200

> 补齐后 8 道闸门对 4 个能力全部 `available=true`。

---

## 三、缺陷 1（**阻断级，代码缺陷**）：DeepSeek 适配器发送了 DeepSeek 不支持的 `response_format`

闸门全通后，真实调用仍返回 `ai_provider_unavailable`，Run 里记录：

```
the server responded with status 400 for POST https://api.deepseek.com/chat/completions
```

### 定位过程

`pallastrade_ai/app/services/pallastrade/ai/providers/deep_seek.rb#build_request_body`：

```ruby
if request.response_schema
  body[:response_format] = {
    type: 'json_schema',
    json_schema: request.response_schema
  }
end
```

### 用真实 API 逐项排除

| 请求 | 结果 |
|---|---|
| A 纯文本（无 `response_format`） | **HTTP 200** ✅ |
| B `response_format = {type: 'json_object'}` | HTTP 400 `Prompt must contain the word 'json' in some form to use 'response_format' of type 'json_object'.` |
| **C `response_format = {type: 'json_schema', json_schema: {...}}`（**适配器实际发送的形状**）** | **HTTP 400 `This response_format type is unavailable now`** ← **命中** |
| E `json_object` + 提示内含 "json" | **HTTP 200**，返回合法 JSON ✅ |

**结论：DeepSeek 的 Chat Completions API 不支持 `response_format.type = 'json_schema'`**（当前仅支持 `json_object`）。

### 影响面

四个 catalog 能力（product_description / product_seo / product_translation / health_fix_suggestion）**都声明了 output schema**，因此都会带上 `response_format` → **接 DeepSeek 时 100% 必然 400，无一能成功**。

### 同源问题：能力目录过度声明

`catalogs/deep_seek.rb`：

```ruby
capabilities: %w[text structured_output]   # ← 两个模型都这么声明
```

但 DeepSeek 的 Chat Completions **不支持结构化输出**。这个过度声明使 `CapabilitySetting` 的 `primary_model_satisfies_capability` 校验通过，问题被推迟到运行期才以 400 暴露。

### 建议修法（供决策，本次未改代码）

1. **最小改动**：`deep_seek.rb#build_request_body` 不再发 `json_schema`；改为在 system/user prompt 里注入「只返回 JSON，字段为 …」并用 `response_format: {type: 'json_object'}`（DeepSeek 要求 prompt 含 "json"）。`parse_response` 已有 `JSON.parse(text)` 兜底，能直接消费。
2. **配套**：把 `catalogs/deep_seek.rb` 的 `structured_output` 能力声明去掉（或改为「prompt 约定式 JSON」），使模型能力与实际 API 一致。
3. 建议为「DeepSeek + 结构化输出」补一条真实回归（当前 spec 用桩，不会发现此问题）。

---

## 四、缺陷 2（**误导级**）：`test_connection` 的 `status` 是硬编码的

```ruby
def test_connection(integration)
  ...
  { success: response.success?, status: 'verified', latency_ms: latency_ms, error: nil }
```

`status` 恒为 `'verified'`（即使 `GET /models` 返回 401，只要不抛异常就会报「verified」，只是 `success: false` 被忽略）。后台 flash 文案是 `"Connection #{result[:status]} (latency: #{result[:latency_ms]}ms)"` → **即使凭据无效也会显示「Connection verified」**。

> 本次实测中它确实报 `verified`（因为 key 有效），但该硬编码使这个「测试连接」按钮**无法用于排障** —— 而后面的 `generate` 路径是另一套代码，两者结论可以完全不同（这正是本次的情形）。

---

## 五、顺带发现

1. **模型 ID 拼写错误（数据侧，已在 dev 修正）**：目录预置 `provider_model_id: 'deepseek-v4-flash'`，而 DeepSeek 实际只认 **`deepseek-flash`**（`GET /models` 返回 `deepseek-flash` / `deepseek-v4-pro`）。已把 dev 上该模型的 ID 改为 `deepseek-flash`。`deepseek-v4-pro` 是正确的，无需改。
2. **`DEPRECATED_MODEL_IDS = %w[deepseek-chat deepseek-reasoner]` 存疑**：实测 `deepseek-chat` 仍返回 **HTTP 200**（且被服务端解析为 `deepseek-flash`），并未失效。
3. **`deploy/.env.dev.example` 未登记 `PALLASTRADE_AI_ENABLED`**（也未登记已在使用中的 3 个 `ACTIVE_RECORD_ENCRYPTION_*`）→ 按模板新建环境会静默地「AI 永远不可用」。
4. **`backend/.env` 里有 `PALLASTRADE_AI_ENABLED=true`，且重复出现两次（第 22、25 行）**，但该文件被 gitignore、从未部署到服务器 → 本地以为开了，线上其实没开。
5. **DeepSeek V4 Flash 是推理型模型**：实测 `max_tokens` 过小时 `content` 为空、内容全在 `reasoning_content` 里。目录默认 `max_output_tokens: 8192` 尚可，但把该值调小会导致「调用成功却拿到空文本」——是个容易误判的坑。

---

## 六、本次在 dev 上做过的写入（供知悉）

| 对象 | 操作 |
|---|---|
| `pallastrade_ai_settings` | 新建 1 行（`store=shop`, `active=true`, `default_model=DeepSeek V4 Flash`） |
| `pallastrade_ai_capability_settings` | 新建 4 行（4 个 catalog 能力 → DeepSeek V4 Flash） |
| `pallastrade_ai_models` (id 1) | `provider_model_id`: `deepseek-v4-flash` → **`deepseek-flash`** |
| 服务器 `deploy/.env.dev` | 追加 `PALLASTRADE_AI_ENABLED=true`（已备份 `.env.dev.bak-ai-20260918095203`） |
| 容器 | `web` / `worker` 重建（`--no-deps --no-build`） |
| `pallastrade_ai_runs` | 8 条失败 Run（4 个能力 × 2 轮尝试），保留作审计 |

> **产品代码未改动**（`git status` 为空）。上表的 dev 配置是使 AI 可用的前提，予以保留。

---

## 七、结论

- 用户的 DeepSeek 配置**本身正确**（key 有效、模型可用、连通 104ms）。
- 但要让 AI 真正跑起来还需要：**全局开关 + store 总开关 + 能力绑定**三层（已补齐）。
- 补齐后暴露出**阻断级代码缺陷**：DeepSeek 适配器发送 `response_format.type='json_schema'`，而 DeepSeek 明确回 `This response_format type is unavailable now` → **四个商品 AI 能力接 DeepSeek 全部不可用**。
- 另有 1 个误导级缺陷（`test_connection` 硬编码 `verified`）+ 4 项顺带发现。

**建议单独立项 `修复：` 修掉缺陷 1 与 2**（缺陷 1 涉及 `pallastrade_ai` gem 的 provider 适配器与能力目录，属代码变更，需按 R8 走 PRD → gate → 验证 → 知识同步）。
