# REQ-20260913-p0-p7-prd-closeout — P0–P7 PRD 状态收口与挂起项备案

> 关联 PRD：N/A（治理收口任务，跨 42 份 PRD 的状态订正）
> 来源：用户指令「完成以上遗留」= `docs/research/RESEARCH-20260913-p0-p7-implementation-audit.md` §5 建议行动第 1–4 项 + §6 未覆盖项
> Task：`TASK-20260913085722-ae3f1a01`；Gate：`GATE-2026-09-13T08-57-36`（docs）
> 产出：`docs/research/RESEARCH-20260913-p0-p7-prd-closeout-and-deferred-register.md`

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 结果 | 满足？ |
|---|---|---|---|---|
| App | `backend/app/` | PRD 状态 / `PRD-\d{8}` | 命中均为**注释级追溯标记**（抽样 6 处，如 `# PALLAS-CUSTOM: DSP-P7-5 (PRD-…)`），无状态解析代码 | 否 |
| Core | `…/pallastrade_core/app/` | 同上 | 同上（仅注释追溯） | 否 |
| API | `…/pallastrade_api/app/` | 同上 | 无命中 | 否 |
| Admin | `…/pallastrade_admin/app/` | 同上 | 无命中（后台导航一致性由 `plugin-nav-validate` 独立把关） | 否 |
| Storefront | `storefront/src/` | 同上 | 无命中 | 否 |
| Platform | `platform/packages/`、`.github/workflows/` | 同上 / `prd` | **workflows 0 命中** → 漂移无法被现有 CI 捕获（→ 已确认另开机制任务） | 否 |

**结论**：PRD 状态元数据只存在于 `docs/prd/**`（索引 + 文件头）与 `harness/gates/**`（闭环证据）。本任务零代码改动；跨层搜索证明「改文档不会遗漏某层的实现」。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-prd` | ✅ 已读 | PRD 生命周期 draft→approved→done 与「知识同步门」；索引为唯一状态入口 |
| `harness-docs` | ✅ 已读 | 治理文档与证据链约定；`doc-impact` 检查面 |
| `harness-standards-audit` | ✅ 已读 | 审计与收口报告的判据要求（可复核、可挑战） |

## 需求标题

把 P0–P7 的全部 PRD 状态与 `docs/prd/README.md` 索引**一次性对齐到可复核口径**，并显式登记尚不能收口的事项。

## 任务类型

文档 / 治理（docs）

## 验收标准（AC）

| AC | 内容 | 验证方式 | 结果 |
|---|---|---|---|
| AC-1 | 索引行数 == PRD 文件数，且状态逐行一致 | 解析脚本复检 | ✅ 117 = 117，漂移 0 |
| AC-2 | 不存在「文件未进索引」 | 同上 | ✅ 0 |
| AC-3 | 每个状态为 `done` 的 PRD 都能指认闭环门禁或显式标注追溯收口 | 本 REQ §L2 对照表 + 报告 §2/§3 | ✅ |
| AC-4 | 名实不符 / 重复件 / 缺失状态行被消除 | 报告 §4 | ✅ |
| AC-5 | 挂起项有登记且含解除条件 | 报告 §5 | ✅ 10 项 |
| AC-6 | 零代码改动 | `git diff --stat` 仅 `docs/**` + `harness/requirements/**` | ✅ |

## L2 追溯收口清单（无 finished 门禁，需人工复核）

`payment-p0-foundation` · `rev-p6-7` · `order-lifecycle-p1` · `chk-p1-1` · `chk-p1-1a` · `r1-contract-generation`
—— 依据见报告 §3。

## 影响面

- 变更文件：`docs/prd/README.md`、42 份 `docs/prd/**/PRD-*.md`、本 REQ、`docs/research/RESEARCH-20260913-p0-p7-prd-closeout-and-deferred-register.md`、审计报告交叉引用。
- 接口/迁移/运行时：**无**。
- 知识同步：`docs/prd/README.md` 既是产出也是索引；无 Skill/规范变更，见 evidence（knowledge）。

## 后续任务

| 任务 | 内容 |
|---|---|
| B（优化） | PRD 状态一致性检查器 + CI/lefthook 接线（用户已确认） |
| C（测试） | dev 真实回滚演练（回退→验证→前滚）+ 演练报告（用户已确认） |
