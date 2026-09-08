# PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8e ReverseCommerce::Recover 跨域收敛（restock AMBIGUOUS 自愈 + 复用 Refunds::Recover） |
| 分类 | payments（语义归属；跨 shipping/recovery） |
| 关联 Skill | pallastrade-payments / pallastrade-admin |
| 关联 REQ | REQ-20260908-rev-p6-8e-reverse-commerce-recover.md |
| 关联 PRD | REV-P6-1~7 + 8a/8b/8c/8d（done）；RestockFact 注释「REV-P6-6 ReverseCommerce::Recover 消费本事实」落地 |
| 需求类型 | 优化迭代（跨域收敛，feature gate） |

> 源：`豆包…/P6` §45（ReverseCommerce::Recover 统一 application layer，消费 Payment/Refund/Restock/Order/
> Journal 事实、不自己猜状态）+ §39-42（Restock Fact / exactly-once）+ §51（P4 能力复用）。**本包 = Order 锚点的
> 跨域收敛入口**：restock 事实 AMBIGUOUS（accepted+eligible 但 StockMovement 缺失）**幂等自愈** + 复用
> `Refunds::Recover`（已存在的逐单收敛；fresh 为 no-op，不重复）；Journal/Reconcile 修复归 P4 ReconcileSweeper
>（本包不重复派发）。无自动取消/无猜测/无资金副作用新增。

## 1. 背景与目标
REV-P6-5 把 restock 决策移到 acceptance 并做 exactly-once（partial unique）；若 acceptance 后进程崩溃/异常，库存
回补动作丢失 → `RestockFact.resolve` 呈 AMBIGUOUS，且**无任何收敛者**（Refunds::Recover 只处理 refund；restock
无人自愈）。§45 要求一个「消费事实、不猜」的 ReverseCommerce::Recover 统一层。目标：Order 级跨域收敛服务——
restock AMBIGUOUS 幂等自愈（补 StockMovement(+)）并复用 Refunds::Recover；rake + runbook 供运维收敛；不打乱既有
各域 sweeper。
成功指标：accepted+eligible 无 movement 的 return item 可一次调用收敛为 RESTOCKED；无重复 StockMovement；
fresh 退款 pass 零副作用；全量绿。

## 2/3. FR
- FR-R68E-101（模型自愈入口）：`ReturnItem#restock_if_ambiguous!`（public，幂等）——仅 accepted? &&
  restock_eligible? && 无 `StockMovement(return_item_id:)` 时执行 restock（复用既有 restock_if_needed 唯一写入
  通道 + RecordNotUnique 跳过）；返回 true=本次已回补 / false=无需（守卫外）。不加新反模式、不改 acceptance 行为。
- FR-R68E-102（跨域收敛服务）：`ReverseCommerce::Recover.call(order:)`（Order 锚点）——
  - **Restock 域**：`order.customer_returns` → return_items → 逐条 `RestockFact.resolve`；AMBIGUOUS →
    `restock_if_ambiguous!`（healed+1）；RESTOCKED/NOT_REQUIRED/NOT_RESTOCKABLE/PENDING 计数（不动作，PENDING
    由上游裁决）；异常 rescue 单条不中断。
  - **Refund 域（复用）**：order 可达 refunds（order.payments.refunds）逐条 `Refunds::Recover.call(refund:)`
    （幂等；fresh/terminal no-op）→ outcome 计数。组合/无 order 退款由全局 Refunds::RecoverSweeperJob 覆盖。
  - 输出聚合 Result（success{ heals, restock: {restocked,not_required,not_restockable,pending,ambiguous},
    refunds:{rerun,timeout,noop}, errors: n }）；不写库（除 restock 自愈与 Recover 既有写）、不 raise。
- FR-R68E-103（Ops 入口）：rake `pallastrade:reverse_commerce:recover[order_id]`（单 order 收敛，TSV 摘要）与
  `pallastrade:reverse_commerce:list_ambiguous[store_id]`（列出 restock AMBIGUOUS return items）。
- FR-R68E-104：runbook `docs/operations/reverse-commerce-recover-runbook.md`（语义/使用/边界）。
- 边界（记录不实施）：Journal/Reconcile 修复派发（P4 sweeper 已拥有）；取消意图恢复/组合级编排；自动调度
  （本包为 service+rake 手动收敛；调度化待评估 restock 时序后另开）。

## 4. NFR
只读为主 + restock 自愈幂等（exactly-once）；不自动退款/取消（沿用 Refunds::Recover 保守 + 无新资金副作用）；
异常降级不中断；无 migration/API/UI。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68E-01 | accepted+eligible 无 movement → restock_if_ambiguous! 回补并 RESTOCKED；重复调用不重复建（count 不变） | 101 |
| AC-R68E-02 | not-accepted / not-eligible / 已有 movement → no-op（false），不建行 | 101 |
| AC-R68E-03 | Recover(order)：AMBIGUOUS 自愈 healed；RESTOCKED/NOT_* /PENDING 计数正确；fresh refund 无副作用 | 102 |
| AC-R68E-04 | 单条 restock/recover 异常 rescue 不中断整单 | 102/103 |
| AC-R68E-05 | rake recover/list_ambiguous 注册可用 | 103 |
| AC-R68E-06 | runbook 存在；skill/scenarios 更新；全量 backend-rspec ×2 + quick check + doc-impact | 104 |

## 6. 跨层搜索（节选）
Core：ReturnItem restock 唯一写入通道（stock_movements.return_item_id partial unique，acceptance
after_transition 触发 private restock_if_needed；RestockFact 五态，注释明言 Recover 消费）；order.customer_returns
（经 return_authorizations）；Refunds::Recover（幂等，fresh no-op）；Refunds::RecoverSweeperJob 全局已覆盖
无 order 退款。无既有 restock 收敛/自愈者（缺口）。Admin/API/Storefront/Platform 无涉（rake+service）。
Skill：payments（REV-P6-5/6/8 系列）、testing、prd、api-v3、customization（已读）。

## 7. 技术影响
Core：`models/pallastrade/return_item.rb`（+public restock_if_ambiguous!，幂等）；
`services/pallastrade/reverse_commerce/recover.rb`（新目录/服务）；`lib/tasks/reverse_commerce.rake`；
runbook。无 migration/API/UI/sidekiq。specs：`spec/models/pallastrade/return_item_restock_recover_spec.rb` +
`spec/services/pallastrade/reverse_commerce/recover_spec.rb`。

## 8. 测试计划
restock 自愈 spec（AC-R68E-01/02：真回补/守卫/no-op/唯一并发跳过）；Recover service spec（AC-R68E-03/04：
构造 accepted-eligible 缺 movement return item + fresh refund，断言 healed 与计数、单条异常不中断）；rake 冒烟
（AC-R68E-05）。回归 refund/return/reconcile/8a-8d 相关 + quick check + 全量 ×2 + doc-impact。

## 9. 文档同步清单
- [ ] payments skill（REV-P6-8e 节）；scenarios GS-072；PRD/REQ/README + runbook；doc-impact。
- [ ] 边界记录：Journal/Reconcile 派发、取消恢复、自动调度 → 后续。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 §45/§39-42 + RestockFact 注释 + 现有域收敛测绘） | AI |
