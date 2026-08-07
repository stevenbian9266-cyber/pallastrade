# PallasTrade — Copilot Instructions (Auto-Injected Every Session)

<!--
  This file is automatically injected by GitHub Copilot into EVERY chat session.
  It is the single most important enforcement file. Rules here CANNOT be skipped.
  AGENTS.md provides detailed reference; this file provides non-negotiable commands.
-->

## ⛔ R0: THE FIRST THING YOU DO — NO EXCEPTIONS

**Before you invoke `create_file`, `replace_string_in_file`, `multi_replace_string_in_file`, or ANY file mutation tool — you MUST first confirm the task uses a valid prefix, then run `harness gate`.**

### Required Prefix Convention

用户输入必须以以下前缀之一开头，Harness 自动识别任务类型：

| 用户说 | AI 理解为 | Gate `--type` |
|---|---|---|
| `修复：xxx` | Bug 修复 | `bugfix` |
| `优化：xxx` / `改进：xxx` | 功能优化 | `feature` |
| `新增：xxx` / `添加：xxx` | 新功能 | `feature` |
| `样式：xxx` | 样式调整 | `style` |
| `需求：xxx` | 泛需求描述 | `feature` |
| `审计：xxx` | 审计 / 盘点 | `audit` |
| `研究：xxx` / `调研：xxx` | 研究 / 评估 | `research` |
| `文档：xxx` | 文档类 | `docs` |
| `重构：xxx` | 重构 / 清理 | `refactor` |
| `安全：xxx` | 安全相关 | `security` |
| `测试：xxx` | 测试相关 | `test` |

**If the user input does NOT start with one of these prefixes**, remind them to add a prefix before proceeding. Do NOT create a gate without a valid prefix.

**无前缀时的处理：**
- 如果用户输入**明显是提问**（"怎么..."、"什么是..."、"解释..."）→ 直接回答，不触发 gate
- 如果用户输入**涉及代码修改**但缺前缀 → AI 提醒用户加前缀后再继续
- 如果用户输入含糊 → AI 用 `vscode_askQuestions` 让用户确认意图（提需求 or 问问题）

### Run the gate

```bash
node scripts/harness/cli.mjs gate --task "<prefix：description>"
```

The CLI auto-detects the `--type` from the prefix. No need to pass `--type` manually.

**If you make ANY file edit without first running `harness gate`, you have committed a process violation. Stop immediately. Inform the user. Delete your edits. Start over with the gate.**

### R0 exceptions (the ONLY file operations allowed while gate is active)

| Allowed | Directory / Scenario | Reason |
|---|---|---|
| ✅ `create_file` / edit | `harness/requirements/` | 需求文档，必须创建才能清 `create-req-doc` check |
| ✅ `create_file` / edit | `harness/gates/` (gate CLI handles this) | Gate 状态文件 |
| ✅ Read any file | All directories | 跨层搜索、读 Skill 文件 |
| 🚫 `create_file` | All other directories | 必须先清 gate |
| 🚫 `replace_string_in_file` | All other directories | 必须先清 gate |

### R0 判断：新建文件还是改已有文件

```
Gate cleared 后：
  改已有文件 → ✅ 直接改
  必须新增文件才能实现需求 → ✅ 允许，在 REQ doc 中说明原因
  改已有文件就能实现但 AI 新建了文件 → 🚫 违规。检查是否漏了跨层搜索
```

This rule catches the #1 cause of duplicate code: AI creates a new controller/service
when one already exists in a gem layer it didn't search.

## Non-Negotiable Rules

### R1: Pre-Coding Gate

**Before invoking ANY file creation or file editing tool**, you MUST run:

```bash
node scripts/harness/cli.mjs gate --task "<brief description>" [--type feature|bugfix|style|audit|research|docs|refactor|security|test]
```

This command creates a gate at `harness/gates/GATE-*.json` and outputs a checklist.

**If the command exits with any code other than 0**, you are **PHYSICALLY FORBIDDEN** from calling:
- `create_file`
- `replace_string_in_file`
- `multi_replace_string_in_file`
- Any other file mutation tool

To clear gate checks one at a time:
```bash
node scripts/harness/cli.mjs gate:clear --gate <GATE-ID> --clear <check-id>
```

Only proceed to implementation when `gate:clear` exits 0 (all checks cleared).

### R1-前置：编辑前强制校验（每个回合都必须做）

在调用任何文件修改工具之前，AI MUST 先运行：

```bash
node scripts/harness/cli.mjs gate:status
```

- **exit 0** → 存在有效 gate → 允许继续编辑
- **exit 1** → 无有效 gate 或未全部清除 → **物理禁止任何文件修改**，必须先创建/处理 gate

