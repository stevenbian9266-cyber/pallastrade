# PallasTrade — Copilot Instructions (Auto-Injected Every Session)

<!-- 强制命令速查。详细规范见 AGENTS.md。本文件规则不可跳过。
     精简于 2026-08-31（token 优化，见 docs/research/RESEARCH-20260831-harness-token-optimization.md）。 -->

## ⛔ R0: THE FIRST THING YOU DO — NO EXCEPTIONS

**Before invoking `create_file` / `replace_string_in_file` / `multi_replace_string_in_file` / ANY file mutation tool — MUST first confirm the task uses a valid prefix, start/resume a Harness Task, build context, then open a task-bound Gate.**

### Required Prefix Convention（Harness 自动识别任务类型）

| 用户说 | Gate `--type` | 用户说 | Gate `--type` |
|---|---|---|---|
| `修复：xxx` | bugfix | `文档：xxx` | docs |
| `优化：xxx` / `改进：xxx` | feature | `重构：xxx` | refactor |
| `新增：xxx` / `添加：xxx` | feature | `安全：xxx` | security |
| `样式：xxx` | style | `测试：xxx` | test |
| `需求：xxx` | feature | `审计：xxx` | audit |
| `研究：xxx` / `调研：xxx` | research | — | — |

**无前缀**：明显提问→直接答；改代码缺前缀→提醒加前缀；含糊→`vscode_askQuestions` 确认。

### Start the lifecycle and run the gate

```bash
npx harness task start --title "<prefix：description>" --allow "<approved-glob>" --json
npx harness brain context --task <TASK-ID>
npx harness risk check --task <TASK-ID>
npx harness gate --task "<prefix：description>" --task-id <TASK-ID>
```

**违规**：未过 gate 就编辑文件 = 流程违规（停止、告知、删改、重开 gate）。

### R0 exceptions（gate 激活期间唯一允许的文件操作）

| Allowed | Directory / Scenario | Reason |
|---|---|---|
| ✅ 编辑 | `harness/requirements/` | 清 `create-req-doc` check |
| ✅ 编辑 | `harness/gates/` | Gate 状态文件 |
| ✅ 读任何文件 | 所有目录 | 跨层搜索、读 Skill |
| 🚫 其他写操作 | — | 必须先清 gate |

### R0 判断：新建文件还是改已有文件

```
Gate cleared 后：改已有文件 → ✅ 直接改
  必须新增文件 → ✅ 允许（REQ doc 说明原因）
  能改已有却新建 → 🚫 违规（先查跨层搜索）
```

## Non-Negotiable Rules

### R1: Pre-Coding Gate（物理强制）

改任何文件前 MUST 运行：

```bash
npx harness gate --task "<brief description>" --task-id <TASK-ID>
```

- gate 非 0 退出 → **物理禁止** `create_file` / `replace_string_in_file` / `multi_replace_string_in_file` / 任何修改工具
- 逐项清：`npx harness gate:clear --gate <GATE-ID> --clear <check-id>`
- 清完 preparation 才实施；task-bound `verify-test` 不可手工 clear（收集证据 → `knowledge verify` → `evidence verify --task <TASK-ID> --gate <GATE-ID>`）

### R1-前置：编辑前强制校验（每回合必做）

```bash
npx harness gate:status
```
- **exit 0** → 有有效 gate → 允许编辑
- **exit 1** → 无有效 gate 或未全清 → **物理禁止修改**，先创建/处理 gate

### R1-续：同一任务的后续回合

先 `gate:status`：exit 0 → gate 有效，同时 `task status --task <TASK-ID>` 确认 worktree 后继续；exit 1 → gate 过期（>24h）或 verify-test 未完，先处理；无活跃 gate → 新建。

### R2: Skill Files Are NOT Optional

feature/bugfix 类型 gate 要求读的 Skill **必须真读**（REQ 的 Skill Consultation Evidence Table 每格填真实结论，不得跳过）。

### R3: User Confirmation for New Features

feature gate 含 `user-confirmed`：呈现需求文档 → **等用户明确确认**（"确认/实施/go ahead/proceed"）→ 才 clear；模糊同意（"ok/看看吧"）不算。

### R4: Cross-Layer Search（6 层，无例外）

`backend/app/` → `pallastrade_core/app/` → `pallastrade_api/app/` → `pallastrade_admin/app/` → `storefront/src/` → `platform/packages/`。
每层独立搜索；找到能力≠他层也有（AP-SEARCH-1/2/3 见 AGENTS.md §2 Step 0）。

### R5: Anti-Patterns Are BLOCKED

完整清单见 `AGENTS.md` §5 + 唯一权威 `harness/policies/anti-patterns.json`（CI 机器执行）。高频：AP-001 内联样式→Tailwind；AP-002 裸 fetch→SDK；AP-006 硬编码色→设计 token。

### R6: Verify or Declare — NO SKIPPING

改后 `verify-test` MUST 用 typed evidence 解决：`harness evidence run --task <TASK-ID> --type test -- <cmd>`；非代码工作可记 justified review evidence（须满足 risk profile + knowledge）。
核心强制（详见 AGENTS.md §6）：UI/后端逻辑 "no test needed" 无效；跳过最小检查致构建损坏=违规；不允许 verify-test pending；禁止手工 clear（用 evidence verify）。

### R7: user-confirmed Requires Explicit User Action

AI **不可自清** `user-confirmed`；须用户明确肯定（"确认/实施/go ahead/proceed"）。模糊（"ok/看看吧"）不算，需澄清。

### R8: PRD-Driven Workflow（一句话需求 → PRD → 实施）

一句话需求（`需求：`/`新增：`/`优化：`/`修复：` 等）MUST 遵循 `ai/skills/pallastrade-prd/SKILL.md`：
1. `npx harness prd new --title "<需求>"`（自动分类+查重>0.3 阻止）→ 按 `docs/prd/_TEMPLATE.md` 扩充 → `docs/prd/{cat}/PRD-*.md`，更新 README 索引
2. 查重优先：命中相似 PRD → `harness prd update` 回写原 PRD，不新建；确属全新才 `--force`；做 6 层跨层搜索
3. 用户确认（approved）后才能开 gate
4. gate + REQ（`harness/requirements/REQ-*.md`）
5. 每 AC 映射测试（标注 `# PRD-xxx AC-x`），`harness prd verify --id PRD-xxx`
6. 接口变更：同步 `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`，`generated:check`
7. 知识同步门：`harness sync-check --id PRD-xxx` → 处理 → `--ack`
**违反 R8 = 流程违规。**

### R9: 分支策略（dev-only，2026-09-05）

- 远程仓库仅 `dev`（无 `main`、无 prod 服务器）；所有提交/推送均在 `dev`
- 发布：push `dev` 即触发 CI 与服务器拉取式部署（pull-deploy.sh dev）；无 dev→main 合并流程
- **gate 绑定当前分支**：在哪个分支开 gate 就在哪个分支完成提交（切分支前先完成 gate）

## Reference

For detailed architecture, customization decision tree, and domain-specific guidance, see `AGENTS.md` in the repository root.
