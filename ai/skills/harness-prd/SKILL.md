---
name: harness-prd
description: Use when the user gives a one-line requirement (一句话需求) and expects AI to expand it into a full PRD and drive the whole development loop — PRD creation (categorized, named, indexed), user confirmation, harness gate, implementation, acceptance criteria, and the knowledge-sync gate. Also use to update a PRD or create a missing PRD for an existing feature. Common phrasings include "一句话需求", "生成PRD", "写PRD", "更新PRD".
---

# Harness PRD-driven workflow（Auto-Docs：PRD 工作流）

> 用户一句话需求 → 详细 PRD → harness 门禁实施 → 测试/验收 → 知识同步 → 收尾。
> 本项目为通用版：分类与跨层搜索由 `harness.config.mjs` 的 `layers`/`prd.categories` 声明。

## 1. 触发与判定

- 一句话需求（含前缀 `需求：`/`新增：`/`优化：`/`修复：` 等）→ 走本工作流
- 提问（怎么/什么是/为什么）→ 直接回答，不走本工作流

## 2. 阶段 0：PRD 生成

1. 运行 `npx harness prd new --title "<需求>"`（自动分类 + 查重，相似度 > 0.3 阻止新建）
2. 命中相似 PRD → `npx harness prd update` 回写原 PRD，不新建
3. 使用模板 `docs/prd/_TEMPLATE.md`，命名 `PRD-{YYYYMMDD}-{category}-{slug}.md`
4. **必须自动扩充正文**（不得只复制一句话）：
   - 背景 / 目标 / 成功指标
   - 用户故事 + 场景（正常/边界/异常）
   - FR（功能需求，可验收）
   - AC（验收标准，每个 FR ≥1 个 AC，可测试）
   - 技术影响 + 测试计划 + 文档同步清单
5. 状态 `draft`；更新 `docs/prd/README.md` 索引

## 3. 阶段 1：用户确认

- 呈现 PRD 摘要 → 用户确认 → 状态 `approved`
- 未确认 → 保持 draft，不进入实施

## 4. 阶段 2-5：实施 / 验证 / 知识同步 / 收尾

- gate → 实施 → 测试（AC↔测试映射，`npx harness prd verify --id PRD-xxx`）
- 文档同步 → evidence → finish

## 5. REQ 简版规范（2026-08-31）

> token 优化（见 docs/research/RESEARCH-20260831-harness-token-optimization.md §5.3）。

**轻量维护任务**（文档/路径修复/小配置，改动 ≤5 文件且无逻辑变更）可走**简版 REQ**：

| 项 | 简版 | 完整版 |
|---|---|---|
| Step 0 跨层搜索 | ✅ 必填（6 层结论） | ✅ |
| Step 1 skill 咨询 | 只填涉及的领域 | 全表 |
| 需求描述 | 一段话 | 完整 |
| 验证方案 | ✅ 必填（AC 映射命令） | ✅ + 测试计划 |
| 用户确认 | ✅ 必填 | ✅ |

判定：改动 ≤5 文件且无逻辑变更 → 简版；否则完整版。核心监督（跨层搜索 + 验证 + 确认）任何版本都保留。
