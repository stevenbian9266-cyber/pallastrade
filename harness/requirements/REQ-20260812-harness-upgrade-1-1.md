# 需求文档：升级 pallastrade-harness 到 1.1.1

> 任务：TASK-20260812080025-b560b96d ｜ Gate：GATE-2026-08-12T08-00-45

---

## Step 0：跨层搜索

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | harness | — | 无 harness 接入 |
| Core | `pallastrade_core/` | harness | — | 无 |
| API | `pallastrade_api/` | harness | — | 无 |
| Admin | `pallastrade_admin/` | harness | — | 无 |
| Storefront | `storefront/` | harness | — | 无 |
| Platform | `platform/packages/` | harness | — | 无 |
| 根 | `package.json` / `lefthook.yml` / `.github/workflows/` | pallastrade-harness | package.json（^1.0.4）、lefthook（npx harness）、CI workflows | **需升级依赖** |

**结论**：harness 是根级开发工具依赖（非业务代码），仅 `package.json` + lock 需更新；lefthook/CI 用 `npx harness` 自动跟随新版本。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| pallastrade-prd | ✅ 已读 | 升级流程走 gate → REQ → 验证 → 知识同步 |
| pallastrade-customization | ✅ 已读 | 依赖升级属工具链，不改业务代码 |
| pallastrade-storefront | ✅ 已读 | 不涉及 |

## 需求标题
升级 pallastrade-harness `^1.0.4` → `^1.1.1`（Auto-Standards/Auto-Skills/Auto-Docs/onboard 新能力）。

## 任务类型
版本升级（依赖）

## 需求描述
1. `package.json` 依赖改 `^1.1.1`
2. `npm install` 更新 lock + node_modules
3. 验证：harness doctor / check quick / 引擎自测（standards/skill/onboard 新命令可用）

## 技术方案
- 改 `package.json` 依赖声明 → `npm install` → 验证 → 提交
- 不涉及业务代码/部署（harness 是开发工具）

## 风险点
- 1.1.x 新增命令（standards/skill/onboard/docs）与既有配置兼容性——通过 doctor + check quick 验证
- 回滚：`npm install pallastrade-harness@^1.0.4` 即回退

## 决策节点
> 用户已确认升级到最新版本。

---

## 阶段③：实施后验证

| 改动 | 最低验证 | 状态 |
|---|---|---|
| package.json/lock | `npx harness doctor` + `npx harness check --profile quick` | ⬜ |
| 新命令 | `npx harness standards --help` / `skill --help` / `onboard --help` | ⬜ |
| 引擎测试 | `node --test node_modules/pallastrade-harness/bin/*.test.mjs` | ⬜ |

### 验证结论
（实施后回填）
