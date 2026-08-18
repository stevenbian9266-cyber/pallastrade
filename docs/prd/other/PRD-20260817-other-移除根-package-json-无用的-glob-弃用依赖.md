# PRD-20260817-other-移除根-package-json-无用的-glob-弃用依赖

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-08-17 实施完成，commit eed376d 已推送 dev） |
| 创建日期 | 2026-08-17 |
| 来源 | 「分析：pallastrade-harness 是否更新到 GitHub + glob 弃用信号」→ 确认实施删除无用 glob 依赖 |
| 分类 | other（自动判定，关键词命中 0） |
| 关联 Skill | 无（纯依赖清理，非业务领域） |
| 关联 REQ | REQ-20260817-remove-root-glob-dep（实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 优化迭代 |

---

## 1. 背景与目标

- **一句话需求原文**：优化：移除根 package.json 无用的 glob 弃用依赖。
- **背景**：
  1. 调查发现根 `package.json` 的 `dependencies` 里有唯一一项 `"glob": "^11.0.0"`，而 `glob@11` 已被官方标记 deprecated（锁文件标注：旧版本含已公开安全漏洞，当前版本为 glob@13）。
  2. 全仓库搜索确认：根目录与 `scripts/` 下**没有任何代码 `import glob`** —— 该直接依赖是**无用残留**。
  3. 注：`glob@11.1.0` 仍会以 `pallastrade-harness@1.1.2` 的传递依赖存在（harness 包内部依赖），本次不处理（属上游，等 harness 发新版）。
- **目标**：删除根 `package.json` 无用的 `glob` 直接依赖，`pnpm install` 同步锁文件，消除项目自身声明的弃用依赖。
- **成功指标**：根 `package.json` 无 glob 直接依赖；`pnpm-lock.yaml` importer 的 `.` 段不再声明 glob；`npx harness` 仍正常工作。

## 2. 用户故事 / 场景

- 作为**仓库维护者**，我希望根依赖清单不声明已弃用且未使用的包，以便 `npm audit`/`pnpm audit` 无多余告警、依赖树干净。
- 场景：
  - 正常流：删 glob 依赖 → `pnpm install` 成功 → `npx harness` 命令可用（doctor/status）。
  - 边界：glob@11.1.0 仍作为 harness 传递依赖存在于锁文件（预期保留，非本次范围）。
  - 异常：若某脚本实际用了 glob（已搜索排除，无此情况）→ 改为显式声明。

## 3. 功能需求（FR）

- FR-001：根 `package.json` 移除 `dependencies.glob`（整块 dependencies 清空或移除该键）。
- FR-002：`pnpm install` 重新生成 `pnpm-lock.yaml`（importer `.` 段不再有 glob specifier）。
- FR-003：`npx harness`（doctor/status/gate:status）与 lefthook 正常可用（harness 引擎不受影响）。

## 4. 非功能需求（NFR）

- 兼容：不改变任何运行时行为（glob 未被引用）；harness 包自带 glob 不受影响。
- 可维护：依赖清单干净，无弃用声明。
- 可验证：`pnpm install` 干净、`npx harness` 命令可用。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`package.json` 中不再含 `"glob"` 依赖项。
- AC-002 ← FR-002：`pnpm-lock.yaml` importer `.` 段不再声明 `glob: ^11.0.0`；`pnpm install --frozen-lockfile` 校验通过（锁文件一致）。
- AC-003 ← FR-003：`npx harness --help` 或 `gate:status` 正常退出 0；`npx lefthook` 配置可解析。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | glob | 无 | 不涉及 |
| Core | `pallastrade_gems/pallastrade_core/app/` | glob | 无 | 不涉及 |
| API | `pallastrade_gems/pallastrade_api/app/` | glob | 无 | 不涉及 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | glob | 无 | 不涉及 |
| Storefront | `storefront/src/` | glob | 无（storefront 有自己的 pnpm-workspace 与 glob 依赖） | 不涉及（不动 storefront） |
| Platform | `platform/packages/` | glob | 无 | 不涉及 |

**结论**：全仓库无代码引用根 `glob` 包；storefront/platform 各自工作区独立，不受根 package.json 影响。删除安全。

## 7. 技术影响

- 涉及文件：根 `package.json`、`pnpm-lock.yaml`。
- 影响面：根依赖树（移除 glob 直接声明；`glob@11.1.0` 仍作为 harness 传递依赖保留在 `packages` 段）。`harness affected` 预期无业务组件受影响。
- 无数据库/接口/后端改动。

## 8. 测试计划

- 无单元测试（纯依赖清单清理）。
- 验证（AGENTS.md §6 配置类变更）：
  - `pnpm install`（或 `--frozen-lockfile` 校验）干净通过。
  - `npx harness --help` / `npx harness gate:status` 正常（引擎可用）。
  - `npx lefthook` 配置解析正常。
  - `harness check --profile quick` 通过（doc-impact 规则覆盖 package.json 变更 → 需同步知识文档）。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：不涉及
- [x] Skill 文档：`package.json` 变更命中 doc-impact 规则（anyOf AGENTS.md / pallastrade-prd SKILL / scenarios.json）→ 评估：纯依赖清理无流程机制变更，结论记入本 PRD §10，doc-impact 判定后按需补充
- [x] README / 规范：无
- [x] 反模式 / 场景库：无
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-17 | 0.1 | 初稿（FR-001~003 / AC-001~003）；用户"优化"确认 → approved | AI |
