# Harness 通用化升级方案 —— AI 原生工程操作系统 v2

> 背景：`pallastrade` 是 harness 的实际应用验证场（dogfood）。本方案的目的是把
> **PallasTrade 定制实现产品化为通用机制**——让任意项目（从 0 开始或存量代码库）
> 都能一键接入，并获得三大核心能力：
>
> 1. **Auto-Standards**：读懂业务代码 → 自动生成/维护规范与规则
> 2. **Auto-Skills**：自动生成领域 Skill 文件并注册
> 3. **Auto-Docs**：自动编写 PRD / 任务文档 / 知识文档正文（pallastrade 已验证，需通用化）
>
> 现状基线（2026-08-12 调研）：引擎 `pallastrade-harness@1.0.4` 已具备
> gate/standards/supervise/task/brain/evidence/recovery/knowledge/adapter/mcp/analyze/init/prd 等能力；
> PallasTrade 定制层含 25+ 领域 Skill、规范注册表、Policies、PRD 工作流。

---

## 一、战略定位升级：从"定制治理工具"到"通用操作系统"

### 1.1 三层架构（通用性的根基）

```text
┌─ ③ 项目定制层（每个项目自持，git 内）─────────────────────────┐
│   harness.config.mjs         项目结构声明（layers/gates/standards…）│
│   ai/skills/                 领域 Skill（AI 生成 + 人确认）          │
│   harness/standards/*.json   项目规范（AI 生成 + 人确认）            │
│   harness/policies/*.json    反模式 / 任务规则 / PRD 分类            │
│   docs/prd/  docs/standards/ 文档资产                               │
├─ ② 通用内容资产层（随 npm 包分发，可覆盖）────────────────────┤
│   presets/                   single / nextjs / rails / monorepo…     │
│   skills/                    通用 Skill 模板库（standards-audit /    │
│                              skill-author / prd / docs…）            │
│   templates/                 PRD / REQ / SKILL / standards 模板      │
│   rules/                     通用规范基线（base-standards.json）      │
├─ ① 引擎层（pallastrade-harness 包，确定性、零 LLM）─────────────┤
│   CLI + MCP + 校验器 + 门禁 + 证据 + 状态存储                        │
└────────────────────────────────────────────────────────────────┘
```

**关键原则**：
- 引擎层**永不内置 LLM**（保持确定性、零依赖、可测试）；内容生成全部委托 AI
- 通用资产层**可被项目覆盖**（项目特定规则优先于通用规则）
- 项目定制层是唯一的"项目特定入口"——这就是为什么 `pallastrade` 的经验能迁移到任意项目

### 1.2 Dogfood 策略

- `pallastrade` 是**验证场**：每个新能力先在 PallasTrade 真实跑通，再抽象进通用资产层
- 每条通用能力必须附"从 PallasTrade 提炼的验收证据"（如 15 个 PRD、25+ Skill 已验证）

---

## 二、能力 A：Auto-Standards —— 读懂代码自动生成规范

### 2.1 现状缺口

- 规范目前是**手写**的 `harness/standards/pallastrade.json`（schema 已具备：id/category/title/authority/scope/severity/enforcement/evidence/fix/exception/knowledgeImpact）
- `harness analyze` 只输出"差距报告 + 配置草案"，**不生成规范内容**
- `harness standards coverage` 能报告缺口，但**没有闭环补全**

### 2.2 设计方案

**新增命令 `harness standards generate`**（引擎层）：

```text
harness standards generate [--domains db,api,security] [--write] [--dry-run]
```

流程（AI 生成 + 引擎校验闭环）：

```text
① harness analyze                 → 技术栈/层/差距基线
② harness doctor + coverage       → 缺失规范清单
③ AI（读业务代码 + 反模式扫描结果 + 现有规范风格）→ 生成规范 JSON 草案
④ harness standards validate      → schema 校验（新命令）
⑤ harness standards list          → 加载验证（防损坏注册表）
⑥ 人确认 → 写回 harness/standards/*.json
⑦ coverage 复测                   → 缺口收敛，迭代至达标
```

**通用 Skill `harness-standards-audit`**（随包分发，AI 生成规范的方法论）：

```
- 输入：analyze 报告、doctor 输出、反模式命中、领域代码样例
- 输出：符合 Standard schema 的 JSON（含 authority/scope/enforcement/evidence/fix）
- 约束：从内置 base-standards.json 继承通用项；只补项目特有项；
        每类至少 1 条；enforcement 如实标注（deterministic 才配 verifier）
- 产出物：harness/standards/{project}.json + 更新 docs/standards/README.md 索引
```

**引擎改动清单**：

