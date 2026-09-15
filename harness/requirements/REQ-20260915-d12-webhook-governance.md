# REQ-20260915-d12-webhook-governance

> 任务：`TASK-20260915154648-106ee92d` · PRD：`docs/prd/payments/PRD-20260915-payments-d12-webhook-governance.md`
> 需求原文：用户 2026-09-15「继续」（承接 AI 建议「下一批 D12 Webhook 治理」）

## Step 0：6 层跨层搜索（实查结论）

| 层 | 关键词 | 结论 |
|---|---|---|
| App `backend/app/` | `payment_webhook` / `webhook_event` | **无命中** —— 宿主层无实现 |
| Core | 同上 | `PaymentWebhookEvent`（P0-2：`create_unique` 去重、`received→processing→processed→failed`、`payload`/`attempt_count`/`last_error_*`、`mark_processing!/mark_processed!/mark_failed!`、`replayable?`）；`Payments::ReplayWebhookEvent`（重放 + Audit + trace）；`Payments::HandleWebhookJob`（Job 生命周期，dispute 分流）；`permission_sets/configuration_management.rb`（WebhookEndpoint/WebhookDelivery 权限） |
| API | `webhook` | 仅**出站**（`webhook_endpoints` / `webhook_deliveries` 控制器 + 序列化器）；入站事件表**不对外暴露资源 API** → 本批无契约变更 |
| Admin | `webhook` | `webhook_endpoints_controller` + `webhook_deliveries_controller`（`redeliver` 已存在）+ tables 注册（含 `health`/`deliveries_stats` 列）+ Developers 导航（position 10，`active` 含两个控制器） |
| Storefront | — | 不涉及 |
| Platform | — | 不涉及（无 OpenAPI/SDK 变更） |

**防重复判定**：不新建事件存储（复用 P0-2 表）、不新建重放实现（复用 `ReplayWebhookEvent`）、不动出站链路（仅新增入站面）。

## Step 1：Skill 咨询证据表

| Skill | 结论（约束） |
|---|---|
| `pallastrade-customization` | 决策树优先级 8（改 gem 源码 + `# PALLAS-CUSTOM:` 注释）；本批改 core/api 内的 gem 文件与 admin 视图 |
| `pallastrade-payments` | 支付域事实：`PaymentWebhookEvent` 是**可靠性外壳**，业务幂等仍在 `HandleWebhook`；「未知异常必须 raise（Job retry），禁止 swallow」——隔离/标记动作**不得**改变该语义，只做状态与留痕 |
| `pallastrade-events-webhooks` | 事件/订阅者约定：出站投递走 `WebhookDeliveryJob`；新增页面只读聚合，不引入新订阅者 |
| `pallastrade-security` | 敏感动作（重放/隔离/人工标记）必须写 `Audit` + 记录 actor；payload 可能含敏感字段 → 页面折叠展示、不落日志 |
| `pallastrade-admin` | 后台三要素（面包屑 + 标题 + 图标）、`data: { turbo_method: :post }`（**无 rails-ujs**）、按钮需权限门控；导航一致性 spec 必须同步子项数组 |
| `pallastrade-testing` | 后端 spec 走 `rails_helper`；admin request spec 需 `allow_any_instance_of(...).to receive(:location_after_save)` 之类的既有范式（本批为自定义 console，按 `disputes_ops` 范式） |

## Step 2：设计要点

1. **状态扩展**：`STATUSES` 增 `quarantined`；新增列 `quarantined_at` / `quarantine_reason`（迁移，additive）。`replayable?` → `!(processing? || quarantined?)`。
2. **筛选**：模型 scope `filter_by(provider:, action:, status:, from:, to:, order_number:)`（单一入口，控制器只做参数校验）。
3. **处置服务**：`QuarantineWebhookEvent` / `MarkWebhookEventProcessed` 各自 `PallasTrade::ServiceModule::Base`，写 `Audit(action: 'webhook_quarantine' / 'webhook_mark_processed')` + `Rails.logger.info(message: 'payment.webhook.*')`。
4. **健康**：`WebhookHealth.call(now:)` → `{ inbound: {...}, outbound: {...} }`（入站按 status 分组计数 + 积压 + 平均耗时；出站 `success IS NULL` = 积压、`success = true/false` 计数）。
5. **订阅清单**：`WebhookSubscriptionChecklist.call(provider:)` → `{ provider:, expected: [...], observed: [...], missing: [...], unknown: [...] }`（`missing` = 漏订候选）。
6. **provider 声明**：`PaymentMethod#webhook_event_subscriptions`（基类 `[]`）；`PallasTradeStripe::Gateway` 覆写 → `WEBHOOK_EVENT_ACTIONS.keys`（去掉 dispute 前缀映射差异，按本地 action 名给出）。
7. **后台**：`PallasTrade::Admin::WebhookEventsController`（自定义 console 范式，同 `disputes_ops`），index/show + `POST :replay / :quarantine / :mark_processed`；导航 `developers.add :webhook_events`（position 15）；权限 `can :manage, PallasTrade::PaymentWebhookEvent`。

