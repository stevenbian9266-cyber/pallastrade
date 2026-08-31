# PRD-20260830-other-修复-skill-权威路径

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-30 |
| 来源 | 优化：修复 SKILL 权威路径 |
| 分类 | other（自动判定，关键词命中 0） |
| 关联 Skill | harness-skill-author / harness-standards-audit / harness-docs |
| 关联 REQ | REQ-20260830-fix-skill-authority-paths.md |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 文档 |

> 🔁 **查重回写**：`harness prd new` 自动查重通过（无相似 PRD 命中）。
> 历史相似任务 TASK-20260819080310（skill 路径漂移 13 处 + harness 1.3.1 解析器修复）为任务级记录，非 PRD 文档，不构成 PRD 冲突。

## 1. 背景与目标

- **一句话需求原文**：优化：修复 SKILL 权威路径
- **背景**：升级 `pallastrade-harness` 至 1.8.0 并完成初始化后，`harness scan` 资产治理报告 4 个 SKILL 的"权威路径失效"（should 级）。这些是 SKILL.md 中以反引号路径形式引用的文件在仓库中不存在：
  1. `ai/skills/harness-standards-audit/SKILL.md` → `rules/base-standards.json`（引擎内置路径，宿主项目无此相对路径）
  2. `ai/skills/pallastrade-cli/SKILL.md` → `.pallastrade/credentials.json`（CLI 运行时生成的凭据文件，gitignored，不入库）
  3. `ai/skills/pallastrade-extensions/SKILL.md` → `lib/pallastrade_simple_sales/engine.rb`（扩展生成器的模板产物结构，非项目源码）
  4. `ai/skills/pallastrade-typescript-sdk/SKILL.md` → `pallastrade/api/app/serializers/**/*.rb`（旧式 gem 路径，实际位于 `backend/pallastrade_gems/pallastrade_api/app/serializers/`，145 个文件）
- **目标**：修正 4 个 SKILL 文档中的路径引用，使 `harness scan` 的"权威路径失效"should 项清零，同时保持文档语义准确
- **成功指标**：`npx harness scan` 不再报告上述 4 个权威路径失效；`npx harness skill check --freshness` 不再报告这 4 项

## 2. 用户故事 / 场景

- 作为**项目维护者**，我希望 SKILL 文档中引用的权威路径真实有效，以便 AI 协作时能准确找到 field-level 细节的权威来源（遵循 `harness-skill-author` §3 规则 5："权威文件真实：路径必须真实存在"）
- 作为**CI/治理检查**，我希望 `harness scan` 的 should 项干净，以便把注意力留给真正需要处理的治理问题
- 场景：
  - 正常流：4 处引用逐一修正后，scan 通过
  - 边界：`.pallastrade/credentials.json` 是运行时产物——修正后文档应说明其"运行时生成、不入库"属性，而不是强行让它在仓库中存在
  - 异常：无（纯文档修正，不涉及功能逻辑）

## 3. 功能需求（FR）

- FR-001：修正 `ai/skills/pallastrade-typescript-sdk/SKILL.md` 中的 `pallastrade/api/app/serializers/**/*.rb` 为真实路径 `backend/pallastrade_gems/pallastrade_api/app/serializers/**/*.rb`（该 glob 现有 145 个匹配）
- FR-002：修正 `ai/skills/pallastrade-cli/SKILL.md` 中对 `.pallastrade/credentials.json` 的引用，明确其"运行时生成、gitignored、不入库"属性，不再作为权威路径被提取
- FR-003：修正 `ai/skills/pallastrade-extensions/SKILL.md` 中对 `lib/pallastrade_simple_sales/engine.rb` 的引用，标注为"生成器模板结构/示例"，不再作为权威路径被提取
- FR-004：修正 `ai/skills/harness-standards-audit/SKILL.md` 中对 `rules/base-standards.json` 的引用，说明其为"引擎随包分发"的内置基线，不再作为宿主项目权威路径被提取
- FR-005：修复后运行验证命令确认 4 项失效全部消失

## 4. 非功能需求（NFR）

