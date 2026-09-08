# PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry-人工裁决与确定性重试-危险操作

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-08 |
| 来源 | 需求：REV-P6-8b Refund Manual Review/Retry 人工裁决与确定性重试（危险操作） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-payments / pallastrade-admin |
| 关联 REQ | REQ-20260908-rev-p6-8b-refund-manual-review-retry.md（实施时回填） |
| 关联 PRD | REV-P6-1~7 + REV-P6-8a（done）；REV-P6-8b=人工操作层，8c=legacy 拆链 |
| 需求类型 | 优化迭代（Manual Review/Retry 人工操作，feature gate） |

> 源：`豆包…/P6` §63（Manual Retry Query / Manual Review）+ §47 Recovery Matrix + §49（同 key 确定性解决）+ §10
> （AMBIGUOUS/MANUAL_REVIEW 语义）+ REV-INV-04（ambiguous 不自动重退，只允许同 idempotency key 确定性解决）。
> 本包 = **人工触发的确定性解决工具**（危险资金操作：权限门控 + 强确认 + 审计）。资金执行只经
> `Refunds::ExecuteJob` → `Execute`（同键 → provider 去重返回真实结果），AP-010 一致；服务内**绝不同步 Execute**。

## 1. 背景与目标
REV-P6-6 自动引擎只收敛 requested/processing；`ambiguous`/`failed`/`manual_review` 只能计数 + warn 交人工
（§46/§47）。REV-P6-8a 已提供只读查看（含在线对账）；但**人工裁决工具缺失**——ambiguous 退款没有「同键重试
确定性解决」入口，failed 无法显式重试，manual_review 无法裁决。目标：Admin 提供一个受控的「重试（同键）」
与「标记人工复核」操作，按 §47/§49 收敛真实资金结果（provider 已成功 → ApplySuccess+Journal；未成功 →
failed/ambiguous 如实），**绝不产生第二笔退款**（单 refund 行 + 稳定 idempotency key）。
成功指标：failed/ambiguous/manual_review 三态可人工同键重试且不重复退款；重试只异步执行；操作带权限/确认/
审计；全量 backend-rspec 绿。

## 2. 用户故事 / 场景
- 作为运营/资金操作员，我在退款详情页看到 ambiguous/manual_review/failed 退款，希望先看对账（8a 已有只读），
  再决定「同键重试」或「标记复核」，以把资金事实收敛为 succeeded/failed，且绝不重复打款。
- 正常流：ambiguous → 人工点「Retry (same key)」→ 状态 processing → ExecuteJob 同键执行 → provider 去重返回
  实际结果 → succeeded（ApplySuccess + Journal）/ failed / ambiguous 再滞留。
- 边界：failed 重试（provider 明确拒绝）→ 同键再次执行可能再次拒绝，如实 failed；manual_review 重试（provider
  实为成功）→ ApplySuccess 收敛；requested（自动路径）/ processing（已在进行）/ succeeded / canceled → 拒绝操作。
- 异常：并发双点 → with_lock 守卫第二次 failure；provider 再次不可用 → 保持 ambiguous，可稍后再试。

## 3. 功能需求（FR）
- FR-R68B-101（状态机）：`Refund#retry_execution` 事件扩展允许 `manual_review → processing`（现仅 failed/
  ambiguous → processing；REV-P6-1 注释已预留「人工裁决后的回退执行」）。
- FR-R68B-102（Core 服务 `Refunds::ManualRetry`）：人工确定性重试——with_lock + 状态守卫（仅
  failed/ambiguous/manual_review）；**要求 provider_idempotency_key 存在**（同键前提，缺失 → failure 不执行）；
  `retry_execution!` → processing + `attempt_count += 1` → 事务提交后 enqueue `Refunds::ExecuteJob(refund.id)`
  （资金执行只经 async Execute，AP-010；Execute 对 processing 以同键重跑 → provider 去重返回真实结果）；
  `PallasTrade::Audit.record(actor:, action: 'refund_manual_retry', resource:, after:{...})`。不可用态
  （requested/processing/succeeded/canceled 或 key 缺失）→ failure，零副作用。
- FR-R68B-103（Core 服务 `Refunds::MarkManualReview`）：人工标记复核——with_lock，仅 processing/ambiguous →
  `enter_manual_review!(code: 'OPERATOR_REVIEW')` + Audit（action 'refund_mark_review'）；其余态 failure。
- FR-R68B-104（Admin）：`RefundsOpsController#retry` / `#mark_review`（POST member，`/admin/refunds/:id/retry`、
  `/admin/refunds/:id/mark_review`）；授权 = manage/update Refund（CanCan）+ 控制器级 `authorize!`；危险操作
  turbo_confirm 强确认文案；成功/失败 flash。
- FR-R68B-105（Show 页/文案）：详情页仅 eligible 状态显示按钮（retry：failed/ambiguous/manual_review；
  mark_review：processing/ambiguous），且 `can?(:update, refund)`；i18n 双语（按钮/确认/提示）。
- FR-R68B-106：nav:validate / doc-impact 过（无新导航项，仅 member action）。

