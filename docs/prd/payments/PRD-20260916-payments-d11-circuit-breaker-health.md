# PRD-20260916-payments-d11-circuit-breaker-health

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D11 切片1 支付路由熔断与健康 —— 软置灰/自动恢复 + 手动一键置灰/解除 + 健康指标（业务方案 §78-D11 / §67.3–§67.4） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-security`、`pallastrade-testing` |
| 关联 REQ | `harness/requirements/REQ-20260916-d11-circuit-breaker.md` |
| 关联 PRD | `PRD-20260915-payments-d8-…`（适用范围 Resolver，本批接入点）；`PRD-20260915-payments-d9-…`（环境/凭据）；`PRD-20260916-payments-d16-…`（入口读模型） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D11 路由与熔断 —— 主备/权重/降级策略 + 健康页 + 告警 + 一键置灰/恢复（本切片：熔断 + 健康 + 手动置灰/解除）。
- **背景（代码事实）**：
  - **已有**：`Payments::Availability::Resolver`（D8）是「入口可用性」唯一求值点（`available_options` / `provider_available?` / `evaluate` 带 reasons），前台列表与 `PaymentSessions::Start` 共用（§66.5 同源硬约束）；入口形态存 `metadata['options'][i]`（D1）；`environment` 过滤（D9）；`Payments::ErrorCodes`（P0）做错误码归一。
  - **缺口**：grep `SAFE_TO_FAILOVER|failover|circuit|breaker|soft_disabled` **零命中** —— 没有熔断状态、没有健康指标聚合、没有一键置灰/解除入口；provider 抖动时前台照旧展示（用户选了才失败）。
- **目标**：provider/入口抖动时**先自动软置灰**（不影响其他入口），可一键手动置灰/解除，并给出可读的健康面（成功率/失败数/错误码 Top5/熔断到期）。
- **成功指标**：① 窗口内样本 ≥ N 且失败率 ≥ X% 时该 option 自动从**前台列表**消失且 `Start` 拒绝（同一 Resolver）；② 手动置灰/解除**写审计**（actor + 原因 + 到期）；③ 健康指标在空库/有数据下都正确且页面恒 200。

## 2. 用户故事 / 场景

- 作为**支付运营**，provider 连续失败时我希望系统自动把该入口降级，避免更多用户踩坑。
- 作为**支付运营**，我需要手动一键置灰（原因 + 时长）与解除，并留下审计。
- 作为**集成工程师**，我需要看到 provider/入口的成功率、失败数与错误码 Top5 以定位问题。
- 场景：① 自动熔断（样本/阈值命中）→ 前台消失、Start 拒绝、审计；② 到期自动恢复（v1：到期即恢复）；③ 手动置灰（未到期不允许自动恢复）→ 手动解除；④ 空窗口不误判（样本不足不动）。

## 3. 功能需求（FR）

- **FR-001**：**熔断状态存储（入口级）** —— 写 `metadata['options'][i]['breaker']`（未选项化 provider 写 `metadata['breaker']`），字段：`opened_at` / `until` / `reason` / `manual` / `failure_rate` / `sample_size`；模型 API：`breaker_state(kind)`、`soft_disabled?(kind)`、`soft_disable!(kind:, until:, reason:, manual:)`、`soft_enable!(kind:)`。
- **FR-002**：**健康指标聚合**（只读，零 provider 调用）—— `Payments::Health::Metrics.call(payment_method:, window:)` → 会话数、失败数、失败率、平均耗时（近似：终态会话 `updated_at - created_at`）、错误码 Top5（来源：窗口内 `PaymentWebhookEvent#last_error_class` / `action=failed`）。
- **FR-003**：**熔断判定与恢复** —— `Payments::CircuitBreaker::Evaluate.call(payment_method:, now:)`：对每个生效入口，当窗口内样本 ≥ `min_samples`（默认 10）且失败率 ≥ `failure_rate_threshold`（默认 0.5）→ 自动软置灰 `cooldown`（默认 15 分钟），写 `AuditLog(action: 'payment_option_auto_soft_disabled')`；对**已到期且非手动**的熔断状态 → 自动解除并写审计。阈值可经 `metadata['breaker_thresholds']` 覆盖。
- **FR-004**：**巡检作业** —— `Payments::CircuitBreaker::SweepJob`（小时级）对全部 active provider 执行 FR-003。
- **FR-005**：**同源门禁** —— `Availability::Resolver#option_allowed?` 增加熔断判定（软置灰入口不可用），`evaluate` 的 reasons 增加 `breaker_open`；前台列表与 `PaymentSessions::Start` 自动继承（复用既有 `payment_option_not_available` 错误码，零前端改动）。
- **FR-006**：**后台一键置灰/解除** —— `PaymentMethodsController` 新增 `soft_disable` / `soft_enable` 成员动作（权限 `:update` + 原因必填 + 时长可选 + 审计 actor）；「支付方式」编辑页新增「熔断与健康」卡（指标 + 状态 + 到期 + 表单）。
- **FR-007**：**只读降级** —— 健康/熔断卡片异常时降级为 nil（页面恒 200，沿 D9/D12 口径）。

