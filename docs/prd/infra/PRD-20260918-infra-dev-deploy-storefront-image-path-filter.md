# PRD-20260918-infra-dev-deploy-storefront-image-path-filter

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-18 |
| 来源 | 「修复这两个问题」（承接上一轮结论：服务器 cron 每轮部署前白等最多 900 秒拉取 storefront 镜像） |
| 分类 | infra（关键词命中 2） |
| 关联 Skill | `pallastrade-deployment`（本地/远端部署与 docker exec 排障）、`harness-skill-author`（repo 守卫测试） |
| 关联 REQ | REQ-20260918-dev-deploy-image-path-filter.md |
| 关联 PRD | N/A |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：`修复这两个问题`（两个问题之一 = 「服务器 cron 每轮白等 900 秒（GHCR 拉取恒超时）」）
- **背景（含对初判的修正）**：
  1. `.github/workflows/deploy.yml` 对 dev 的**每次 push** 都重建并推送 storefront 镜像，**没有任何 paths 过滤**；构建产物包含源码 mtime 等因素，因此**即使 storefront 一个字节都没改，也会产出新的 manifest digest**。
  2. 服务器 `deploy/pull-deploy.sh` 每轮都执行 `timeout 900 docker pull ghcr.io/.../pallastrade-storefront:dev`。
  3. **修正**：起初怀疑「拉取恒超时（空转）」。2026-09-18 在服务器实测：镜像收敛后 `docker pull` 在交互式/重定向/`-q`/后台四种上下文下都是 **1–2 秒**返回（`Status: Image is up to date`）。也就是说 **900 秒不是空转，而是真实下载**（跨境带宽 + 新 manifest）。
  4. 真正的问题因此是**耦合**：只要推送（哪怕只改后端）就产生新镜像 → 服务器必须先花最多 900 秒下载，**才轮到代码部署**；期间所有 5 分钟一圈的 cron tick 都被 flock 跳过（实测 14:00 与 14:35 两轮均如此）。**后端改动的部署被无谓推迟最多 15 分钟。**
- **目标**：让「与 storefront 构建输入无关」的推送**不再产生新镜像** → 服务器拉取退化为秒级 no-op → 代码部署立即开始。
- **成功指标**：
  - backend-only 推送后，服务器 `docker pull` 阶段耗时 **< 5s**（当前最多 900s）；
  - `git push` → 代码在容器内生效（`/rails/.deployed-revision`）的延迟 **下降 ≥ 10 分钟**；
  - storefront 改动仍然产出新镜像（不得漏构建）。

## 2. 用户故事 / 场景

- 作为维护者，我推一个只改后端的提交，希望 dev 在几分钟内生效，而不是先等一个内容没变的 storefront 镜像下载 15 分钟。
- 正常流：推送 `storefront/**` 或 SDK 包 → 镜像重建并推送 → 服务器拉取并重建 storefront 容器。
- 正常流：推送仅后端文件 → Deploy 工作流不触发 → 服务器 `docker pull` 秒回 `up to date` → 直接进入代码部署。
- 边界：同时改后端与 storefront → 与今天一致（重建镜像）。
- 异常：需要强制重建镜像时（例如构建参数/基础镜像变更、镜像损坏）→ `workflow_dispatch` 手工触发。

## 3. 功能需求（FR）

- FR-001：`deploy.yml` 仅在 storefront **构建输入**变化时运行（`on.push.paths` 过滤）。
- FR-002：过滤集合必须覆盖 `storefront/Dockerfile` 的**全部 COPY 来源**（构建上下文是仓库根，Dockerfile 实际 COPY 了 `storefront/**` 与 `platform/packages/{sdk,sdk-core,cli}`）。
- FR-003：保留 `workflow_dispatch`（手工强制重建）与 `branches: [dev]`。
- FR-004：机器守卫——当有人给 Dockerfile 增加新的 COPY 来源却忘了同步 `paths` 时，必须有测试失败（否则本优化会静默地把 storefront 变更挡在构建之外）。

## 4. 非功能需求（NFR）

- 不改变服务器侧 `pull-deploy.sh` 的语义（仍按 HEAD 或镜像 digest 变化判定是否部署）。
- 守卫测试秒级、零外部依赖（只读文件），可进 `repo-guards-test` 验证器与 CI。
- 兼容：不引入新的 secret / 变量；不改动镜像 tag 方案（仍 `:dev`）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`deploy.yml` 的 `on.push` 存在 `paths` 过滤且**非空**。
- AC-002 ← FR-002：`storefront/Dockerfile` 中每个 `COPY <src>` 的来源都被 `paths` 中某个 glob 覆盖。
- AC-003 ← FR-003：`workflow_dispatch` 与 `branches: [dev]` 仍存在。
- AC-004 ← FR-004：新增一个未覆盖的 COPY 来源时，守卫测试必须失败（用「把过滤集合与 COPY 来源求交集」的判定实现，并在测试内自证判定有效）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `ghcr\|pull-deploy\|storefront image\|镜像` | 0 | 不涉及（部署链路不在 App 层） |
| Core | `pallastrade_gems/pallastrade_core/app/` | 同上 | 14（均为「镜像」字样，如 npm 镜像源注释） | 否（与部署流水线无关） |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | 0 | 不涉及 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 同上 | 2（同为「镜像」字样） | 否 |
| Storefront | `storefront/src/` | 同上 | 3（`npmmirror` 等镜像源字样） | 否 |
| Platform | `platform/packages/` | 同上 | 2（镜像源字样） | 否 |

