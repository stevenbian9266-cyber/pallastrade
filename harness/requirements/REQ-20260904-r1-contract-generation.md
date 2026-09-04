# REQ-20260904-r1-contract-generation

> 关联 PRD：`docs/prd/api/PRD-20260904-r1-contract-generation-infra.md`
> Task：TASK-20260904023203-21329797；Gate：GATE-2026-09-04T02-32-12
> 用户确认（2026-09-04）：方案 A = Schema 全自动生成 + Paths 维持校验；执行环境 = Docker web 容器。

## Step 0：跨层搜索（6 层结论）

| 层 | 结论 |
|---|---|
| backend/app（host） | `backend/lib/tasks/` 现无 openapi/contracts rake；`api_docs_controller` 静态服务 `public/api-docs/`；typelizer host initializer 在 pallastrade_api gem（host 加载） |
| pallastrade_core | 无相关；`metafield.rb` 注释提及 openapi 语义 |
| pallastrade_api | `lib/pallastrade/api/openapi/schema_helper.rb`（all_schemas/admin_schemas/typelizer_schemas+patches/x-typelizer 标记）与 `path_sorter.rb`（canonical paths 排序）可复用；gem 无 spec/、无 spec/dummy；rswag-specs 仅 gemspec dev dep（host bundle 不可用）→ rswag 全量重建不可行（方案 B 排除）；typelizer 为 runtime dep（host bundle 可用）|
| pallastrade_admin | 无引用 |
| storefront | 不消费 yaml（SDK 类型经 typelizer→backend/packages/sdk→构建 vendor）；无裸引用 |
| platform | `platform/packages/sdk|admin-sdk/src/types/generated/*` 为 typelizer 产物副本（backend/packages/ 同源，docker 后手工 cp）；`platform/docs/api-reference/{store,admin}.yaml` 为 backend/public/api-docs 手工副本；`platform/scripts/ci/api-v3-docs-check.mjs` 校验 endpoint 存在性 |
| 结论 | **generated:check 现状 = 空转**：`harness.config.mjs → generatedCheck.checks` 两个命令均 `|| echo SKIP`（SDK Types 脚本在 sdk package.json 不存在 → 恒 SKIP；CLI Admin Spec 同理）→ 漂移检测失效。typelizer 已可运行（host context，generated:check 曾跑出 no drift 但实际未运行生成）。yaml 为纯手维护（store 92 ops/admin 240 ops/178 schemas 中 62/66 带 x-typelizer 标记 → 曾由管线生成）。R1 目标：让 schema 段自动生成 + check 接入 generated:check，paths 维持手维护 + $ref 完整性校验 |

## Step 1：Skill 咨询

| Skill | 结论 |
|---|---|
| pallastrade-api-v3 | API 契约以 serializer typelize 为 schema 源；api-docs yaml 维护规范（本 REQ 落地为 rake 自动化） |
| pallastrade-typescript-sdk | SDK 类型由 typelizer writer store/admin 生成 → backend/packages/sdk(+admin-sdk)/src/types/generated；platform 为副本 |
| harness-prd | 同 PRD 推进：实施块 + AC + changelog；generated:check 配置在 harness.config.mjs → generatedCheck.checks |
| pallastrade-deployment | 生成命令在 Docker web 容器执行（docker exec pallastrade-web-1），backend 挂载 /rails |

## 任务类型

优化（R1 契约生成基建：typelizer/yaml 可运行化，方案 A）

## 需求描述

1. **宿主 rake 任务** `backend/lib/tasks/api_docs.rake`：
   - `api:docs:schemas:generate` / `api:docs:schemas:check`：对 store.yaml & admin.yaml 仅重写 `components.schemas` 中 **typelizer 拥有项**（现带 `x-typelizer: true` 或名字存在于 SchemaHelper 生成集）；保留手维护/非 serializer schema 与 `components` 之外全文（info/paths/tags/…）字节不变；新增 serializer 自动补 schema；被删 serializer 的 x-typelizer schema 移除。合并算法：`committed_schemas` 为基底 → 逐个用生成集覆盖（生成集 = `SchemaHelper#all_schemas`(store) / `#admin_schemas`(admin)，深 stringify key）→ 移除「x-typelizer 标记且不在生成集」条目 → 确定性 dump（Psych indentation 2、LF、不 sort paths）。
   - `api:docs:validate`：Psych 解析两 yaml；所有 `#/components/schemas/X` $ref 目标存在；重复 key 检测。
