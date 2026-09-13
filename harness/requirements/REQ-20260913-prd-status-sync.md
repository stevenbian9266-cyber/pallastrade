# REQ-20260913-prd-status-sync — PRD 状态一致性检查器

> 关联 PRD：`docs/prd/harness/PRD-20260913-harness-prd-状态一致性检查器-readme-索引-文件头状态自动同步-引擎口径归一-ci-lefthook-漂移即失败.md`（approved）
> 来源：P0–P7 收口实测（`docs/research/RESEARCH-20260913-p0-p7-prd-closeout-and-deferred-register.md` §4/§6）+ 用户明确确认「是：新增检查器（自动同步 + 漂移即失败）并接入 CI / lefthook」
> 本 REQ 覆盖**设计阶段**；实施与验证在后续任务中执行（本任务只交付 PRD + REQ，避免与实施任务的 allow 范围冲突）

## Step 0：跨层搜索（6 层，已执行）

| 层 | 搜索路径 | 关键词 | 结果 | 满足？ |
|---|---|---|---|---|
| App | `backend/app/` | `docs/prd` / `PRD-\d{8}` | 247 个文件命中，**全部为注释级追溯标记**（抽样：`disputes/deadline_sweeper_job.rb` 的 `# PALLAS-CUSTOM: DSP-P7-5 (PRD-…)`） | 否（不涉及） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 同上 | 同上（注释级） | 否 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | 同上 | 无 | 否 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | 同上 | 无 | 否 |
| Storefront | `storefront/src/` | 同上 | 无 | 否 |
| Platform | `platform/packages/`、`.github/workflows/`、`lefthook.yml`、`node_modules/pallastrade-harness/bin/` | `prd` / `docs/prd` | **workflows 0 命中**、`lefthook.yml` 无 prd 检查；引擎 13 个模块读 `docs/prd`（`harness.mjs:1107` 用窄口径正则 `\\| 状态 \\| ([^\|]+) \\|`） | **需新建（本 REQ）** |

**结论**：全仓无 PRD 状态一致性检查 → 无重复实现风险。检查器放在**仓库脚本层**（`scripts/ci/`），不改 `node_modules`（不可持久化）。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `harness-prd` | ✅ 已读 | 阶段 0 生成 PRD → 阶段 1 用户确认 → 阶段 2-5 实施/验证/知识同步；REQ 简版判定 = 「≤5 文件且无逻辑变更」→ **本任务含新增脚本（逻辑变更）→ 用完整版 REQ** |
| `pallastrade-prd` | ✅ 已读 | 索引为唯一状态入口；`harness prd verify` 的 AC 追溯；知识同步门 `sync-check` |
| `harness-docs` | ✅ 已读 | `doc-impact` 规则表：`lefthook.yml` 变更 ⇒ 必须同步 `AGENTS.md` + `ai/skills/pallastrade-prd/SKILL.md` + `harness/scenarios/scenarios.json` |

## 需求描述

新增零依赖检查器 `scripts/ci/prd-status-sync.mjs`，双向比对 `docs/prd/README.md` 索引与各 PRD 文件头 `| 状态 |` 行，检出 `state-drift` / `not-indexed` / `missing-file` / `unparsable-status-row` 四类问题；`--fix` 以文件头为准回写索引；接入 lefthook pre-commit 与 CI job，漂移即失败。

## 验收标准与验证方案

| AC | 验证命令 / 方式 |
|---|---|
| AC-001 `--check` 对真实仓库返回 0 | `node scripts/ci/prd-status-sync.mjs --check` |
| AC-002 人为制造漂移 → 退出码 1 + 报文件名 | 测试用例（tmp 夹具） |
| AC-003 `--fix` 后 `--check` 返回 0 | 测试用例（tmp 夹具） |
| AC-004 补空格/缺状态行被报出 | 测试用例（tmp 夹具） |
| AC-005 lefthook + CI 已接入 | `npx lefthook run pre-commit`（暂存 docs/prd/**）+ workflow diff |
| AC-006 文件未进索引被报出 | 测试用例（tmp 夹具） |

## 影响面

- 新增 `scripts/ci/prd-status-sync.mjs`、`tests/prd-status-sync.test.mjs`
- 修改 `lefthook.yml`、`.github/workflows/harness-full.yml`
- 知识同步：`AGENTS.md`、`ai/skills/pallastrade-prd/SKILL.md`、`harness/scenarios/scenarios.json`
- 零应用代码 / 零 DB / 零 API 变更
