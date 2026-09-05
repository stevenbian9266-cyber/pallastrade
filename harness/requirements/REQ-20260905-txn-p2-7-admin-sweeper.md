# REQ-20260905-txn-p2-7-admin-sweeper — TXN-P2-7 slice2（Admin UI + 保守 sweeper + 最小 metrics）

- 关联 PRD：docs/prd/payments/PRD-20260905-payments-txn-p2-7-operational-hardening-backend-slice.md（approved，回写 slice2）
- 任务：TASK-20260905040006-eb2c2df2
- Gate：GATE-2026-09-05T04-00-15
- 类型：feature / risk critical
- 用户决策（2026-09-05 vscode_askQuestions 三项明确选择）：sweeper=保守（仅 recovery_required 自动）；Admin=完整资源页；metrics/alerts=最小集

## Skill 表（真读结论）
| Skill | 结论 |
|---|---|
| pallastrade-customization | Admin = Rails 框架 gem（pallastrade_admin ResourceController + PermissionRegistry）；新增只读+动作资源镜像 email_logs/contact_messages（read-only + resolve 模式）；Store has_many 可加 |
| pallastrade-payments | RecoverJob（resolver 判定/幂等）为 enqueue 目标；Recover 仅接受 recovery_required/finalizing；manual_review 必须人工（AC-2014）；Finalize 幂等 INV-08 |
| pallastrade-data-model | CommerceTransaction 字段/trace 齐全；needs_attention/trace 已在 slice1；Store 尚无 commerce_transactions has_many |
| pallastrade-prd | 回写流程已用（prd update 命中相似 PRD） |

## 跨层（6 层）要点
- Core：CommerceTransaction.needs_attention/trace（slice1）；Store 无 assoc → 加 has_many commerce_transactions
- API/Admin：pallastrade_admin email_logs/contact_messages 为镜像模板（controller/routes/tables/nav/views/i18n/spec 全确认）
- 调度：host sidekiq_schedule.rb（sidekiq-cron）加 RecoverSweeperJob
- storefront/platform：不涉及
- PermissionRegistry 实际注册位于 host `backend/config/initializers/pallastrade_permission_registry.rb`（SuperUser 经 can :manage, :all 覆盖）

## 实施清单
1. core：store.rb 加 `has_many :commerce_transactions`；新建 `RecoverSweeperJob`（保守：recovery_required→enqueue RecoverJob；manual_review/stuck 计数+日志）
2. host：sidekiq_schedule.rb 增 cron 条目；pallastrade_permission_registry.rb 增 :transactions（read/update, store_id）
3. admin gem：transactions_controller（index/show/recover）、routes、tables 注册（:transactions, link_to_action: :show）、nav（Orders 组）、views（index 汇总卡+render_table；show trace+recover 按钮）
4. i18n：admin gem en.yml（orders.transactions 等）+ host admin_nav.zh-CN.yml 双语
5. specs：recover_sweeper_job_spec（AC-721/722/723）、requests admin transactions_spec（AC-711/712/713）
6. 知识：payments SKILL changelog + data-model SKILL（store assoc）+ scenarios（GS-047）+ runbook 补 sweeper/Admin

## 验证
- docker rspec：新 specs + 回归（p0-payment-rspec / chk-p1-5 至少定向）
- rubocop 0；nav_validate（pallastrade:admin:nav_validate）绿；doc-impact 绿
