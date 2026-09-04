# Contract Generation (R1)

单一契约管线：Rails serializers（typelize hints）→ Typelizer（SDK TS 类型）+ 宿主 rake（OpenAPI `components.schemas`）→ 发布副本。

## 命令

| 命令 | 作用 |
|---|---|
| `bash scripts/ci/contracts.sh` | 全量生成（幂等）：docker `typelizer:generate` + `api:docs:schemas` + 同步 platform 副本 |
| `docker exec pallastrade-web-1 bash -lc 'cd /rails && bundle exec rake api:docs:schemas:check'` | OpenAPI schema 漂移门（exit 1 = drift） |
| `docker exec pallastrade-web-1 bash -lc 'cd /rails && bundle exec rake api:docs:validate'` | OpenAPI 结构校验（Psych 解析 + paths 全部 `$ref` 有目标） |
| `docker exec -e ENABLE_TYPELIZER=1 pallastrade-web-1 bash -lc 'cd /rails && bundle exec rake typelizer:generate'` | SDK TS 类型生成（backend/packages/{sdk,admin-sdk}/src/types/generated） |
| `npx harness generated:check` | 漂移门：运行 contracts.sh 前后快照 repo（*.ts/*.yaml/*.json），有变化即 fail |

## 语义

- **Schema 全自动**：`components.schemas` 中 Typelizer 拥有项（serializer 生成、`x-typelizer: true`）由 rake 从 serializers 重写；新增 serializer 自动补、删除自动清。
- **Paths 维持校验**：`paths`（端点/参数/响应）为手维护权威；`api:docs:validate` 硬校验 paths 的每个 `$ref` 有 schema 目标，防手维护漂移。
- **幂等**：管线输出确定性；generate 两次 == 一次。改动后先跑 `contracts.sh` 提交产物，`generated:check` 才可通过。

## 已知边界

- components 内部手写 schema（无 serializer 支撑）的悬空 ref 仅 WARN（`api:docs:validate` 输出），有 serializer 后由生成自动替换。
- `contracts.sh` 需 docker + linux；无 docker 时 SKIP（CI node-only runner 通过但为空转）；Windows dev 可用 PowerShell 等效命令或 Git Bash。
- SDK `dist`/zod 重生成 + storefront `.sdk-vendor` 刷新属发布期步骤（types/zod 源文件已纳入本管线同步）。
