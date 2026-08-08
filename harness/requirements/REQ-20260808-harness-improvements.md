# REQ-20260808-harness-improvements — Harness 评级改进建议实施

- 日期：2026-08-08
- 任务类型：feature（优化：harness 改进建议实施）
- Gate：GATE-2026-08-08T03-20-30
- 分支：main @ e916045f

## 1. 背景

对 PallasTrade Harness 工程化机制评级（7.6/10, L3）后，产出 6 项改进建议。本 REQ 实施全部 6 项：

| # | 优先级 | 事项 | 说明 |
|---|---|---|---|
| I-1 | P0 | 修复 AP-009a 检测误报 | 改为"静态字符串 redirect + 附近有 guard 则豁免" |
| I-2 | P1 | gate git 级校验 | pre-commit 检查当前分支存在已清除 gate |
| I-3 | P1 | 跨 agent 危险操作/密钥防护 | 新增 scan-secrets，接入 lefthook + CI |
| I-4 | P2 | 场景执行器 | 静态 readiness 校验 + 预留 LLM 执行器接口 |
| I-5 | P2 | 覆盖率门禁 | harness coverage 检查 + storefront 接入 vitest coverage |
| I-6 | P3 | evidence 接入 release + CI | release 证据纳入 harness evidence，CI 产出证据 artifact |

## 2. 跨层搜索结果（R4）

| 层 | 搜索关键词 | 发现 |
|---|---|---|
| backend/app/ | simplecov, coverage | `spec/rails_helper.rb` 已配 SimpleCov（minimum line:80 branch:60 + Cobertura）；无 harness 覆盖率门禁 |
| core gem | coverage, testing | 测试助手在 host spec 加载；gem 自身无独立覆盖率配置 |
| api gem | coverage, testing | `testing_support/v3/base.rb`（api_key factory）；无覆盖率配置 |
| admin gem | coverage, testing | Capybara 支持；无覆盖率配置 |
| storefront/src/ | coverage, vitest | `vitest.config.ts` **无 coverage 配置**；无 `@vitest/coverage-v8` 依赖 |
| platform/packages/ | coverage, vitest | sdk / admin-sdk 已有 `@vitest/coverage-v8` + coverage 配置（provider:v8）；sdk 有 `test:coverage` |

其他关键发现：
- AP-009a 三处 error 违规（`middleware.ts:102` / `layout.tsx:72` / `checkout/[id]/page.tsx:46`）逐行核查均为**误报**：均有 guard 或跳转动态路径
- `ai/hooks/warn_on_secrets.sh` / `block_destructive_db.sh` 含完整密钥/危险命令模式（但仅 Claude 生效）
- `release-manifest.yml` 已调用 `ci-evidence.mjs`（可扩展）
- `eval-ai.mjs --scenarios` 只有契约校验，无执行器

## 3. Skill 咨询证据表（R2）

| Skill | 咨询结论 |
|---|---|
| pallastrade-customization | 本任务属 harness 基础设施自建（scripts/harness 为活跃建设区），直接修改 `scripts/harness/` 与 `harness/`，不涉及 gem/host 定制 |
| pallastrade-testing | 后端覆盖率标准：SimpleCov line 80/branch 60（已有）；TS 侧 vitest v8 provider 模式（参照 sdk） |

## 4. 实施方案

### I-1 AP-009a 误报修复（P0）

**根因**：`redirect\s*\(` 正则命中所有 redirect 调用，无 guard 感知。

**方案**：
- `harness/policies/anti-patterns.json`：AP-009a 改为
  - `pattern`: `redirect\s*\(\s*['"]`（仅命中"硬编码字符串路径"的 redirect——这是自循环的真实危险形态）
  - 新增规则字段 `guardPattern` + `guardLookback`
- `scripts/harness/scan-anti-patterns.mjs`：规则命中时，向前 `guardLookback` 行内匹配 `guardPattern` 则豁免
- 效果：3 处误报清零；真实 `redirect('/us/en')` 无 guard 仍被拦截

### I-2 gate git 级校验（P1）

- `scripts/harness/cli.mjs` 新增 `gate:required` 命令：检查当前分支存在 `cleared:true` 且未过期的 gate（按类型 24/48h），否则 exit 1
- `lefthook.yml` pre-commit 新增 `harness-gate` 命令
- 逃生阀 `HARNESS_GATE_SKIP=1`（对齐 `PALLASTRADE_HOOKS_DISABLE=1` 模式）

### I-3 跨 agent 危险操作/密钥防护（P1）

