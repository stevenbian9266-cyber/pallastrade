# PRD-20260913-harness-prd-状态一致性检查器-readme-索引-文件头状态自动同步-引擎口径归一-ci-lefthook-漂移即失败

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-13 实施完成：脚本 + 9 项回归测试全绿 + lefthook/CI 接线 + 知识同步；实仓 118 文件/118 索引 `--check` exit 0） |
| 创建日期 | 2026-09-13 |
| 来源 | 优化：PRD 状态一致性检查器（README 索引 ↔ 文件头状态自动同步 + 引擎口径归一 + CI/lefthook 漂移即失败） |
| 分类 | harness（自动判定） |
| 关联 Skill | `harness-prd` / `pallastrade-prd` / `harness-docs` |
| 关联 REQ | REQ-20260913-prd-status-sync.md（实施时回填） |
| 关联 PRD | N/A（查重 0 命中；与 `PRD-20260809-harness-prd-dedupe-update` 不同：那份管新建去重，本份管状态一致性） |
| 需求类型 | 优化迭代（工程机制：把 PRD 状态权威性从人工约定升级为机器强制） |

## 1. 背景与目标

- **一句话需求原文**：优化：PRD 状态一致性检查器（README 索引 ↔ 文件头状态自动同步 + 引擎口径归一 + CI/lefthook 漂移即失败）
- **背景**（均为 2026-09-13 实测，非推测）：
  1. **索引↔文件漂移无法被机器发现**：收口前 `docs/prd/README.md` **114 行** vs 文件 **117 份** → **漂移 25 处 + 5 份未进索引 + 3 份无状态行**；`.github/workflows/` 中 **0 处** PRD 检查。
  2. **引擎口径窄**：harness 引擎用 `\| 状态 \| ([^|]+) \|`（单空格）解析状态 → **补空格的表格行对它不可见**，当前 **4/117** 份 PRD 对引擎不可见（`chk-p1-1a` / `fin-p4-1` / `dsp-p7-4` / `p3-stockreservation`）。
  3. **重复骨架头部**：**11 份** PRD 保留了 `prd new` 骨架（重复 H1 + 重复元数据表），首行与正文块状态可能各说各话。
- **目标**：新增一个零依赖检查器 + 提交/CI 接线，使「PRD 状态一致」成为**可机器验证**的约束而非人工约定。
- **成功指标**：① 对收口后的仓库 `--check` 返回 0；② 人为制造 1 处漂移 → 退出码 1 且报出文件名与两侧值；③ `--fix` 后再次 `--check` 返回 0；④ lefthook pre-commit 与 CI job 均已接入。

## 2. 用户故事 / 场景

- 作为**工程负责人**，我希望提交后忘了同步 PRD 索就**直接失败**，以便索引始终可信。
- 作为 **AI / 维护者**，我希望一条命令能把历史漂移**批量修好**，而不是逐文件手工比对。
- 场景（正常/边界/异常）：
  1. 改了文件头状态但没改索引 → `--check` 失败（state-drift）。
  2. 改了索引但没改文件 → `--check` 失败（state-drift，反向）。
  3. 新增 PRD 未进索引 → `--check` 失败（not-indexed）。
  4. 索引指向不存在的文件 → `--check` 失败（missing-file）。
  5. 状态行带补空格 / 缺失 → `--check` 失败（unparsable-status-row）。
  6. 运行 `--fix` → 对齐、再次 `--check` 返回 0（幂等）。
- 边界：仓库存在**引擎词表外**的状态（`merged`、`⛔废弃`）→ 检查器取**并集**而不得拒绝。

## 3. 功能需求（FR）

- FR-001：新增 `scripts/ci/prd-status-sync.mjs`（Node ESM，**零第三方依赖**），支持 `--check`（默认）/ `--fix` / `--json` / `--root <dir>`。
- FR-002：**双向解析**：`docs/prd/README.md` 索引行（状态|PRD|分类|日期|REQ）与每份 `docs/prd/**/PRD-*.md` 文件头的 `| 状态 | … |` 行。
- FR-003：检出四类问题：`state-drift`（两侧不同）、`not-indexed`、`missing-file`、`unparsable-status-row`。
- FR-004：`--fix` 以**文件头状态为准**回写索引；仅当文件无状态行时以索引为准补齐文件并打印告警；**不新建/不删除文件**。实施补充：`--fix` 还会把**引擎不可见**（补空格/制表符）的 `| 状态 | … |` 行归一为 `| 状态 | <status> |`（语义不变，仅对齐引擎口径；词表图例行不动）。
- FR-005：状态词表 = 引擎词表（draft/reviewing/approved/implementing/verifying/done/rejected） ∪ 仓库扩展（merged/obsolete/⛔废弃）。
- FR-006：接入 `lefthook.yml` pre-commit（glob `docs/prd/**`）与 `.github/workflows/harness-full.yml`（新增 `prd-status` job）。
- FR-007：退出码：`0` 一致；`1` 存在漂移；`2` 用法/IO 错误（CI 可区分）。

