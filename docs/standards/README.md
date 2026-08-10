# PallasTrade 规范资产索引（Standards Registry）

> 项目规范分散在多个文件（CLAUDE.md / Skill / 配置文件）中。本索引统一登记，
> 供 AI 与开发者快速定位"某项规范在哪里定义"。**本文件不重复规范内容，只做指针。**

## 规范类型与位置

| 规范类型 | 位置 | 覆盖内容 |
|---|---|---|
| **全局工程规范** | `AGENTS.md`（根） | 仓库结构、分支策略（§0.4）、gate 流程、反模式（§5）、验证要求（§6）、知识同步（§7）、危险操作（§8）、PRD 工作流（§2 Step 3） |
| **AI 强制规则** | `.github/copilot-instructions.md` | R0–R9 强制命令（前缀、gate、跨层搜索、PRD、验证证据、分支策略） |
| **分支策略** | `scripts/release/README.md` §分支策略、`AGENTS.md` §0.4 | dev 开发 + main 生产（部署/Tag 只打 main） |
| **后端规范** | `backend/CLAUDE.md`、`backend/AGENTS.md` | Rails 约定、gem 修改规则（PALLAS-CUSTOM）、测试栈（RSpec/Factory Bot/Capybara） |
| **平台规范** | `platform/CLAUDE.md`、`platform/AGENTS.md` | TypeScript 约定、Biome、包结构、发布模型 |
| **商城前端规范** | `storefront/CLAUDE.md` | Code Style（函数式组件、命名导出、绝对导入、Tailwind）、Biome、测试（Vitest/Testing Library/Playwright） |
| **样式/视觉规范** | `storefront/CLAUDE.md` §Code Style、`ai/skills/pallastrade-storefront/SKILL.md` Style Guide 章节、`ai/skills/pallastrade-admin/SKILL.md` Styling 章节、Tailwind 配置/设计 token | UI 一致性、AP-001（禁内联样式）、AP-006（禁硬编码色值） |
| **Logo 使用规范** | `docs/standards/logo.md` | Logo 源文件、各使用位置（Header/结算/邮件/og/favicon/admin）的格式与尺寸要求 |
| **Harness 独立化路线图** | `docs/standards/harness-standalone-roadmap.md` | harness 引擎解耦/开源/冷启动/渐进/自学习 + 自有项目提效的权威方案（已批准 v2） |
| **领域技术规范** | `ai/skills/*/SKILL.md`（24 个） | 各领域约定：API v3（前缀 ID/分页/scope）、数据模型、事件、支付、i18n 等 |
| **API 接口规范** | `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/` | OpenAPI：端点、参数、响应包络、错误 |
| **反模式库** | `harness/policies/anti-patterns.json` | AP-001~AP-009（CI 强制） |
| **任务规则** | `harness/policies/task-rules.json` | TR-001~（AI 执行规则） |
| **PRD 分类规则** | `harness/policies/prd-categories.json` | PRD 自动分类关键词 |
| **评估场景库** | `harness/scenarios/scenarios.json` | GS-xxx Eval 场景（AI 行为验证） |
| **格式化/静态检查** | `biome.json`（platform + storefront）、`backend/.rubocop.yml`（如有） | 代码格式与静态检查 |

## 规范变更流程

1. 修改规范定义文件（上表左列）→ 按 `AGENTS.md` §7 同步矩阵更新关联文档
2. 新增反模式 → `harness/policies/anti-patterns.json` + `AGENTS.md` §5 + `.github/copilot-instructions.md`
3. 新增任务规则 → `harness/policies/task-rules.json` + `AGENTS.md`
4. 本索引本身被修改 → 运行 `harness docs:check` 验证引用
