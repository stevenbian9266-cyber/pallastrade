# REQ-20260905-txn-p2-6-contract-snapshot — P2-6 契约快照

- 关联 PRD：PRD-20260905-payments-txn-p2-6-contract-snapshot
- 任务：TASK-20260905024214-83e1abea
- Gate：GATE-2026-09-05T02-42-24
- 类型：feature / risk standard

## 目标
R1 契约生成归一到含 CommerceTransaction（OpenAPI store.yaml schemas + SDK store TS types），`api:docs:check` 归绿并提交；P2-6 下一阶段做 SDK 消费与 storefront 迁移。

## Skill 表
| Skill | 结论 |
|---|---|
| pallastrade-api-v3 | serializer typelize 已就绪（CommerceTransactionSerializer）；R1 生成链路 rake/typelizer 可用（ENABLE_TYPELIZER=1，store writer → backend/packages/sdk）；api-docs 手维护路径+自动 schema 设计 |
| pallastrade-data-model | CommerceTransaction 字段即 typelize attributes 源（P2 收口已建 serializer） |

## 实施
1. 容器内 `ENABLE_TYPELIZER=1 bundle exec rake api:docs:generate`（写 backend/packages/{sdk,admin-sdk} TS + backend/public/api-docs schemas）。
2. `api:docs:schemas:check` + `validate` + `api:docs:check` 全绿。
3. 提交生成产物；知识 changelog（api-v3 SKILL）。

## 验证
- verifier `chk-r1-contracts`（rubocop rake + schemas:check + validate）作为 registered test 证据；p0 verifier 可选回归。
- 二次运行幂等（再跑 schemas:check 无漂移）。

## 收尾
prep（user-confirmed 以用户指示授权清除）→ 生成 → 验证 → evidence → coverage-gate → commit → 重跑 verifier → finish。
