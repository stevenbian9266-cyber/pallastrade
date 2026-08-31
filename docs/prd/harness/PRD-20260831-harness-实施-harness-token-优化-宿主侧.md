# PRD-20260831-harness-实施-harness-token-优化-宿主侧

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-31 |
| 来源 | 优化：实施 harness token 优化（宿主侧） |
| 分类 | harness（自动判定） |
| 关联 Skill | harness-prd / pallastrade-project |
| 关联 REQ | REQ-20260831-harness-token-optimization-host.md |
| 关联 PRD | N/A（全新需求；查重 4 个 33% 相似 PRD 均为标题含"优化"误判，主题无关，已 --force） |
| 需求类型 | 优化迭代（配置 + 文档） |

> 🔁 查重回写：`prd new` 检测 4 个 33% 相似 PRD（新建店铺表单/ai-tools/l4-promotion/glob 依赖），标题均含"优化"但主题与 token 消耗完全无关 → 误判，`--force` 新建。

## 1. 背景与目标

- **一句话需求原文**：结合 RESEARCH-20260831-harness-token-optimization.md 方案，只优化本项目（d:\pallastrade）相关的内容，安装的 pallastradeharness 引擎内容不动
- **背景**：接入 harness 后 token 消耗明显增多（实测每会话固定 ~27-38K + 每任务增量 ~25-35K）。方案文档已完成分析（RESEARCH-20260831），本任务实施**宿主侧**可执行项（方案 §4/§5）
- **目标**：在不削弱约束监督（gate/反模式/证据/知识同步/危险操作）前提下，降低宿主侧 token 消耗
- **成功指标**：
  - 注入文件（AGENTS.md + copilot-instructions.md）总大小 37.8KB → ≤28KB
  - feature 任务 gate 检查数 24 → ≤17（designStage 关闭）
  - 每会话固定注入 -30%，每任务增量 -40% 以上

## 2. 用户故事 / 场景

- 作为**AI 协作开发者**，我希望 harness 流程减少冗余注入和文档产物，以便 token 消耗降低、任务更快
- 作为**项目维护者**，我希望约束监督（gate/反模式/证据/知识同步）完整保留，以便工程质量不受影响
- 场景：
  - 正常流：配置优化生效后，新 feature 任务不再强制 4 设计文档
  - 边界：AGENTS.md/copilot-instructions 瘦身后，R0-R9 命令与约束必须完整保留（CI/流程引用）
  - 异常：模板精简不得破坏 PRD/REQ 结构要求（FR/AC/跨层搜索/知识同步字段保留）

## 3. 功能需求（FR）

- FR-001：`harness.config.mjs` 关闭 `designStage`（feature 任务不再强制 4 设计文档）
- FR-002：`harness.config.mjs` 限制 `brain.maxContextAssets`（24→10）与 `maxAssetBytes`（524288→262144）
- FR-003：`harness.config.mjs` 限制 `evidence.maxOutputBytes`（262144→65536）
- FR-004：`AGENTS.md` 精简 §2 与 copilot-instructions 重复的命令块（Step -2/-1/2/3 → 指针），保留全部约束规则
- FR-005：`.github/copilot-instructions.md` 精简为速查表（保留 R0-R9 全部命令与规则，压缩叙述）
- FR-006：`docs/prd/_TEMPLATE.md` 精简说明性文字（保留结构骨架）
- FR-007：`harness/requirements/_TEMPLATE.md` 精简说明性文字（保留跨层搜索表 + skill 咨询表）
- FR-008：`ai/skills/pallastrade-project/SKILL.md` 增加"Token 节俭操作习惯"（读大文件先 grep、命令输出裁剪、批量 clear 等）
- FR-009：`ai/skills/harness-prd/SKILL.md` 增加"REQ 简版规范"（轻量维护任务 REQ 可只填跨层搜索+验证方案）
- FR-010：修复后验证约束完整性（nav:check、docs:check、gate 检查数、注入文件大小）

## 4. 非功能需求（NFR）

- 兼容：不改引擎（node_modules/pallastrade-harness 不动）；所有改动为宿主配置/文档
- 可维护性：瘦身后保留指针（AGENTS.md ↔ copilot-instructions.md 互相引用）
- 可验证性：注入文件大小、gate 检查数、nav:check/docs:check 均可机械复验
- 安全：不改任何代码/DB/依赖；AGENTS.md §8 危险操作、§5 反模式、§6 验证矩阵、§7 知识同步完整保留

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：新开 feature gate 检查数 ≤17（不再含 create-ui-doc 等 7 项设计检查）
- AC-002 ← FR-002/003：`harness.config.mjs` 中 brain.maxContextAssets=10、evidence.maxOutputBytes=65536 生效（`harness doctor` / config 加载无报错）
- AC-003 ← FR-004：`AGENTS.md` 大小 ≤22KB（原 27.5KB），且 `harness nav:check` + `docs:check` 通过
- AC-004 ← FR-005：`copilot-instructions.md` 大小 ≤7KB（原 10.3KB），R0 前缀表 + R1-R9 命令完整（grep 校验关键命令存在）
- AC-005 ← FR-006/007：两个模板大小分别 ≤2KB / ≤3KB，且 PRD/REQ 结构字段保留
- AC-006 ← FR-008/009：两个 skill 包含新规范章节
- AC-007 ← FR-010：`harness scan` 39/39 ok；`harness doctor` 关键项通过

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | config, harness | 无 | ✅ 无冲突 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | config, harness | `configuration_management.rb`, `menu_config.rb`（业务配置） | ✅ 与 harness 配置无关 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | config | 无 | ✅ 无冲突 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | config | `menu_configs_controller.rb`（业务菜单配置） | ✅ 无关 |
| Storefront | `storefront/src/` | config | `lib/pallastrade/config.ts`（业务配置） | ✅ 无关 |
| Platform | `platform/packages/` | config | 仅 node_modules 依赖 | ✅ 无冲突 |

