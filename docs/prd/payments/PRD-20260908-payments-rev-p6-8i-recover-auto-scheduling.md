# PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8i ReverseCommerce::Recover 自动调度化（restock-AMBIGUOUS 扫描 + RecoverJob/Sweeper）（用户三包授权 #3） |
| 分类 | payments |
| 关联 Skill | pallastrade-payments / pallastrade-events-webhooks（jobs/schedule） |
| 关联 REQ | REQ-20260908-rev-p6-8i-recover-auto-scheduling.md |
| 关联 PRD | 8e（Recover 手动收敛 + rake + runbook，边界「自动调度 → 后续」）；8f（组合取消已收敛）；6（Refunds::RecoverSweeperJob 模式） |
| 需求类型 | 优化迭代（自动调度化，feature gate） |

> 源：REV-P6 §45/§46 + 8e 边界「自动调度待评估 restock 时序后另开」。**本包 = 8e Recover 调度化**：
> 新增 per-order `ReverseCommerce::RecoverJob` + `RecoverSweeperJob`（sidekiq-cron */5，capped），扫描
> restock-AMBIGUOUS return items → 收敛其所属订单。镜像 Refunds::RecoverSweeperJob 保守哲学：只 enqueue
> 幂等 Recover（不直接做资金/库存副作用；rescue 不 re-raise，周期重扫）。手动 rake/runbook 保留。

## 1. 背景与目标
8e 的 `ReverseCommerce::Recover` 只经 rake/服务手动触发；restock AMBIGUOUS（accepted+eligible 但 StockMovement
缺失）若无人跑 rake 会滞留。目标：周期自动扫描并 enqueue 幂等收敛，capped 防风暴；ambiguous/manual 语义不变。
成功指标：*/5 扫描 store 内 accepted+eligible+无 movement 的 return items → 每订单一次 RecoverJob（幂等自愈），
capped 超限 warn；全量绿。

## 2/3. FR
- FR-R68I-101（RecoverJob）：`ReverseCommerce::RecoverJob#perform(order_id)` —— find order → `Recover.call`
  （幂等）；rescue StandardError 仅 log 不 re-raise（周期重扫，防 sidekiq 重试放大）。
- FR-R68I-102（Sweeper）：`ReverseCommerce::RecoverSweeperJob#perform(store_id: nil, max_enqueues: 20)`——
  候选查询：`ReturnItem.accepted` JOIN inventory_unit→order（store 归属）+ LEFT JOIN stock_movements
  (return_item_id NULL) → 逐条 `restock_eligible?` + `RestockFact.resolve == AMBIGUOUS` 复核 → 收集 order ids
  （去重）→ enqueue RecoverJob，累计 ≤ max_enqueues（超出 warn+计数）；metrics log（event
  reverse_commerce.recover_sweeper）。
- FR-R68I-103（调度注册）：`backend/config/sidekiq_schedule.rb` +`reverse_commerce_recover_sweeper`（*/5，
  default queue）。
- 边界（记录不实施）：不改手动 rake/runbook 语义；ambiguous 之外状态仍由既有 sweeper/人工；不做 refund 域
  额外的自动调度（Refunds::RecoverSweeperJob 已覆盖）。

## 4. NFR
只 enqueue 幂等 RecoverJob（自身零副作用/不重复 StockMovement——partial unique + RestockFact 幂等）；rescue
不 re-raise；capped；无 migration/无 v3 端点。

## 5. AC
| AC | 条件 | FR |
|---|---|---|
| AC-R68I-01 | 有 restock-AMBIGUOUS 订单的 store 扫描 → 每订单 enqueue RecoverJob 恰一次（order 去重） | 102 |
| AC-R68I-02 | RecoverJob.perform_now 幂等自愈（movement 恢复且重复跑不重复建）；order 不存在 no-op 不 raise | 101 |
| AC-R68I-03 | 跨店隔离（其他店 ambiguous 不 enqueue）；store_id 单店限定 | 102 |
| AC-R68I-04 | capped：ambiguous 订单数 > max_enqueues 时只 enqueue ≤ cap 并 warn/计数 | 102 |
| AC-R68I-05 | schedule 注册条目存在；既有 sweeper 行为不变（回归） | 103 |
| AC-R68I-06 | 全量 backend-rspec ×2 + quick check + doc-impact | — |

## 6. 跨层搜索
core：8e Recover/rake list_ambiguous + Refunds::RecoverSweeperJob/RecoverJob 模板；ReturnItem.accepted +
stock_movements + RestockFact。无既有自动 restock 收敛调度（缺口）。admin/api/storefront/platform 无涉
（job + schedule）。

## 7. 技术影响
core jobs：pallastrade/reverse_commerce/{recover_job,recover_sweeper_job}.rb（新，BaseJob）；host
backend/config/sidekiq_schedule.rb（+条目）。specs：jobs/reverse_commerce/*（sweeper enqueue/cap/隔离 +
job 幂等自愈/异常）。无 migration/无 v3/无 UI。

## 8. 测试计划
sweeper spec（真 ambiguous fixture 镜像 8e：shipped_order+track_inventory+RA+stock_item+return_item→
cr.save! 后删 movement 成 AMBIGUOUS）：enqueue 去重、store 隔离、cap；job spec（perform_now 自愈 + 缺 order
no-op）。回归 8e/6/8g/8h + quick check + 全量 ×2。

## 9. 文档同步清单
- [x] payments skill（8i 节）；runbook reverse-commerce-recover 更新；scenarios GS-076；PRD/REQ/README；doc-impact。
- [x] 边界：手动 rake 保留；调度为 */5 capped。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（8e 边界落地：调度化；镜像 Refunds::RecoverSweeperJob 保守哲学） | AI |
| 2026-09-08 | 1.0 | done：实施完成（commit 99fd899）——RecoverJob+RecoverSweeperJob+schedule；spec 3/3 + schedule；全量 ×2 绿 | AI |
