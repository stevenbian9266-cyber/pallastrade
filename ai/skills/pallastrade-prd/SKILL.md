---
name: pallastrade-prd
description: Use when the user gives a one-line requirement (一句话需求) and expects AI to expand it into a full PRD document and drive the whole development loop — PRD creation (categorized, named, indexed), user confirmation, harness gate, implementation, automated tests + acceptance criteria, API doc sync, and the knowledge-sync gate. Also use when the user asks to update a PRD, create a missing PRD for an existing feature, or run PRD-driven task flows. Common phrasings include "一句话需求", "生成PRD", "PRD驱动的开发", "写PRD", "更新PRD", "这个需求帮我写详细文档".
---

# PallasTrade PRD 驱动的自动化开发工作流

> 本 Skill 定义：**用户一句话需求 → 详细 PRD → harness 门禁实施 → 测试/验收 → 知识同步 → 收尾** 的完整闭环。
> 所有 AI 助手（Copilot / Claude Code / Codex 等）在收到一句话需求时，必须遵循本工作流。

## 1. 触发与判定

- 用户输入为**一句话需求**（含前缀如 `需求：`/`新增：`/`优化：`/`修复：` 等）→ 走本工作流
- 用户输入为提问（怎么/什么是/为什么）→ 直接回答，不走本工作流
- 需求类型判定：新功能 / 优化迭代 / Bug 修复 / 接口变更 / 样式 / 文档

## 2. 阶段 0：PRD 生成（一句话 → PRD）

### 2.1 查重（防重复，机制自动执行 + AP-SEARCH 反模式）

> ✅ **机制强制**：`harness prd new --title "<需求>"` 会自动扫描 `docs/prd/**` 已有 PRD，
> 计算标题相似度（英文词 + 中文 2-gram Jaccard）：
> - **相似度 > 0.3** → CLI 列出候选 PRD 并**阻止新建**（exit 1）
> - 此时**必须回写更新原 PRD**：`harness prd update --path <PRD> --title "<需求>"`，
>   然后在原 PRD 内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**
> - 确属全新需求才用 `--force` 强制新建

1. 运行 `harness prd new --title "<需求>"`（自动查重）
2. 6 层跨层搜索（backend/app、core、api、admin、storefront、platform）确认无已实现能力
3. 命中相似 PRD → `harness prd update` 回写原 PRD（走优化迭代流程），不新建

### 2.2 分类判定
1. 读取 `harness/policies/prd-categories.json`
2. 需求描述匹配关键词 → 取命中数最多分类
3. 无命中 → `other/`；AI 可语义微调（记录到 PRD 元数据）

### 2.3 生成 PRD
1. 使用模板 `docs/prd/_TEMPLATE.md`
2. 命名：`PRD-{YYYYMMDD}-{category}-{slug}.md`（slug kebab-case ≤6 词）
3. 存放：`docs/prd/{category}/PRD-{YYYYMMDD}-{category}-{slug}.md`
4. 必须自动扩充（不得只复制一句话）：
   - 背景/目标/成功指标
   - 用户故事 + 场景（正常/边界/异常）
   - **FR**（功能需求，可验收）
   - **AC**（验收标准，每个 FR ≥1 个 AC，可测试）
   - 跨层搜索记录（6 层表）
   - 技术影响 + `harness affected`
   - 测试计划（新增/更新）
   - 文档同步清单（含接口影响预判）
5. 状态：`draft`
6. 更新 `docs/prd/README.md` 索引

### 2.4 接口影响预判
- 若涉及 controller/routes/serializer/API → 在 PRD §9 标记"需更新 store/admin.yaml"

## 3. 阶段 1：用户确认

- 呈现 PRD 摘要 → 用户明确确认（"确认"/"认可"/"实施"）
- 确认后 PRD 状态 → `approved`
- 未确认 → 保持 draft，不进入实施

## 4. 阶段 2：gate + 实施

1. `npx harness gate --task "<PRD 标题>"`（前缀自动判定类型）
2. 依据 PRD 生成 REQ：`harness/requirements/REQ-{YYYYMMDD}-{slug}.md`（用 `_TEMPLATE.md`），回填关联 PRD
3. 清除 gate checks（6 层搜索 / skill 读取 / create-req-doc / req-doc-has-skill-table / user-confirmed）
4. Harness 0.4+：运行 `harness supervise plan --task "<PRD 标题>" --allow <glob...>`，固化 Change Plan、风险、适用规范与证据需求
5. 实施（按 PRD FR 逐个实现）：
   - 新功能 → 创建测试文件（见 §5）
   - 优化迭代 → 升级测试 + 更新 PRD §8/§10
   - 接口变更 → 同步 API 文档（见 §6）
