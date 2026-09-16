# REQ-20260916-d14b-dispute-deadlines

> 需求：D14 切片2 争议期限提醒与超期处理（T-3/T-1 分档幂等告警 + 超期策略化自动 lost）
> 业务方案 §78-D14 / §71.2；PRD：`docs/prd/payments/PRD-20260916-payments-d14b-dispute-deadlines.md`
> 任务：见 gate 记录（critical —— 含「自动置 lost」的资金语义动作）

## 6 层跨层搜索结果（gate 强制）

| 层 | 路径 | 关键词 | 结论 |
|---|---|---|---|
| App | `backend/app/` | `dispute` / `deadline` | 无命中（不满足） |
| Core | `pallastrade_core/app/` | `deadline` / `evidence_due_at` | `Disputes::ScanDeadlines`（只读、单档 72h）、`Disputes::DeadlineSweeperJob`（只发事件）、`Disputes::DeadlineAlertSubscriber`（due_soon 审计 / overdue 打标记）、`Dispute`（状态机 + `evidence_due_at` + `attention_reason`）——**有底座，缺分档幂等与超期处置** |
| API | `pallastrade_api/app/` | `dispute` | 无期限端点（无需变更） |
| Admin | `pallastrade_admin/app/` | `dispute` | `disputes_ops_controller` + `views/…/disputes_ops/{index,show}`（需加分档看板/列/历史） |
| Storefront | `storefront/src/` | — | 不涉及（无需变更） |
| Platform | `platform/packages/` | `dispute` | 无命中（无需变更） |

## Skill Consultation Evidence Table（gate 强制，真实结论）

| Skill | 结论 |
|---|---|
| `pallastrade-payments` | DSP-P7-5 的**只读扫描 + 只发事件**是明确铁律（「零业务动作：不改任何 dispute/payment/order 状态」）；本切片**有意**把「超期处置」写进新服务 `AlertDeadlines` 并**默认关闭**，属对既有铁律的**受控扩展**（PRD §4 兼容说明必须记录）；`attention_reason` 升级语义（不覆盖既有非空值）沿用 DSP-P7-10 B2 |
| `pallastrade-admin` | `disputes_ops` 是 `ResourceController` 范式（`for_store` 作用域 + ransack 白名单 + 只读展示 + 危险操作走 confirm/permission/audit）；新增看板数据须在控制器内一次聚合，禁止逐行 N+1；导航一致性 spec 本次**不新增子项**（沿用既有 `disputes_ops`） |
| `pallastrade-data-model` | 新表必须带 `store_id` + 唯一键（`(dispute_id, tier)`）+ 查询索引（`(store_id, alerted_at)`）；jsonb 存快照；迁移只建表不回填；模型带 `filter_by` 口径便于页面/计数共用 |
| `pallastrade-security` | 「自动置 lost」是资金语义动作 ⇒ 策略门控（默认关闭）+ 单轮上限 + 仅处理「未提交证据」+ 审计 actor=system + 可追溯；策略改动写审计 |
| `pallastrade-testing` | 验证器登记 + 幂等/跳档/超期分支/策略开关/零资金副作用/权限覆盖；用例环境无关（CI 预置数据用 `find_by || create`） |

## 设计要点（实施依据）

