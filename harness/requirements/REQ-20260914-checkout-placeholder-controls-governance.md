# REQ-20260914-checkout-placeholder-controls-governance — 结算页占位控件治理

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-placeholder-controls-governance.md`（done）
> 来源：research §9.3 P1「占位功能治理」；用户「继续」授权
> Task：`TASK-20260914105255-96f96764`；Gate：`GATE-2026-09-14T10-53-16`（feature）
> 产出：结算页不再有「假控件」；Marketing 真正生效；3 项无后端占位用单一开关隐藏（可逆）

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 关键词 | 结果 |
|---|---|---|---|
| App | `backend/app/` | newsletter/marketing/sms | 无实现 |
| Core | `pallastrade_core/app/` | newsletter / addon / sms | `NewsletterSubscriber.subscribe` ✓；**无** AddOn/SMS 模型 |
| API | `pallastrade_api/app/` | newsletter / sms / addon | `store/newsletter_subscribers_controller.rb`（subscribe/verify）✓；`store/customers_controller.rb`（`accepts_email_marketing`）✓；无 sms/addon 端点 |
| Admin | `pallastrade_admin/app/` | marketing/sms/addon | 仅客户营销字段可编辑；无 sms/addon |
| Storefront | `storefront/src/` | placeholder/opt-in | `AddOnsSection.tsx`、`SaveInfoSection.tsx`、`UnifiedCheckout.tsx`（marketing/sms）、`AddressFormFields.tsx`（`showSmsOptIn`） |
| Platform | `platform/packages/` | newsletter | SDK `newsletterSubscribers.subscribe/verify` + 类型 ✓ |

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-storefront`（域） | ✅ 已读 | 结算组件/文案约定；**改动后必须跑 `pnpm test` + `pnpm check` + `pnpm typecheck`**（CI 红线教训）；Money 契约（raw 判逻辑、display 只渲染） |
| `pallastrade-api-v3`（域） | ✅ 已读 | newsletter 端点属 Store API（publishable key）；BFF 服务端调用形态与既有 `/api/checkout/*` 一致 |
| `pallastrade-prd`（流程） | ✅ 已读 | PRD → 用户确认 → gate → REQ → AC↔测试 → 知识同步门 |

## 决策记录（ADR 摘要）

1. **Marketing 接线**（后端已有能力）：提交时 best-effort 订阅；**失败不阻断下单**（与「订单已落库后置副作用」一致）。
2. **SMS / Save Info / Add-ons 隐藏**（后端不存在）：单一开关 `SHOW_PLACEHOLDER_SECTIONS=false`；组件与文案保留 → 回滚成本 = 一个常量。
3. **CheckoutView 扩展不做**（同 §9.3 P1）：3/4 能力已被既有字段覆盖，仅剩形式统一，收益不抵改动面（结论记入 research）。
4. **范围外**：Add-ons 定价管线、SMS 通道、结算页 Save-Info 持久化 → 各自另立 PRD。

## 实施结果

| 项 | 结果 |
|---|---|
| FR-001 Marketing 接线（BFF + best-effort） | ⏳ |
| FR-002 占位开关（3 处隐藏，可逆） | ⏳ |
| FR-003 i18n 保留 | ⏳ |
| FR-004 知识同步（Skill/GS-116/research） | ⏳ |

## 验证与证据

| 证据 | 结果 |
|---|---|
| AC-001/002/003/004（vitest） | ⏳ |
| `pnpm check` + `pnpm typecheck` | ⏳ |
| dev 实测（提交带 marketing → DB 出现订阅） | ⏳ |
