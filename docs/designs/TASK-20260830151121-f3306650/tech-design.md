# 技术设计 — 修复 SKILL 权威路径（TASK-20260830151121-f3306650）

> 本任务是纯 SKILL 文档路径引用修正，无代码逻辑变化。以下为现状识别（Part A）与复用决策（Part B）。

## Part A：现状识别

### A1 业务系统盘点

- 升级 `pallastrade-harness` 1.8.0 后，`harness scan` 资产治理报告 4 个 SKILL 的"权威路径失效"（should 级）
- 涉及系统：AI Skills 知识库（`ai/skills/`）、Harness 资产治理扫描器（`harness scan` / `skill check --freshness`）
- 无业务功能系统受影响

### A2 数据模型识别

- 无数据库模型变更
- 涉及文件均为 Markdown 文档（SKILL.md），非数据表

### A3 字段盘点

- 4 个 SKILL.md 中各 1 处路径引用需修正（共 4 处）：
  1. `pallastrade-typescript-sdk/SKILL.md` L526：`pallastrade/api/app/serializers/**/*.rb` → `backend/pallastrade_gems/pallastrade_api/app/serializers/**/*.rb`
  2. `pallastrade-cli/SKILL.md` L40：`.pallastrade/credentials.json` 去掉反引号并明确"运行时生成、gitignored、不入库"
  3. `pallastrade-extensions/SKILL.md` L100：`lib/pallastrade_simple_sales/engine.rb` 标注"generated 模板结构"
  4. `harness-standards-audit/SKILL.md` L52：`rules/base-standards.json` 改写为"引擎随包分发内置基线"（不含反引号路径）

### A4 代码结构

- 涉及目录：`ai/skills/`（4 个 SKILL.md）
- 相关代码结构：`backend/pallastrade_gems/pallastrade_api/app/serializers/`（145 个文件，已 glob 验证）
- 无代码文件变更

## Part B：复用决策矩阵

| 需求 | 决策 | 目标 | 依据 |
|---|---|---|---|
| 修正 SDK SKILL 路径 | 调用已有 | `backend/pallastrade_gems/pallastrade_api/app/serializers/` | 已有 145 个 serializer 文件，直接引用真实路径 |
| 修正 CLI SKILL 路径 | 调用已有 | 现有文档表述 | 运行时产物路径，调整表述而非新建文件 |
| 修正 Extensions SKILL 路径 | 调用已有 | 现有文档表述 | 生成器模板结构，标注示例性质 |
| 修正 Standards SKILL 路径 | 调用已有 | 现有文档表述 | 引擎内置基线，改写为说明性表述 |
| 修复验证 | 调用已有 | `harness scan` / `skill check --freshness` / `docs:check` | 复用既有机械校验命令，无需新工具 |

## 技术方案

1. 逐文件修正 4 处路径引用（见 A3 字段盘点）
2. 保留文档语义：不因规避检查而丢失"凭据保存位置 / 扩展模板结构 / 引擎基线"等技术信息
3. 验证：`harness scan` + `skill check --freshness` 确认 4 项失效消失；`docs:check` 确认无断链

## 风险与回滚

- 风险：低（纯文档文本修正）
- 回滚：`git checkout -- ai/skills/` 即可恢复
