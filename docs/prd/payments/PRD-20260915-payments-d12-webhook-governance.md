# PRD-20260915-payments-d12-webhook-governance

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：D12 Webhook 治理 —— 入站事件流页面 + 详情/重放/隔离 + 端点健康 + 订阅核对清单（业务方案 §78-D12 / §69） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-events-webhooks`、`pallastrade-security`、`pallastrade-testing` |
| 关联 REQ | `harness/requirements/REQ-20260915-d12-webhook-governance.md` |
| 关联 PRD | `PRD-20260902-payments-payment-p0-foundation-hardening…`（P0-2 事件存储 + P0-6 审计）；`PRD-20260911-payments-dsp-p7-1…`（dispute 事件族分流） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D12 Webhook 治理：事件流页面 + 详情/重放/死信 + 端点健康 + 订阅核对清单。
- **背景（代码事实，§69 已确认）**：
  - **已有**：`PallasTrade::PaymentWebhookEvent`（P0-2 事件存储：`provider/provider_event_id` 唯一去重、`received→processing→processed|failed` 状态机、`payload` jsonb、`attempt_count`、`last_error_*`、按 `payment_session` 关联）；`Payments::ReplayWebhookEvent`（人工重放 + 审计 + trace 日志）；出站侧 `WebhookEndpoint`/`WebhookDelivery` + 后台「Developers → Webhook endpoints / deliveries」（含 `redeliver`）。
  - **缺口**：入站事件**没有任何运营页面**（排障要写 SQL）；无「人工标记已处理」；无「隔离/忽略未知事件」；无端点健康聚合；无订阅核对清单（无法检出漏订事件）。
- **目标**：把入站事件变成**可看、可筛、可处置**的运营面，并给出可检出的「漏订/未知事件」信号。
- **成功指标**：① 排障可在页面完成（按 provider/action/status/时间/会话/订单筛选 → 详情 → 重放/隔离）；② 漏订事件可检出（期望事件集 − 近 30 天观察集）；③ 健康指标可读（近 24h 失败率/积压/平均处理时长 + 出站投递成功率）。

## 2. 用户故事 / 场景

- 作为**支付运营**，我希望按订单号或 provider 事件 id 直接定位到事件详情，以便不写 SQL 排障。
- 作为**支付运营**，我希望对 failed 事件一键重放，对未知事件**隔离**（保留留痕、不再处理），对已人工处理的事件标记 `processed`。
- 作为**集成工程师**，我希望看到「Stripe 应订阅哪些事件 vs 最近实际收到哪些」的对照，以便发现漏订。
- 场景：① 失败事件 → 重放 → 状态回流；② 未知事件（provider 新类型）→ 隔离 + 理由；③ 期望事件 30 天未见 → 清单红标；④ 端点（出站）连续失败 → 健康卡提示。

## 3. 功能需求（FR）

- **FR-001**：`PaymentWebhookEvent` 增补 —— 新状态 `quarantined`（隔离）+ 列 `quarantined_at` / `quarantine_reason`（迁移）；隔离事件**不再参与处理**（`replayable?` 返回 false，Job 侧不重放）。
- **FR-002**：筛选 scope —— `provider` / `action` / `status` / 时间范围 / `payment_session` / 订单号（经 `payment_session.order` 反查）。
- **FR-003**：人工处置服务（均写 `Audit` + 结构化 trace 日志，actor 记录后台用户）：
  - `Payments::QuarantineWebhookEvent`（隔离，需 reason）；
  - `Payments::MarkWebhookEventProcessed`（人工标记已处理）；
  - 复用既有 `Payments::ReplayWebhookEvent`（重放）。
- **FR-004**：`Payments::WebhookHealth`（只读聚合）——
  - 入站近 24h：各状态计数、失败率、平均处理时长（`processed_at - received_at`）、积压（received + processing）、最近失败时间；
  - 出站近 24h：成功/失败计数、成功率、积压（`success IS NULL`）、最近失败时间。
- **FR-005**：`Payments::WebhookSubscriptionChecklist` —— 按 provider 计算：`expected`（provider 声明）− `observed`（近 30 天落库 action）= **漏订候选**；`observed` − `expected` = **未知事件**（建议隔离或新增订阅）。
- **FR-006**：provider 声明期望事件 —— `PaymentMethod#webhook_event_subscriptions`（基类 `[]`；Stripe 覆写 → `WEBHOOK_EVENT_ACTIONS.keys` 映射为本地 action 集）。
- **FR-007**：后台页面 —— `Developers → Webhook Events`：
  - index：筛选条（provider/action/status/时间/订单号）+ 分页 + 行内状态徽章 + 健康卡 + 订阅核对清单卡；
  - show：事件元数据（provider/event_id/event_type/action/status/attempt/耗时）、payload（折叠 + 复制）、解析结果、last_error、关联（payment_method / payment_session / order）、动作按钮（重放/标记已处理/隔离）；
  - 导航注册（Developers 区 + tabs nav）+ 权限（`can?(:manage, PallasTrade::PaymentWebhookEvent)`）+ i18n（gem en + 宿主 zh-CN）。
- **FR-008**：既有出站页不动（`webhook_deliveries` 保留），仅新增入站面；表结构变更仅 additive。

## 4. 非功能需求（NFR）

