# Harness 工程化机制评级报告（2026-08-08 第三次）

> 审计任务：再次审计 harness 评级，确认是否达到顶级
> 对比上次：2026-08-08 第二次评级 **8.6/10, L3（向 L4 过渡）**

---

## 一、总分：8.6 / 10（L3 稳定，**尚未达到顶级**）

较上次持平（改进项被 freshness 回归抵消）。**顶级（L4/L5）未达成**——L4 三项候选仍有 3 项未完成（见 §三）。

## 二、12 维度评分明细

| # | 维度 | 权重 | 评分 | 依据 | 变化 vs 上次 |
|---|---|---|---|---|---|
| 1 | 门禁机制 (gate) | 10% | **9.5** | gate 创建/清除/status/required/clean；9 种任务类型；绑定 branch+HEAD；lefthook pre-commit 强制 | — |
| 2 | 需求与 PRD 工作流 | 10% | **9.2** | REQ/PRD 模板 + 15 分类 + `prd new/list/verify` + AC↔测试追溯 + **`--allow-missing-tests` 豁免（已实施）** | ↑ 9.0→9.2 |
| 3 | 跨层搜索 | 8% | **9.0** | 6 层强制 + AP-SEARCH-1/2/3 + gate search checks | — |
| 4 | 反模式库 | 10% | **9.0** | 10 条 AP（guard-aware）+ CI/lefthook 强制 + **全仓 0 error / 10 warning（全部为动态样式合理例外，GS-010 认可）** | ↑ 8.5→9.0 |
| 5 | 验证与证据 | 8% | **8.5** | verify-test + 证据矩阵（截图/日志/DB）+ evidence 采集 | — |
| 6 | 知识同步 | 10% | **8.5** | doc-impact 15 规则 + sync-check 门 + nav:check（15 引用有效） | ↓ 9.0→8.5（freshness 回归） |
| 7 | 场景库/Eval | 8% | **8.0** | **GS-001~015 连续（GS-010 已补齐）+ 15/15 valid + readiness 12 checked**；仍无 LLM 执行器（promptfoo） | ↑ 7.5→8.0 |
| 8 | 测试覆盖 | 8% | **7.0** | backend 80/60；**storefront/platform 仍 5%**；未持续执行（无 nightly 常驻） | — |
| 9 | 危险操作防护 | 8% | **9.0** | block_destructive_db.sh + warn_on_secrets.sh + scan-secrets + hooks.json 双重防护 | — |
| 10 | CI 集成 | 8% | **8.5** | **7 个 workflow**（ai/backend/harness-full/monorepo-contract/platform/release-manifest/storefront）全监听 [main, dev] + lefthook | — |
| 11 | 分支策略 | 6% | **8.5** | dev 开发/main 生产 + R9 + release README | — |
| 12 | 文档导航 | 6% | **8.5** | AGENTS.md §0 导航地图 + nav:check 校验 + standards 索引 | — |

**加权总分**：0.95+0.92+0.72+0.90+0.68+0.85+0.64+0.56+0.72+0.68+0.51+0.51 = **8.64 ≈ 8.6/10**

## 三、L 等级评估（是否达到顶级）

| 条件 | 状态 |
|---|---|
| **L3 基础**（CI 红绿 + git 物理拦截 + gate 绑定） | ✅ 全部稳定达成 |
| **L4①** 高覆盖率门槛 | ⚠️ backend 达标(80/60)，但 **storefront/platform 仅 5%**，未提升 |
| **L4②** 全量测试常驻 | ⚠️ **无 nightly workflow**，全量测试未持续执行 |
| **L4③** LLM Eval 执行器 | ⚠️ **promptfoo 未接入**（GS 场景仅 readiness/静态校验） |
| **L5（顶级）** | ❌ 依赖 L4 全达成，当前不满足 |

**结论**：**8.6/10，L3 稳定成熟，尚未达到顶级（L4/L5）**。距离 L4 差三项：①覆盖率门槛提升 ②全量测试常驻 ③LLM Eval 执行器。

## 四、本次审计发现的问题（新）

| 优先级 | 问题 | 影响 |
|---|---|---|
| P1 | **freshness 4 errors**（skill 引用失效路径）：`pallastrade-storefront/SKILL.md` 引用 `lib/emails/`（不存在）；`pallastrade-typescript-sdk/SKILL.md` 引用 `packages/admin-sdk/src/admin-client.ts`（不存在）——skill 文档路径过时未同步 | 维度 6/7 |
| P2 | freshness 检查器**不解析 glob 路径**（`storefront/src/**/__tests__/*.test.tsx` 实际存在但被报 not found）——误报源，应支持 glob | 维度 6 |
| P3 | GS-015 readiness 无 checks 定义（eval-scenarios 提示） | 维度 7 |

## 五、验证证据（本次实测）

| 项 | 结果 |
|---|---|
| `doctor` | ✅ 11/11 |
| `test:harness`（契约测试） | ✅ 11/11（含 `prd verify --allow-missing-tests` 新用例） |
| `eval-ai --scenarios` | ✅ **15/15 valid**（GS-001~015 连续） |
| `eval-scenarios --readiness` | ✅ 12 scenarios checked，critical capabilities ready |
| `eval-ai --check-freshness` | ⚠️ **4 errors**（2 处真实过时 + 2 处 glob 误报） |
| 反模式扫描（全仓） | ✅ **0 error / 10 warning**（动态样式合理例外） |
| `nav:check` | ✅ 15 引用有效，各层 CLAUDE 引用完整 |
| CI workflows | ✅ 7 个全监听 [main, dev] |

## 六、改进建议（按优先级）

| 优先级 | 建议 | 目标维度 |
|---|---|---|
| P0 | 修复 freshness：更新 skill 文档中失效路径（`lib/emails/`、`admin-client.ts`），并让 freshness 检查器支持 glob | 6/7 |
| P1 | 提升 storefront/platform coverage 阈值（5%→更高）并纳入 `check --profile full` 持续执行 | 8 |
| P1 | 新增 nightly workflow（全组件全量测试 + coverage 门禁常驻） | 8/10 |
| P2 | 接入 promptfoo LLM Eval 执行器（GS 场景 → 真实 LLM 执行） | 7 |
| P2 | 补齐 GS-015 readiness checks 定义 | 7 |
| P3 | 清理 10 个合理例外 warning 的豁免标注（显式 allowlist 而非默认忽略） | 4 |

**总体评价**：工程化机制成熟、闭环完整，作为"私有化电商平台"的 AI 编码治理体系已达到 L3 顶配；但要达到**顶级（L4/L5）**，核心差距在**质量数据闭环**（覆盖率门槛 + 常驻全量测试 + LLM Eval）与 **skill 文档新鲜度回归**。
