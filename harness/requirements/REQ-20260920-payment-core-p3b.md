# REQ-20260920-payment-core-p3b（P3-B 路由策略写入 + 无订单上下文预览）

> Gate：`GATE-2026-09-20T11-4x-xx`（feature）｜ 关联 PRD：`docs/prd/checkout/PRD-20260920-checkout-…md`（P3 切片）
> 前置：P3-A（`9c2b74b2`：`Routing::{Policy,Decide}` 决策核心）

## Step 0：跨层搜索（6 层）

关键词：`routing` / `policy` / `write!` / `preview` / `private_metadata`

| 层 | 路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 无实现 | ❌ |
| Core | `pallastrade_core/app/` | `payments/routing/{policy,decide}`（P3-A：**读 + 决策**，无写入原语、无预览）、`providers/{config,state,account}`（P0：状态与账户闸门） | ⚠️ 需扩展 |
| API | `pallastrade_api/app/` | 零契约变化 | ❌ 不涉及 |
| Admin | `pallastrade_admin/app/` | 后台策略页属 P3-C（本期不做页面） | ⚠️ 延后 |
| Storefront | `storefront/src/` | 前台只消费方式列表 | ❌ |
| Platform | `platform/packages/` | 无契约变化 | ❌ |

**结论**：新增 `Policy.write!`（白名单 + 幂等）与 `Routing::Summary`（无订单上下文预览，复用 `Decide` 的候选装配与排序）。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ | 直接改 gem + `# PALLAS-CUSTOM:`；策略落 `store.private_metadata`（零迁移） |
| `pallastrade-payments` | ✅ | 硬门唯一权威 `Availability::Resolver`；预览**必须显式标注**跳过了订单级闸门（不假装完整决策） |
| `harness-prd` | ✅ | PRD 在册，P3-B 为切片推进 |
| `pallastrade-admin` / `pallastrade-api-v3` | ⏭️ 不涉及 | 本期零页面、零契约变化 |

## 需求

1. **`Policy.write!`**：白名单（`mode ∈ 已实现模式`、`priority` 目标 ∈ 本店 provider、`markets` 键 ∈ 本店市场）→ 非法值进 `rejected` 并忽略；同值重复写入幂等（不写库不审计）；只写 `store.private_metadata['payment_routing']`，零资金副作用。
2. **`Routing::Summary.for_store`**：回答「顾客会看到什么 / 会走哪家」——复用 `Decide` 的候选装配（`option_for` / `account_allows?` / `candidate` / `rank`），**跳过订单级闸门**（D8 范围 / D11 熔断 / D15c 认证）并显式标记 `order_gates: 'skipped'`、`status: 'preview'`；无候选 → 该方式不出现在结果里（不猜）。

**不做**：后台策略页与 Preview 页面（P3-C）、决策落库留痕、成本/健康维度。

## AC

| AC | 判定 | 验证 |
|---|---|---|
| AC-1 | 写入后 `Policy.for_store` 读回一致（mode / priority / updated_by） | 服务 spec |
| AC-2 | 未实现模式、非本店 provider、非本店市场键 → `rejected` 且不落库 | 服务 spec |
| AC-3 | 同值重复写入 `unchanged` = true 且 `updated_at` 不变；零资金副作用 | 服务 spec |
| AC-4 | 预览显式标注 `order_gates: 'skipped'`；按策略优先序选 winner 且 `basis = priority_override` | 服务 spec |
| AC-5 | 停用厂商在预览里以 `provider_disabled` 出现（不静默丢弃）；方式集合来自实际声明（不捏造） | 服务 spec |

## 测试计划

`harness verify payment-routing-rspec`（扩展为 20 例：decide 11 + policy_write 9）
