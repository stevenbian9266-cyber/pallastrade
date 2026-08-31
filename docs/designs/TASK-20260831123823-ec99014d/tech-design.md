# 技术设计 — 实施 harness token 优化（宿主侧，TASK-20260831123823-ec99014d）

> 本任务为 harness 宿主侧配置/文档优化，无代码逻辑变化。

## Part A：现状识别

### A1 业务系统盘点

- 接入 harness（1.7.0→1.8.0）后 token 消耗明显增多
- 已产出方案文档：`docs/research/RESEARCH-20260831-harness-token-optimization.md`（实测数据 + 14 项方案）
- 本任务实施方案 §4/§5 的宿主侧项（不改引擎）

### A2 数据模型识别

- 无数据库模型变更
- 涉及文件均为配置/文档/Markdown

### A3 字段盘点（改动清单）

| 文件 | 改动 |
|---|---|
| `harness.config.mjs` | 加 `designStage:{enabled:false}`；`brain.maxContextAssets 24→10`、`maxAssetBytes 524288→262144`；`evidence.maxOutputBytes 262144→65536` |
| `AGENTS.md` | §2 Step -2/-1/2/3 命令块压缩为指针（与 copilot R0/R1/R3/R8 重复） |
| `.github/copilot-instructions.md` | 重写为速查表（保留 R0-R9 全部命令） |
| `docs/prd/_TEMPLATE.md` | 删说明/示例注释，保留结构骨架 |
| `harness/requirements/_TEMPLATE.md` | 压缩说明文字 |
| `ai/skills/pallastrade-project/SKILL.md` | 加"Token 节俭"章节 |
| `ai/skills/harness-prd/SKILL.md` | 加"REQ 简版规范" |

### A4 代码结构

- 涉及目录：根（harness.config.mjs / AGENTS.md / .github/）、docs/prd/、harness/requirements/、ai/skills/
- 无代码文件变更；不触引擎（node_modules/pallastrade-harness）

## Part B：复用决策矩阵

| 需求 | 决策 | 目标 | 依据 |
|---|---|---|---|
| 配置优化 | 调用已有 | `harness.config.mjs` | 已有配置结构，追加/修改字段 |
| 注入文件瘦身 | 调用已有 | `AGENTS.md` / `copilot-instructions.md` | 保留约束、去重、加指针 |
| 模板精简 | 调用已有 | 两个 `_TEMPLATE.md` | 保留结构、删说明 |
| skill 规范 | 调用已有 | 两个 skill | 追加章节 |
| 验证 | 调用已有 | `nav:check` / `docs:check` / `scan` / gate 检查数 | 复用既有机械校验 |

## 技术方案

1. 修改 `harness.config.mjs` 三处配置（designStage/brain/evidence）
2. 重写 `copilot-instructions.md` 为速查表（10.3→~6KB）
3. 精简 `AGENTS.md` §2（27.5→~20KB）
4. 精简两个模板
5. 追加两个 skill 章节
6. 验证：nav:check / docs:check / scan / gate 检查数 / 文件大小

## 风险与回滚

- 风险：中（权威文件瘦身需确保约束零丢失）
- 缓解：grep 校验 R0-R9 关键命令 + nav:check/docs:check 复验
- 回滚：`git checkout -- <file>` 恢复
