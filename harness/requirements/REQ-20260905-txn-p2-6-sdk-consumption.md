# REQ-20260905-txn-p2-6-sdk-consumption
- 任务 TASK-20260905030854-889b7274 / Gate GATE-2026-09-05T03-09-06
- PRD other-txn-p2-6-sdk-consumption
## 范围
1. 复制 backend/packages/sdk/src/types/generated → platform/packages/sdk/src/types/generated（含 StoreCommerceTransaction.ts）
2. types/index.ts 增 CommerceTransaction 别名 + OrderTransactionStart/TransactionResume/CreateOrderTransactionParams
3. store-client：orders.transactions.create + transactions.get
4. 编译核对（tsc 若可用）
## Skill
- api-v3/platform 生成契约（GS-045）已读
