# PRD-20260809-harness-prd-dedupe-update

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-09 |
| 来源 | 需求：harness PRD 查重回写机制升级（避免重复新建，相似 PRD 回写更新原文档） |
| 分类 | harness（工程机制） |
| 关联 Skill | pallastrade-prd |
| 关联 REQ | （实施时回填） |
| 需求类型 | 优化迭代（工程机制） |

## 1. 背景与目标

- **一句话需求原文**：如果需求、任务等已有 PRD 或内容相似度很高的 PRD 了，回写更新原有 PRD；PRD 尽量不要为了新建而新建（如已有商品信息相关 PRD，新需求在原有 PRD 内完整更新即可）
- **背景**：当前 `harness prd new` 仅做**幂等保护**（同名文件存在才拒绝），无**相似度查重**——同类需求会被重复新建 PRD（如 OSS 存储 / OSS Cache-Control 分别建了两个 PRD，本可融合）。`pallastrade-prd` SKILL.md §2.1 有查重步骤但靠 AI 自觉，无机制强制
- **目标**：
  - `harness prd new` 自动检测相似 PRD（标题/关键词相似度），相似则提示回写更新原 PRD 而非新建
  - 新增 `harness prd update` 回写命令（把新需求追加到已有 PRD）
  - `--force` 参数允许显式跳过查重强制新建
- **成功指标**：同类需求不会产生重复 PRD；查重/回写有明确命令与提示

## 2. 用户故事 / 场景

- 作为开发者：提"OSS 图片优化"需求 → `prd new` 检测到已有 OSS 相关 PRD → 提示回写原 PRD
- 作为开发者：确认是全新需求 → `--force` 新建
- 场景：命中同类 PRD（回写）、完全新需求（新建）、模糊匹配（提示人工判断）

## 3. 功能需求（FR）

- FR-001：`prd new` 生成前扫描 `docs/prd/**` 已有 PRD，计算标题/关键词相似度（英文词 + 中文 2-gram Jaccard）
- FR-002：相似度 > 阈值（0.3）时打印候选 PRD 列表 + 建议，exit 1（阻止新建）；`--force` 跳过查重
- FR-003：新增 `prd update --path <PRD文件> --title "<新需求>"`：在目标 PRD 追加来源/变更记录（回写）
- FR-004：更新 `ai/skills/pallastrade-prd/SKILL.md` §2.1/§3：查重由机制自动执行，相似则走 `prd update` 回写

## 4. 非功能需求（NFR）

- 兼容：现有 `prd new` 用法不变（无相似时不打扰）
- 性能：查重扫描 docs/prd（文件数有限，毫秒级）
- 可维护：相似度逻辑独立函数，便于调参

## 5. 验收标准（AC）

- AC-001 ← FR-001/002：`prd new --title "OSS 图片缓存优化"` 检测到已有 OSS PRD 并提示回写（exit 1）；`--force` 可新建
- AC-002 ← FR-003：`prd update --path .../PRD-xxx.md --title "新需求"` 在目标 PRD 追加变更记录
- AC-003 ← FR-004：SKILL.md 查重章节更新为机制自动执行 + 回写流程

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 无 | 不涉及 | 不适用 |
| Core | `pallastrade_gems/**` | 无 | 不涉及 | 不适用 |
| API | `pallastrade_gems/pallastrade_api/**` | 无 | 不涉及 | 不适用 |
| Admin | `pallastrade_gems/pallastrade_admin/**` | 无 | 不涉及 | 不适用 |
| Storefront | `storefront/src/` | 无 | 不涉及 | 不适用 |
| Platform | `platform/packages/` | 无 | 不涉及 | 不适用 |
| Harness | `scripts/harness/` | prd new、查重 | `cli.mjs`（prd 子命令，仅幂等无查重）、`pallastrade-prd/SKILL.md` §2.1（人工查重） | 需增强 |

**结论**：机制改动集中在 `scripts/harness/cli.mjs`（prd 子命令）+ `ai/skills/pallastrade-prd/SKILL.md`，无业务层影响。

## 7. 技术影响

- 修改：`scripts/harness/cli.mjs`（prd new 查重 + 新增 prd update）
- 修改：`ai/skills/pallastrade-prd/SKILL.md`（查重/回写流程）
- 依赖：Node 内置（readdirSync/readFileSync），无新依赖
- 影响面：仅 harness CLI + skill 文档

## 8. 测试计划

- `npm run test:harness`（harness 契约测试）
- 手动：`prd new --title "OSS 图片缓存优化"` → 应提示相似 PRD；`--force` 可新建；`prd update` 回写验证
- 映射：AC-001~003

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-prd/SKILL.md`（查重/回写流程）
- [x] `docs/prd/README.md` 索引
- [x] `AGENTS.md` / `copilot-instructions.md`（PRD 查重回写流程）
- [x] `harness/scenarios/scenarios.json`（新增 GS-016 PRD dedupe eval scenario）
- [x] PRD 状态更新

**知识评估结论**（sync-check）：pallastrade-prd Skill 已更新 §2.1/§10；AGENTS.md + copilot-instructions.md 的查重步骤改为机制自动执行 + 回写；scenarios.json 新增 GS-016 覆盖查重回写行为。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿 | AI |
| 2026-08-09 | 0.2 | 实施完成：cli.mjs prd new 查重（查询覆盖率 + 最小交集）与 --force、新增 prd update 回写；SKILL.md 查重/回写流程更新；契约测试 11/11 通过 | AI |
