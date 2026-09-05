# PRD-20260905-checkout-paymentcombination-txn-化-组合交易收敛到-transactions-finalize-recov

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-05 |
| 来源 | 需求：PaymentCombination txn 化——组合交易收敛到 Transactions::Finalize/Recover（每成员 TransactionOrder + OnPaymentSuccess 收敛）。用户决策（2026-09-05 vscode_askQuestions）：**全收敛到 Finalize**（不复用 Complete 阶段1；SettleJob→RecoverJob）/ **每成员一笔 TransactionOrder** / **PSP 成功收敛到 OnPaymentSuccess** |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-payments / pallastrade-events-webhooks / pallastrade-data-model |
| 关联 REQ | REQ-20260905-paymentcombination-txn.md |
| 关联 PRD | PRD-20260904-payments-txn-p2-5（Finalize 前置）等 |
| 需求类型 | 优化迭代（组合支付收口到 durable transaction 编排；RISK-01/P2-5 Strangler 延续） |

## 1. 背景与目标
- **一句话需求原文**：PaymentCombination txn 化——组合交易收敛到 Transactions::Finalize/Recover。
- **背景**：单订单标准流程已 transaction-first（P2-2..6）；组合支付（2+ 订单合并收银台）仍是独立 PaymentCombination aggregate：`Create` 建组合+splits+primary session；PSP 成功直接 `PaymentCombinations::Complete`（阶段1 入账：组合单 Payment(order_id=nil)+splits 回填+订单 payment_total；阶段2 成员 CombinationMemberComplete；失败入 `CombinationSettleJob` 补偿）——**不在 durable CommerceTransaction 编排内**，Admin/trace/needs_attention/sweeper 看不到组合，组合恢复游离于统一 orchestration boundary 之外（P2 §56/AC-2015）。
- **目标（用户三项决策）**：组合创建即建 durable txn（purpose=combined_payment，每成员一笔 TransactionOrder，primary 角色为首单）并绑定 primary session.transaction_id；PSP 成功统一经 `Transactions::OnPaymentSuccess` → `Transactions::Finalize`（Finalize 组合分支自包含"入账+成员完成"，不复用 `PaymentCombinations::Complete` 阶段1）；资金已入账但成员未全完成 → txn `recovery_required`（INV-03），由 `Transactions::Recover`/`RecoverSweeperJob` 幂等收尾（取代 CombinationSettleJob 于 txn 路径）；`PaymentCombinations::Complete`/`CombinationSettleJob` 保留为 legacy 非 txn 组合的适配器（Strangler，§56 不一次性删除）。
- **成功指标**：组合 PSP 成功 → txn payment_confirmed→finalizing→completed；成员失败 → recovery_required 且不重复入账（幂等）；p0/组合/支付回归全绿；Admin trace 可见组合交易。

## 2. 用户故事 / 场景
- 顾客：2+ 订单合并收银台支付成功 → 全部订单 paid/completed（与现状一致），且产生 durable txn 供运营查看/恢复。
- 运营：组合支付"资金已入账、某成员订单完成失败" → Admin Transactions 看到 recovery_required + trace（成员完成态）→ Recover（sweeper 自动或手工）幂等收尾；不再依赖只对组合隐藏的 SettleJob。
- 边界：组合 PSP 拒绝 → session failed、组合/txn 保持可重试（INV-05，语义不变）；非 txn legacy 组合（存量）继续走 Complete+SettleJob（适配器）。