**结论**：token 优化仅涉及 `harness.config.mjs` + 文档/模板/skill（宿主侧），6 层无重复配置；不触引擎（node_modules/pallastrade-harness）。

## 7. 技术影响

- 涉及文件（全部宿主侧）：
  - `harness.config.mjs`（FR-001/002/003）
  - `AGENTS.md`（FR-004）
  - `.github/copilot-instructions.md`（FR-005）
  - `docs/prd/_TEMPLATE.md`（FR-006）
  - `harness/requirements/_TEMPLATE.md`（FR-007）
  - `ai/skills/pallastrade-project/SKILL.md`（FR-008）
  - `ai/skills/harness-prd/SKILL.md`（FR-009）
  - `docs/prd/README.md`（索引）
- 影响面：无代码/依赖/DB/接口变更；影响未来所有会话的注入量与任务流程
- 反模式：无 AP 违规（不动代码）

## 8. 测试计划

- 验证命令（AC 映射）：
  - AC-001 → 新开 gate 实测检查数（`harness gate --type feature`）
  - AC-002 → `npx harness doctor` + config 加载
  - AC-003/004 → `npx harness nav:check` + `docs:check` + 文件大小实测 + grep 校验关键命令
  - AC-005 → 模板文件大小 + 结构字段 grep
  - AC-006 → skill 文件 grep 新章节
  - AC-007 → `npx harness scan`
- 无新增单元测试（配置/文档变更）；机械复验证据足够

## 9. 文档同步清单（知识同步门）

| 知识资产 | 结论 |
|---|---|
| API 文档 | ✅ 无需更新（无接口变更） |
| Skill 文档 | ✅ **已更新**：`pallastrade-project`（加 Token 节俭章节）、`harness-prd`（加 REQ 简版规范） |
| AGENTS.md / copilot-instructions.md | ✅ **已更新**（本任务瘦身对象，约束全保留） |
| 场景库（scenarios.json） | ✅ **已更新**：新增 **GS-044**「Token-frugal harness workflow」，`eval-ai --scenarios` 45/45 有效 |
| 模板 | ✅ **已更新**：`docs/prd/_TEMPLATE.md`、`harness/requirements/_TEMPLATE.md` 精简 |
| PRD 索引 | ✅ 已更新（docs/prd/README.md） |
| 其他（历史/并行任务变更） | 非本任务范围，不处理 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-31 | 0.1 | 初稿（基于 RESEARCH-20260831-harness-token-optimization.md §4/§5） | AI |
| 2026-08-31 | 0.2 | 实施完成：7 文件修改 + 验证通过（AC-001~007）；知识同步：GS-044 场景 + 模板/skill 更新；PRD → done | AI |
| 分类 | （自动判定，见 `harness/policies/prd-categories.json`） |
| 关联 Skill | （对应领域 skill 名） |
| 关联 REQ | REQ-YYYYMMDD-xxx.md（实施时回填） |
| 关联 PRD | （查重回写时填原 PRD ID；全新需求填 N/A） |
| 需求类型 | 新功能 / 优化迭代 / Bug 修复 / 接口变更 / 样式 / 文档 |

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **一句话需求原文**：<用户输入原文>
- **背景**：为什么做、解决什么问题
- **目标**：期望达成的结果
- **成功指标**：可量化指标（如：导入 1 万 SKU 耗时 < 60s）

## 2. 用户故事 / 场景

- 作为 <角色>，我希望 <能力>，以便 <价值>
- 场景列表（正常流 + 边界 + 异常）

## 3. 功能需求（FR）

- FR-001：<可验收的功能描述>
- FR-002：...

## 4. 非功能需求（NFR）

- 性能 / 安全 / 兼容 / 可维护性

## 5. 验收标准（AC，与测试一一映射）

> ⚠️ 以下为示例，正式内容请删除注释标记并替换为真实 AC：
- <!-- AC-001 ← FR-001：<可验证的判定条件> -->
- <!-- AC-002 ← ... -->

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | | | |
| Core | `pallastrade_gems/pallastrade_core/app/` | | | |
| API | `pallastrade_gems/pallastrade_api/app/` | | | |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | | | |
| Storefront | `storefront/src/` | | | |
| Platform | `platform/packages/` | | | |

**结论**：哪些层已有能力 / 哪些需新建 / 防重复判定

## 7. 技术影响

- 涉及组件 / 文件 / 依赖 / 数据库 / 接口
- 影响面（`harness affected --base origin/main` 输出）

## 8. 测试计划

- 新增测试文件（路径清单）
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射（AC-xxx → 测试文件）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |
