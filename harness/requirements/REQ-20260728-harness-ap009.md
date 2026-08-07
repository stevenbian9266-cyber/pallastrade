# REQ-20260728-harness-ap009

## Step 0：跨层搜索

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 发现 |
|---|---|---|---|---|
| App | `backend/app/` | redirect, catch, empty array | 无直接相关 | — |
| Core | `pallastrade_core/` | redirect, middleware | 无 | — |
| API | `pallastrade_api/` | authenticate, 401 | `api_key_authentication.rb` | 401 是触发源 |
| Admin | `pallastrade_admin/` | redirect, catch | 无 | — |
| Storefront | `storefront/src/` | redirect(), .catch(() => []) | `layout.tsx` (主), `addresses/page.tsx`, `middleware.ts` | 找到 2 处 AP-009 模式 |
| Platform | `platform/packages/` | redirect, catch | 无 | — |

### 现存的 AP-009 模式（扫描结果）

1. **`storefront/src/app/[country]/[locale]/layout.tsx:51,72`** — catch 返回 `[]` → redirect 到同 URL → 无限循环 ✅ 已修复
2. **`storefront/src/app/[country]/[locale]/(storefront)/account/addresses/page.tsx:28`** — `catch(() => ({ data: [] }))` — 潜在风险（低，不触发 redirect）

---

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读 | 修改 Harness 体系属于配置/工具链级别，不涉及应用层代码 |
| `pallastrade-storefront` | ✅ 已读 | Storefront 中 `redirect()` 使用模式已确认 |

---

## 需求标题
Harness 机制：新增 AP-009 "降级态自循环" 反模式及配套检测

## 任务类型
功能优化 (feature)

## 需求描述

前一次 Bug（页面无限重定向）暴露了一个通用缺陷模式：当 API 失败时，降级逻辑返回空集合，然后空集合导致重定向到与当前 URL 相同的地址，形成无限循环。这需要一个通用的架构约束来预防。

### 方案内容

1. **`harness/policies/anti-patterns.json`** — 新增 AP-009 规则
2. **`scripts/harness/check-degraded-loop.mjs`** — 新建启发式检测脚本
3. **`scripts/harness/cli.mjs`** — 将 check-degraded-loop 集成到 `harness check` 流程
4. **`AGENTS.md`** — 反模式表新增 AP-009

### AP-009 定义

- **ID**: AP-009
- **名称**: degraded-loop（降级态自循环）
- **严重程度**: error
- **规则**: catch 块返回空集合 `[]` 且该空集合被用于判定逻辑 → 判定失败 → redirect/retry 到当前状态 → 无限循环
- **检测**: 静态检测（grep 模式匹配）+
  启发式 AST 扫描（redirect 目标与当前 URL 比较）

## 影响范围

| 文件 | 操作 | 说明 |
|---|---|---|
| `harness/policies/anti-patterns.json` | 修改 | 新增 AP-009 |
| `scripts/harness/check-degraded-loop.mjs` | 新建 | 检测脚本 |
| `scripts/harness/cli.mjs` | 修改 | 集成到 check 命令 |
| `AGENTS.md` | 修改 | 同步反模式表 |

## 技术方案

- 层级：Harness 配置层（`harness/policies/` + `scripts/harness/`）
- 选择理由：不涉及应用代码，纯粹的工具链改进
- 检测方式：正则 + AST 启发式（复用现有 scan-anti-patterns 模式）

## 风险点

- 误报：部分 `catch(() => [])` 模式可能是安全的（如仅用于渲染空列表）→ 使用 severity: warning
- 跨层覆盖：Storefront（TypeScript）+ Backend（Ruby）都需要不同的检测规则
