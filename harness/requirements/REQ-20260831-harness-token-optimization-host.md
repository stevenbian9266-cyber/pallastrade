# REQ-20260831-harness-token-optimization-host.md

> 任务：优化：实施 harness token 优化（宿主侧）
> 任务 ID：TASK-20260831123823-ec99014d
> 关联 PRD：PRD-20260831-harness-实施-harness-token-优化-宿主侧

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | config, harness, token | 无相关文件 | ✅ 无冲突 |
| App — views/decorators | `backend/app/` | config, harness | 无相关文件 | ✅ 无冲突 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | config | `configuration_management.rb`, `menu_config.rb`（业务配置模型） | ✅ 与 harness 配置无关 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | config, harness | 无相关文件 | ✅ 无冲突 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | config | 无 | ✅ 无冲突 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | config | `menu_configs_controller.rb`（业务菜单配置） | ✅ 无关 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | config | 无相关文件 | ✅ 无冲突 |
| Storefront | `storefront/src/` | config | `lib/pallastrade/config.ts`（业务配置） | ✅ 无关 |
| Platform | `platform/packages/` | config | 仅 node_modules 依赖 | ✅ 无冲突 |

### 搜索结论

- token 优化仅涉及宿主侧 `harness.config.mjs` + 文档/模板/skill（7 个文件）
- 6 层无重复的 harness/token 优化配置；core/admin 层的 config 文件均为**业务配置**（菜单/权限/店铺），与本任务无关
- **引擎（node_modules/pallastrade-harness）不修改**（用户明确要求）

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树确认：本任务为配置/文档优化，无功能定制分支适用；"Settings/Config → 最低优先级前先尝试"——本次即配置层优化 |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | "一句话需求 → 完整 PRD → gate 实施 → 测试验收 → 知识同步"；本次按此工作流，且将新增"REQ 简版规范"（FR-009） |
| `ai/skills/pallastrade-project/SKILL.md` | ✅ 已读 | 项目结构/路由权威；将新增"Token 节俭操作习惯"（FR-008） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | — | — |
| `pallastrade-decorators` | ⬜ 不涉及 | — | — |
| `pallastrade-dependencies` | ⬜ 不涉及 | — | — |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | — |
| `pallastrade-storefront` | ⬜ 不涉及 | — | — |
| `pallastrade-testing` | ⬜ 不涉及 | — | — |
| `pallastrade-i18n` | ⬜ 不涉及 | — | — |

> ⛔ 本表必读项全部为"已读"，需求文档有效。

---

## 需求标题

实施 RESEARCH-20260831-harness-token-optimization.md 方案 §4/§5 的宿主侧优化项（配置 + 注入文件瘦身 + 模板精简 + skill 规范），不改动 pallastradeharness 引擎。

## 任务类型

功能优化（实为配置 + 文档优化）

## 需求描述

接入 harness 后 token 消耗明显增多。方案文档已完成分析（固定注入 37.8KB + feature 任务 24 项检查 + 4 设计文档等）。本任务实施宿主侧 7 个文件的优化：
1. `harness.config.mjs`：关闭 designStage、限制 brain/evidence（FR-001/002/003）
2. `AGENTS.md` / `copilot-instructions.md`：瘦身去重（FR-004/005，约束全保留）
3. 两个模板精简（FR-006/007）
4. 两个 skill 增加规范（FR-008/009）
**不修改**：node_modules/pallastrade-harness 引擎。

## 影响范围（harness affected 输出）

- 修改文件（7 个，宿主侧）：
  - `harness.config.mjs`
  - `AGENTS.md`
  - `.github/copilot-instructions.md`
  - `docs/prd/_TEMPLATE.md`
  - `harness/requirements/_TEMPLATE.md`
  - `ai/skills/pallastrade-project/SKILL.md`
  - `ai/skills/harness-prd/SKILL.md`
- 无代码/依赖/DB/接口变更；影响未来会话注入量与任务流程

## 技术方案（初步）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `harness.config.mjs` | 加 `designStage:{enabled:false}`；`brain.maxContextAssets 24→10`、`maxAssetBytes 524288→262144`；`evidence.maxOutputBytes 262144→65536` |
| 2 | `AGENTS.md` | §2 Step -2/-1/2/3 命令块压缩为指针（与 copilot R0/R1/R3/R8 重复），保留 Step 0/1/4 + §0/§1/§3-§8 |
| 3 | `copilot-instructions.md` | 重写为速查表：R0 前缀表 + 核心命令 + R1-R9 一行规则 + 指针到 AGENTS.md |
| 4 | `docs/prd/_TEMPLATE.md` | 删说明/示例注释，保留结构骨架 |
| 5 | `harness/requirements/_TEMPLATE.md` | 压缩说明文字，保留跨层搜索表 + skill 表 |
| 6 | `pallastrade-project/SKILL.md` | 加"Token 节俭"章节（6 条操作习惯） |
| 7 | `harness-prd/SKILL.md` | 加"REQ 简版规范"（轻量任务简版 REQ） |

验证方式：见 PRD §8（gate 检查数、注入大小、nav:check/docs:check、scan）。

## 风险点

- 中：AGENTS.md/copilot-instructions 瘦身需确保约束零丢失——用 grep 校验 R0-R9 关键命令保留 + nav:check/docs:check 复验
- 低：配置改动影响后续所有任务流程（designStage 关闭后 UI 重构任务需手动补设计文档）——已在 PRD 记录决策点
