# REQ-20260920-payment-core-p3a（P3-A 方式级路由决策核心）

> 任务：`TASK-…`（见 gate）｜Gate：`GATE-2026-09-20T11-…`（feature）
> 关联 PRD：`docs/prd/checkout/PRD-20260920-checkout-支付核心统一-…md`（P3 切片）
> 前置：P0-A/P0-B（厂商层）已交付 `e31647aa` / `e1c9de0a`

## Step 0：跨层搜索（6 层）

关键词：`routing` / `decide` / `priority` / `method_key` / `option_id`

| 层 | 路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 无支付路由实现 | ❌ |
| Core | `pallastrade_core/app/` | `payments/availability/{rule_set,evaluator,resolver}`（D8 求值**权威**：范围/熔断/认证/能力）、`providers/{config,state,validate,account}`（P0）、`circuit_breaker`（D11）、`three_d_secure`（D15c） | ⚠️ **有硬门、无路由**（没有任何「同一方式多家厂商选谁」的能力）→ 需新建 |
| API | `pallastrade_api/app/` | 本切片不动 API（无端点/序列化变更） | ❌ 不涉及 |
| Admin | `pallastrade_admin/app/` | 后台已有厂商配置与诊断卡（P0-A/B）；策略写入面属 P3-B | ⚠️ 本切片不加页面 |
| Storefront | `storefront/src/` | 前台只消费「跨厂商聚合后的方式列表」；路由为服务端归属决策 | ❌ 本切片不改前台 |
| Platform | `platform/packages/` | 无契约变化 | ❌ |

**结论**：新建 `payments/routing/{policy,decide}.rb`；硬门**全部复用** `Availability::Resolver`（与前台同一求值点，避免第二套过滤逻辑）。策略存 `store.private_metadata['payment_routing']`（零迁移）。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ | 直接改 gem + `# PALLAS-CUSTOM:`；配置落 metadata（与 D8/D11/P0 同范式） |
| `pallastrade-payments` | ✅ | 前台入口集合唯一权威 = `Availability::Resolver`；厂商三态 = `Providers::State`（P0）；路由不得复制其判定 |
| `harness-prd` | ✅ | P3 为既有 PRD 的切片，PRD 已在册（implementing）→ 不需新 PRD |
| `pallastrade-api-v3` / `pallastrade-storefront` | ⏭️ 不涉及 | 零契约/零前台改动（P3-B 才动） |

## 需求

给定「订单 + 支付方式」，选出**唯一的承运厂商**，并给出可解释、可复现的决策对象：

1. **硬门**（任一不过即出局，且记录 reason）：方式未配置 / 厂商非 enabled（disabled·suspended）/ 账户未开通 / `Resolver` 判定该单不可用（D8 范围 · D11 熔断 · D15c 认证 · 能力目录）。
2. **排序**：策略优先序（**市场覆写 > 全局**，来自 `store.private_metadata['payment_routing']`）→ 入口 `position` → `provider.prefixed_id`（确定性兜底）。
3. **决策对象**：`status` / `chosen` / `candidates[rank,basis]` / `rejected[reason]` / `mode` / `applied` / `inputs` 快照 / `policy_version`。
4. **模式诚实性**：仅支持 `off` / `shadow` / `priority_only`；未实现模式（`priority_cost*`）归一为 `off` 并标 `unsupported_mode`（**不猜成本**）。`off`/`shadow` 下 `applied = false`（零行为变化）。
5. **铁律**：纯读、零写入、零网络、零资金副作用；候选为空 → `no_candidate`（不回落默认厂商）；同输入同策略 → 同结果。

**不做（P3-B/后续）**：策略写入后台页面与 Preview、决策落库留痕（PaymentSession 字段）、成本/健康维度排序、跨厂商 fallback 切换。

## AC

| AC | 判定 | 验证 |
|---|---|---|
| AC-1 | 四类硬门各自产生对应 reason（method_not_configured / provider_disabled / provider_suspended / account_not_opened / not_available_for_order） | 服务 spec |
| AC-2 | 优先序覆写改变 winner 且 `basis = priority_override`；市场覆写优先于全局；否则 `basis = position` | 服务 spec |
| AC-3 | 同输入两次结果逐字段一致（含 candidates 顺序） | 服务 spec |
| AC-4 | `off`/`shadow` → `applied` false；`priority_only` → true；未实现模式 → `mode = off` 且 `unsupported_mode` true | 服务 spec |
| AC-5 | 零资金副作用（Payment / PaymentSession 计数不变） | 服务 spec |

## 测试计划

`harness verify payment-routing-rspec`（新注册，11 例）

## 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-20 | 1.0 | 初稿：路由决策核心（硬门复用 Resolver + 优先序排序 + 决策对象 + 模式诚实性） | AI |