| 改动 | 说明 |
|------|------|
| `standards generate` 命令 | 组装 AI 工作流（dry-run 优先，写回前自动备份） |
| `standards validate` 命令 | schema/字段级校验 + 加载冒烟测试 |
| `standards gap` 命令 | 基于 coverage + 代码扫描输出"规范缺口+建议" |
| 内置 `skills/harness-standards-audit/` | AI 方法论 skill |

---

## 三、能力 B：Auto-Skills —— 自动生成领域 Skill

### 3.1 现状缺口

- PallasTrade 已有 25+ 领域 SKILL.md（frontmatter: `name` + `description`），**但全部手工创建**
- harness 只有结构校验（`plugin-structure-check.mjs`），**没有生成与注册闭环**
- 注册依赖手改 `AGENTS.md §0.1` + `ai/README.md` + §0.2 路由表

### 3.2 设计方案

**新增命令 `harness skill new`**（引擎层）：

```text
harness skill new --domain payments          # 生成 SKILL.md 骨架 + 自动注册
harness skill check [--files ...]            # 结构/索引一致性校验（复用现有检查）
harness skill list --json                    # 领域清单 + 注册状态
```

**通用 Meta-Skill `harness-skill-author`**（随包分发，AI 生成 skill 的方法论）：

```
- 输入：新领域代码路径、命名约定、现有 skill 风格样例
- 提炼：领域概念图 → 常用操作 → 常见报错/陷阱 → 权威文件索引
- 输出：SKILL.md（frontmatter 合规 + description 含触发短语）
- 注册：更新 AGENTS.md §0.1 规范总表 + §0.2 任务路由 + ai/README.md 索引
- 校验：harness skill check 通过后才算完成
```

**注册闭环（引擎自动完成，替代手改）**：

```text
harness skill new --domain xxx
  → 生成 ai/skills/xxx/SKILL.md 骨架
  → 自动在 AGENTS.md §0.1 / ai/README.md 插入索引行
  → AI 填充正文 → harness skill check 校验
  → 人确认 → 生效
```

---

## 四、能力 C：Auto-Docs —— 自动写 PRD/任务文档（通用化）

### 4.1 已验证的机制（pallastrade 实证）

```text
一句话需求
  → ai/skills/pallastrade-prd/SKILL.md（触发判定 + 完整工作流）
  → harness prd new（自动分类 + 查重 >0.3 阻止 + 幂等）
  → docs/prd/_TEMPLATE.md（AI 强制扩充正文：背景/FR/AC/跨层搜索/测试计划/文档清单）
  → gate 强制（PRD 不完成无法进入实施）
  → 证据 + 知识同步 + 收尾
```

**这是已经跑通的模式**（15 个 AI 生成的 PRD 文件为证）。通用化目标：把
`pallastrade-prd` 从"项目定制"抽象为"可配置通用能力"。

### 4.2 通用化设计

**通用 Skill `harness-prd`**（随包分发）+ **可插拔模板**：

```text
presets/nextjs → templates/prd/nextjs/_TEMPLATE.md
presets/rails  → templates/prd/rails/_TEMPLATE.md
presets/single → templates/prd/single/_TEMPLATE.md
项目可覆盖      → docs/prd/_TEMPLATE.md（优先）
```

- 模板通过 `harness.config.mjs` 的 `prd.categories`（替代手写 `prd-categories.json`）声明分类
- 跨层搜索表由 `layers` 自动生成（不再硬编码 6 层）
- `harness prd new` 已支持自动分类+查重，**引擎无需大改**，主要补"模板路由 + 分类配置化"

**新增 `harness docs generate`**（知识文档自动起草）：

```text
harness docs generate --asset README.md          # 基于 doc-impact 命中的资产起草更新
harness docs generate --api                      # 基于路由/序列化器生成 API 文档草案
harness docs generate --type prd --title "..."   # 复用 prd new（已有）
```

原则：**AI 起草 → 人确认 → 写回**；生成的文档必须可被 `docs:check`（断链校验）与
`doc-impact`（知识同步门）验证，防止生成物"漂移失联"。

---

## 五、冷启动产品化：从 0 / 存量项目一键接入

### 5.1 两条接入路径

```text
路径 1：从 0 开始（新项目）
  harness create my-app --stack nextjs|rails|single|monorepo
    → 脚手架 + harness init（自动）+ 生成首个规范/Skill/PRD 模板
    → 立刻具备完整生命周期

路径 2：存量项目（brownfield，核心场景）
  harness onboard
    → analyze（技术栈/层/差距）
    → doctor（缺什么）
    → AI 生成规范草案（能力 A）+ 首轮 Skill 草案（能力 B）
    → 人确认 → gate 激活 → 进入受治理开发
```

### 5.2 Onboard 交互式仪表盘