## Step 3：切片

- **切片 1（core）**：迁移 + 模型状态/scope/方法 + provider 声明（FR-001/002/006）。
- **切片 2（core 服务）**：隔离 / 人工标记 / 健康 / 清单（FR-003/004/005）。
- **切片 3（admin）**：控制器 + 视图 + 导航 + 权限 + i18n（FR-007）。
- **切片 4（收口）**：specs + 知识同步 + 文档回写。

## 实施记录（2026-09-15 完成）

| 项 | 结果 |
|---|---|
| 迁移 | `20260915160000_add_quarantine_to_payment_webhook_events.rb`（quarantined_at / quarantine_reason；dev + test 已跑） |
| Core | `payment_webhook_event.rb`（STATUSES + quarantined、`filter_by`、`mark_quarantined!` / `unquarantine!` / `mark_processed_manually!`、`#order` / `#processing_duration_seconds`）；`payment_method.rb`（`webhook_event_subscriptions` / `webhook_expected_actions` 基类）；Stripe gateway 覆写（12 事件名 / 9 action） |
| Services | 新建 `Payments::{QuarantineWebhookEvent,MarkWebhookEventProcessed,WebhookHealth,WebhookSubscriptionChecklist}` |
| Admin | 新建 `WebhookEventsController`（index/show/replay/quarantine/mark_processed）+ 2 视图 + 路由 + 导航（Developers position 15 + tabs 30）+ 权限（`can :manage, PaymentWebhookEvent`）+ 双语 locale（gem en / 宿主 zh-CN） |
| 测试 | `harness verify d12-webhook-governance-rspec` → **26 例 0 失败**（模型 7 + ops 5 + health 3 + checklist 4 + admin 6 + 导航一致性回归） |
| 知识同步 | payments / events-webhooks / admin 三个 Skill + AGENTS §6 + GS-138（138/138 valid）+ 业务方案 §69 回写 + PRD §9/§10 |

### 决策与偏差

1. **不改状态机语义**：隔离作为**第五态** additive 加入（`received/processing/processed/failed` 语义不变），`processing` 中不可隔离；业务异常仍必须 raise 交 Job 重试 —— 运营面只动“事件壳”。
2. **Stripe 覆写必须 public**：`webhook_event_subscriptions` / `webhook_expected_actions` 落在 `gateway.rb` 的 private 区段之后（D10 方法之前），首版误判为 private → runner 报 `private method` → 已显式 `public` 并加注释。
3. **入站 ≠ 出站**：入站事件（provider→本站）与出站投递（本站→商户）是两条链，本批只在入站侧新建页面，出站页（endpoints/deliveries/redeliver）零改动（已写入 events-webhooks Skill 对照表）。
4. **共享 `now` 的规格坑（已修）**：健康聚合 spec 中 `let(:now)` 被前一行 `delivered_at: now - …` 提前求值 → 后续记录 `created_at > now` 被窗口排除 → 断言 total 偏差；改用 `Time.current` 即时取值。
5. **`ResultError` 无 `message`**：`flash_action_result` 首版用 `result.error&.message` → NoMethodError；改为 `respond_to?(:message) ? message : to_s`。
6. **测试夹具坑**：`create(:payment_session, …)` 缺 STI `type` 列（工厂仅 `:bogus_payment_session` 设置）→ 改用 `:bogus_payment_session` 夹具。
7. **未覆盖（后续小批）**：告警推送（失败率/积压阈值）、清单/事件流导出 CSV、按支付商的「已隔离事件」聚合视图。