2. **SDK 类型接入**：`api:docs:generate` = `typelizer:generate`（两 writer）+ `api:docs:schemas:generate`；`api:docs:check` = 同 generate 后 git 语义零 diff（幂等校验，配合 generated:check）。
3. **编排脚本**：`scripts/ci/contracts.sh`（root，PowerShell/bash 双兼容尽量 bash）：docker exec web 容器跑 generate/check + platform 副本同步（backend/public/api-docs→platform/docs/api-reference/{store,admin}.yaml；backend/packages/sdk→platform/packages/sdk types；admin-sdk 同）。
4. **generated:check 接线**（harness.config.mjs）：`generatedCheck.checks` 两条目改为真实命令（docker-gated，docker 缺席时 `echo SKIP` 保持 CI-safe）：
   - `SDK Types`: `docker exec pallastrade-web-1 bash -lc 'cd /rails && ENABLE_TYPELIZER=1 bundle exec rake typelizer:generate'`
   - `OpenAPI Schemas`: `docker exec pallastrade-web-1 bash -lc 'cd /rails && bundle exec rake api:docs:schemas:check'`
5. **一次性规范化提交**：在 docker 运行 `api:docs:schemas:generate` → 将产物（yaml schema 段归一化 diff）纳入本包；再跑 `schemas:check` 幂等 0 diff 验证。
6. **文档**：PRD（api 分类）+ changelog；`pallastrade-api-v3`/`pallastrade-typescript-sdk` skill changelog；`docs/contracts/` README（生成/校验命令）。

范围锁：不做 rswag paths 全量重建（方案 B 排除）；不改 serializer/端点（本包只加生成器）；不新增 DB/迁移；storefront 不受影响。

## 影响范围

- 新增：`backend/lib/tasks/api_docs.rake`、`scripts/ci/contracts.sh`（或等价）、`docs/contracts/README.md`
- 修改：`harness.config.mjs`（generatedCheck.checks）、`backend/public/api-docs/{store,admin}.yaml`（x-typelizer schema 段归一化）、PRD + skills changelog
- 验证：docker 内 `api:docs:schemas:check` exit 0；`rake typelizer:generate` 幂等；`api:docs:validate` 通过；platform `api-v3-docs-check` 通过；storefront typecheck 0（回归）

## 技术方案（初步）

- rake 内用 Psych.safe_load 读 yaml（allow_alias 视文件决定）；线级定位 `components:\n  schemas:` 段（参照 path_sorter 线级思路）或整块重 dump 仅 schemas 子树（先试整块重 dump，diff 大则转线级块替换）。
- schema 条目 dump 风格对齐已提交风格：key 无引号、`nullable: true`、2-space、长字符串不折行 → `Psych.dump(hash.deep_stringify_keys, indentation: 2)` 前缀需 `---\n`?（条目级不带头）。实践以幂等（check=0）为准绳：**首跑 diff 允许，之后必须 0 diff**。
- 注意既有 Psych 损坏史（store.yaml 曾 € 乱码截断）：validate 用 Psych 全量 parse 兜底。

## 风险点

- YAML 格式化与历史 rswag/Psych 输出不完全一致 → 首跑大 diff；缓解：幂等校验 + 归一化一次提交；线级块替换保 paths 字节不变。
- typelizer schema 与手维护 schema 冲突（同名不同源）→ 生成集覆盖为准（x-typelizer 语义）。
- docker 不可用时 check SKIP → CI 语义同现状（真校验在本地/有容器环境跑）。

## 决策节点

✅ 用户确认（2026-09-04）：方案 A；Docker 执行。