## 4. 非功能需求（NFR）
- 资金安全：绝不同步 Execute（AP-010）；同 refund 单键（provider_idempotency_key）→ 永不第二笔退款
  （REV-INV-04）；重试仅 operator 显式触发（无任何自动重退 ambiguous 路径）。
- 幂等/并发：with_lock 状态守卫，双点只生效一次。
- 审计：每次人工资金操作落 Audit（actor/action/resource）。
- 兼容：8a 详情页/列表不改；Execute/Recover/状态机其余事件不动（仅扩展 retry_execution）。

## 5. 验收标准（AC，与测试一一映射）
| AC | 条件 | FR |
|---|---|---|
| AC-R68B-01 | retry_execution 允许 failed/ambiguous/manual_review → processing（模型事件覆盖三态） | 101 |
| AC-R68B-02 | ManualRetry eligible（key 存在）→ processing + attempt+1 + ExecuteJob enqueue（带 refund.id）+ Audit；无同步 Execute | 102 |
| AC-R68B-03 | ManualRetry 不可用态（requested/processing/succeeded/canceled / key 缺失）→ failure 零副作用 | 102 |
| AC-R68B-04 | 并发/重复：已 processing 再 retry → failure 不重复入队 | 102 |
| AC-R68B-05 | MarkManualReview：processing/ambiguous → manual_review + Audit；其余 failure | 103 |
| AC-R68B-06 | POST retry/mark_review：无权限拒绝；成功/失败 flash；危险操作带强确认（turbo_confirm） | 104 |
| AC-R68B-07 | Show 页仅 eligible 状态显示对应按钮且权限门控 | 105 |
| AC-R68B-08 | nav:validate + doc-impact 过；全量 backend-rspec ×2 绿 | 106/全部 |

## 6. 跨层搜索记录（6 层，gate 强制）
| 层 | 路径 | 关键词 | 找到 | 满足 |
|---|---|---|---|---|
| App | `backend/app/` | refund manual retry | 无 override | 无涉 |
| Core | `pallastrade_core/app/` | Refund 状态机 retry_execution 预留（failed/ambiguous→processing）；Execute claim 对 processing 同键重跑=resolve 原语；Recover 不处理 ambiguous/failed/manual（交人工）；Audit.record 存在 | 缺人工服务与 manual_review→processing → 新增 |
| API | `pallastrade_api/app/` | manual retry endpoint | 无（8a 已定不加 API） | 无涉 |
| Admin | `pallastrade_admin/app/` | RefundsOpsController/视图（8a 产出）；TransactionsController#recover（member POST+确认+授权模板） | 加 member action + 按钮 | 扩展 |
| Storefront | `storefront/src/` | 无涉 | — | 无涉 |
| Platform | `platform/packages/` | 无涉（dashboard 不接） | — | 无涉 |
**结论**：底座齐备（状态机预留/Execute 同键/Recover 留人工/Audit）；本包新增两个 core 人工服务 + 状态机小扩展 +
Admin 两个 member action/按钮/文案。无 API/DB/Storefront/Platform。

## 7. 技术影响
- Core：`models/pallastrade/refund.rb`（retry_execution 增 manual_review→processing）；新增
  `services/pallastrade/refunds/manual_retry.rb`、`manual_review.rb`（或 mark_manual_review 服务）。无 migration。
- Admin gem（# PALLAS-CUSTOM）：`admin/refunds_ops_controller.rb`（+retry/mark_review member）、
  `views/.../refunds_ops/show.html.erb`（按钮区）、routes（member post ×2）、i18n（en + zh-CN）。
- 无 API/Storefront/Platform。quick check 无 AP（绝不同步 Execute）。

## 8. 测试计划
- 新增：`spec/services/pallastrade/refunds/manual_retry_spec.rb`（AC-R68B-02/03/04：eligible 三态成功入队+审计、
  不可用态/缺 key 拒绝、并发幂等）；`spec/services/pallastrade/refunds/mark_manual_review_spec.rb`
  （AC-R68B-05）；`spec/requests/pallastrade/admin/refunds_ops_actions_spec.rb`（AC-R68B-06/07：权限/确认/按钮
  显隐/入队）。模型事件覆盖并入 manual_retry_spec（AC-R68B-01）。
- 回归：refund 模型/服务/8a refunds_ops + transactions admin + reconcile（既有绿集）。
- 运行：docker exec spec → 全量 backend-rspec ×2（提交前/后）+ quick check + doc-impact。

## 9. 文档同步清单（知识同步门）
- [ ] Skill：`pallastrade-payments`（REV-P6-8b 节：ManualRetry/MarkManualReview/同键 resolve 语义）。
- [ ] scenarios：GS-069（REV-P6-8b Manual Review/Retry）。
- [ ] PRD 状态 + README 索引 + REQ 关联；doc-impact 过；无 API/导航新增。
- [ ] 边界：孤儿退款配对 / retry 全自动 / ReverseCommerce::Recover 跨域 → 8c。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（依据 §63/§47/§49/§10 + Execute/Recover 语义） | AI |
| 2026-09-08 | 0.2 | 实施：retry_execution 扩展 manual_review→processing + ManualRetry/MarkManualReview 服务 + Admin retry/mark_review member + Show 按钮 + i18n；新 spec 14 例全绿 + 回归 80 例绿 + quick check（无 AP/nav OK） | AI |
