# PRD-20260913-payments-dsp-p7-7-admin-disputes-console（争议管理后台控制台）

| 元数据 | 值 |
|---|---|
| 状态 | approved（2026-09-13 用户显式确认实施；三项决策：① 动作集合**包含** `dry_run`；② **允许**真实执行 `recover`（带 turbo_confirm + 幂等 + 负向断言）；③ `OrderManagement`/`OrderDisplay` 补 Dispute **只读**规则） |
| 创建日期 | 2026-09-13 |
| 来源 | 用户指令「继续」→ 承接 DSP-P7-6 的下一切片（P7-0 FR-007；源计划 §66/§67） |
| 分类 | payments（`harness prd new` 自动判定） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-testing` |
| 关联 REQ | `REQ-20260913-dsp-p7-7-admin-disputes-console.md`（gate 时生成） |
| 关联 PRD | 源计划 §66（展现面）/§67（动作集）；前置 P7-1..6；范式参照 `PRD-20260908-payments-rev-p6-8a/8b`（Refunds Ops 只读 + 动作）、`...-8h`（Payments Ops） |
| 需求类型 | 新功能（Admin UI + 4~5 个安全动作；**0 migration**、0 API） |

> **切片定位（源计划 §66/§67）**：P7 线的**落地页**——运营收到 P7-5 期限告警 / P7-6 收敛通知后，
> 能在后台看到完整事实链（§66 列出的 18 项）并执行 4 个**安全动作**
> （Refresh Provider State / Retry Recovery / Generate Evidence Snapshot / Mark Manual Review）。
> **危险操作 `Accept Dispute` / `Submit Evidence` 明确不在本切片**（源计划 §67：必须 permission + confirmation + audit）→ 归 **P7-8**；
> 本切片**永不**执行资金动作（不退款、不重扣、不 provider mutation）。

---

## 1. 背景与目标

- **一句话需求原文**：「继续」（承接 P7-6 交付后的下一包；P7-0 FR-007 = Admin Dispute Console）。
- **背景**：
  1. **事实链已通，人看不见**：P7-1..6 打通了 durable 模型 → 事件入口 → 只读裁决 → 资金入账 + 对账 → 证据快照 → 期限告警 → 收敛动作；
     但 `grep dispute` 在 `pallastrade_admin` = **0 命中**，`PallasTrade::Dispute` **无授权规则、无 `for_store`、无 ransack 白名单、
     无表格注册、无路由/导航**（侦察确认 5+ 个缺口）→ 运营在后台**看不到任何争议**。
  2. **告警无处落地**：P7-5 发布 `dispute.evidence_due_soon/overdue`、P7-6 发布 `dispute.recovery_repaired/manual_review`，
     但运营点进去没有页面可看（源计划 §66 要求 18 项一屏可见：Dispute ID / Payment / CommerceTransaction / Order / Provider /
     Amount-Currency / Reason / State / Flags / Deadline / Provider References / Refund overlap / Financial movements / Journal /
     Reconciliation / Evidence Snapshot / Recovery Status / Last Provider Event）。
  3. **原语已就绪，UI 只需编排**：`Disputes::ResolveFact`（只读裁决）/ `Disputes::Recover`（`apply:` 可控，已含 dry-run）/
     `Disputes::BuildEvidenceSnapshot`（transient 投影）/ `Reconciliations::ReconcileDispute`（零 provider I/O）——
     本切片**不新增任何事实语义**，只做展现与动作编排。
  4. **危险动作必须显式隔离**：`Accept Dispute`（接受争议 = 放弃抗辩）与 `Submit Evidence`（提交证据 = 对外法律陈述）
     属危险动作（源计划 §67）→ 本切片**不实现**，并在页面上明确标注归属 P7-8。
  5. **范式可完全复用**：`RefundsOpsController`（只读 index/show + `retry`/`mark_review` POST + `authorize_admin` override +
     `audit_actor` + `turbo_confirm`）、`PaymentsOpsController`（跨表 scope）、`PallasTrade.admin.tables.register`（列表列注册）、
     双语硬门槛（`bin/rails pallastrade:admin:nav_validate` 规则⑧：String label 必须 en + zh-CN 同时存在）。
- **目标**：
  1. **模型能力补齐（零 schema）**：`PallasTrade::Dispute.for_store(store)`（防跨店泄露）+ `whitelisted_ransackable_attributes`
     （列表过滤/排序白名单）。
  2. **只读 Console**：`GET /admin/disputes`（store 作用域 + Ransack 过滤/排序 + 表格注册）与
     `GET /admin/disputes/:id`（§66 全字段下钻；在线只读对账 + 证据投影，**异常一律降级不 500**）。
  3. **安全动作（POST，全部幂等、零资金副作用）**：
     `refresh`（刷新 provider 状态 = `ResolveFact(fetch: true)` 只读）/
     `recover`（收敛重试 = `Recover(fetch: true, apply: true)`，唯一允许的写且幂等）/
     `snapshot`（生成证据快照 = `BuildEvidenceSnapshot(fetch: true)`，不落库）/
     `mark_review`（人工标记复核 = 标 `attention_reason` + `manual_review` + 审计）。
  4. **权限接线**：注册 `:disputes` capability（`read`/`update` + 数据域 `store_id`）→ DB 角色可勾选；
     `OrderManagement` / `OrderDisplay` 权限集授予只读（使运营角色可见）。
  5. **导航与双语**：Orders 组新增 `disputes_ops`（position 50，紧随 `payments_ops` 48）；`en.yml` + `admin_nav.zh-CN.yml`
     成对文案；动作按钮遵循既有约定（eligible + `can?(:update)` 才显示；`turbo_confirm` 强确认）。
- **成功指标**（可验证）：
  1. **跨店隔离**：列表/详情只含 `current_store` 的争议（他店 dispute 不出现，越权访问 `:id` 一律 404）；
  2. **过滤生效**：`q[state_cont]` / `q[attention_reason_eq]` 等白名单条件真实生效（非白名单静默丢弃属 Ransack 语义，不 500）；
  3. **详情完整**：§66 的 18 项均有落点；缺 payment / 缺 txn / 无 provider 契约时**降级展示**而非 500；
  4. **动作正确**：4 个动作的 flash 摘要与事实一致；`recover` 重复执行第二次 `noop`（幂等）；`snapshot` 不落库；
     `mark_review` 写 attention + manual_review 且带 actor 审计；
  5. **铁律负向断言**：所有动作前后 `Payment` / `Refund` / `Order` / `CommerceTransaction` / `StockReservation` / `InventoryUnit`
     行数与属性零变化；**未调用**任何 provider 写方法；**不存在** Accept/Submit 端点（路由层面不存在）；
  6. **权限**：无权限用户 → 拒绝（302/403）且零写；`can?(:read, PallasTrade::Dispute)` 的角色能看到导航项；
  7. **回归**：全量 spec 绿 + `nav_validate` 通过 + `generated:check` 无漂移 + `doc-impact` synced。

## 2. 用户故事 / 场景

- 作为**运营/风控**：收到「争议证据将到期」告警后，我要能在后台打开该争议，一眼看到金额/原因/截止/缺什么材料，并点按钮刷新 provider 状态。
- 作为**财务**：我要能看到该争议的资金移动（Journal）与对账结论，确认「扣回/返还」都已入账且金额一致。
- 作为**工程**：我要 Console 只做编排——动作全部幂等、可重跑、零资金副作用；危险操作（接受争议/提交证据）不在本切片且路由层面不存在。

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | 列表跨店隔离 | 安全 | 店铺 A 的管理员只看到 A 的 dispute；B 的出现即视为缺陷 |
| S2 | 过滤与排序 | 正常 | 按 `state` / `attention_reason` / `evidence_due_at` 过滤与排序（白名单列） |
| S3 | 详情全字段 | 正常 | §66 的 18 项齐全（含 journal 行、对账分类、证据缺口、收敛状态） |
| S4 | 无 payment 锚点 | 边界 | `unlinked_payment` 争议详情：Payment/Order 段显示 `—`，页面 200 |
| S5 | 对账失败降级 | 异常 | `ReconcileDispute` 抛错 → 页面 200 + 对账卡片显示 degraded |
| S6 | 证据投影失败降级 | 异常 | `BuildEvidenceSnapshot` 抛错 → 页面 200 + 证据卡片显示 degraded |
| S7 | 刷新 provider 状态 | 正常 | 点击 → 只读 `fetch` → flash 显示 provider 状态与裁决（零写） |
| S8 | 收敛重试 | 正常 | 点击 → 执行收敛 → flash 显示 decision（如 `lifecycle_repaired`）；**重复点击** → 第二次 `noop` |
| S9 | 生成证据快照 | 正常 | 点击 → flash 显示缺口数（如 3 项缺失）；**不落库**、不提交 |
| S10 | 人工标记复核 | 正常 | 点击 → `attention_reason` + `state=manual_review` + 审计（actor 可见）；重复点击幂等 |
| S11 | 无权限访问 | 安全 | 无 `read` 权限用户访问列表/详情 → 302/403 且零写；动作按钮不可见且 POST 被拒 |
| S12 | 危险操作不存在 | 安全 | 路由中**没有** accept / submit_evidence 端点；页面上没有对应按钮（仅文案说明归 P7-8） |
| S13 | 跨店越权读详情 | 安全 | 用 A 店会话访问 B 店 dispute id → 404（`for_store` 作用域） |

## 3. 功能需求（FR）

- **FR-P77-01（模型能力，零 schema）**：`PallasTrade::Dispute` 新增
  ①`scope :for_store, ->(store) { where(store_id: store.id) }`（`store_id` 列已存在；**防跨店泄露**，`ResourceController#find_resource`
  与 `#scope` 都会调它）；②`self.whitelisted_ransackable_attributes = %w[state kind provider outcome attention_reason amount currency
  evidence_due_at evidence_submitted_at funds_withdrawn_at funds_reinstated_at resolved_at created_at]`（列表过滤/排序白名单，
  与 `Refund` / `PromotionRedemption` 同写法）。**不新增列、不改语义**。
- **FR-P77-02（列表页）**：`DisputesOpsController#index` → `GET /admin/disputes`：
  store 作用域（`for_store`）× Ransack（`q[...]`）× Pagy 分页；表格注册 `PallasTrade.admin.tables.register(:disputes, ...)`，
  列含 `prefixed_id`（`dsp_`）/ `state`（badge partial）/ `provider` / `amount`+`currency` / `evidence_due_at` / `attention_reason` / `created_at`；
  页顶 `alert alert-info` 渲染 `admin.orders.disputes_ops_help`（说明只读边界 + 动作范围 + 危险操作归 P7-8）。
- **FR-P77-03（详情页 §66 展示面）**：`#show` → `GET /admin/disputes/:id`，按下表落地 18 项（缺失即降级展示，不 500）：
  | §66 字段 | 数据来源 |
  |---|---|
  | Dispute ID / Provider / Amount-Currency / Reason / State / Flags / Deadline | `PallasTrade::Dispute` 行（`prefixed_id` / `provider` / `amount,currency` / `reason,network_reason_code` / `state` / `attention_reason` / `evidence_due_at,evidence_submitted_at`） |
  | Payment / CommerceTransaction / Order | 关联对象（可空 → 显示 `—`），按 prefixed id 展示 |
  | Provider References | `provider_dispute_reference` / `provider_charge_reference` / `provider_payment_reference` |
  | Refund overlap | 同一 payment 下的 `Refund` 列表（只读；overlap 由对账/证据段间接体现） |
  | Financial movements | `FinancialLedgerEntry.where(dispute_id: dispute.id)`（金额/方向/`effective_at`/`state`） |
  | Journal | 同上（按 `entry_type` 分组展示 `DISPUTE_FUNDS_WITHDRAWN` / `DISPUTE_FUNDS_REINSTATED`） |
  | Reconciliation | 在线 `Reconciliations::ReconcileDispute.call(dispute:)`（零 provider I/O）→ 分类/原因/期望账行 |
  | Evidence Snapshot | 在线 `Disputes::BuildEvidenceSnapshot.call(dispute:)`（**默认不触网**）→ 分段可用性 + `missing_evidence[]` |
  | Recovery Status | `private_metadata['recovery']`（最近一次收敛：`at` / `decision` / `actions` / `from` / `to`）+ 是否有 attention |
  | Last Provider Event | 该 dispute 关联 payment 的最近 `PaymentWebhookEvent`（若有），否则 `—` |
- **FR-P77-04（降级纪律）**：详情页对 `ReconcileDispute` / `BuildEvidenceSnapshot` / `ResolveFact` 的调用**逐个 rescue**（`StandardError → nil`），
  降级时对应卡片显示 degraded 文案；整体页面恒 200（对齐 `RefundsOpsController#show` 既有哲学）。
- **FR-P77-05（`refresh` = Refresh Provider State）**：`POST /admin/disputes/:id/refresh` → `Disputes::ResolveFact.call(dispute:, fetch: true)`；
  flash 呈现 `resolution` / `provider_status` / `fact_type` / `status`；**零写**（不落库、不改状态）；provider 降级时 flash 如实提示
  （`unsupported` / `unavailable`，不伪造成功）。
- **FR-P77-06（`recover` = Retry Recovery）**：`POST /admin/disputes/:id/recover` → `Disputes::Recover.call(dispute:, fetch: true, apply: true)`；
  flash 呈现 `decision` 与动作计数（如 `lifecycle_repaired` / `journal_repaired` / `manual_review_flagged`）；**幂等**（重复执行 → `noop`）；
  这是本切片**唯一允许的写**（写面严格限定在 P7-6 已交付的：状态单调前进 / 账行补记 / attention+manual_review）。
- **FR-P77-07（`dry_run` = 收敛预览）**：`POST /admin/disputes/:id/dry_run` → `Disputes::Recover.call(..., apply: false)`；
  flash 呈现「将会做什么」（计划动作，`status=planned`）；**数据库零变化**（供运营在真正执行前预检）。
- **FR-P77-08（`snapshot` = Generate Evidence Snapshot）**：`POST /admin/disputes/:id/snapshot` →
  `Disputes::BuildEvidenceSnapshot.call(dispute:, fetch: true)`；flash 呈现分段可用性 + `missing_evidence` 数量；
  **不落库、不提交**（`submission_ready` 恒 false；实际提交归 P7-8）。
- **FR-P77-09（`mark_review` = Mark Manual Review）**：`POST /admin/disputes/:id/mark_review`，语义与 P7-6 一致：
  `attention_reason`（**仅当为空时写入**；已有原因则不覆盖）+ `state = manual_review`（若尚未）+ 审计痕迹
  （`private_metadata['admin_review'] = { at, actor }`，actor 来自 `audit_actor`）；重复执行幂等（第二次不重复写）。
- **FR-P77-10（权限与确认）**：
  ①动作按钮仅在「状态 eligible **且** `can?(:update, dispute)`」时渲染（沿用 `refunds_ops/show` 双条件）；
  ②所有 POST 动作带 `data: { turbo_confirm: <i18n 文案> }`（危险/写入动作强确认）；
  ③控制器 `authorize_admin` override：`authorize! :admin, model_class` + 动作映射（读动作→`:read`，写动作→`:update`）；
  ④`backend/config/initializers/pallastrade_permission_registry.rb` 注册 `:disputes`（`actions: %w[read update]`、`data_fields: %w[store_id]`）；
  ⑤`PermissionSets::OrderManagement` 增 `can :read, PallasTrade::Dispute`（`OrderDisplay` 同）——使运营角色默认可读。
- **FR-P77-11（路由 / 导航 / 双语）**：
  ①`resources :disputes, only: [:index, :show], controller: 'disputes_ops'` + `member { post :refresh; post :recover; post :dry_run; post :snapshot; post :mark_review }`（插在 routes.rb `payments_ops` 之后，保持同风格注释）；
  ②导航 Orders 组新增 `orders.add :disputes_ops`（`label: 'admin.orders.disputes_ops'`、`url: :admin_disputes_path`、`position: 50`、
  `active: -> { controller_name == 'disputes_ops' }`、`if: -> { can?(:read, PallasTrade::Dispute) || can?(:manage, PallasTrade::Order) }`）；
  ③文案成对：gem `config/locales/en.yml` 与宿主 `backend/config/locales/admin_nav.zh-CN.yml` 各加
  `disputes_ops` / `disputes_ops_help` / `disputes_refresh`(+`_done`/`_failed`) / `disputes_recover`(+`_confirm`/`_done`/`_failed`) /
  `disputes_dry_run`(+`_confirm`/`_done`/`_failed`) / `disputes_snapshot`(+`_done`/`_failed`) / `disputes_mark_review`(+`_confirm`/`_done`/`_failed`)。
- **FR-P77-12（铁律负向边界）**：本切片**不存在**以下能力（路由层面亦不存在）：
  `Accept Dispute`（接受争议）/ `Submit Evidence`（提交证据）/ 任何退款、重扣、新建 `Payment`、provider 写调用、
  `order`/`inventory`/`CommerceTransaction` 变更、账行改写（append-only）；页面上仅以文案说明这些动作归 P7-8。
- **FR-P77-13（边界）**：0 migration（`store_id` 列已存在）、0 API 端点（仅 Admin HTML 路由）、0 新事实语义
  （一切判定/写入复用 P7-1..6 服务）、不改 P7-1..6 既有行为与既有断言。

## 4. 非功能需求（NFR）

- **只读优先**：列表/详情默认零写；唯一写路径是 `recover`（幂等）与 `mark_review`（幂等）。
- **降级不 500**：所有在线只读调用逐个 rescue；provider 不可用时页面照常渲染并如实标注。
- **安全**：`for_store` 作用域（跨店越权 → 404）；动作按钮双条件显隐 + `turbo_confirm`；CanCan 授权在控制器与导航各一道。
- **i18n 硬门槛**：所有新 String label 必须 en + zh-CN 成对（`nav_validate` 规则⑧；静态版 `scripts/nav-validate-static.mjs` 亦扫）。
- **性能**：列表 `includes` 关联（payment/order）+ Pagy 分页（默认 25）；详情页对账/证据各**在线一次**，不做 N+1（journal 单查询）。
- **可维护**：状态/裁决/attention 的 badge 映射集中在一个 helper（`disputes_ops_helper.rb`），视图不写业务判断。

## 5. 验收标准（AC，与测试一一映射）

- **AC-P77-01 ← FR-P77-02**：`GET /admin/disputes` 200，含本店 dispute 的 `dsp_` id；**不含**他店 dispute（跨店隔离）。
- **AC-P77-02 ← FR-P77-02**：`q[state_cont]=lost` 过滤生效（只返回 lost）；`q[s]=amount+desc` 排序生效（白名单列）。
- **AC-P77-03 ← FR-P77-03**：`GET /admin/disputes/:id` 200，body 含 dispute id / payment id / txn 引用 / order 号 / provider 引用 /
  金额币种 / reason / state / `evidence_due_at`；含 journal 账行 id 与对账分类文案。
- **AC-P77-04 ← FR-P77-03/04**：无 payment 锚点的 dispute 详情 200 且 Payment 段显示 `—`；
  对账或证据投影抛错（打桩）时页面仍 200 且显示 degraded。
- **AC-P77-05 ← FR-P77-05**：`POST :refresh` → 302 且 flash 含 resolution；**零写**（dispute 属性快照不变、账行数不变）；
  provider 降级（无契约）→ flash 如实含 `unsupported`。
- **AC-P77-06 ← FR-P77-06**：`POST :recover`（provider `lost` / 本地 `opened`）→ 状态收敛为 `lost` + flash 含 `lifecycle_repaired`；
  **重复 POST → 第二次 `noop`**（幂等，零新账行）。
- **AC-P77-07 ← FR-P77-07**：`POST :dry_run` → 302 且 flash 含计划决策；**数据库零变化**（state / attention / 账行数 / `updated_at` 不变）。
- **AC-P77-08 ← FR-P77-08**：`POST :snapshot` → 302 且 flash 含缺口数量；**不落库**（无新行、`updated_at` 不变）。
- **AC-P77-09 ← FR-P77-09**：`POST :mark_review` → `attention_reason` 写入（若原本为空）+ `state = manual_review` +
  `private_metadata['admin_review']['actor']` 记录；**已有 attention 时不被覆盖**；重复 POST 幂等。
- **AC-P77-10 ← FR-P77-10**：无 `read` 权限用户 `GET /admin/disputes` → 非 200（302/403）且零写；
  `GET /admin/disputes/:id` → 同样被拒；POST 动作被拒且状态不变。
- **AC-P77-11 ← FR-P77-10**：跨店越权：用 A 店会话对 B 店 dispute 发 `GET :show` → 404（`for_store` 生效）。
- **AC-P77-12 ← FR-P77-12**：路由**不存在** `accept` / `submit_evidence` 端点（`Rails.application.routes` 断言 0 命中）；
  **负向断言**：所有动作执行前后 `Payment` / `Refund` / `Order` / `CommerceTransaction` / `StockReservation` / `InventoryUnit`
  行数与属性不变，且未调用 provider 写方法。
- **AC-P77-13 ← FR-P77-11**：导航一致性 spec 的 Orders children 期望数组含 `disputes_ops`；
  `admin.orders.disputes_ops` 与 `..._help` 在 `en` + `zh-CN` **两份** locale 中均存在（`nav_validate` 通过）。
- **AC-P77-14 ← FR-P77-02**：`PallasTrade.admin.tables.get(:disputes)` 非 nil 且可见列含 `prefixed_id` / `state`；
  列表页渲染 state badge（`dsp_` id 与状态文案同现）。
- **AC-P77-15 ← FR-P77-01**：`PallasTrade::Dispute.for_store(store)` 只返回该店行；`whitelisted_ransackable_attributes`
  含 `state` / `attention_reason` / `evidence_due_at`（模型级断言）。
- **AC-P77-16 ← FR-P77-13**：回归——全量 spec 绿、`generated:check` 无漂移、`doc-impact` synced（无既有断言修改，除导航一致性数组）。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`dispute` / `chargeback` / `ops` / `admin` / `for_store` / `ransack` / `tables.register` / `navigation`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App | `backend/app/` | 仅 `spec/requests/pallastrade/admin/*`（无 dispute admin 代码）；`backend/config/initializers/pallastrade_permission_registry.rb`（权限注册表）、`backend/config/locales/admin_nav.zh-CN.yml` | ⚠️ 需注册 `:disputes` capability + 补 zh-CN 文案 |
| Core | `pallastrade_core/app/` | `models/pallastrade/dispute.rb`（**无 `for_store` / 无 ransack 白名单**）、`permission_sets/{order_management,order_display,super_user}.rb`、`models/pallastrade/ability.rb` | ⚠️ 需补 `for_store` + ransack 白名单 + 权限集只读规则 |
| Admin | `pallastrade_admin/app/` + `config/` | `controllers/.../payments_ops_controller.rb`、`refunds_ops_controller.rb`（范式）、`config/routes.rb:321-341`、`config/initializers/pallastrade_admin_navigation.rb:80-113`、`config/locales/en.yml:482-483`、`app/views/pallastrade/admin/{payments,refunds}_ops/*` | ❌ 无 dispute 页面 → 本切片新增（范式可直接复制） |
| API | `pallastrade_api/app/` | 无命中（无 dispute 端点） | ❌ 本切片不加 API（Console 仅 HTML） |
| Storefront | `storefront/src/` | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | 无命中 | ❌ 无 SDK 变更 |

**结论**：Admin 侧 dispute 展现**完全不存在**，模型侧缺 2 项能力（`for_store` / ransack 白名单）与权限接线 →
本切片新增 `DisputesOpsController` + 5 个动作路由 + 表格注册 + helper + 双语 + 权限注册；
**防重复判定（AP-SEARCH-1/2/3）**：不新建事实/裁决/对账/证据/收敛逻辑（全部复用 P7-1..6 服务），
不新建导航顶级项（挂既有 Orders 组），不新建权限体系（走既有 registry + permission sets）。

## 7. 技术影响

- **新增文件**：`pallastrade_admin/app/controllers/pallastrade/admin/disputes_ops_controller.rb`、
  `app/helpers/pallastrade/admin/disputes_ops_helper.rb`、`app/views/pallastrade/admin/disputes_ops/{index,show}.html.erb`、
  `app/views/pallastrade/admin/tables/columns/_dispute_state.html.erb`（badge）、
  `backend/spec/requests/pallastrade/admin/disputes_ops_spec.rb`、`.../disputes_ops_actions_spec.rb`。
- **修改文件**：`pallastrade_core/app/models/pallastrade/dispute.rb`（`for_store` + ransack 白名单）、
  `pallastrade_core/app/models/pallastrade/permission_sets/{order_management,order_display}.rb`、
  `backend/config/initializers/pallastrade_permission_registry.rb`、`pallastrade_admin/config/routes.rb`、
  `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb`、`pallastrade_admin/config/initializers/pallastrade_admin_tables.rb`、
  `pallastrade_admin/config/locales/en.yml`、`backend/config/locales/admin_nav.zh-CN.yml`、
  `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（Orders children 数组）。
- **数据**：**零 schema 变更**（`store_id` 已存在；无新表——P7-4 证据快照为 transient，不落库）。
- **接口**：无 API / 无 SDK 变更；`generated:check` 应保持无漂移。
- **兼容**：不改 P7-1..6 服务符号与语义；模型新增 scope 与白名单为纯增量。
- **回滚**：删除路由/导航条目即隐藏入口；控制器/视图删除无数据影响（唯一写路径是幂等收敛与人工标记）。
- **风险**：
  ①**跨店泄露**（若忘记 `for_store`）→ AC-P77-11 越权用例钉死；
  ②**页面 500**（对账/证据/provider 异常）→ FR-P77-04 降级纪律 + AC-P77-04；
  ③**误当资金操作入口**（运营以为点按钮会退款）→ 页面文案明确「零资金副作用 + 危险操作归 P7-8」；
  ④**权限收紧导致运营看不见**（`Dispute` 原无任何规则）→ FR-P77-10⑤ 给 OrderManagement/OrderDisplay 补只读规则 + AC-P77-10。

## 8. 测试计划（AC ↔ 测试文件）

| AC | 测试文件（新增/修改） | 类型 |
|---|---|---|
| AC-P77-01..04、11、14 | `backend/spec/requests/pallastrade/admin/disputes_ops_spec.rb`（新增） | 请求（列表/详情/跨店/降级/表格注册） |
| AC-P77-05..10、12 | `backend/spec/requests/pallastrade/admin/disputes_ops_actions_spec.rb`（新增） | 请求（动作成功/幂等/dry-run/权限/铁律负向断言） |
| AC-P77-13 | `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb`（修改数组）+ `bin/rails pallastrade:admin:nav_validate` | 导航/双语 |
| AC-P77-15 | `backend/spec/models/pallastrade/dispute_spec.rb`（追加 `for_store` / ransack 白名单断言） | 模型 |
| AC-P77-16 | 注册 verifier `backend-rspec`（全量）+ `generated:check` + `doc-impact` | 回归 |

## 9. 文档同步清单（知识同步门）

- [x] **`ai/skills/pallastrade-payments/SKILL.md`**：新增「Dispute Admin Console（DSP-P7-7）」段（只读投影 / 5 个动作语义 / `operator_review` 只补不覆盖 / 权限与导航接线 / P7-8 危险操作分界）+ Changelog 条目
- [x] **`ai/skills/pallastrade-admin/SKILL.md`**：已评估，无需更新——本切片沿用既有 Ops 页面范式（资源控制器 + 注册表驱动表格 + helper 徽章 + `PallasTrade.t` 文案），未引入新 admin 框架能力
- [x] **`ai/skills/pallastrade-data-model/SKILL.md`**：已更新——`attention_reason` 写者清单补 DSP-P7-7 console（`operator_review`，写者为 `Disputes::MarkManualReview`）
- [x] **`harness/scenarios/scenarios.json`**：新增 GS-098（只读投影 + 动作永不触资金 + 跨店隔离 + 危险操作闸门）→ `eval-ai --scenarios` 99/99 通过
- [x] **`docs/prd/README.md`**：登记本 PRD 索引行
- [x] **`harness/requirements/REQ-20260913-dsp-p7-7-admin-disputes-console.md`**：gate 时生成并回填
- [x] **API 文档**：N/A（无接口变更）→ `generated:check` 无漂移为证
- [x] 收尾评估 `prd` Skill / `AGENTS.md` / `copilot-instructions.md` / `deployment` Skill：均无需更新（无新流程/无新增治理规则/无部署面变更）；`doc-impact --base origin/dev` 全部 synced

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿（承接 DSP-P7-6；源计划 §66/§67；含 6 层跨层搜索与既有范式侦察） | AI |
| 2026-09-13 | 0.2 | 用户确认（approved）：全量实施（含 5 个动作，其中 4 个来自源计划 §67 + `dry_run` 预览）；允许真实执行 `recover`；给 OrderManagement/OrderDisplay 补 Dispute 只读规则 | AI |
| 2026-09-13 | 0.3 | 实施完成：列表/七卡详情/5 动作/权限与导航接线/`MarkManualReview` 新服务；specs 58 例全绿（含负向断言）、RuboCop 0 offenses（新增 5 文件 + 修改 9 文件基线对比无新增）、知识同步已回填（§9） | AI |