## 3. FR / AC
| # | FR | AC（可测试） |
|---|---|---|
| FR-1 | `PaymentCombinations::Create` 在建组合后同步建 durable txn（combined_payment；amount=组合合计；currency）+ 每 unpaid 成员一笔 TransactionOrder（primary 首单，其余 participant，amount_snapshot=amount_due）+ 回填 session.transaction_id 与 txn.payment_combination，txn start_payment→payment_pending | AC-1：创建后 combo.commerce_transaction 存在（purpose=combined_payment、amount 正确）；成员 TransactionOrder 数与 unpaid 数一致；primary session.transaction_id=txn.id；txn.state=payment_pending |
| FR-2 | `Transactions::Finalize` 组合分支：txn 挂 payment_combination 时自含入账（组合 Payment(order_id=nil) 完成 + splits captured/payment 回填 + 成员订单 payment_total/payment_state + combination succeed——从 PaymentCombinations::Complete 提取共享入账 primitive）+ 锁外逐成员 CombinationMemberComplete；全完成→txn complete；成员失败→组合已 succeed 但订单 balance_due → txn recovery_required + last_error（INV-03），不重复入账 | AC-2：PSP 成功+全成员完成 → combo succeeded、各单 paid/completed、txn completed；重复 Finalize 幂等（已完成短路）；成员失败 → combo succeeded、txn recovery_required、不二次建 Payment/splits 不重复 |
| FR-3 | `Transactions::OnPaymentSuccess` 组合分支收敛：session 同时挂 combination+txn → 锁内 confirm_payment!（payment_pending→payment_confirmed）→ Finalize（组合分支）；仅 legacy 非 txn session 仍走 `PaymentCombinations::Complete` 适配器 | AC-3：组合 PSP 成功 → OnPaymentSuccess → txn 经历 payment_confirmed→finalizing→completed（全成员）；webhook 与 controller complete 双路径同语义（单 choke point） |
| FR-4 | Recover 对 recovery_required 组合 txn：resolver 判定 paid → Finalize（组合分支幂等收尾）；`RecoverSweeperJob` 自动覆盖（组合 txn recovery_required 现被 needs_attention 捕获） | AC-4：recovery_required 组合 txn Recover → 补完成成员 + txn completed；重复安全 |
| FR-5 | legacy 兼容：无 txn 的组合 session（存量/回退）行为不变（Complete+SettleJob 适配器保留） | AC-5：legacy 组合完成路径规格不回归 |
| FR-6 | PaymentCombination 增加 has_one :commerce_transaction（inverse，FK 在 txn） | AC-6：模型关联可用 |

## 4. 跨层搜索记录（6 层）
| 层 | 结果 |
|---|---|
| backend/app | 无宿主组合代码（全在 gems） |
| Core | `PaymentCombinations::{Create,Complete}`、`CombinationMemberComplete`、`CombinationSettleJob`、`Transactions::{Finalize,Recover,OnPaymentSuccess}`、`CommerceTransaction/TransactionOrder/PaymentCombination/PaymentSession`（session 可同时挂 combination+transaction；TransactionOrder role primary/participant、order 唯一）——接缝已定位 |
| API | `store/payment_combinations_controller`（创建返回 combination，无客户端面改动）；`orders/payment_sessions#complete` 已接 OnPaymentSuccess（P2-5）；webhook 组合分支待收敛 |
| Admin | Transactions Admin（P2-7 slice2）将自动覆盖组合 txn（trace/needs_attention） |
| Storefront | `PaymentCheckoutModal`/`paymentCombinations` SDK 无请求面改动 |
| Platform | SDK paymentCombinations.create/get 不变 |

## 5. 技术方案
1. `payment_combination.rb`：`has_one :commerce_transaction`（inverse_of :payment_combination）。
2. 提取入账 primitive：`PaymentCombinations::Complete#record_payment!/find_combination_payment/captured_share` → 新服务 `PaymentCombinations::Settlement`（settle!(combination, payment_session) 幂等：已 succeeded 短路）。`Complete` 改为薄适配器（Settlement + 成员 + SettleJob），供 legacy 非 txn 组合。
3. `Finalize`：txn.payment_combination 存在 → 组合分支：begin_finalizing 后（锁外）Settlement + 逐成员 CombinationMemberComplete；全完成 → complete!；成员失败 → mark_recovery_required!+last_error（INV-03）。单订单分支不变。
4. `OnPaymentSuccess`：组合分支——txn 存在→confirm_payment!→Finalize；txn 不存在（legacy）→Complete 适配器。
5. webhook 组合完成路径收敛：session 有 txn → 经 OnPaymentSuccess（读 handle webhook 现组合调用点改造）。
6. specs：create（AC-1）、finalize 组合分支（AC-2）、on_payment_success 组合（AC-3）、recover 组合（AC-4）、legacy 回归（AC-5）。

## 6. 测试计划
- 新增/更新：`payment_combinations/create` 相关 spec；`transactions/finalize` 组合分支；`on_payment_success`；`recover` 组合；webhook 组合 spec；`payment_combinations/complete`（适配器回归）；`combination_settle_job`（legacy 回归）。
- 回归：p0-payment-rspec（含 handle_webhook_combination、order_payment_sessions controller）、chk-p1-5。

## 7. 文档同步清单
- `ai/skills/pallastrade-payments/SKILL.md` changelog；scenarios.json 新 GS；completion report §Remaining（组合项完成）。
- 无 OpenAPI/API 面改动（组合 API 请求面不变）。

## 8. 变更记录
- 2026-09-05 v0.1：approved（用户三项决策）。
