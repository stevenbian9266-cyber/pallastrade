# RESEARCH-20260831-harness-token-optimization.md

# Harness 引擎 Token 优化方案（pallastradeharness 版）

> 目标：在不削弱 harness 对项目的约束与监督（gate 机制、跨层搜索、反模式拦截、证据验证、知识同步、危险操作拦截）的前提下，降低接入 harness 后的 token 消耗。
>
> 适用对象：**pallastradeharness 引擎项目**（`github.com/stevenbian9266-cyber/pallastradeharness`）。宿主侧优化已于 2026-08-31 在 PallasTrade 仓库实施（见该仓库 git 记录），本文件仅保留引擎侧可移植优化。
>
> 创建：2026-08-31 ｜ 状态：draft ｜ 类型：引擎优化蓝图

---

## 1. 背景与目标

### 1.1 问题

接入 harness（1.7.0 → 1.8.0）后，AI 编码会话的 token 消耗明显增多（估算 3-5 倍）。经实测定位，消耗主要来自：

1. **每会话固定注入**：`AGENTS.md`（27.5KB）+ `copilot-instructions.md`（10.3KB）+ user memory（12.6KB）+ 系统提示/工具 schema
2. **任务流程产物**：feature 档强制 PRD + REQ + 4 个设计文档 + 24 项 gate 检查
3. **AI 读取量**：强制读 3 个 SKILL（平均 ~28KB）+ 模板 + 引擎源码
4. **命令输出**：task list（6.8KB）等（实测单命令输出不大，但累计可观）

### 1.2 目标

- **不削弱约束监督**：gate、反模式、证据、知识同步、危险操作拦截全部保留
- **降低 token 消耗**：每会话固定成本 -30~40%，每任务增量成本 -45~55%（宿主已实施部分 + 引擎可移植部分）
- **可执行**：给出引擎项目的具体改动（文件/函数/代码），供移植到 pallastradeharness 仓库

### 1.3 成功指标

- 每会话固定注入 ≤ 20KB（当前 ~50KB）
- feature 任务 gate 检查数 ≤ 12 项（当前 24 项）
- 单个普通任务 token 消耗降低 ≥ 40%

---

## 2. Token 消耗构成（实测数据）

### 2.1 每会话固定成本（~27-38K tokens）

| 来源 | 大小 | 折算 tokens | 优化项 |
|---|---|---|---|
| `AGENTS.md`（自动注入） | 27.5KB | ~7K | 宿主已实施（瘦身 25.2KB） |
| `.github/copilot-instructions.md`（自动注入） | 10.3KB | ~2.5K | 宿主已实施（瘦身 6.3KB） |
| user memory（自动加载前 200 行） | 12.6KB | ~3K | 宿主已实施（清理） |
| 系统提示 + 工具 schema | — | ~15-25K | 环境级（难改，可裁剪工具暴露） |

### 2.2 每 feature 任务增量成本（~25-35K tokens）

| 环节 | 规模 | 优化项 |
|---|---|---|
| 强制读 3 个 SKILL（customization 10.4K + prd 1.9K + 领域均值 15.4K） | ~28KB ≈ 7K | 引擎 6.3（check 可配置化） |
| 读 PRD/REQ 模板 | ~8KB ≈ 2K | 引擎 6.5（模板随包精简） |
| 写 PRD + REQ + 4 设计文档 | ~25-30KB ≈ 6-8K | 引擎 6.2（designStage 分级） |
| harness 命令输出累计 | ~20KB ≈ 5K | 引擎 6.1 / 6.4 |
| 调查读引擎源码/配置 | ~20-50KB ≈ 5-12K | 操作习惯（宿主已实施） |

### 2.3 实测修正（重要）

- `gate:clear` 单次回显仅 ~150 字符（**不是** 16KB）
- `brain context` 命令输出仅 0.1KB（不把 24 资产塞进对话）
- `task list` 是单命令输出最大者（6.8KB，80+ 历史任务）
- **真正大头 = 固定注入文件 + AI 读写的文档量 + 任务流程产物**

### 2.4 历史积累规模

- `harness/gates/`：230 个 gate 文件（696KB）
- `harness/requirements/`：79 个 REQ
- `docs/prd/`：48 个 PRD（479KB）
- `docs/designs/`：8 个设计文档（1.8.0 后开始产生）

---

## 3. 引擎侧优化方案总览

