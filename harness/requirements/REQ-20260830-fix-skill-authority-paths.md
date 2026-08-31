# REQ-20260830-fix-skill-authority-paths.md

> 任务：优化：修复 SKILL 权威路径
> 任务 ID：TASK-20260830151121-f3306650
> 关联 PRD：PRD-20260830-other-修复-skill-权威路径

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | credential, serializer | 无相关文件 | ✅ 无冲突 |
| App — views/decorators | `backend/app/` | credential, serializer | 无相关文件 | ✅ 无冲突 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | credential, serializer, engine | 无相关文件 | ✅ 无冲突 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | credential, serializer, engine | 无相关文件 | ✅ 无冲突 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | serializer | 无 | ✅ 无冲突 |
| API Gem — serializers | `backend/pallastrade_gems/pallastrade_api/app/serializers/` | serializer | **145 个 serializer 文件** | ✅ 确认真实路径 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | credential, serializer | 无相关文件 | ✅ 无冲突 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | credential, serializer | 无相关文件 | ✅ 无冲突 |
| Storefront | `storefront/src/` | credential | 无相关文件 | ✅ 无冲突 |
| Platform | `platform/packages/` | credential | 无相关文件 | ✅ 无冲突 |

### 搜索结论

- **`pallastrade/api/app/serializers/**/*.rb`（旧路径）** → 真实位置在 API Gem 层 `backend/pallastrade_gems/pallastrade_api/app/serializers/`（145 个文件，已用 glob 验证匹配）。SKILL 文档需改为此真实路径。
- **`.pallastrade/credentials.json`** → 6 层均不存在。它是 `pallastrade-cli` 运行期生成的凭据文件（gitignored），本就不该入库。文档表述需明确"运行时生成、不入库"。
- **`lib/pallastrade_simple_sales/engine.rb`** → 6 层均不存在。它是 `pallastrade-extension` 生成器的模板产物结构。文档表述需标注"生成器模板/示例"。
- **`rules/base-standards.json`** → 项目内不存在。它由引擎随包分发（`node_modules/pallastrade-harness/rules/base-standards.json`，已确认存在）。文档表述需说明"引擎内置基线"。
- 任务为纯文档修正，0 行新代码；无重复实现风险。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | "This skill is a decision tree. It maps a customization need to the right specific skill" — 本任务非功能定制，走文档维护路径；无相关决策树分支适用 |
| `ai/skills/harness-skill-author/SKILL.md` | ✅ 已读 | "起草规则 5：**权威文件真实**：路径必须真实存在，作为唯一 field-level 细节来源" — 直接支撑本次权威路径修复的正当性 |
| `ai/skills/harness-standards-audit/SKILL.md` | ✅ 已读 | "继承通用项：与 `rules/base-standards.json` 冲突时，项目规范优先但需说明" — 该引用为引擎内置基线，需调整为不触发权威路径检查的表述 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | "一句话需求（含前缀 `优化：` 等）→ 走 PRD 工作流；必须自动扩充正文" — 本 REQ 即按此工作流产出 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读（间接） | 通过 `pallastrade-typescript-sdk/SKILL.md` 引用确认 serializer 位于 API gem `app/serializers/`（145 文件） |
| `pallastrade-typescript-sdk` | ✅ | ✅ 已读（被修复对象） | 第 526 行旧路径 `pallastrade/api/app/serializers/**/*.rb` → 修正为 `backend/pallastrade_gems/pallastrade_api/app/serializers/**/*.rb` |
| `pallastrade-cli` | ✅ | ✅ 已读（被修复对象） | 第 40 行 `.pallastrade/credentials.json` 为运行期产物（gitignored），需调整表述 |
| `pallastrade-extensions` | ✅ | ✅ 已读（被修复对象） | 第 100 行 `lib/pallastrade_simple_sales/engine.rb` 为生成器模板结构，需标注"生成/示例" |
| `pallastrade-decorators` | ⬜ 不涉及 | — | — |
| `pallastrade-dependencies` | ⬜ 不涉及 | — | — |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | — |
| `pallastrade-storefront` | ⬜ 不涉及 | — | — |
| `pallastrade-testing` | ⬜ 不涉及 | — | — |
| `pallastrade-i18n` | ⬜ 不涉及 | — | — |

---

## 需求标题

修复 4 个 SKILL 文档中的失效权威路径引用，使 `harness scan` / `skill check --freshness` 的权威路径检查清零。

## 任务类型

功能优化（实为文档/内容维护）

## 需求描述

升级 harness 1.8.0 后，资产治理扫描报告 4 个 SKILL 的"权威路径失效"（should 级）。逐一核实后确认：1 个为旧式 gem 路径需改真实路径，3 个为运行时产物/生成器模板/引擎内置文件——引用语义合理但被检查器误判为权威路径。本任务修正这 4 处文档表述，不改变任何代码行为。

## 影响范围（harness affected 输出）

- 改动文件（4 个，均在 `ai/skills/`）：
  - `ai/skills/pallastrade-typescript-sdk/SKILL.md`
  - `ai/skills/pallastrade-cli/SKILL.md`
  - `ai/skills/pallastrade-extensions/SKILL.md`
  - `ai/skills/harness-standards-audit/SKILL.md`
- 无代码/依赖/接口/DB 变更；无 UI 变更；无测试代码变更

## 技术方案（初步）

| # | 文件 | 现状 | 修正方案 |
|---|---|---|---|
| 1 | `pallastrade-typescript-sdk/SKILL.md` L526 | `pallastrade/api/app/serializers/**/*.rb` | → `backend/pallastrade_gems/pallastrade_api/app/serializers/**/*.rb`（glob 145 匹配） |
| 2 | `pallastrade-cli/SKILL.md` L40 | `.pallastrade/credentials.json`（反引号） | 去掉反引号，明确"运行时生成、gitignored、不入库"，避免被提取为权威路径 |
| 3 | `pallastrade-extensions/SKILL.md` L100 | `lib/pallastrade_simple_sales/engine.rb`（反引号列表项） | 标注"generated/示例"说明性关键词，避免被提取为权威路径 |
| 4 | `harness-standards-audit/SKILL.md` L52 | `rules/base-standards.json`（反引号） | 改写为"引擎随包分发内置基线"表述（不含反引号路径），避免被提取 |

验证方式：`npx harness scan` + `npx harness skill check --freshness`（AC-001~005）。

## 风险点

- 低：纯文档文本修正，不触碰代码；`docs:check` 可复验无断链
- 中：需确认修改后的表述不丢失原有技术信息（如 CLI 凭据保存位置、扩展模板结构说明）——方案中保留语义
