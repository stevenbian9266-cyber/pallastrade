# REQ-20260916-d11-circuit-breaker

> 任务：`TASK-20260916004503-194cce68` · PRD：`docs/prd/payments/PRD-20260916-payments-d11-circuit-breaker-health.md`
> 需求原文：用户 2026-09-16「继续」（承接 AI 建议「下一批 D11 路由与熔断」）

## Step 0：6 层跨层搜索（实查结论）

| 层 | 关键词 | 结论 |
|---|---|---|
| App `backend/app/` | `breaker` / `soft_disabled` | **无命中** |
| Core | `circuit\|breaker\|failover\|soft_disabled` | **全局零命中**（D11 确实缺失）；可复用点：`Payments::Availability::Resolver`（`available_options` / `provider_available?` / `evaluate` — 入口可用性唯一求值点）、`PaymentMethod`（`effective_payment_options` / `effective_payment_option`（D16 读模型）/ `metadata`）、`Payments::ErrorCodes`（P0 归一） |
| API | `payment_option` | checkout 与 payment_method 序列化器（D16 已补 `option_id`/`method_key`/`display_name`）；门禁复用既有 `payment_option_not_available` → **零契约变更** |
| Admin | `payment_methods` | `payment_methods_controller`（D1 选项化 / D8 范围 / D9 环境与凭据卡）+ `payments_helper`（D9 卡帮助方法）→ 新增两动作 + 「熔断与健康」卡 |
| Storefront | — | 前台只渲染 `available_payment_methods`（软置灰即消失）→ 零改动 |
| Platform | — | SDK 类型无变化 |

**防重复判定**：不新建可用性求值路径（复用 D8 Resolver 并加一道门禁）；不新建错误码（复用 `payment_option_not_available`，避免前端映射改动）；不建表（状态存 metadata）。

## Step 1：Skill 咨询证据表

| Skill | 结论（约束） |
|---|---|
| `pallastrade-payments` | 支付域事实：入口形态在 `metadata['options'][i]`；D8 §66.5 同源硬约束（Start 必须复算）；熔断**不得**产生资金副作用（纯读 + metadata 写） |
| `pallastrade-admin` | 三要素（标题/面包屑/图标）、`button_to`（无 rails-ujs）、动作需权限门控与审计 actor（沿用 payment_methods 既有 `audit_actor`） |
| `pallastrade-security` | 敏感动作审计；metadata 不含凭据（breaker 只存状态/原因/阈值） |
| `pallastrade-testing` | 后端 spec 范式；时间窗口断言需显式控制 `created_at`/`updated_at`（update_columns） |

## Step 2：设计要点

1. **状态存取**：`metadata`（= `private_metadata` API 别名）—— 选项化时 `metadata['options'][i]['breaker']`，否则 `metadata['breaker']`；写入用 `update_columns(private_metadata:)` 避免 provider 校验/远端调用（D9 已验证的范式）。
2. **阈值**：常量默认（`min_samples: 10` / `failure_rate_threshold: 0.5` / `cooldown: 15.minutes`）+ `metadata['breaker_thresholds']` 覆盖。
3. **指标**：窗口内 `PaymentSession`（按 `payment_method_id` + `payment_option_id` 可选）分组计数 + 错误码 Top5（`PaymentWebhookEvent.last_error_class` 分组，`action=failed`）。
4. **判定**：样本 < min → 不动；≥ min 且失败率 ≥ 阈值 → `soft_disable!`（幂等：已开且未到期 → 跳过）；到期且 `manual=false` → `soft_enable!`。
5. **门禁**：`Resolver.option_allowed?` 内加 `break_through?` 检查（选项已有 breaker 状态）；`evaluate` 收集 `breaker_open` reason。
6. **后台**：`soft_disable`（reason 必填 + minutes 可选，写 `payment_option_soft_disabled` 审计）/ `soft_enable`（写 `payment_option_soft_enabled`）；卡片只读降级。

## Step 3：切片