```text
harness onboard
┌─ 接入进度 ─────────────────────────────┐
│ ✅ 1. 项目识别（stack/layers/commands）│
│ ✅ 2. 配置生成（harness.config.mjs）    │
│ ⬜ 3. 规范生成（0/8 类，AI 起草中…）    │
│ ⬜ 4. Skill 生成（0/6 领域，AI 起草中…）│
│ ⬜ 5. 模板就绪（PRD/REQ/证据）          │
│ ⬜ 6. Gate 激活（lefthook 接入）        │
│ ⬜ 7. 基线审计（anti-patterns/secrets） │
└────────────────────────────────────────┘
每步可单独重跑；全部完成 = 从"无规范"到"受治理"。
```

---

## 六、知识闭环增强（Knowledge Loop 2.0）

现状：`doc-impact` / `sync-check` 已能**识别**受影响知识资产，但只强制"去同步"这个动作。

升级：**AI 起草 + 人确认 + 自动写回**

```text
代码变更
  → doc-impact 识别受影响资产（AGENTS/Skill/README/API 文档/PRD）
  → AI 按模板起草更新内容（复用能力 A/B/C 的生成器）
  → 人确认（diff 审查）→ 写回
  → ai/memories/*.md 沉淀架构决策（已有 memories 目录约定）
  → KnowledgeAsset 记录来源文件 hash + 最后验证时间（防过期漂移）
```

---

## 七、MCP 增强：让任意客户端获得三大能力

在现有 10 个 MCP tools 基础上新增：

```text
generate_standards   → 触发能力 A（AI 生成规范草案）
generate_skill       → 触发能力 B（AI 生成 skill 草案）
generate_docs        → 触发能力 C（PRD/知识文档起草）
```

任何 MCP 客户端（VS Code、Claude Desktop、Codex）都可直接调用，**无需懂 CLI**。

---

## 八、通用内容资产包（随 npm 包分发）

| 资产 | 内容 | 状态 |
|------|------|------|
| `presets/` | single / nextjs / rails / monorepo / pallastrade（新增 `api-only`、`miniapp`） | ✅ 已有，需补 |
| `skills/` | harness-standards-audit / harness-skill-author / harness-prd / harness-docs | 🆕 新增 |
| `templates/` | PRD / REQ / SKILL / standards / 文档模板（按 preset 分栈） | 🆕 新增 |
| `rules/` | base-standards.json（380 行已有）+ 分语言反模式基线（rb/ts/py/go） | ✅ 已有，需扩展 |
| `examples/` | 一个最小完整示例项目（含生成的规范/Skill/PRD 全套） | 🆕 新增 |

---

## 九、版本与迁移

### 9.1 版本规划

```text
v1.x（当前）  确定性治理壳：gate/standards/supervise/evidence/mcp
v2.0          通用化三大能力：standards generate / skill new / docs generate
              + onboard 冷启动 + 内容资产包 + MCP 增强
```

### 9.2 兼容迁移（存量项目平滑升级）

- 所有新增命令 **dry-run 优先**，写回前自动备份（沿用 `state:migrate` 模式）
- `harness.config.mjs` schema 向后兼容（新增字段可选）
- 现有 `prd-categories.json`、`standards/*.json` 结构不变，仅增加"生成"入口
- 提供 `harness migrate v1-to-v2 --dry-run` 预检

### 9.3 工程质量

- 每个新命令配套 `*.test.mjs`（沿用现有 node --test 模式）
- Windows/macOS/Ubuntu × Node 22/24 CI（已有）
- npm OIDC trusted publishing + SLSA provenance（已有）
- 文档站同步更新（docs/commands.md 等）

---

## 十、实施路线图

| Phase | 内容 | 验收标准 |
|-------|------|---------|
| **P1** | 能力 A：`standards generate/validate/gap` + `harness-standards-audit` skill | 在 `pallastrade` 生成 ≥3 类新规范并过 coverage |
| **P2** | 能力 B：`skill new/check/list` + `harness-skill-author` skill + 自动注册 | 在 `pallastrade` 用命令生成 1 个新领域 skill 并注册成功 |
| **P3** | 能力 C 通用化：`harness-prd` skill + 模板路由 + `docs generate` | 用一个全新示例项目（非 Rails）跑通 PRD 自动生成 |
| **P4** | 冷启动：`harness create` + `harness onboard` 仪表盘 | 从 0 项目 10 分钟内完成接入；存量项目 30 分钟内 |
| **P5** | MCP 增强 + 内容资产包 + 示例仓库 + 文档站 | 任意 MCP 客户端可调 generate_* 三工具 |

> 每 Phase 以 `pallastrade` dogfood 为第一验证场，通过后再抽象进通用层。

