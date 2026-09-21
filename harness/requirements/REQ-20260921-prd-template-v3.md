# REQ-20260921-prd-template-v3

> 关联 PRD：`docs/prd/harness/PRD-20260921-harness-prd-template-v3.md`（状态 done）
> 关联 Task：`TASK-20260921005836-88540004`　门禁：`GATE-2026-09-21T00-58-54`（feature）
> 反模式版本：`harness/policies/anti-patterns.json`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `docs/prd` / `_TEMPLATE.md` / `prd new` / `prd verify` / `prd-template`（含视图/装饰器/订阅者） | 0 命中 | — |
| App — views/decorators | `backend/app/` | 同上 | 0 命中 | — |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/` | 同上 | 0 命中 | — |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/` | 同上 | 0 命中 | — |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/` | 同上 | `app/controllers/pallastrade/api/v3/store/catalog_events_controller.rb:10`（注释引用 PRD 路径） | ❌ 仅文档链接，无结构依赖 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/` | 同上 | 0 命中 | — |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/` | 同上 | 0 命中 | — |
| Storefront | `storefront/src/` | 同上 | 0 命中 | — |
| Platform | `platform/packages/` | 同上 | 0 命中 | — |

补充扫描（`harness/`、`scripts/ci/`、`.github/`、`tests/`，工具链依赖核实）：
- `harness prd new`：仅原样复制 `docs/prd/_TEMPLATE.md`（`harness.mjs` L1051-1062，不做结构解析）
- `harness prd verify`：全文匹配 `AC-(\d+)`，**忽略 HTML 注释**（L1140-1146）→ 章节号重排安全；模板示例放注释内不会成为 phantom AC
- `scripts/ci/prd-status-sync.mjs`：仅解析状态头行与索引行；`tests/prd-status-sync.test.mjs` 不依赖模板结构
- `harness eval-llm --generate`：promptfoo 产物生成器（`promptfooconfig.yaml` 头部声明「do not edit by hand / 改 scenarios.json 后重跑」）——发现 `gs-013.txt` 存在上次升级未重跑的既有漂移

### 搜索结论

<!-- 总结：哪些层已有能力？哪些层需要新建？若全部已有 → 任务完成，0 行新代码。 -->

六层**均无**按 PRD 模板结构消费的运行时代码（唯一命中为注释链接）。需要新建的是**知识层能力**：17 节模板结构、功能详述要件、`tests/prd-template-structure.test.mjs` 机器守卫；需要修复的是 **promptfoo 生成物漂移**（上轮漏跑生成器）。零运行时代码改动。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树「Settings → Configuration → Events → Dependencies → Admin / Ransack → Generators → Decorators → Extensions」——本任务不新增/修改任何应用行为，决策树全链路不适用（文档/工具链交付） |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读（定位浏览） | 「Admin 定制在 Gem 源文件原地改（PALLAS-CUSTOM 注释）+ 视图路径优先 host app」——本任务 0 触达 admin 控制器/视图/导航（6 层扫描 admin 零命中） |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读（定位浏览） | 目录图（Product/Variant/Category/搜索）——本任务 0 触达商品域（6 层扫描零命中） |

**按需 Skill（本次涉及）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-prd` | ☑ | ✅ 已读 | §2.3「模板已固化为 14 节（§0–§13）…模板是下限不是上限」+ 篇幅下限；§7「收尾五处同时核对」（①状态头 ②同步清单勾选 ③变更记录 ④README 索引 ⑤REQ 引用）→ **本任务即该清单的升级对象，五处均需按新编号同步**；§10 禁止「PRD 状态落后于代码」 |
| `harness-prd` | ☑ | ✅ 已读 | §5 简版 REQ 规范：改动 ≤5 文件且无逻辑变更可简版 → 本任务交付面 6+ 文件（模板/SKILL/场景库/promptfoo/AGENTS/config/测试），取**完整版 REQ** |
| `harness-docs` | ☑ | ✅ 已读 | §3 规则：更新后必须 `harness docs:check`（断链校验）+ 知识同步门 `doc-impact` 放行；草案→确认→写回 |
| `pallastrade-testing` | 评估 | ✅ 已评估 | RSpec/Capybara 域；本任务测试为仓库级 `tests/*.test.mjs`（node:test）守卫（既有 8 文件 + `harness.config.mjs` 注册模式），非 RSpec 域 |
| `pallastrade-api-v3` / `pallastrade-events-webhooks` / `pallastrade-storefront` / `pallastrade-i18n` 等 | 未涉及 | — | 无接口/事件/组件/文案改动（6 层搜索零命中） |

---

## 需求标题

PRD 模板 v3 升级：新增 UI / UX / 数据与埋点三节 + 功能详述 + 机器可检查结构守卫（17 节 §0–§16）

## 任务类型

功能优化（流程机制 / 知识工具链）

## 需求描述

