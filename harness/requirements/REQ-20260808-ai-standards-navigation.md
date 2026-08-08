# AI Coding 规范文件导航体系 — 梳理方案

> 需求来源：AI 执行 coding 任务时需阅读的规范/约束文件过于分散，缺乏统一指令与路径导航。
> 本文件为**梳理方案**（本次仅输出方案，不实施）。

---

## 一、现状盘点（26+ 个规范文件，7 类）

### 1.1 文件全景

| 类别 | 文件 | 规模 | 注入/读取方式 |
|---|---|---|---|
| **自动注入指令** | 根 `AGENTS.md` | 208 行 | ✅ Copilot 每会话自动注入 |
| | `.github/copilot-instructions.md` | 159 行 | ✅ Copilot 每会话自动注入 |
| **各层指令** | `backend/AGENTS.md`（2 行）+ `backend/CLAUDE.md`（122 行） | 薄+厚 | AGENTS 自动注入（薄指针），CLAUDE 需主动读 |
| | `platform/AGENTS.md`（11 行）+ `platform/CLAUDE.md`（500 行） | 薄+厚 | 同上 |
| | `storefront/AGENTS.md`（13 行）+ `storefront/CLAUDE.md`（482 行） | 薄+厚 | 同上 |
| | `ai/AGENTS.md` | 132 行 | 非自动（ai 目录） |
| **Skill（25 个）** | `ai/skills/*/SKILL.md` | 每个 100-300 行 | gate 强制读 2-3 个；其余按任务匹配 |
| **工程规则** | `harness/policies/anti-patterns.json`（10 条 AP） | 机器可读 | CI 执行；AI 需主动读 |
| | `harness/policies/task-rules.json`（TR-xxx） | 规则 | AI 执行 |
| | `harness/policies/prd-categories.json` | 分类 | AI 用（prd new） |
| | `harness/config.json` | 配置 | harness 用 |
| | `harness/scenarios/scenarios.json`（GS-xxx） | 场景 | eval 用 |
| **规范索引** | `docs/standards/README.md` | 刚建 | 需主动 |
| **PRD 体系** | `docs/prd/`（模板+索引+分类） | 新建 | 需主动 |
| **AI 命令/代理** | `ai/commands/doctor.md`、`ai/agents/pallastrade-expert.md` | 各一 | 需主动 |
| **记忆** | `ai/memories/*.md` | 5 个 | 需主动 |

### 1.2 发现的分散问题

| # | 问题 | 证据 |
|---|---|---|
| **P-1 反模式三处重复** | AP-001~009 同时存在于 `AGENTS.md` §5（11 处）、`.github/copilot-instructions.md`（7 处）、`harness/policies/anti-patterns.json`（10 条）→ 改一处漏两处 | 三文件命中统计 |
| **P-2 验证规则两处重复** | `AGENTS.md` §6（5 处）+ `copilot-instructions.md` R6（10 处） | 命中统计 |
| **P-3 无统一导航地图** | AI 不知道"什么任务该读哪些文件"，靠经验/记忆，易漏 | 无任务→文件映射 |
| **P-4 自动注入层太薄** | 自动注入仅 367 行（根 AGENTS + copilot-instructions）；详细规范在 1104 行 CLAUDE.md + 25 个 skill 中 → AI 常漏读 | 行数对比 |
| **P-5 各层 AGENTS/CLAUDE 分裂** | backend/platform/storefront 的 AGENTS.md 是"指针"指向 CLAUDE.md；Copilot 自动注入薄指针、不注入厚内容 | 2-13 行 vs 122-500 行 |
| **P-6 Skill 触发无集中索引** | 25 个 skill 仅 gate 强制 2-3 个，其余靠 AI 自行判断领域匹配 | 无触发表 |
| **P-7 权威源不清** | 同一概念（反模式、验证、规范）在多个文件，未标注"谁是唯一权威" | 无权威性标注 |

---

## 二、目标与设计原则

| 原则 | 说明 |
|---|---|
| **单一权威源（SSOT）** | 每个规范概念只在**一个**机器/权威文件中定义，其他文件引用或精简摘要 |
| **导航入口薄而全** | 自动注入文件 = "文件地图"（薄，但包含全部路径+触发条件），不承载详细规范 |
| **详细规范按需加载** | 厚内容放 skill/CLAUDE，任务匹配时读取（gate 强制或路由表触发） |
| **任务→文件显式路由** | 提供任务类型 → 必读文件集 的显式映射，AI 无需自行推断 |
| **可机器校验** | 去重/路由表可被 harness 校验（doc-impact 扩展） |

