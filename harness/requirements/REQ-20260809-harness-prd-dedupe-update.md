# REQ-20260809-harness-prd-dedupe-update

## 需求
harness PRD 查重回写机制升级：`prd new` 自动查重（相似 PRD 提示回写而非新建），新增 `prd update` 回写命令。

## 背景
- 当前 `prd new` 仅幂等保护（同名拒绝），无相似度查重 → 同类需求重复新建 PRD
- SKILL.md §2.1 有查重步骤但靠 AI 自觉

## 方案
1. `scripts/harness/cli.mjs`：
   - `prd new` 扫描 `docs/prd/**`，标题相似度（英文词 + 中文 2-gram Jaccard）> 0.3 时提示候选 PRD + 建议回写，exit 1；`--force` 跳过
   - 新增 `prd update --path <file> --title "<需求>"`：向目标 PRD 追加来源/变更记录
2. `ai/skills/pallastrade-prd/SKILL.md`：§2.1/§3 更新为机制自动查重 + 回写流程

## Skill 咨询证据表
| Skill | 关键结论 |
|---|---|
| pallastrade-prd | 查重步骤 §2.1（AP-SEARCH 反模式），需机制化 |
| pallastrade-customization | 不适用（harness 工程系统） |
| pallastrade-deployment | 不适用 |

## 验证
- `npm run test:harness` 契约测试通过
- 手动：`prd new --title "OSS 图片缓存优化"` 提示相似 PRD；`--force` 新建；`prd update` 回写
- `node scripts/harness/cli.mjs prd new --title "..."` 实际验证

## 跨层搜索
- scripts/harness/cli.mjs：prd 子命令（幂等保护，无查重）→ 增强
- ai/skills/pallastrade-prd/SKILL.md：§2.1 查重 → 更新
- 其余 6 层业务无影响
