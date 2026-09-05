# TXN-P2 Completion Report（2026-09-05）

> Commerce Transaction Orchestration & Recovery —— P2 后端核心交付 + Storefront/API 迁移收口报告。
> 对应 `豆包梳理业务需求/P2 — Commerce Transaction Orchestration & Recovery.md` §65 产物清单。
> 分支：`dev`。每工作包均经 Harness feature gate（task→brain→risk→gate→REQ→evidence→commit）。
> 更新：2026-09-05 —— TXN-P2-6 三包全部完成并推送 dev（HEAD `40840b8`）。

## 1. 交付清单（commit 时间线，dev）

| Commit | 包 | 内容 |
|---|---|---|
| `0e306fa`/`e03b9f4`/`64f92b5` | TXN-P2-0 + RISK-01 | 语义审计（RESEARCH-20260904-txn-p2-0）；组合成员完成 primitive 按 standard/legacy 分流（CombinationMemberComplete） |
| `b781f7f` | TXN-P2-1 | CommerceTransaction/TransactionOrder 数据层 + 状态机 + immutable snapshot + recovery 元数据 |
| `a837be7` | TXN-P2-2 | Transactions::Start/Resume + PaymentSession.transaction_id FK + Store API create/show + request specs |
| `b9d4880` | TXN-P2-3 | PaymentFactResolver（paid/unpaid/ambiguous）+ PaymentMethod#fetch_payment_status（Stripe/bogus） |
| `a7e0bd3` | TXN-P2-4 | Recovery Engine：状态机 recovery 出口 + Transactions::Recover + RecoverJob |
| `045d7d6` | TXN-P2-5 | Unified Finalization：Transactions::Finalize + OnPaymentSuccess + Webhook/controller 接线 + Recover 收敛 |
| `4362104` | TXN-P2-7（后端切片） | needs_attention scope + trace + rake list/recover + ops runbook |
| `c3a36a6` | P2 收口 | `CommerceTransactionSerializer`（typelize 全字段，生成源）+ 本 completion report + prd/api-v3 SKILL 同步 |
| `c202121` | TXN-P2-6 轮1 契约快照 | store.yaml +75 schema `CommerceTransaction`（typelizer-owned）+ backend/packages/sdk `StoreCommerceTransaction.ts` + backend/app/javascript types；`api:docs:check` 归绿 |
| `f276e84` | GS-045 | scenarios.json 增 GS-045（契约快照 / transaction-first 契约演进） |
| `bf2e296` | TXN-P2-6 轮2 SDK 消费 | platform/packages/sdk：types/generated `StoreCommerceTransaction` + `CommerceTransaction` 别名 + `OrderTransactionStart`/`CreateOrderTransactionParams`/`TransactionResume`；client `orders.transactions.create` + `transactions.get`；README 同步 |
| `40840b8` | TXN-P2-6 轮3 storefront | checkout/start BFF + `order-payment` action transaction-first（`payment_execution`=session，PATCH complete 不变）；`quote_changed` 409 映射；SDK dist 重建（hash `index-D4oztWwf`）；scenarios GS-046 + storefront SKILL/README 同步 |

## 2. 冻结决策（TXN-P2-0，见 RESEARCH-20260904-txn-p2-0）

- Transaction 边界/基数：`CommerceTransaction × N TransactionOrder`；同一商业意图一个 active transaction；balance_collection/combined_payment 目的枚举；immutable snapshot（不可覆写，非价格计算源）；quote consent（过期自动 Refresh，商业事实变→409 quote_changed）；PaymentSession = transaction 的 attempt（无 PaymentAttempt）；finalization = Transactions::Finalize（P2-5）；Money-state invariant（payment_confirmed 不可逆）。

## 3. 核心不变量落地（INV-01..10 / AC-2001..2020）

| Invariant | 落地 |
|---|---|
| INV-02 PSP success 不可逆 | 状态机禁 payment_confirmed→payment_pending（AC-403 测试） |
| INV-03 success+local incomplete=recovery_required | Finalize 失败→mark_recovery_required（AC-504/417） |
| INV-04 Recovery 不建新 Payment | Recover/OnPaymentSuccess 无创建路径 |
| INV-08 finalization 幂等 | Finalize/Recover/OnPaymentSuccess 幂等短路（AC-502/513/415） |
| INV-05 decline≠failure | p0 回归 AC-2008（PaymentSessions Start Policy） |
| Payment Start Policy | payment_confirmed/finalizing/recovery_required/completed/manual_review 禁新 session（P2-1/2 状态机 + Start） |

## 4. 回归矩阵

- `p0-payment-rspec`（注册 verifier）：每个工作包 staged + 新 HEAD 全绿。
- 定向：TXN-P2-2 services 7 + request 5；P2-3 resolver 11 + stripe 7；P2-4 model+recover+job 15；P2-5 finalize/on_payment_success/recover 18 + webhook/controller 15；P2-7 model 9 —— 全部 0 failures。
- 新增文件 rubocop 0（全包）。
- TXN-P2-6：`storefront-test`（注册 verifier，全量 vitest）46 files / 267 tests PASS（轮3，含 BFF route + OrderPaymentContent quote_changed 用例）；SDK `pnpm typecheck`/biome 全绿；store.yaml `schemas:check/validate/api:docs:check` 幂等归绿（轮1）。

## 5. Remaining / 后续（明确记录）

> 更新于 2026-09-05：**TXN-P2-6 已全部完成**（轮1 契约快照 `c202121` → 轮2 SDK 消费 `bf2e296` → 轮3 storefront 迁移 `40840b8`）。

| 项 | 阻塞/前置 | 备注 |
|---|---|---|
| Admin transaction inspection UI | Admin resource 基建 | P2-7 延后记录 |
| metrics / alerts / 自动 stuck sweeper | 可观测组件 + Admin 基建 | P2-7 延后记录（后端切片 + rake 已交付，UI/告警/调度未做） |
| 组合（PaymentCombination）txn 化 | 后续 combined strategy | 组合 adapter 保持（RISK-01 / P2-5 Strangler）；会话仍挂组合非 txn |
| storefront Resume（账户态 transactions.get 消费） | 需 customer JWT 登录流 | 轮3 仅 guest checkout transaction-first；账户态 resume/重试 UI 后续 |

## 6. Rollback / 兼容

- 全部为新增服务/状态出口 + Strangler 接线（webhook/controller 无 txn 行为不变）；无破坏性迁移（P2-1 FK 可空、P2-2 transaction_id 可空）；P0/P1 行为由 p0-payment-rspec/chk-p1-5 回归保护。
- 回退：逐 commit revert（base `30111b2` 之前 P0/P1 已推 dev）。