6. 实施中和提交前运行 `harness supervise diff --base <base> --plan <plan-path>`；PallasTrade `guard` 模式下阻断 error/critical，所有 finding 必须可追溯到 Standard ID 和源码位置

## 5. 测试与验收机制

- 测试位置约定：
  - 后端：`backend/spec/{models,requests,services,features}/`（RSpec + Factory Bot）
  - Storefront：`storefront/src/**/__tests__/*.test.tsx`（Vitest + Testing Library）
  - Platform：`platform/packages/*/tests/*.test.ts`（Vitest）
- **新功能**：为每个 AC 创建测试；测试头部标注 `# PRD-xxx AC-xxx`
- **优化迭代**：定位已有测试（跨层搜索测试目录）→ 新增/修改覆盖变更后 AC
- **验收强制**：AC 必须被测试覆盖；无测试的 AC 不允许标记 done

## 6. API 文档同步

- 检测：修改了 `backend/app/controllers/**/api/v3/**` 或 gem 内 controller/routes，或 PRD 分类为 api
- 同步：
  - `backend/public/api-docs/store.yaml` / `admin.yaml`
  - `platform/docs/api-reference/store.yaml` / `admin.yaml`
- 验证：`npx harness generated:check` + `pnpm --filter @pallastrade/sdk generate:types`

## 7. 阶段 3：验证（R6 强制）

- 按改动类型跑最小验证（见 AGENTS.md §6 表格：Ruby→quick check、TS/TSX→pnpm build/lint、UI→截图/DOM、后端→Rails log）
- 证据必须客观（截图/日志/DB 查询），"no test needed" 是极少数例外
- preparation checks 清除后即可进入 implementation；`verify-test` 始终留在 verification 阶段，附证据清除后 gate 才进入 `finished`，PRD 状态 `verifying` → `done`

## 8. 阶段 4：知识同步门（收尾）

按本次变更类型，逐项判定 §8 知识资产矩阵（见 `harness/requirements/REQ-20260808-prd-driven-workflow.md` §八）：

| 变更类型 | 必须评估/同步的资产 |
|---|---|
| Model/DB | 领域 Skill、data-model Skill、场景库、测试 |
| API 端点 | store/admin.yaml、api-v3 Skill、SDK 类型、场景库 |
| UI 组件/页面 | storefront Skill、组件测试、场景库 |
| 样式/token | 样式规范（CLAUDE.md/Skill Style Guide 章节）、AP-006 |
| 新反模式 | `harness/policies/anti-patterns.json` + AGENTS.md §5 + copilot-instructions |
| 新任务规则 | `harness/policies/task-rules.json` + AGENTS.md |
| CLI/命令 | cli Skill、`ai/commands/`、CLI README |
| 包/SDK | sdk Skill、packages README、根 README |
| 技术选型/架构 | 根 AGENTS.md、各层 CLAUDE/AGENTS、技术规范、README |
| 安全 | security Skill、AGENTS.md §8 危险操作 |
| 部署/配置 | deployment Skill、.env.example |
| 流程机制 | 本 Skill、AGENTS.md、copilot-instructions、场景库 |

执行：
1. 运行 `npx harness sync-check`（若已实现）输出待评估清单
2. 逐项处理：有变更 → 更新；无变更 → 记录"已评估，无需更新"
3. 结论写入 PRD §9/§10
4. 更新 `docs/prd/README.md` 索引
5. 运行 `npx harness doc-impact --base origin/main` + `eval-ai --check-freshness`

## 9. Bug 修复简版

- 走 `bugfix` gate，但同样生成 PRD（简版：省略用户故事，聚焦复现步骤 + 根因 + 验证）
- 优化迭代且 PRD 不存在 → **自动创建** PRD（用户需求点 4）

## 10. 禁止事项

- 禁止在未生成 PRD / 未确认 / 未清 gate 前写实现代码
- 禁止创建重复 PRD（`harness prd new` 自动查重；相似 PRD 必须用 `harness prd update` 回写原文档）
- 禁止跳过分层测试或知识同步门
- 禁止在 PRD 未 done 时关闭 gate（verify-test 前置）