| 项 | 改动位置 | 节省（每任务） | 约束影响 | 风险 |
|---|---|---|---|---|
| 3.9 gate 输出精简 | `bin/harness.mjs` / `bin/gate-lifecycle.mjs` | -3~5K | 无 | 低 |
| 3.10 check 可配置化 | `bin/config-loader.mjs` | -5~10K | 按配置（默认零变化） | 中 |
| 3.11 designStage 分级 | `bin/config-loader.mjs` | -5~10K | 无 | 中 |
| 3.12 task list 裁剪 | `bin/task-orchestrator.mjs` | -1K | 无 | 低 |
| 3.13 前缀档位引导 | CLI/文档 | -10~20K（配合宿主） | 规则正当用法 | 低 |
| 3.14 token 统计工具 | `bin/metrics.mjs` | 长期（可度量） | 无 | 低 |
| 3.15 模板随包精简 | `templates/prd/`、`templates/req/` | -2~4K | 无 | 低 |

---

<!-- §4 宿主侧优化（harness.config.mjs 配置 / AGENTS.md / copilot-instructions / user memory / 操作习惯）已于 2026-08-31 在 PallasTrade 仓库实施，本引擎版已移除。 -->

---

<!-- §5 宿主模板精简（docs/prd/_TEMPLATE.md / harness/requirements/_TEMPLATE.md / REQ 简版规范）已于 PallasTrade 仓库实施，本引擎版移除。引擎模板随包精简见 §6.5。 -->

---

## 6. 引擎项目可实施（pallastradeharness 侧）

> 以下为 **`github.com/stevenbian9266-cyber/pallastradeharness`** 引擎的优化建议，按文件/函数定位。

### 6.1 gate 输出精简（低风险）

**文件**：`bin/harness.mjs` / `bin/gate-lifecycle.mjs`

| 改进 | 位置 | 说明 |
|---|---|---|
| gate 创建支持 `--quiet` | `bin/harness.mjs` gate 命令 | 只输出 check 计数 + 必读提示，不输出全部 check 列表（默认全量保留） |
| `gate:clear` 回显精简 | `gate-lifecycle.mjs` recompute/print | 只显示"变更项 + 剩余计数 + 未清项 id"，不重复输出 check 描述 |
| `gate:status` 增加 `--short` | 同上 | 单行输出状态 |

### 6.2 designStage 分级（中风险，收益大）

**文件**：`bin/config-loader.mjs`（`DESIGN_STAGE_CHECKS` 插入逻辑）

当前：`designStage.enabled=true` 时所有 feature 任务强制 4 设计文档。

建议：支持三级：
```js
designStage: {
  enabled: 'auto',   // false | true | 'auto'
  designsDir: 'docs/designs',
  // auto：按任务关键词判断——含 ui/页面/组件/交互/视觉 关键词才强制
  uiKeywords: ['ui', '页面', '组件', '交互', '视觉', '样式', 'storefront', 'dashboard'],
}
```
`auto` 模式：任务描述命中 `uiKeywords` 才插入设计检查；否则跳过（保留 `design-confirmed` 为可选）。

### 6.3 内置 check 可配置化（中风险）

**文件**：`bin/config-loader.mjs`（`getGateChecks`）

当前：`BASE_CHECK_DEFS` 引擎内置，项目 config 只能**追加**（按 id 去重），无法删除。

建议新增配置项：
```js
gates: {
  // 允许项目禁用内置 check（默认全保留）
  disableChecks: {
    feature: ['read-skill-prd', 'create-prd-doc'],  // 示例：轻档项目
  },
}
```
实现：`getGateChecks` 中 `merged.filter(c => !disabled.has(c.id))`。默认 `disableChecks` 为空 → **约束零变化**，仅需要的项目自行降档。

### 6.4 task list / 输出裁剪（低风险）

| 改进 | 位置 | 说明 |
|---|---|---|
| `task list` 默认只显示最近 20 个 + `--all` 全量 | `bin/task-orchestrator.mjs` | 避免 80+ 任务 6.8KB 全量 |
| `task list` 支持 `--status` 过滤 | 同上 | `--status active/planned/completed` |
| 统一输出宽度参数 | `bin/cli-utils.mjs` | 全局 `--width` 控制表格换行 |

### 6.5 PRD/REQ 模板随包精简

**文件**：`templates/prd/_TEMPLATE.md`、`templates/req/_TEMPLATE.md`（引擎内置模板）

- 删除"⚠️ 示例/注释"说明块
- 保留结构骨架
- 与宿主侧 5.1/5.2 同步

### 6.6 token 统计工具（长期，可度量）

**文件**：`bin/metrics.mjs`（1.8.0 已有本地匿名指标）

扩展 `harness metrics` 输出：
- 每个 task 的：命令调用次数、输出总字节、产物文档数（PRD/REQ/designs）
- 会话级汇总：固定注入大小 + 任务增量
- 目的：让 token 优化可量化、可回归（防止未来版本回退）