## 4. 非功能需求（NFR）

- **安全**：熔断状态变更必须写 `Audit`（自动 = `system` / 手动 = 后台用户）；不得因熔断产生任何资金副作用（纯读 + metadata 写）。
- **性能**：指标聚合为单次分组查询（不加载 payload）；门禁为内存判断（选项已加载）。
- **兼容**：无迁移（复用 metadata）；Resolver 语义 additive（无 breaker 状态 = 行为不变，零回归）。
- **范围纪律（本切片不做）**：四类路由中的**主备链/权重/成本路由**（§67.1）与告警渠道推送（§67.4 第三行）留待 v2；本切片只交付与验收锚点「provider 抖动时不掉单；熔断自动生效并可手动解除」直接对应的部分。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：`soft_disable!` / `soft_enable!` / `soft_disabled?` / `breaker_state` 在选项化与未选项化两种形态下都正确（含到期判定）。
- **AC-002** ← FR-002：`Metrics.call` 在空库返回零值；有数据时计数/失败率/错误码 Top5 正确且有界（≤5）。
- **AC-003** ← FR-003：样本不足**不**熔断；命中阈值自动置灰并写审计；重复执行幂等（不重复开新窗口）。
- **AC-004** ← FR-003：到期且非手动 → 自动解除 + 审计；**手动置灰到期不自动解除**。
- **AC-005** ← FR-005：软置灰入口从 `Resolver.available_options` 消失、`evaluate` 给 `breaker_open`，`Provider_available?` 在唯一入口被熔断时为 false（即 `Start` 拒绝路径成立）。
- **AC-006** ← FR-006：后台 `soft_disable` 需要原因（缺原因不改变状态）；成功写审计（actor = 当前用户）；`soft_enable` 解除；无权限被拒。
- **AC-007** ← FR-007：健康/熔断卡在服务异常时降级、编辑页仍 200。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `breaker` / `soft_disabled` | 无命中 | ❌ 未满足 |
| Core | `pallastrade_core/app/` | 同上 | `payments/availability/resolver.rb`（唯一求值点）、`payment_method.rb`（option 读模型 + metadata）、`payment_methods/credentials.rb`（D9 模式参考） | ⚠️ 部分（求值点已有，熔断/指标缺） |
| API | `pallastrade_api/app/` | `payment_option` | checkout / payment_method 序列化器（D16 已补展示元数据） | ✅ 无需变更（门禁走既有错误码） |
| Admin | `pallastrade_admin/app/` | `payment_methods` | `payment_methods_controller`（D1/D8/D9 动作与卡片）+ `payments_helper` | ⚠️ 部分（需新增两动作 + 卡片） |
| Storefront | `storefront/src/` | — | 前台只消费 `available_payment_methods`（软置灰即消失）→ **零改动** | ✅ 无需变更 |
| Platform | `platform/packages/` | — | 无契约变更（复用既有错误码） | ✅ 无需变更 |

**结论**：承载点 = Core（熔断存储/指标/判定 + Resolver 接入）+ Admin（两动作 + 卡片）；API/Storefront/Platform 零改动；复用 D8 Resolver 与 §66.5 同源约束，不新建求值路径。

## 7. 技术影响

- **Core**：`payment_method.rb`（breaker API）；新增 `payments/health/metrics.rb`、`payments/circuit_breaker/evaluate.rb`、`jobs/pallastrade/payments/circuit_breaker/sweep_job.rb`；`payments/availability/resolver.rb`（门禁 + reasons）。
- **Admin**：`payment_methods_controller`（`soft_disable` / `soft_enable`）+ 路由 + 视图卡片 + 帮助方法（指标格式化）+ i18n（gem en + 宿主 zh-CN）。
- **数据库**：无迁移（metadata）。
- **测试**：模型、指标、判定、Resolver 回归（D8 spec 复用）、Admin 请求。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 模型 | `backend/spec/models/pallastrade/d11_soft_disable_spec.rb` | AC-001 |
| 服务 | `backend/spec/services/pallastrade/payments/d11_health_metrics_spec.rb` | AC-002 |
| 服务 | `backend/spec/services/pallastrade/payments/d11_circuit_breaker_spec.rb` | AC-003/004 |
| 回归 | `backend/spec/services/pallastrade/payments/availability/resolver_spec.rb`（+ 新增熔断用例） | AC-005 |
| 请求 | `backend/spec/requests/pallastrade/admin/d11_payment_method_soft_disable_spec.rb` | AC-006/007 |

