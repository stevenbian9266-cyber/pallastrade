# Harness 工程化机制评级报告（2026-08-08 第二次）

> 审计任务：GATE-2026-08-08T11-06-27（audit，dev 分支）
> 对比上次：2026-08-07 首次评级 **7.6/10, L3**

---

## 一、总分：8.6 / 10（L3 成熟，向 L4 过渡）

**较上次提升 +1.0 分**（主要来自 PRD 工作流、知识同步门、导航地图、分支策略、nav:check 等新增能力）。

## 二、12 维度评分明细

| # | 维度 | 权重 | 评分 | 依据 | 亮点 / 不足 |
|---|---|---|---|---|---|
| 1 | 门禁机制 (gate) | 10% | **9.5** | gate 创建/清除/status/required/clean；9 种任务类型；绑定 branch+HEAD；feature 含 prd-created+read-skill-prd | ✅ 完整闭环；lefthook pre-commit 强制 |
| 2 | 需求与 PRD 工作流 | 10% | **9.0** | REQ 模板 + PRD 模板/分类(15类)/verify + `prd new/list/verify` 命令 + AC↔测试追溯 | ✅ 一句话需求全自动；不足：prd verify 对删除类任务无测试会失败 |
| 3 | 跨层搜索 | 8% | **9.0** | 6 层强制 + AP-SEARCH-1/2/3 + gate search checks | ✅ 每任务强制 |
| 4 | 反模式库 | 10% | **8.5** | 10 条 AP（含 guard-aware AP-009a/b）+ CI 强制 + scan-anti-patterns | ⚠️ 全仓仍有 **94 个 warning**（0 error）；AP-009 在 storefront 有 1 处待清 |
| 5 | 验证与证据 | 8% | **8.5** | verify-test + 证据矩阵（截图/日志/DB）+ evidence 采集 | ✅ 证据驱动 |
| 6 | 知识同步 | 10% | **9.0** | doc-impact **15 规则** + sync-check 门 + nav:check + GS-013/014/015 | ✅ 全矩阵（Skill/README/Agent/规范/API 文档/反模式/场景） |
| 7 | 场景库/Eval | 8% | **7.5** | 14 个 GS 场景（001-009, 011-015）+ eval-scenarios readiness | ⚠️ **缺 GS-010**（编号不连续）；无 LLM 执行器（promptfoo 未接入） |
| 8 | 测试覆盖 | 8% | **7.0** | harness 自测 10/10 + coverage 配置 | ⚠️ 阈值低（storefront/platform 仅 5%）且未持续执行 |
| 9 | 危险操作防护 | 8% | **9.0** | block_destructive_db.sh + warn_on_secrets.sh + scan-secrets 10 规则 + hooks.json | ✅ 双重防护（hook + 扫描器） |
| 10 | CI 集成 | 8% | **8.5** | 6 个 workflow 全监听 `[main, dev]` + lefthook pre-commit(4)+pre-push(1) | ✅ dev 推入即验证；不足：部分组件 CI 未含全量测试 |
| 11 | 分支策略 | 6% | **8.5** | dev 开发/集成 + main 生产 + R9 规则 + release README | ✅ 已规范化 |
| 12 | 文档导航 | 6% | **8.5** | AGENTS.md §0 导航地图（15 引用）+ nav:check 校验 + standards 索引 | ✅ 唯一路由表 |

**加权总分**：0.95+0.90+0.72+0.85+0.68+0.90+0.60+0.56+0.72+0.68+0.51+0.51 = **8.58 ≈ 8.6/10**

## 三、L 等级评估

| 条件 | 状态 |
|---|---|
| L3① CI 真实红绿 | ✅ harness-full + 6 组件 workflow |
| L3② git 物理拦截 | ✅ lefthook（pre-commit 4 项 + pre-push doc-impact）|
| L3③ gate 任务类型 + branch/HEAD 绑定 | ✅ 9 类型 + 绑定 |
| L4 候选：高覆盖率门槛 | ⚠️ 阈值低（5%）|
| L4 候选：全量测试常驻 | ⚠️ 未持续 |
| L4 候选：LLM Eval 执行器 | ⚠️ promptfoo 未接入 |

**结论**：L3 稳定达成；L4 差"覆盖率门槛提升 + 全量测试常驻 + Eval 执行器"三项。

## 四、改进建议（按优先级）

| 优先级 | 建议 | 影响维度 |
|---|---|---|
| P0 | 清理 94 个反模式 warning（含 storefront AP-009 .catch(()=>[])）| 4 |
| P0 | 补齐 GS-010 编号或重编号 | 7 |
| P1 | 提升 coverage 阈值并纳入 `check --profile full` 持续执行 | 8 |
| P1 | `prd verify` 支持删除类任务豁免（无测试 AC 标注允许）| 2 |
| P2 | 接入 promptfoo LLM Eval 执行器（GS 场景 → 真实 LLM 执行）| 7 |
| P2 | 全量测试常驻（nightly workflow 覆盖全部组件）| 8/10 |
| P3 | 各层 CLAUDE.md 与 §0 导航地图双检（nav:check 扩展）| 12 |

## 五、验证证据

- 命令全集：22 个 harness 命令（gate 5 + 分析 2 + 质量 9 + PRD 3 + 证据 2 + 其他）
- 规则库：反模式 10 条、doc-impact 15 规则、场景 14 个、任务规则 TR-xxx
- 门禁：pre-commit 4（gate:required/反模式/degraded-loop/secrets）+ pre-push 1（doc-impact）
- 自测：harness.test 10/10；doctor 11/11；反模式 0 error；eval-scenarios readiness 全通过
- 导航：nav:check 15 引用有效