---

## 三、方案设计

### 3.1 核心：建立"指令导航地图"（唯一路由表）

**位置**：根 `AGENTS.md` 顶部新增 **§0「AI Coding 文件导航地图」**（自动注入，AI 一进来就看到）。

**内容**：一张总表 + 任务路由表 + 权威源标注。

**总表**（示例结构）：

| 文件 | 类别 | 权威角色 | 何时读取 | 更新责任人 |
|---|---|---|---|---|
| `AGENTS.md`（根） | 自动注入 | **导航入口 + 全局规范权威** | 每会话 | 工程负责人 |
| `.github/copilot-instructions.md` | 自动注入 | 强制命令速查（R0-R8） | 每会话 | 工程负责人 |
| `backend/CLAUDE.md` | 后端规范 | 后端权威 | 涉及 backend 代码 | 后端维护者 |
| `platform/CLAUDE.md` | 平台规范 | 平台权威 | 涉及 platform 代码 | 平台维护者 |
| `storefront/CLAUDE.md` | 商城规范 | 商城权威（含样式规范） | 涉及 storefront 代码 | 商城维护者 |
| `ai/skills/*/SKILL.md` | Skill | 领域知识权威 | gate 强制 + 任务匹配（见路由表） | 各领域维护者 |
| `harness/policies/anti-patterns.json` | 反模式 | **反模式唯一权威**（机器） | CI 强制；AI 违规时 | 工程负责人 |
| `harness/policies/task-rules.json` | 任务规则 | 任务规则权威 | 新功能/优化 | 工程负责人 |
| `harness/policies/prd-categories.json` | PRD 分类 | 分类权威 | prd new | 工程负责人 |
| `harness/scenarios/scenarios.json` | 场景库 | Eval 权威 | 能力变更 | 工程负责人 |
| `docs/standards/README.md` | 规范索引 | **规范文件指针权威** | 不确定规范位置时 | 工程负责人 |
| `docs/prd/_TEMPLATE.md` | PRD 模板 | PRD 权威模板 | 一句话需求 | AI |
| `ai/commands/doctor.md` | AI 命令 | 命令定义 | 运维诊断 | AI 维护者 |
| `ai/agents/pallastrade-expert.md` | AI 代理 | 专家代理定义 | 多步调研 | AI 维护者 |
| `ai/memories/*.md` | 记忆 | 决策记录 | 重要决策 | AI |

### 3.2 去重方案

#### D-1 反模式去重（P-1）
- **权威源**：`harness/policies/anti-patterns.json`（唯一完整定义，CI 已用它）
- `AGENTS.md` §5：保留**精简摘要表**（AP 编号 + 一句话 + 指向 json 的路径），删除完整描述
- `.github/copilot-instructions.md`：删除 AP 重复段，改为"反模式见 `AGENTS.md` §5 + `harness/policies/anti-patterns.json`"一行引用
- 效果：3 处 → 1 处完整 + 2 处指针

#### D-2 验证规则去重（P-2）
- **权威源**：`AGENTS.md` §6（验证矩阵 + 证据要求）
- `.github/copilot-instructions.md` R6：精简为"验证要求见 `AGENTS.md` §6"，保留最小强制（verify-test 必须清、证据必备）
- 效果：2 处完整 → 1 处完整 + 1 处指针

#### D-3 各层指令瘦身（P-5）
- 保持各层 `AGENTS.md` 为"薄指针"（现状合理）
- 增强：在各层 AGENTS.md 的指针中加入"本层规范文件清单"（CLAUDE.md + 相关 skill 路径），避免只指向一个 CLAUDE.md

### 3.3 任务 → 文件路由表（P-6/P-7 核心）

新增于导航地图中的"任务路由表"，12 类任务 × 必读文件：