- 新增 `scripts/harness/scan-secrets.mjs`：扫描代码中的
  - 密钥形态（复用 warn_on_secrets.sh 全部模式：sk_live_/rk_live_/sk_/AKIA/ghp_/gho_/github_pat_/sk-/sk-ant-/敏感变量赋值）
  - 破坏性代码（复用 block_destructive_db.sh：db:drop/db:reset/DROP TABLE/DELETE FROM pallastrade_*/delete_all/destroy_all）
  - 排除 .env.example / README / lockfile（与 warn_on_secrets.sh 一致）
- `lefthook.yml` pre-commit 新增 `harness-secrets`（限 staged）
- `.github/workflows/harness-full.yml` 新增 `secrets` job（全仓扫描）
- 保留 Claude hooks 不变（Claude 下仍生效）

### I-4 场景执行器（P2）

- 新增 `scripts/harness/eval-scenarios.mjs`：
  - `readiness` 模式：逐 GS 场景静态校验其引用的能力是否存在（GS-001 生成器、GS-002 dependencies、GS-003 支付网关、GS-004 SDK、GS-005/006 hooks 脚本、GS-007 无 v1 路由、GS-008 doc-impact 规则、GS-009 doctor、GS-011 category 控制器），任一缺失 exit 1
  - `--prompts` 模式：输出每个场景的 LLM 执行 prompt（为未来 LLM 执行器预留接口）
- `scripts/harness/cli.mjs`：新增 `eval-scenarios` 命令；`check --profile full` 接入 `ai-scenarios`（本地执行 readiness）

### I-5 覆盖率门禁（P2）

- 新增 `scripts/harness/coverage.mjs`：
  - 解析 backend `coverage/cobertura-coverage.xml`（SimpleCov 已产出）与 storefront/platform `coverage/coverage-summary.json`（vitest v8）
  - 与 `harness/config.json` 中 `coverage.thresholds` 比较；`--enforce` 时低于阈值 exit 1
- `harness/config.json`：新增 `coverage` 阈值配置；`full` profile 加入 `coverage`
- `storefront/vitest.config.ts`：加 coverage（provider:v8, include src, json-summary reporter）
- `storefront/package.json`：新增 `test:coverage` 脚本 + `@vitest/coverage-v8` devDependency（需 pnpm install 更新 lockfile）
- `.github/workflows/harness-full.yml` 新增 `coverage` job（storefront coverage + backend 已有数据 → `coverage --enforce`）

### I-6 evidence 接入 release + CI（P3）

- `scripts/release/ci-evidence.mjs`：在 release evidence 中嵌入 harness evidence（doctor / anti-patterns / affected）
- `.github/workflows/harness-full.yml` 新增 `evidence` job：运行 `harness evidence` 并 upload artifact

## 5. 涉及文件清单

**新增**：
- `scripts/harness/scan-secrets.mjs`
- `scripts/harness/eval-scenarios.mjs`
- `scripts/harness/coverage.mjs`

**修改**：
- `harness/policies/anti-patterns.json`（AP-009a）
- `scripts/harness/scan-anti-patterns.mjs`（guard-aware）
- `scripts/harness/cli.mjs`（gate:required / eval-scenarios / coverage / ai-scenarios 接线）
- `scripts/harness/harness.test.mjs`（新增 scanner 契约测试）
- `lefthook.yml`（gate:required + secrets 两个 pre-commit 命令）
- `harness/config.json`（coverage 阈值 + full profile）
- `storefront/vitest.config.ts`（coverage）
- `storefront/package.json`（test:coverage + devDep）
- `.github/workflows/harness-full.yml`（secrets / coverage / evidence job）
- `scripts/release/ci-evidence.mjs`（嵌入 harness evidence）

## 6. 验证计划

| 变更 | 验证 |
|---|---|
| AP-009a | `scan-anti-patterns.mjs scan` 后 error 数 3→0；harness.test.mjs 新增用例 |
| gate:required | 有 gate 分支 exit 0 / 无 gate 分支 exit 1（node 直测） |
| scan-secrets | 构造含密钥/危险命令的临时文件 → exit 1；干净文件 → exit 0 |
| eval-scenarios | `eval-scenarios --readiness` 全部 ✅（或记录缺失） |
| coverage | 本地无数据时 warning；storefront 跑 `test:coverage` 后解析成功 |
| evidence | `cli.mjs evidence` 正常产出 artifact |
| 整体 | `harness check --profile quick` 通过；harness.test.mjs 5+ 用例全过 |

## 7. 不做（范围外）

- promptfoo 等真实 LLM 执行器（仅预留接口）
- 危险命令的终端级拦截（git 无法拦截 shell 键入；保留 Claude hooks 覆盖）
- 覆盖率的 CI 强制跑完整测试（后端复用 CI 已生成的 SimpleCov 数据）