- 兼容：改动仅限 `ai/skills/` 下 4 个 SKILL.md 文档文本，不影响任何代码/配置/依赖
- 可维护性：保持文档语义准确，不因规避检查而扭曲技术事实
- 可验证性：修复效果可通过 `harness scan` / `skill check --freshness` 机械复验

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`npx harness scan` 不再报告 `pallastrade-typescript-sdk` 权威路径失效（`pallastrade/api/app/serializers/**/*.rb`）
- AC-002 ← FR-002：`npx harness scan` 不再报告 `pallastrade-cli` 权威路径失效（`.pallastrade/credentials.json`）
- AC-003 ← FR-003：`npx harness scan` 不再报告 `pallastrade-extensions` 权威路径失效（`lib/pallastrade_simple_sales/engine.rb`）
- AC-004 ← FR-004：`npx harness scan` 不再报告 `harness-standards-audit` 权威路径失效（`rules/base-standards.json`）
- AC-005 ← FR-005：`npx harness skill check --freshness` 不再报告上述 4 项权威路径失效；`harness scan` 汇总显示 0 个 skill 权威路径待升级

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | credential, serializer | 无 | ✅ 无冲突（该层无 credential/serializer 文件） |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | credential, serializer, engine | 无相关文件 | ✅ 无冲突 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | serializer | `app/serializers/` 下 **145 个** serializer 文件 | ✅ 确认真实路径为 `backend/pallastrade_gems/pallastrade_api/app/serializers/` |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | credential, serializer | 无 | ✅ 无冲突 |
| Storefront | `storefront/src/` | credential | 无 | ✅ 无冲突 |
| Platform | `platform/packages/` | credential | 无 | ✅ 无冲突 |

**结论**：
- `pallastrade-typescript-sdk` 的旧路径 `pallastrade/api/app/serializers/**/*.rb` → 真实位置在 API gem 层（`backend/pallastrade_gems/pallastrade_api/app/serializers/`，145 文件），需改路径
- 其余 3 个引用（`.pallastrade/credentials.json`、`lib/pallastrade_simple_sales/engine.rb`、`rules/base-standards.json`）经 6 层搜索确认在任何层都不存在——它们是运行时产物/生成器模板/引擎内置文件，引用本身合理，需调整表述避免被误判为权威路径
- 无重复实现风险：本任务只改文档文本，不新建任何文件

## 7. 技术影响

- 涉及文件（全部为文档文本修正，在 `ai/skills/` 下）：
  - `ai/skills/pallastrade-typescript-sdk/SKILL.md`（1 处路径修正）
  - `ai/skills/pallastrade-cli/SKILL.md`（1 处表述修正）
  - `ai/skills/pallastrade-extensions/SKILL.md`（1 处表述修正）
  - `ai/skills/harness-standards-audit/SKILL.md`（1 处表述修正）
- 影响面：无代码/依赖/数据库/接口变更；影响 `harness scan` should 级报告与 SKILL 文档准确性
- 反模式检查：无 AP 违规（不动代码）

## 8. 测试计划

- 验证命令（AC 映射）：
  - AC-001~004 → `npx harness scan`（skill 权威路径 section 不再报 4 项失效）
  - AC-005 → `npx harness skill check --freshness`（4 项权威路径失效消失）
- 文档校验：`npx harness docs:check`（确认无断链引入）
- 无新增单元测试（纯文档变更，按 §6 验证矩阵 docs 类豁免，但保留机械复验证据）

## 9. 文档同步清单（知识同步门）

| 知识资产 | 结论 |
|---|---|
| API 文档（`backend/public/api-docs/*.yaml`） | ✅ 已评估，无需更新（无接口变更） |
| Skill 文档（doc-impact 规则） | ✅ 本任务即修改 SKILL 文档本身（4 个 SKILL.md 路径修正） |
| README / Agent 文件 / 样式规范 / 技术规范 | ✅ 已评估，无需更新（不改规范/流程；AGENTS.md §0.1 引用路径已在初始化时统一为 pallastrade-* 真实命名） |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新（无 AP 规则变更） |
| 场景库（scenarios.json） | ✅ **已更新**：新增 **GS-041**「SKILL authority paths stay valid」（`ai/skills/**/SKILL.md` 变更触发），`eval-ai --scenarios` 42/42 有效 |
| 本 PRD 状态更新 + `docs/prd/README.md` 索引 | ✅ 已更新（PRD 状态 → done，索引已含本 PRD） |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-30 | 0.1 | 初稿（按 _TEMPLATE.md 完整扩充） | AI |
| 2026-08-30 | 0.2 | 实施完成：4 处路径修正，scan 39/39 ok；知识同步：新增 GS-041 场景，PRD 状态 → done | AI |