### 6.7 config-loader 增加输出级可调项

**文件**：`bin/config-loader.mjs`（`DEFAULT_CONFIG`）

新增（默认保守，项目按需开启）：
```js
output: {
  gateListVerbose: true,     // gate 创建/clear 是否输出全部 check（默认 true 保兼容）
  taskListDefaultLimit: 20,  // task list 默认条数（0=全量）
  requireSkillRead: true,    // gate 强制读 skill（默认 true 保约束）
}
```

---

## 7. 引擎侧实施计划

> 宿主侧阶段（配置/模板/注入文件/操作习惯）已于 2026-08-31 在 PallasTrade 仓库实施。以下为 **pallastradeharness 引擎**的迭代计划。

### 阶段 D1：低风险输出精简（建议 v1.9.0）

- [ ] 6.1 gate 输出精简（gate 创建 `--quiet`、`gate:clear` 回显、`gate:status --short`）
- [ ] 6.4 task list 裁剪（默认 20 条 + `--all` + `--status` 过滤）
- [ ] 6.5 模板随包精简

### 阶段 D2：中风险能力分级（建议 v1.10.0）

- [ ] 6.2 designStage 分级（`enabled: 'auto'` + uiKeywords）
- [ ] 6.3 check 可配置化（`gates.disableChecks`，默认空=约束零变化）
- [ ] 6.7 config-loader 输出级可调项（`output` 段）

### 阶段 D3：可度量（建议 v1.11.0+）

- [ ] 6.6 token 统计工具（`metrics` 扩展：每 task 命令数/输出字节/产物文档数）
- [ ] 3.13 前缀档位引导文档
- [ ] 回归：`node --test` 全量 + 宿主实测前后对比

---

## 8. 验证与效果评估

### 8.1 每项改动的验证方式

| 改动 | 验证 |
|---|---|
| 6.1 gate 输出精简 | 引擎 `node --test` 契约测试（输出格式断言）+ 宿主实测 |
| 6.2 designStage 分级 | 宿主配置 `enabled:'auto'` 后，UI/非 UI 任务 gate 检查数差异 |
| 6.3 check 可配置 | 引擎 `node --test` 契约测试 + 宿主实测（默认行为不变） |
| 6.4 task list 裁剪 | `task list` 默认 ≤20 条，`--all` 全量 |
| 6.6 metrics | `harness metrics` 输出每 task token 相关指标 |

### 8.2 总体效果评估

| 维度 | 当前 | 目标 |
|---|---|---|
| 每会话固定注入 | ~50KB | ≤20KB |
| feature gate 检查数 | 24 | ≤12（或按档位 7-17） |
| 单任务 token | ~25-35K | ~12-18K |
| 综合节省 | — | **40-60%** |

### 8.3 回归防线

- 引擎改动必须有契约测试（`node --test` 全量 274+ 通过）
- 约束核心（gate/反模式/证据/知识同步/危险操作）**默认行为零变化**，降档是项目显式配置
- 用 `harness metrics` 跟踪 token 相关指标，防回退

---

## 9. 附录

### 9.1 关键文件索引（引擎侧）

| 文件 | 作用 |
|---|---|
| `pallastradeharness/bin/config-loader.mjs` | 引擎 check 生成（6.2/6.3/6.7） |
| `pallastradeharness/bin/harness.mjs` | 引擎 CLI 入口/输出（6.1） |
| `pallastradeharness/bin/gate-lifecycle.mjs` | gate 状态输出（6.1） |
| `pallastradeharness/bin/task-orchestrator.mjs` | task list 输出（6.4） |
| `pallastradeharness/bin/cli-utils.mjs` | 输出宽度控制（6.4） |
| `pallastradeharness/bin/metrics.mjs` | 引擎指标（6.6） |
| `pallastradeharness/templates/prd/`、`templates/req/` | 引擎模板（6.5） |

### 9.2 约束不可动清单（红线）

以下**必须保留**，任何优化不得削弱：
- ✅ Gate 机制（改代码前强制）
- ✅ 6 层跨层搜索
- ✅ 反模式拦截（AP-001~009，CI 执行）
- ✅ verify-test 证据控制（截图/日志/DB，禁止手工 clear）
- ✅ 知识同步门（doc-impact / sync-check）
- ✅ 危险操作物理拦截（db:drop / force-push / 密钥写入）
- ✅ user-confirmed 由用户明确确认

### 9.3 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-31 | 0.1 | 初稿（完整版：宿主 + 引擎） | AI |
| 2026-08-31 | 0.2 | 引擎版：移除宿主侧章节（§4/§5），§3/§7/§8/§9 改为引擎视角，供移植到 pallastradeharness | AI |