**结论**：本能力**不在任何应用层**，唯一权威面是 CI/部署配置：`.github/workflows/deploy.yml`（构建+推送）、`deploy/pull-deploy.sh`（服务器拉取）、`storefront/Dockerfile`（构建输入定义）、`tests/*.test.mjs`（既有 repo 守卫族）。因此**不新建应用层代码**，只改 CI 配置 + 新增守卫测试。

## 7. 技术影响

- 涉及文件：`.github/workflows/deploy.yml`（+ `paths` 过滤与说明注释）、`tests/deploy-paths-filter.test.mjs`（新增）、`harness.config.mjs`（`repo-guards-test` 纳入新测试）、`AGENTS.md` §6（repo-guards 行描述）、`deploy/README.md`（说明过滤与手工重建）。
- 数据库/接口/序列化：**零影响**。
- 影响面：`harness affected` 在本仓对 `origin/main...HEAD` 取 diff 会失败（dev-only 仓），以人工判定为准 —— 改动只涉及 CI 触发条件与守卫测试。

## 8. 测试计划

- 新增：`tests/deploy-paths-filter.test.mjs`
  - AC-001 `deploy.yml` 存在非空 `paths`
  - AC-002 Dockerfile 的 COPY 来源 ⊆ `paths` 覆盖集合
  - AC-003 `workflow_dispatch` + `branches: [dev]` 保留
  - AC-004 判定有效性自证（构造一个未被覆盖的假 COPY 来源，断言判定函数返回「未覆盖」）
- 更新：`harness.config.mjs`（`repo-guards-test` 命令追加该测试文件）
- AC 映射：AC-001..004 → `tests/deploy-paths-filter.test.mjs`（测试内以注释标注 `# PRD-20260918-infra-dev-deploy-storefront-image-path-filter AC-00x`）

## 9. 文档同步清单（知识同步门）

`harness sync-check --id PRD-20260918-infra-dev-deploy-storefront-image-path-filter` 结论逐项登记：

| 同步门资产 | 本批结论 | 依据 |
|---|---|---|
| `pallastrade-deployment Skill` | ✅ updated | 新增「storefront 镜像的重建触发条件」小节（触发集合 + 机器守卫 + 手工强制重建 + 判断口诀）；并订正「拉取慢 ≠ 拉取空转」的实测事实 |
| 部署 README（`deploy/README.md`） | ✅ updated | 拉取式机制第 1 条改为「监听 `[dev]` 且仅当构建输入变化时」，并补「为什么加过滤 / 如何强制重建」说明块 |
| `.env.example` | ⛔ not-applicable | 本批未新增/修改任何环境变量（只改 CI 触发条件） |
| `AGENTS.md` | ✅ updated | §6 repo-guards 行补「部署路径过滤守卫（Dockerfile COPY 来源 ⊆ deploy.yml paths）」 |
| `scenarios.json` / `场景库` | ✅ updated | 新增 GS-182「A backend-only push must not rebuild the storefront image」（`eval-ai --scenarios` 183/183 valid） |
| `pallastrade-prd Skill` | ➖ reviewed-no-change | PRD 流程本身未变（本批按既有 `prd new` → 模板扩充 → REQ → gate 流程执行） |
| `copilot-instructions.md`（R0–R9） | ➖ reviewed-no-change | 强制命令速查未变；本批未新增规则，只登记一件部署事实 |
| API 文档 / `pallastrade-api-v3 Skill` / SDK 类型 | ⛔ not-applicable | 本批**零 API 改动**；sync-check 的「API 端点变更」组由**并行会话的未提交文件**（`payment_sessions_controller.rb`）触发，与本 PRD 无关 |
| 迁移 / schema.rb / 反模式清单 | ⛔ not-applicable | 零数据库、零应用层代码 |

## 10. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-09-18 | 创建 | 由「服务器每轮白等 900 秒」引出；实测修正了「空转」初判，改为「镜像重复产出 → 部署被下载阻塞」的耦合问题 |
| 2026-09-18 | 实施完成 | `deploy.yml` 加 `paths` 过滤 + `tests/deploy-paths-filter.test.mjs`（AC-001..004，含判定自证）+ `repo-guards-test` 纳管 + 文档三处同步；`repo-guards-test` 全绿 |
