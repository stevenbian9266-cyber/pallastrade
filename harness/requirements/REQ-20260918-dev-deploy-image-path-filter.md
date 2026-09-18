# REQ-20260918-dev-deploy-image-path-filter

关联 PRD：`docs/prd/infra/PRD-20260918-infra-dev-deploy-storefront-image-path-filter.md`
任务：`TASK-20260918074058-bafcc3c9`（优化：dev 推送即重建 storefront 镜像导致服务器每轮部署前多花最多 900 秒）
分支：dev（dev-only 仓，见 `AGENTS.md` §0.4）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers/views | `backend/app/` | `ghcr` / `pull-deploy` / `storefront image` / `镜像` | 0 | 不涉及 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | 同上 | 14（均为「镜像」字样，如 npm 镜像源注释） | 否 |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | 同上 | 0 | 不涉及 |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | 同上 | 2（同为「镜像」字样） | 否 |
| Storefront | `storefront/src/` | 同上 | 3（`npmmirror` 等镜像源字样） | 否 |
| Platform | `platform/packages/` | 同上 | 2（镜像源字样） | 否 |

### 搜索结论

本能力**不在任何应用层**：唯一权威面是 CI/部署配置与守卫测试族 ——
`.github/workflows/deploy.yml`（构建 + 推送镜像）、`deploy/pull-deploy.sh`（服务器拉取判定）、
`storefront/Dockerfile`（定义 storefront 镜像的构建输入）、`tests/*.test.mjs`（既有 repo 级守卫）。
→ 不新建应用层代码，只改 CI 触发条件 + 新增守卫测试 + 文档。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树 9 行全部面向**应用层**（Settings / Config / Events / `PallasTrade.dependencies` / Admin-Ransack / Generators / Decorators / Extensions），优先级「Settings → Configuration → Events → Dependencies → Admin / Ransack → Generators → Decorators → Extensions」；本需求是 **CI/部署配置**，不属于任何一档 → 不适用定制树（也印证「不新建应用层代码」的结论） |
| `ai/skills/pallastrade-deployment/SKILL.md` | ✅ 已读 | §「PallasTrade 自有服务器部署（阿里云 dev/prod 双环境）」记录了完整链路：**CI `deploy.yml` 监听 `[dev]`，runner 构建 storefront 镜像并 push**（本批要加过滤的就是这一步）；§「pull-deploy 变化判据：**实际运行态**」明确判定依据是 ① `docker exec pallastrade-dev-web-1 cat /rails/.deployed-revision` ② storefront 容器镜像 ID —— 本优化**不改判据**，只避免「无关改动也产出新镜像」 |
| `ai/skills/harness-skill-author/SKILL.md` | ✅ 已读 | 规定领域 SKILL 的四段结构（核心概念 / 常用操作 / 常见问题与陷阱 / 权威文件）与完成标准（`harness skill check`、注册进 `AGENTS.md §0.1` 与 `ai/README.md`）→ 本批对 `pallastrade-deployment` 的修改必须保持该结构并追加 Changelog；repo 级守卫的注册范式（`tests/*.test.mjs` → `harness.config.mjs` 的 `repo-guards-test`）由既有条目（`tests/docker-health.test.mjs` 等）确认 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | 是 | ✅ 已读 | 测试栈约定用 node:test 写仓库级守卫（`tests/*.test.mjs`），与 rspec 分离；守卫测试只读文件、秒级完成 |
| 其余领域 Skill（api-v3 / data-model / payments / catalog / storefront 等） | 否 | — | 本次零应用层改动（无模型/接口/视图/序列化器变更） |

---

## Step 2：用户确认

- 用户原话：**「修复这两个问题」**（承接上一轮我列出的两条：① `catalog_health/coverage_spec.rb` 红灯；② 服务器每轮白等 900 秒）。
- 据此视为对本文档与 PRD 的授权（`user-confirmed`），实施范围限于 PRD §7 列出的文件。

---

## 实施记录

| 文件 | 动作 | 说明 |
|---|---|---|
| `.github/workflows/deploy.yml` | 改 | `on.push` 增加 `paths` 过滤（覆盖 Dockerfile 全部 COPY 来源）+ 说明注释；保留 `workflow_dispatch` |
| `tests/deploy-paths-filter.test.mjs` | 新增 | AC-001..AC-004 守卫（含判定有效性自证） |
| `harness.config.mjs` | 改 | `repo-guards-test` 纳入新测试文件 |
| `AGENTS.md` | 改 | §6 repo-guards 行补「部署路径过滤守卫」 |
| `deploy/README.md` | 改 | 说明镜像仅在构建输入变化时重建 + 手工强制重建 |
| `ai/skills/pallastrade-deployment/SKILL.md` | 改 | 补「镜像重建触发条件」小节（+ scenarios.json 同步） |

## 验证计划

- `npx harness verify repo-guards-test --task <id>`（秒级，含新守卫）
- `npx harness doc-impact --base origin/dev`（Skill 变更 → scenarios.json 同步）
- 服务器侧只读复核：过滤生效后 backend-only 推送的 `docker pull` 耗时应 < 5s（下一批推送时观察 `/var/log/pallastrade-pull.log`）