用户指出 `docs/prd/_TEMPLATE.md`「还是太粗糙，缺少了 UI、UE、任务涉及的功能说明等」，要求「再一次升级成更标准的 PRD，内容更详细一点」。方案（用户已确认）：17 节完整方案——新增 §4 界面规格（UI）、§5 交互与体验（UX）、§6 数据与埋点；§3 拆出「3.2 功能详述」（八要件）；写作要求升级（篇幅下限 200/150/100 + 节级豁免 + 示例注释纪律）；并把「更标准」落为**机器可检查的结构守卫**。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 14,
  "affectedComponents": ["backend", "harness"],
  "errors": [],
  "estimatedTests": 42
}
```

> 注：`filesChanged: 14` 含**并行会话**的未提交改动（backend/payments 域 WIP）；本任务自身只触碰 `docs/`、`harness/`、`tests/`、`AGENTS.md`。

## 技术方案（初步）

| 文件 | 动作 | 说明 |
|---|---|---|
| `docs/prd/_TEMPLATE.md` | 重写 | 14 节 → 17 节（§0–§16）；§4/§5/§6 新增；§3.2 功能详述；写作要求升级；元数据增「目标用户」「界面影响」；示例统一放 HTML 注释 |
| `ai/skills/pallastrade-prd/SKILL.md` | 修改 | §2.3 清单→17 节；§7/§8 章节号引用修正（§9→§12 同步清单、§13→§16 变更记录、§10→§13 风险）；§11 变更记录 |
| `harness/scenarios/scenarios.json` | 修改 | GS-013 description/mustDo/mustNotDo 升级为 17 节契约 |
| `harness/promptfoo/**` | 再生成 | `harness eval-llm --generate`（生成器唯一权威；修复既有漂移） |
| `AGENTS.md` | 修改 | §6 验证矩阵新增「PRD 模板 → repo-guards-test」行；§7 同步门编号引用更新 |
| `harness.config.mjs` | 修改 | `repo-guards-test` 命令数组注册 `tests/prd-template-structure.test.mjs` |
| `tests/prd-template-structure.test.mjs` | 新增 | 结构守卫：§0–§16 序列 / 八要件 / 五件套 / 四件套 / 写作要求 / 跨文件一致（SKILL·GS-013·promptfoo）/ 元数据行；AC-001..009 标签 |
| `harness/requirements/REQ-20260921-prd-template-v3.md` | 新增 | 本文件 |
| `docs/prd/README.md` | 修改 | 索引新增一行（`prd-status-sync` 守门） |

硬约束：零运行时代码改动；历史 PRD 不回改（新模板为超集）；`prd verify`/`prd-status-sync` 行为不依赖章节号（已核实）。

## 风险点

| # | 风险 | 缓解 |
|---|---|---|
| R-1 | 存在按章节号解析的未知消费方 | 已全仓核实（含「章节号」语义扫描）；守卫测试覆盖结构完整性 |
| R-2 | 新模板过重 → 后续 PRD 灌水 | 三档下限 + 节级豁免 + 示例注释纪律；用户可随时降档（S-4/USER） |
| R-3 | `harness.config.mjs` 被并行会话覆盖（仓库实测过） | 编辑前 diff、提交前 `git diff --cached` 逐文件核对、`git show --stat` 复核 |
| R-4 | promptfoo 再生成产生大面积 diff | 先 `git diff --stat` 评估；契约性变化整体纳入（生成器权威） |
| R-5 | 守卫过严/脆弱 | 断言基于标题正则与关键词（非快照）；负例自证（注释掉 §5 子节→红） |

回滚：`git revert <本次提交>`（或按文件 `git checkout` 旧版 + 同步回退 SKILL/GS-013/promptfoo）；回滚后必跑 docs:check + repo-guards-test + eval-ai --scenarios。

## 决策节点

> ⏸️ **请确认以上理解与方案是否正确。确认（"确认/实施"）后 AI 将执行：清 `user-confirmed` → 按方案实施 → 证据链 → 提交 dev。**
> 若你希望调整（如篇幅下限、豁免规则、是否需要数据与埋点节），请直接指出。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 模板/守卫测试 | `docs/prd/_TEMPLATE.md`、`tests/prd-template-structure.test.mjs`、`harness.config.mjs` | `harness verify repo-guards-test --task TASK-20260921005836-88540004` | 62/62 全绿（含新守卫 9 用例） | ✅ |
| 知识同步 | Skill/场景库/promptfoo/AGENTS | `harness docs:check` + `harness eval-ai --scenarios` + `harness doc-impact --base origin/dev` | docs:check 279 文档 0 断链 · eval-ai 206/206 · doc-impact 3 synced / 0 missing | ✅ |
| AC 映射 | PRD 9 条 AC | `harness prd verify --id PRD-20260921-harness-prd-template-v3` | 全部 AC 有测试覆盖（22 处引用全通过） | ✅ |
| 守卫负例自证 | 破坏 §5.2 子节标题后重跑守卫 → 还原 | 守卫红且点名缺失子节 → 还原后绿 | exit=1 fail 1，点名「缺少子节：### 5.2 反馈机制」；还原字节一致 → 9/9 绿 | ✅ |

### 新增 admin 页面三要素检查（固定检查项）

本任务无 admin 页面改动 → **不适用**。

### 验证结论

<!-- 实施后填写：逐条通过/失败与修复记录。 -->

逐条通过（2026-09-21）：模板 §0–§16 重写 381 行；守卫 9 用例全绿且负例自证有效；GS-013 升级后 eval-ai 206/206；promptfoo 全量再生成（15 → 206 场景）；docs:check / doc-impact 全绿；`prd verify` 全部 AC 有测试覆盖。零失败、零返工。收尾时状态/清单/变更记录/索引/REQ 五处已同时核对。
