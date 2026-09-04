# PRD-20260904-api-txn-p2-2-transactions-start-resume

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-04 |
| 来源 | P2 程序文档 §14/§15/§53 + TXN-P2-0 审计（§5 冻结决策/§6.5 QUOTE_CONSENT/§6.6 session 关系/§6.12 API 提案） |
| 分类 | api（harness prd new 自动判定，因含 Store API） |
| 关联 Skill | pallastrade-api-v3、pallastrade-payments、pallastrade-checkout、pallastrade-data-model |
| 关联 REQ | REQ-20260904-txn-p2-2.md（实施时回填） |
| 关联 PRD | PRD-20260904-checkout-txn-p2-1-commercetransaction-core（TXN-P2-1，已完成） |
| 需求类型 | 新功能 |

> 本包范围：**核心服务（Start/Resume）+ session.transaction_id 迁移 + 单订单 Store API（start/resume）+ 报价同意（quote consent）**。组合 Start API、storefront 消费、409 前端均延后（TXN-P2-5/6）。

## 1. 背景与目标

- **一句话需求原文**：让 READY 的 Checkout 能通过 `Transactions::Start` 启动 durable CommerceTransaction（冻结 snapshot、绑定参与者、委托 `PaymentSessions::Start` 并关联会话），并提供 Resume 读模型。
- **背景**：TXN-P2-1 已建 `CommerceTransaction`/`TransactionOrder` 底座；尚无任何服务/入口创建与复用交易。
- **目标**：同一商业意图重复调用只产生同一 active Transaction（业务幂等）；启动时冻结报价证据；quote 过期仅当商业事实变化才要求用户重新确认（QUOTE_CONSENT，409 `QUOTE_CHANGED`）；PaymentSession 归属 Transaction。
- **成功指标**：Start/Resume 服务 spec 全绿；`payment_sessions.transaction_id` 写入正确；单订单 API request spec 绿；既有支付/checkout 回归不破坏（未接 storefront 前旧入口行为不变）。

## 2. 用户故事 / 场景

- 作为系统，我希望以「启动交易」为统一入口创建/复用支付执行，以便后续 FactResolver/Recovery 有交易上下文。
- 正常：READY 订单 Start → 建 transaction（created→payment_pending）+ snapshot + session 绑定 → 返回 {transaction, payment_execution}。
- 幂等：5 次点击 / timeout 重试 / 并发 → 同一 active Transaction + 复用 active session（P0 二次锁）。
- 异常：quote 过期且商业事实变化 → 409 QUOTE_CHANGED（带 latest），不创建 session；readiness 缺失 → checkout_not_ready。
- 恢复：`payment_pending` 交易可 Resume（继续复用/新建合法 session）；终态交易 Start → 新交易或错误（按 Payment Start Policy）。

## 3. 功能需求（FR）

- FR-201：`PallasTrade::Transactions::Start`（core service）：入参 order(s)/purpose/payment_method/external_data/expected_checkout_version/expected_price_version/expected_fingerprint(可选)。
- FR-202：流程=参与者解析 → CheckoutSnapshot 载入 → Readiness（复用 `OrderCheckout::Readiness`，缺项→`checkout_not_ready`）→ 过期则 `OrderCheckout::Refresh` → **quote consent 比对**（金额/币种/行项目/运费/promo/tax 相对 snapshot）→ 变化→`quote_changed` 业务错误（latest quote）；未变→透明续期 → 查找/创建 active Transaction（幂等，参考 `CommerceTransaction.active_for_order`）→ 冻结 snapshot（`snapshot!`）→ 建 `TransactionOrder`(role) → `PaymentSessions::Start` → session.transaction_id 绑定 → 返回。
- FR-203：业务幂等：同 order+purpose 存在 active（created/payment_pending）Transaction 即复用（不重复 snapshot 冻结/参与者）。
- FR-204：Payment Start Policy：Transaction 状态为 payment_confirmed/finalizing/completed/recovery_required/manual_review 时禁止创建新 session（返回业务错误）。
- FR-205：`PallasTrade::Transactions::Resume`：读模型（transaction + participants + sessions + payment 摘要 + state），供 GET。
- FR-206：migration：`pallastrade_payment_sessions.transaction_id`（可空 FK → commerce_transactions）；存量 NULL（不回溯）。
- FR-207：Store API（单订单）：`POST /api/v3/store/orders/:order_id/transactions`（order 域授权，同 payment_sessions create 的 store+owner 作用域；body: payment_method_id/external_data/expected_*）→ 201 {data:{transaction,payment_execution}}；409/checkout_not_ready/422 结构化错误。
- FR-208：`GET /api/v3/store/transactions/:id`（owner 作用域）→ Resume 视图 {state,participants,payment_state,recovery,completion}。
- FR-209：CommerceTransaction/TransactionOrder 只读 serializer（Store v3，prefixed `txn_`；不含内部 recovery 明细，最小字段）。

## 4. 非功能需求（NFR）

- 幂等与并发：Start 在 Transaction 与 Session 双层防重；provider I/O 在 Order 锁外（沿用 PaymentSessions::Start 结构）。
- 兼容：既有 `POST /orders/:order_id/payment_sessions`（payment-session-first）**保持不变**；TXN-P2-6 前 storefront 仍走旧入口。
- 授权：所有新端点 current_store + owner/token 作用域（对齐 OrderResolvable/OrderLock）。
- 文档：新增端点进 `backend/public/api-docs/store.yaml`（R1 契约校验 `api:docs:validate` 通过）。

## 5. 验收标准（AC，与测试一一映射）

- AC-201 ← FR-201/202：READY 订单 Start → Transaction(created→payment_pending) + snapshot 冻结 + 1 TransactionOrder(primary) + session.transaction_id 绑定。
- AC-202 ← FR-203：重复 Start（同 order/purpose/active 内）→ 同一 active Transaction、不重复冻结/参与者、复用/新建合法 session（P0 幂等兜底）。
- AC-203 ← FR-204：终态（completed 等）Transaction 再 Start 新支付被拒（业务错误）。
- AC-204 ← FR-202：quote 过期且商业事实变化 → `quote_changed` 错误 + latest quote；无变化 → 透明续期继续。
- AC-205 ← FR-202：readiness 缺失 → `checkout_not_ready`。
- AC-206 ← FR-205/208：Resume 返回交易状态/参与者/支付摘要。
- AC-207 ← FR-207：API 201 形状 {transaction, payment_execution}；409/422 结构化错误；owner/store 越权 404。
- AC-208 ← FR-206：迁移可 up/down；存量 session transaction_id NULL。
- AC-209：既有 p0-payment-rspec / chk-p1-5-rspec / start_spec 回归全绿（旧 payment-session 入口行为不变）。
- AC-210：RuboCop 0；store.yaml `api:docs:validate` 通过。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 结果 | 满足？ |
|---|---|---|---|---|
| App | backend/app/ | transaction | 无 | 否 |
| Core | .../core/app/ | Transactions::Start | 无（TXN-P2-1 仅有模型） | 否（需新建服务） |
| API | .../api/app/ | transactions | 无资源；orders/payment_sessions 为参照 | 否（需新建端点） |
| Admin | .../admin/ | transaction | 无 | 否（TXN-P2-7） |
| Storefront | storefront/src/ | transaction | 无 | 否（TXN-P2-6） |
| Platform | platform/packages/sdk | transactions | 无 | 延后（TXN-P2-6 或本包 SDK 类型最小同步） |

**结论**：全层无 Start/Resume 能力 → core 新建 services + api 新建 store 端点；payment_sessions 既有控制器/Start 为复用蓝本。

## 7. 技术影响

- core：`services/pallastrade/transactions/{start,resume}.rb`（模块 PallasTrade::Transactions）。
- core model：`PaymentSession` 增 `belongs_to :commerce_transaction`(可空) + 反向 `CommerceTransaction.has_many :payment_sessions`（可空 FK）。
- api：`store/orders/transactions_controller.rb`（create）+ `store/transactions_controller.rb`（show）；routes；`CommerceTransactionSerializer`。
- migration：`payment_sessions.transaction_id` 可空 FK + index。
- 文档：store.yaml 增量（2 端点 + schema）；`generated:check`/`api:docs:validate`。
- 不改既有支付入口行为（strangler，TXN-P2-6 才切）。

## 8. 测试计划

- 新增 core：`spec/services/pallastrade/transactions/start_spec.rb`（AC-201/202/203/204/205）、`resume_spec.rb`（AC-206）。
- 新增 request：`spec/requests/api/v3/store/orders/transactions_controller_spec.rb`、`store/transactions_controller_spec.rb`（AC-207）。
- 迁移/模型：`spec/models/pallastrade/payment_session_transaction_spec.rb`（AC-208）。
- 回归：p0-payment-rspec / chk-p1-5-rspec / chk-p1-3-rspec。
- 每条 spec 头标注 `# PRD-20260904-api-txn-p2-2 AC-xxx`。

## 9. 文档同步清单（知识同步门）

- [ ] store.yaml（新端点）+ `api:docs:validate` — 延后：R1 契约基建收口（TXN-P2-6 随 storefront 迁移一并）
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`（changelog：transactions 端点）
- [x] `ai/skills/pallastrade-payments/SKILL.md` / `pallastrade-checkout/SKILL.md` changelog（Start 接线）
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态
- [ ] 若 SDK 类型同步 → `platform/packages/sdk/src/types`（zod/ts）`generated:check` — 延后：TXN-P2-6 storefront 迁移

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-04 | 0.1 | 初稿 | AI |
| 2026-09-04 | 0.2 | approved（用户"实施"）；core Start/Resume + PaymentSession.transaction_id FK + API create/show + request specs 全绿（services 7 + request 5）；状态 approved；store.yaml/SDK 延后 R1/TXN-P2-6 | AI |