---

## 十一、风险与边界（诚实声明）

1. **不替代人**：AI 生成的规范/Skill/文档一律 `draft`，必须人确认（gate 的 WAIT check）
2. **生成质量靠闭环**：schema 校验 + coverage 收敛 + docs:check 断链 + 结构检查，四道关卡兜底
3. **避免过度生成**：按领域、按 gap 触发，不批量扫全库（防"规范通胀"）
4. **确定性边界**：引擎永不调用 LLM；生成永远是"AI 起草 + 机制校验 + 人拍板"
5. **历史代码不背锅**：复杂度/重复度只查新增代码（沿用现有设计），存量治理走独立 audit 任务

---

## 附：与现有方案的关系

- 本方案在 `harness升级方案.md`（七大系统 + 11 步生命周期）**之上**追加"通用化 + 内容生成"维度
- 现有七大系统（Project Brain / Task / Risk / Standards / Supervisor / Evidence / Knowledge Loop）全部保留，本方案为其补齐**内容供给端**
- 一句话：**七大系统负责"管"，本方案新增的三大能力负责"产"**——"AI 产内容、Harness 管质量"

## 十二、2026-08-14 落地：复盘驱动自升级 + 通用化清理

> 本节记录 2026-08-14 在 PallasTrade（dogfood 场）实施的实际落地，作为上述方案的**第一阶段验证**。

### 12.1 复盘机制（dogfood 场）

- 复盘文档规范：`harness/reviews/REVIEW-YYYYMMDD.md`（任务清单 + 可沉淀规则 H1..Hn，机器可解析字段：kind/target/priority/pattern/message/fix/rule）
- 首次复盘：`harness/reviews/REVIEW-20260814.md`（9 条可沉淀规则 H1-H9，从配置中心 + CI 治理全日提炼）

### 12.2 自升级机制：`harness review` 命令（引擎层，已实现）

| 子命令 | 作用 |
|---|---|
| `harness review new` | 生成复盘骨架（harness/reviews/REVIEW-YYYYMMDD.md） |
| `harness review status` | 列出已有复盘 |
| `harness review propose` | 解析复盘 H 段 → 对比规则库 → 输出提案（add/update + 分类） |
| `harness review apply` | 把 standard/anti-pattern 提案**写回通用规则库**（rules/base-*.json，ID 自动递增）；engine/docs 提案输出待办清单 |

**自升级闭环**：任务结束 → AI 复盘（harness/reviews/）→ `review propose` 提炼 → `review apply` 规则自升级（自动）+ 引擎/文档改进清单（半自动，随版本发布）。

首次生效：`review apply` 已将 H3/H7/H8 写入 `rules/base-standards.json`（STD-REVIEW-001/002/003：扫描类 CI 检查、加密存储验证、命名转换）。

### 12.3 通用化清理（去 PallasTrade 特定内容）

已完成：
- 删除 `presets/pallastrade.mjs`（presets 现仅 single/nextjs/rails/monorepo 四个通用模板）
- docs（README/index/getting-started/contributing）：来源说明、preset 列表、"保持项目无关"检查措辞通用化
- `bin/scan-secrets.mjs`：SEC-003/DNG-002/DNG-003 从绑定 `pallastrade_` 表前缀/sk_ 品牌格式改为通用危险操作规则（DROP TABLE / mass DELETE 核心表 / admin secret key）
- `bin/config-loader.mjs` 注释、`bin/eval-llm.mjs` 示例模板、`bin/init.mjs` 文案、`bin/harness.mjs` CLI 标题通用化

保留（包名事实，非"项目内容"）：`package.json` name/repository、npm 安装命令、`.bin` shim、docs 中的包名引用。

**待办（标记）**：
- `bin/eval-ai.mjs` / `bin/eval-scenarios.mjs`：深度耦合 `backend/pallastrade_gems/pallastrade_*` 路径 → 需改为**配置驱动**（config 声明 gemRoots/gemPrefix），P1
- H1（gate 分支校验）/ H2（doc-impact 同 commit 提示）/ H5（CLI 中文参数）：引擎改进待发版
- H4（flock 超时）/ H6（测试 DB 残留）/ H9（lazy routes FAQ）：文档待补

### 12.4 关键教训（写进通用规则）

- **扫描类检查**：排除内部记录目录；通用英文词不整词禁止；检查器自身代码不得含被禁词（STD-REVIEW-001）
- **加密存储验证**：查原始列，不用 ORM 解密 getter（STD-REVIEW-002）
- **group.name 命名转换**：只转换第一个分隔符，保留组内下划线（STD-REVIEW-003）
- 规则库变更与触发它的代码必须在**同一 commit**（doc-impact 约束，H2）
