# PRD-20260831-infra-部署脚本固化与容错-deploy-sf-固化-pull-deploy-磁盘预检与-flock-超时-deploy-rea

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-31 |
| 来源 | 优化：部署脚本固化与容错（deploy-sf 固化 + pull-deploy 磁盘预检与 flock 超时 + deploy README 规范） |
| 分类 | infra（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-{YYYYMMDD}-{category}-{slug}

| 元数据 | 值 |
|---|---|
| 状态 | draft / reviewing / approved / implementing / verifying / done / rejected / merged |
| 创建日期 | YYYY-MM-DD |
| 来源 | 一句话需求原文 |
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

- AC-001 ← FR-001：<可验证的判定条件>
- AC-002 ← FR-002：<可验证的判定条件>

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
