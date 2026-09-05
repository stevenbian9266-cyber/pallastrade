# PRD-20260905-payments-txn-p2-6-contract-snapshot

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-05 |
| 来源 | TXN-P2-6（Storefront/API Migration）第一阶段：契约快照——CommerceTransaction 入 OpenAPI store.yaml + SDK TS types，`api:docs:check` 归绿 |
| 分类 | payments |
| 关联 REQ | REQ-20260905-txn-p2-6-contract-snapshot.md |
| 需求类型 | 接口/契约收口（生成式，无手工行为改动） |

## 1. 目标
- 运行 R1 契约生成（`ENABLE_TYPELIZER=1 rake api:docs:generate`：typelizer TS → backend/packages/{sdk,admin-sdk}；schemas → backend/public/api-docs/{store,admin}.yaml）。
- store.yaml schemas 纳入 `CommerceTransaction`（及必要时相关 PaymentSession 引用）typelizer-owned 项；路径（paths）仍手维护不动。
- `api:docs:schemas:check` / `api:docs:validate` / `api:docs:check` 全绿（含 SDK types 无漂移）。
- 提交生成产物；不改 controller/行为；SDK 消费/storefront 迁移为下一阶段。

## 2. 范围/非范围
- 做：生成产物提交 + docs（skill changelog）/REQ。
- 不做：storefront/SDK client 方法/组件迁移（下一阶段）；store.yaml paths 手补（仍手维护，next 阶段随 endpoint 契约）；platform 副本同步（下一阶段 SDK round 一并 docker cp + zod + biome）。

## 3. AC
- AC-901 生成后 `api:docs:schemas:check`、`validate`、`api:docs:check` 退出 0。
- AC-902 store.yaml schemas 含 CommerceTransaction（`x-typelizer` owned），SDK store types 含 CommerceTransaction.ts。
- AC-903 产物 diff 可控（新增 CommerceTransaction 等；无意外大范围无关改写——若 typelizer 全量改写超预期，评估并记录）。
- AC-904 生成式改动可重复（再跑一次无漂移）。

## 4. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-05 | 0.1 | approved（用户"按你建议来"= ①分两轮，本轮②契约快照） | AI |