| 任务类型 | 必读文件（按顺序） |
|---|---|
| **新功能/一句话需求** | 根 AGENTS.md → copilot-instructions → **pallastrade-prd** → **pallastrade-customization** → 领域 skill → 对应层 CLAUDE.md → task-rules.json |
| **Bug 修复** | 根 AGENTS.md → copilot-instructions → 领域 skill → 对应层 CLAUDE.md → anti-patterns.json（违规检查） |
| **接口增删改查** | 根 AGENTS.md → **pallastrade-api-v3** → 对应层 CLAUDE.md → `backend/public/api-docs/*.yaml` → generated-check |
| **UI/组件/样式** | 根 AGENTS.md → **pallastrade-storefront** → storefront/CLAUDE.md（Code Style）→ docs/standards（样式规范指针）→ anti-patterns.json（AP-001/006） |
| **模型/DB 变更** | 根 AGENTS.md → **pallastrade-data-model** → 领域 skill → 对应层 CLAUDE.md |
| **支付相关** | 根 AGENTS.md → **pallastrade-payments** → **pallastrade-security** → 对应层 CLAUDE.md |
| **安全/权限** | 根 AGENTS.md → **pallastrade-security** → anti-patterns.json → AGENTS.md §8（危险操作） |
| **事件/订阅者** | 根 AGENTS.md → **pallastrade-events-webhooks** → 对应层 CLAUDE.md |
| **SDK/CLI/平台** | 根 AGENTS.md → **pallastrade-typescript-sdk** / **pallastrade-cli** → platform/CLAUDE.md |
| **部署/配置** | 根 AGENTS.md → **pallastrade-deployment** → .env.example → 部署 README |
| **i18n** | 根 AGENTS.md → **pallastrade-i18n** → 对应层 CLAUDE.md |
| **测试补充** | 根 AGENTS.md → **pallastrade-testing** → 对应层测试约定 |

> 加粗 = gate 强制或路由表必读；其余为任务匹配时读。

### 3.4 权威性标注（P-7）

每个文件在导航地图中标三个字段：
- **权威角色**：唯一权威 / 补充 / 指针
- **冲突裁决**：两文件冲突时以谁为准（如：反模式冲突 → anti-patterns.json 为准；规范冲突 → 导航地图标注的最高权威为准）
- **更新触发**：什么变更必须更新它（对应 doc-impact 矩阵）

### 3.5 维护规则（防再分散）

1. **新增规范文件** → 必须登记到导航地图（否则视为未正式纳入）
2. **修改权威文件** → 按 doc-impact 矩阵同步其指针文件
3. **去重校验**（可选，纳入 harness）：
   - `harness nav:check`：校验导航地图中的文件都存在 + 指针文件未复制完整内容（检测重复）
   - doc-impact 增加"导航地图更新"规则（改规范 → 需更新 AGENTS.md §0）

---

## 四、实施计划（本次不实施，后续按序推进）

| 步骤 | 内容 | 工作量 |
|---|---|---|
| P1 | 根 `AGENTS.md` 新增 §0 导航地图（总表 + 任务路由表 + 权威源） | 中 |
| P2 | 反模式去重：AGENTS.md §5 精简 + copilot-instructions 改指针 | 小 |
| P3 | 验证规则去重：copilot-instructions R6 精简为指针 | 小 |
| P4 | 各层 AGENTS.md 增强指针（列出本层 CLAUDE + 相关 skill） | 小 |
| P5 | doc-impact 增加"导航地图维护"规则 + `nav:check` 校验命令 | 中 |
| P6 | 端到端演练：用一个任务走导航地图 → 验证读文件正确 | 中 |

---

## 五、风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| 去重后指针失效（指向不存在的章节） | 中 | nav:check 校验路径；doc-impact 覆盖 |
| 导航地图本身膨胀 | 中 | 只放路径+触发条件，不放详细内容（薄而全） |
| AI 仍不读导航地图 | 低 | 放自动注入文件顶部（§0），第一屏可见 |
| 各层 CLAUDE 与导航地图冲突 | 低 | 冲突裁决规则：导航地图标注的最高权威为准 |
| 改动范围大 | 中 | P1-P6 分步，每步独立验证 |

---

## 六、决策节点

1. **导航地图放哪**：建议根 `AGENTS.md` §0（自动注入）。备选：独立 `docs/standards/README.md` 升级。→ 请确认
2. **去重程度**：建议反模式/验证规则"权威文件完整 + 指针精简"。是否同意？
3. **是否加 `nav:check` 命令**：需要改 harness CLI。→ 请确认