## 9. 收口清单

- [x] 本 PRD（approved → done）
- [x] REQ：`harness/requirements/REQ-20260916-d11-circuit-breaker.md`
- [x] gate + prep 清理（critical：恢复计划 `REC-73d696dbbfdee5`）
- [x] 用户确认：用户 2026-09-16「继续」（承接「下一批 D11 路由与熔断」）
- [x] 知识同步：`pallastrade-payments` Skill（新增「熔断与健康」段）+ AGENTS §6 verifier 行 + 场景库 GS-141 + 业务方案 §67 回写

### 9.1 实施记录（2026-09-16，切片1）

| 项 | 内容 |
|---|---|
| Core | `PaymentMethod` breaker 状态机（`BREAKER_KEY`/`BREAKER_DEFAULTS`/`breaker_state`/`soft_disabled?`/`soft_disable!`/`soft_enable!`/`breaker_thresholds`）；`payments/circuit_breaker.rb`（`parse_time`）；`payments/health/metrics.rb`；`payments/circuit_breaker/evaluate.rb`；`jobs/pallastrade/payments/circuit_breaker/sweep_job.rb`；`availability/resolver.rb` 门禁 + `breaker_open` reason |
| 调度 | `config/sidekiq_schedule.rb` 注册 `payment_circuit_breaker_sweep`（`15 * * * *`） |
| Admin | `payment_methods_controller#soft_disable/#soft_enable`（原因必填 + 审计）+ 路由 + `_breaker.html.erb` 卡（24h 指标 + 逐入口状态/动作）+ `payments_helper`（`breaker_health_metrics`/`breaker_health_rows` + 格式化）+ i18n（gem en / 宿主 zh-CN） |
| 验证 | 新增验证器 `d11-circuit-breaker-rspec`（7 文件 / 40 例全绿，含 D8 resolver 回归） |
| 决策 1 | **指标口径 = provider 级**：会话不持久化入口（`Start#option_kind` 仅建会话前校验），入口级失败率无数据源 → 自动判定按 provider 级窗口聚合，对全部生效入口落状态；入口级粒度体现在状态与手工动作。 |
| 决策 2 | **手动置灰 = 粘性**（`manual: true` + `until = nil`，人工解除为准）；自动置灰到期由 `Evaluate` 清除状态行（不依赖后台） |
| 决策 3 | `SweepJob#perform(now:)` 接受 **Time**（字符串只到秒，会漏掉同秒内新建样本） |
| 延后 | v2：主备链/权重/成本路由（§67.1）+ 告警渠道推送（§67.4） |

### 9.2 知识同步门评估（`harness sync-check`）

| 触发项 | 结论 |
|---|---|
| API 端点变更（`pallastrade_admin/config/routes.rb`） | **已评估，无需更新契约**：新增的是 **HTML 后台 member 路由**（`soft_disable` / `soft_enable`），非 `/api/v3/admin/*` 契约面；D11 不新增/修改任何 API v3 端点，`harness generated:check` ✅ 无漂移（store/admin.yaml / SDK 类型 / 序列化器类型均未变）。 |
| Skill / PRD 机制（`pallastrade-{admin,payments}/SKILL.md`、`docs/prd/README.md`） | **已完成**：`pallastrade-payments` 新增「熔断与健康」段（状态机/指标口径/判定/巡检/门禁/后台/回归）；`pallastrade-admin` 新增「支付熔断与健康」段（卡片 + 两动作 + 粘性语义 + 历史坑）；`docs/prd/README.md` 索引由 `prd-status-sync --fix` 登记本 PRD。 |
| `AGENTS.md` §6 | **已完成**：新增 d11 verifier 行（≤3 min）。 |
| `harness/scenarios/scenarios.json` | **已完成**：GS-141（142/142 校验通过）。 |
| `copilot-instructions.md` / `pallastrade-prd` Skill | **已评估，无需更新**：D11 未变更命令面、任务前缀、PRD 模板/分类/查重规则。 |
| 业务方案 §67 回写 | **已完成**：§67.3 顶部实施注 + 批次表 D11 行实施注（含 v2 延后项）。 |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片1：熔断 + 健康 + 手动置灰/解除；路由四类与告警推送留 v2） |
| 1.0 | 2026-09-16 | **实施完成（切片1）→ done**：break 状态机（入口级）+ `Metrics`（provider 级窗口口径）+ `Evaluate`（自动判定/到期恢复/幂等）+ `SweepJob`（小时级巡检）+ Resolver 同源门禁 + 后台两动作与「熔断与健康」卡；验证器 `d11-circuit-breaker-rspec`（40 例全绿）。**指标粒度定为 provider 级**（会话不持久化入口）；**手动置灰粘性**；`SweepJob` 时间参数改收 Time。 | AI |
