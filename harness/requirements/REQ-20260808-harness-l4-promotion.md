# REQ-20260808-harness-l4-promotion — Harness L4 三项改进

> 关联 PRD：`docs/prd/harness/PRD-20260808-harness-l4-promotion.md`
> 任务类型：feature（需求：实施 L4 三项）

## Step 0：跨层搜索

| 层 | 搜索路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| harness | harness/config.json | coverage.thresholds | storefront 5 / platform 5 | 目标 |
| harness | scripts/harness/coverage.mjs | vitest summary 解析 | storefront/platform 均支持 | 复用 |
| harness | scripts/harness/eval-scenarios.mjs | prompts 输出 | 15 GS 执行器 prompts | 扩展为 promptfoo |
| harness | scripts/harness/cli.mjs | check / coverage / eval-scenarios | 命令已注册 | 新增 eval-llm |
| CI | .github/workflows/*.yml | storefront/backend/platform-ci | workflow_call 组件 CI | 复用至 nightly |
| Storefront | storefront/src/ | 测试 | 4 个测试文件 | 需补充 |
| Platform | platform/packages/sdk | vitest | vitest.config.ts 存在 | 建立 coverage |
| Backend | backend/ | coverage | SimpleCov（容器内） | 已有 80/60 |

**结论**：coverage 机制已具备（coverage.mjs 支持三组件），缺"高阈值 + 数据 + 常驻执行"；promptfoo 完全未接入；nightly 无 workflow。

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 工程机制属 harness 层，走决策树无关项；本任务为工程机制扩展 |
| `pallastrade-testing/SKILL.md` | ✅ 已读 | RSpec/Vitest 测试位置约定；coverage 阈值由 harness/config.json 控制 |
| `pallastrade-prd/SKILL.md` | ✅ 已读 | §4 gate+REQ 流程；§6 接口/CI 同步 |

---

## 需求标题

Harness L4 三项改进：覆盖率门槛、nightly 全量测试常驻、promptfoo LLM Eval 执行器

## 需求描述与验收

1. **覆盖率门槛**（AC-001/002/005）：storefront 阈值 5→12%（补测试至 lines≥15%）；platform 建立基线阈值 5→10%；`harness coverage --enforce` 三组件通过
2. **nightly workflow**（AC-003）：`.github/workflows/nightly.yml`（cron 每日 + workflow_dispatch）跑 backend rspec / storefront / platform / harness full / coverage enforce
3. **promptfoo**（AC-004）：root devDependency + `harness eval-llm --generate`（GS 场景→promptfoo 配置）+ `pnpm eval:llm`；运行需用户 LLM key（不入库）

## 影响文件

- `harness/config.json`（阈值）
- `.github/workflows/nightly.yml`（新增）
- `package.json`（promptfoo + eval:llm）
- `scripts/harness/eval-llm.mjs`（新增）+ `cli.mjs`（注册）
- `harness/promptfoo/promptfooconfig.yaml`（生成，提交）
- `storefront/src/`（补测试）
- `platform/packages/sdk/`（补测试/coverage）

## 测试计划

- `harness coverage --enforce` 全组件通过
- `harness eval-llm --generate` 生成配置 + 结构校验
- `pnpm eval:llm --dry-run` 或配置加载校验（不实际调 LLM）
