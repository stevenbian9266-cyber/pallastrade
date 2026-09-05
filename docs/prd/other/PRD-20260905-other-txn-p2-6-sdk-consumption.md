# PRD-20260905-other-txn-p2-6-sdk-consumption

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-05 |
| 来源 | TXN-P2-6 第二阶段：SDK 消费（platform SDK 同步 CommerceTransaction 类型 + orders.transactions.create / transactions.get client） |
| 分类 | other |
| 关联 REQ | REQ-20260905-txn-p2-6-sdk-consumption.md |
| 需求类型 | SDK/平台（transaction-first 前置） |

## 1. 目标
- 把 `backend/packages/sdk` 生成的 `StoreCommerceTransaction.ts` 同步到 platform SDK generated 目录（同 writer 产物）。
- types barrel 导出 `CommerceTransaction` 别名；新增 `OrderTransactionStart`/`TransactionResume` 等手写接口与 `CreateOrderTransactionParams`。
- store-client：`orders.transactions.create`（POST /orders/:id/transactions）+ 顶层 `transactions.get`（GET /transactions/:id）。
- 本阶段不切换 storefront（下一步）。

## 2. AC
- AC-1001 platform sdk generated 含 StoreCommerceTransaction.ts 且 digest 与 backend 一致。
- AC-1002 SDK 类型编译通过（tsc/typecheck 若环境可用；否则 store-client 静态核对）。
- AC-1003 client 方法指向正确路径与参数。

## 3. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-05 | 0.1 | approved（用户"继续"授权） | AI |