- **性能**：列表页 `limit/offset` 分页，筛选走既有索引（`payment_method_id+status`、`provider+provider_event_id`）；健康/清单聚合**单次 SQL 聚合**，不逐条加载 payload。
- **安全**：payload 可能含敏感信息 → 详情页按需折叠；隔离/重放/标记均写审计（actor=当前后台用户）；`quarantine_reason` 长度截断。
- **兼容**：新增状态对既有状态机 additive（`received/processing/processed/failed` 语义不变）；无 API 契约变更（内部表不对外暴露资源 API）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：隔离后 `status == 'quarantined'`、`quarantined_at`/`quarantine_reason` 落库，且 `replayable? == false`。
- **AC-002** ← FR-002：筛选 scope 组合正确（provider/action/status/时间/订单号）。
- **AC-003** ← FR-003：三个处置动作各自写 `Audit`（action 名区分）+ 状态正确流转；重放走既有 Job。
- **AC-004** ← FR-004：健康聚合在**空库**与**有数据**两种情形下数值正确（计数/失败率/积压/平均时长）。
- **AC-005** ← FR-005：清单正确给出漏订候选与未知事件（期望集来自 provider 声明）。
- **AC-006** ← FR-006：Stripe 声明覆盖其 `WEBHOOK_EVENT_ACTIONS` 全部事件；其他 provider 默认空集不报错。
- **AC-007** ← FR-007：后台 index/show 可访问（权限门控）、筛选与动作端点可用、导航子项与 tabs 一致（含 `navigation_consistency_spec` 回归）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `payment_webhook` / `webhook_event` | 无命中 | ❌ 未满足 |
| Core | `pallastrade_core/app/` | 同上 | `models/pallastrade/payment_webhook_event.rb`（状态机 + `create_unique` + `mark_*`）、`services/pallastrade/payments/replay_webhook_event.rb`、`jobs/pallastrade/payments/handle_webhook_job.rb`、`models/pallastrade/permission_sets/configuration_management.rb` | ⚠️ 部分（缺隔离/人工标记/健康/清单） |
| API | `pallastrade_api/app/` | 同上 | 仅 `webhook_delivery_serializer` + `webhook_endpoints_controller`（出站）；入站事件**不对外** | ✅ 无需变更 |
| Admin | `pallastrade_admin/app/` | `webhook` | `webhook_endpoints_controller` / `webhook_deliveries_controller`（含 `redeliver`）+ 表格注册 + Developers 导航（position 10） | ⚠️ 部分（仅出站；入站零页面） |
| Storefront | `storefront/src/` | — | 不涉及 | ✅ 无需变更 |
| Platform | `platform/packages/` | — | 不涉及（无契约变更） | ✅ 无需变更 |

**结论**：承载点集中在 Core（模型 + 新服务）与 Admin（新控制器/视图/导航/i18n）；API/Storefront/Platform 零改动；不新建重复能力（复用 P0-2 事件表 + P0-6 审计 + 既有重放服务）。

## 7. 技术影响

- **迁移**：`add_column(pallastrade_payment_webhook_events, quarantined_at: :datetime, quarantine_reason: :string)`（additive，无回填）。
- **Core**：`payment_webhook_event.rb`（状态/scope/方法）、新增 3 服务（Quarantine / MarkProcessed / WebhookHealth + SubscriptionChecklist）、`payment_method.rb`（`webhook_event_subscriptions` 基类）、Stripe gateway 覆写。
- **Admin**：新增 `WebhookEventsController` + 视图（index/show/筛选/动作）+ 导航 + i18n；`configuration_management.rb` 增权限。
- **测试**：模型 spec、服务 spec（3 个）、admin request spec、导航一致性回归。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 模型 | `backend/spec/models/pallastrade/payment_webhook_event_quarantine_spec.rb` | AC-001/002 |
| 服务 | `backend/spec/services/pallastrade/payments/webhook_event_ops_spec.rb`（隔离/标记/审计） | AC-003 |
| 服务 | `backend/spec/services/pallastrade/payments/webhook_health_spec.rb` | AC-004 |
| 服务 | `backend/spec/services/pallastrade/payments/webhook_subscription_checklist_spec.rb` | AC-005/006 |
| 请求 | `backend/spec/requests/pallastrade/admin/webhook_events_spec.rb`（index/show/动作/权限/导航） | AC-007 |

## 9. 收口清单

- [x] 本 PRD（approved → **done**，2026-09-15 实施完成）
- [x] REQ：`harness/requirements/REQ-20260915-d12-webhook-governance.md`（含 6 层搜索 + Skill 咨询表 + 实施记录）
- [x] gate `GATE-2026-09-15T15-48-25` + prep 清理；critical 恢复计划 `REC-e76b3e4a990eb4`
- [x] 用户确认：用户 2026-09-15「继续」（承接「下一批 D12 Webhook 治理」）
- [x] 验证：`harness verify d12-webhook-governance-rspec`（含 `navigation_consistency_spec` 回归）
- [x] 知识同步（`sync-check` 三组逐条评估）：**已更新** —— `pallastrade-payments` / `pallastrade-events-webhooks` / `pallastrade-admin` Skill、`AGENTS.md`（§6 verifier 行）、`harness/scenarios/scenarios.json`（GS-138）、测试（新增 5 个 spec 文件 + 导航一致性回归）；**已评估无需更新** —— `pallastrade-data-model` Skill（两列 additive，且该表为内部可靠性外壳、非业务数据模型）、`pallastrade-api-v3` Skill 与 `api-docs/*.yaml` / SDK 类型（本批为后台 HTML 路由，无 API v3 契约变更，`generated:check` 零漂移）、`pallastrade-prd` Skill、`copilot-instructions.md`

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-15 | 初版（v1 范围：入站事件流 + 处置动作 + 健康 + 订阅清单） |
| 1.0 | 2026-09-15 | 实施完成：迁移（quarantine 两列）+ 模型（状态/筛选/方法）+ 4 服务 + admin console（页面/导航/权限/i18n 双语）+ 5 个 spec 文件；验证器 26 例 + 导航一致性回归全绿 |