- 切片 1：模型 API + 指标服务（FR-001/002）。
- 切片 2：判定服务 + Job + Resolver 门禁（FR-003/004/005）。
- 切片 3：后台动作 + 卡片 + i18n（FR-006/007）。
- 切片 4：规格 + 知识同步 + 文档回写。

## 实施记录（2026-09-16）

- **改动清单（切片1 一次落地，无迁移）**
  - Core：`pallastrade_core/app/models/pallastrade/payment_method.rb`（`BREAKER_KEY` / `BREAKER_DEFAULTS` /
    `breaker_state` / `soft_disabled?` / `soft_disable!` / `soft_enable!` / `breaker_thresholds` +
    private `write_breaker_state`；`option_display_name(kind = nil)` 扩参以支持逐入口展示）；
    `app/services/pallastrade/payments/circuit_breaker.rb`（`parse_time`）；
    `app/services/pallastrade/payments/health/metrics.rb`；
    `app/services/pallastrade/payments/circuit_breaker/evaluate.rb`；
    `app/jobs/pallastrade/payments/circuit_breaker/sweep_job.rb`；
    `app/services/pallastrade/payments/availability/resolver.rb`（`option_allowed?` 门禁 + `breaker_open` reason）。
  - 调度：`backend/config/sidekiq_schedule.rb`（`payment_circuit_breaker_sweep`，cron `15 * * * *`）。
  - Admin：`payment_methods_controller.rb`（`soft_disable` / `soft_enable`，原因必填 + 审计）、`config/routes.rb`（2 member 路由）、
    `views/.../payment_methods/_breaker.html.erb`、`edit.html.erb`（挂载）、`helpers/.../payments_helper.rb`
    （`breaker_health_metrics` / `breaker_health_rows` / 格式化 helper）、i18n（gem `en.yml` + 宿主 `admin_payment_methods.zh-CN.yml`）。
  - 规格：`backend/spec/models/pallastrade/d11_soft_disable_spec.rb`、`backend/spec/services/pallastrade/payments/d11_health_metrics_spec.rb`、
    `d11_circuit_breaker_spec.rb`、`backend/spec/jobs/pallastrade/payments/d11_circuit_breaker_sweep_job_spec.rb`、
    `backend/spec/services/pallastrade/payments/availability/d11_breaker_gating_spec.rb`、
    `backend/spec/requests/pallastrade/admin/d11_payment_method_soft_disable_spec.rb`（+ D8 `resolver_spec.rb` 回归）。
  - 验证器：`harness.config.mjs` 注册 `d11-circuit-breaker-rspec`（7 文件 / **40 例全绿**，证据 `EVD-20260916011008-f4c576b132`）。
- **决策与偏差**
  1. **指标粒度 = provider 级**（原 FR-002 计划入口级）：`PaymentSession` 不持久化入口（`Start#option_kind` 只做建会话前校验），
     入口级失败率无真实数据源 → 不做「按 external_data 猜入口」的伪口径；改为 provider 级窗口聚合 + 入口级状态/手工动作，
     并在 `Metrics` 顶部标注为唯一口径。
  2. **手动置灰粘性**：`manual: true` 时 `until = nil`，`soft_disabled?` 对手动置灰直接返回 true（人工解除为准）；
     自动置灰到期即失效（状态行由 `Evaluate` 清理）。
  3. **`SweepJob#perform(now:)` 只认 Time/秒级字符串**：`Time.zone.parse(str)` 会截断亚秒 → 同秒内新建的会话样本被漏掉
     （spec 实测命中）；改为 `Time` 直传、字符串走解析并注明精度。
  4. **`option_display_name` 扩参**（D16 读模型）以支持卡面逐入口展示；未传参行为不变（零回归）。
  5. **后台确认弹窗文案**复用交互确认键 `breaker_confirm`（明确「不影响已建会话/支付/订单」）。
- **延后（v2）**：主备链/权重/成本路由（§67.1）与告警渠道推送（§67.4）—— 本切片只交付熔断 + 健康 + 手动置灰/解除。