1. **唯一写入口**：`Disputes::AlertDeadlines.call(store: nil, now:, limit:)` —— 扫描复用 `ScanDeadlines`（不重写筛选），写台账 + 发事件 + （策略开启时）置 lost；sweeper 只做调度与摘要。
2. **幂等键**：台账 `(dispute_id, tier)` 唯一；服务内 `find_or_create_by` + `RecordNotUnique` 兜底（并发重跑安全）。
3. **分档语义**：`tiers_days = [3, 1]` → 阈值 72h / 24h；`reached_tiers(hours_remaining)` 返回所有已到达档（升序），`overdue` 为特殊档（<0h）；**台账补齐所有到达档**（不遗漏），**仅最新未提醒档发事件**（不噪音），历史档标记 `backfilled`。
4. **超期处置**：策略 `auto_lose_on_overdue`（默认 false）→ 对「超期 + 未提交证据 + 非终态 + 状态 ∈ opened/needs_response/under_review」执行 `transition_to!('lost')` + `attention_reason = 'evidence_overdue'`（不覆盖非空）+ 审计；单轮上限 `auto_lose_limit`（默认 100）。
5. **零资金副作用**：不写 funds 时间戳（因此不触发 DSP-P7-3 资金入账事件）、不改 Payment/Refund/Journal/Order/库存、零 provider 调用。
6. **兼容收窄（记录在案）**：既有 `dispute.evidence_due_soon` / `dispute.evidence_overdue` 事件名与 payload 不变，但**发布时机**由「每轮都发」收窄为「有新档位时」；订阅者既有语义不变。
7. **后台**：`disputes_ops` index 顶部看板（t3/t1/overdue 计数，一次聚合）+ 列表「期限」列 + 详情提醒历史；筛选参数 `deadline=t3|t1|overdue`。

## 切片拆分

- 切片 2（本批）：分档策略 + 台账 + 提醒服务 + sweeper/订阅者接入 + 后台看板/列/历史。
- 后续：§71.3 拒付率看板与卡组织阈值预警；提醒外发渠道（邮件/IM）；`expired` 语义细化。

## 实施记录（收口时补全）

- **改动清单（2026-09-16 收口）**：
  - 迁移 `backend/db/migrate/20260916200000_create_pallastrade_dispute_deadline_alerts.rb`（新表 + 唯一键 + 店铺索引；**只建表不回填**）。
  - Core：`models/pallastrade/dispute_deadline_alert.rb`（新）、`services/pallastrade/disputes/deadline_policy.rb`（新）、
    `services/pallastrade/disputes/alert_deadlines.rb`（新）、`jobs/pallastrade/disputes/deadline_sweeper_job.rb`（接入 + 摘要扩展）、
    `subscribers/pallastrade/disputes/deadline_alert_subscriber.rb`（分档分支）、`models/pallastrade/dispute.rb`（关联）。
  - Admin：`disputes_ops_controller.rb`（看板/筛选/徽章 + **覆盖 `search_collection`**）、`views/…/disputes_ops/{index,show}.html.erb`、
    `tables/columns/_dispute_deadline.html.erb`（新）、`pallastrade_admin_tables.rb`（`:deadline_tier`，position 27）、
    `config/locales/en.yml` + 宿主 `backend/config/locales/admin_dispute_deadlines.zh-CN.yml`。
  - 验证器：`harness.config.mjs` 注册 `d14b-dispute-deadlines-rspec`（5 份新 spec + 3 份 DSP-P7-5 回归 spec）、`AGENTS.md` §6 行、场景库 GS-149。
  - API / Storefront / Platform：**零改动**。
- **验证器用例数**：`d14b-dispute-deadlines-rspec` = **41 examples, 0 failures**（证据 `EVD-20260916060158-ba2f00c517`）。
- **决策与偏差**：
  1. 策略键定为 `Store#private_metadata['dispute_deadline_policy']`（**不是** `dispute_policy`，避免与其它域冲突）。
  2. 全局 sweeper 采用**逐店策略**（扫描窗口取 `max(策略最宽档, 7*24h)`），而非把店铺策略错误地套到全库。
  3. 台账补齐全档位、但**只对最新档发事件** —— 「不遗漏」与「不噪音」分开取舍（PRD §4 兼容说明已记录）。
  4. 既有 job spec 的严格 `expect(...).to receive(:publish).with(...)` 与新增事件冲突 → 改为「先放行其它事件名，再保留原桶断言」，
     **不改既有契约断言本身**。
  5. 实测发现两个静默坑并已写入 Skill：`safe_value` 只适用 outcome（数组 → 被吞 → 空列表）；action 内改 `params[:q]` 对筛选无效
     （基类 `load_resource` 先取 `collection`）。