此校验在 Copilot 环境下是唯一的机械强制点——如果跳过，等于绕过了整个 gate 机制。

### R1-续：同一任务的后续回合

**当在同一需求上继续工作时**（例如"做 P1-6"这种分项实施），先检查 gate 是否仍有效：

```bash
node scripts/harness/cli.mjs gate:status
```

- 如果 exit 0 → gate 有效，可以继续编辑
- 如果 exit 1 → 说明 gate 过期（>24h）或 `verify-test` 未完成，需要处理
- 如果无活跃 gate → 必须创建新 gate

### R2: Skill Files Are NOT Optional

For `feature` and `bugfix` task types, the gate requires reading Skill files.
**You must actually read them** — not just mark the check as done.
The requirements document template (`harness/requirements/_TEMPLATE.md`) includes a
Skill Consultation Evidence Table. Every cell must be filled with a real finding.

### R3: User Confirmation for New Features

For `feature` type tasks, the gate includes `user-confirmed`.
You MUST present the requirements document to the user and WAIT for explicit confirmation
before marking this check as done. Do not proceed without it.

### R4: Cross-Layer Search

Every task requires searching across all 6 layers:
1. `backend/app/`
2. `backend/pallastrade_gems/pallastrade_core/app/`
3. `backend/pallastrade_gems/pallastrade_api/app/`
4. `backend/pallastrade_gems/pallastrade_admin/app/`
5. `storefront/src/`
6. `platform/packages/`

Finding a capability in one layer does NOT mean it exists in others.
You MUST search each layer independently.

### R5: Anti-Patterns Are BLOCKED

The following are physically blocked (CI enforced, not just suggested):
- AP-001: `style={{ }}` inline styles → Use Tailwind classes
- AP-002: Raw `fetch()` calls → Use `@pallastrade/sdk`
- AP-003: `Model.create()` outside specs → Use Factory Bot / Services
- AP-004: `after_save` callbacks → Use Subscribers
- AP-005: Unscoped model queries → Always scope via `current_store`
- AP-006: Hardcoded hex colors → Use CSS custom properties
- AP-008: Copying Gem views to Host App → Modify Gem source directly

### R6: Verify or Declare — NO SKIPPING

After implementing code changes, the `verify-test` gate check MUST be resolved.
You MUST either:
- Run relevant tests (`harness check --profile quick` or `pnpm test`), OR
- Explicitly document "no test needed" with a reason (e.g., "纯样式调整，无逻辑变更")

### Minimum Verification Per Change Type

"no test needed" is the RARE exception. If you changed any of the following, run the corresponding minimum check:

| What you changed | Minimum check | Est. Time |
|---|---|---|
| Any TypeScript/TSX file | `pnpm build` or `pnpm lint` | ≤2 min |
| Any Ruby file | `harness check --profile quick` | ≤5 min |
| Model / DB schema / migration | + `harness check --profile full` | ≤45 min |
| API endpoint (new/modified) | + `harness generated:check` (OpenAPI + SDK types) | ≤5 min |
| UI component / style | + `harness e2e dashboard` or `harness e2e storefront` | ≤15 min |
| Payment logic | + payment sandbox gate | ≤30 min |
| AI Skill file (`ai/skills/`) | + `harness eval ai --check-freshness` | ≤2 min |

### Verification Evidence Required

Before clearing `verify-test`, you MUST provide objective evidence of the fix working:

| What you changed | Required evidence |
|---|---|
| UI (view/component/style) | Screenshot or DOM snapshot showing corrected state |
| Backend logic | Rails log line showing success (200/302) or `Completed ... OK` |
| Data fix | DB query result showing before/after |
| Config-only change | Server restart + log line confirming new config loaded |

**"no test needed" is NOT valid for UI or backend logic changes — browser/log verification is mandatory.**

**If you skip even the minimum check and the build breaks (like a missing backtick), you have committed a process violation.**

**You CANNOT skip this step or leave `verify-test` pending.**
A gate with `verify-test` still pending is considered invalid for continuation.

### R7: user-confirmed Requires Explicit User Action

The `user-confirmed` gate check **MUST NOT be cleared by the AI**. It may only
be cleared after the user explicitly confirms the requirements document with a
clear affirmative (e.g., "确认", "实施", "go ahead", "proceed").
Ambiguous or implicit approval (e.g., "ok", "看看吧") does NOT count — ask
the user to clarify before proceeding.

## Reference

For detailed architecture, customization decision tree, and domain-specific guidance,
see `AGENTS.md` in the repository root.