## 4. 非功能需求（NFR）

- **零依赖**：仅用 `node:fs` / `node:path`，不新增 npm 包。
- **确定性**：同输入必得同输出；`--fix` 只改状态列，不动排序/日期/REQ 列。
- **性能**：117 份 PRD 全量扫描 < 1s。
- **不破坏**：对无法解析的文件只报不改；`--fix` 不新建不删除。
- **跨平台**：Windows（本地）与 Linux（CI）行为一致。
- **可测试**：核心逻辑以 `--root` 参数解耦，支持在临时目录跑回归。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001/007：`node scripts/ci/prd-status-sync.mjs --check` 在当前（已收口）仓库返回 0。
- AC-002 ← FR-003：人为把某 PRD 文件头改为与索引不一致 → `--check` 退出码 1，输出含文件名与两侧值。
- AC-003 ← FR-004：对 AC-002 状态跑 `--fix` 后再次 `--check` 返回 0。
- AC-004 ← FR-003（`unparsable-status-row`）：对补空格/缺状态行样本能报出该问题。
- AC-005 ← FR-006：`lefthook.yml` 与 `harness-full.yml` 均出现该检查命令，且 `npx lefthook run pre-commit` 对暂存的 `docs/prd/**` 能执行到它。
- AC-006 ← FR-003（`not-indexed`）：对「文件未进索引」样本能报出该问题。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | prd/status | 无（应用层不读取 PRD 状态） | 否（不涉及） |
| Core | `pallastrade_gems/pallastrade_core/app/` | 同上 | 仅注释级 `# PALLAS-CUSTOM: DSP-P7-x (PRD-…)` 追溯标记 | 否（不涉及） |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | 无 | 否（不涉及） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 同上 | 无 | 否（不涉及） |
| Storefront | `storefront/src/` | 同上 | 无 | 否（不涉及） |
| Platform | `platform/packages/` + `.github/workflows/` + `lefthook.yml` | prd | **workflows 0 命中**；`lefthook.yml` 无 prd 检查；引擎 `node_modules/pallastrade-harness/bin/*.mjs` 有 13 个模块读 `docs/prd`（含 `harness.mjs:1107` 的窄口径状态正则） | **是（本 PRD 新建能力）** |

**结论**：全仓无任何 PRD 状态一致性检查 → 无重复实现风险；引擎侧只读不改（本 PRD 在**仓库脚本层**实现，避免修改 node_modules 不可持久化）。

## 7. 技术影响

- 新增：`scripts/ci/prd-status-sync.mjs`、`tests/prd-status-sync.test.mjs`。
- 修改：`lefthook.yml`（pre-commit +1 command）、`.github/workflows/harness-full.yml`（+1 job）。
- 知识同步（`doc-impact` 规则要求）：`AGENTS.md`（§0.1 登记新脚本）、`ai/skills/pallastrade-prd/SKILL.md`（流程步骤补检查器）、`harness/scenarios/scenarios.json`（Eval 场景）。
- 不改应用代码 / 数据库 / API / 运行时。

## 8. 测试计划

- 新增测试：`tests/prd-status-sync.test.mjs`（`node --test`，在 `os.tmpdir()` 构造 mini 仓库树，不污染真实仓库）。
- 手工验收：`npx lefthook run pre-commit`（AC-005）。
- AC 映射：AC-001/002/003/004/006 → `tests/prd-status-sync.test.mjs`；AC-001 另需对**真实仓库**跑一次 `--check`（集成级）；AC-005 → lefthook 执行日志。

## 9. 文档同步清单（知识同步门）

- [x] 不涉及 API 文档
- [x] Skill 文档：`ai/skills/pallastrade-prd/SKILL.md`（增补「状态一致性检查器」步骤）
- [x] `AGENTS.md` §0.1（登记 `scripts/ci/prd-status-sync.mjs`）
- [x] `harness/scenarios/scenarios.json`（新增 Eval 场景）
- [x] `docs/prd/README.md` 索引（本 PRD 自身 + 检查器修复项）
- [x] 本 PRD 状态更新

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿（基于 P0–P7 收口的实测漂移数据） | AI |
| 2026-09-13 | 1.0 | 实施完成：`scripts/ci/prd-status-sync.mjs` + `tests/prd-status-sync.test.mjs`（9 用例）+ lefthook pre-commit + harness-full.yml `prd-status` job + AGENTS/Skill/scenarios 同步；实仓回填 5 处历史问题后 `--check` exit 0 | AI |
