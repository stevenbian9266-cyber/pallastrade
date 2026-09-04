# REQ-20260902-payment-p0

> 关联 PRD：PRD-20260902-payments-payment-p0-foundation-hardening-paymentsession-payment-正式关联-
> 权威任务书：`豆包梳理业务需求/P0任务.md`；现状事实：`豆包梳理业务需求/支付现状分析.md`

## Step 0：跨层搜索（已执行，详见 PRD §6）

结论：支付核心在 core/stripe gems；webhook 入口在 api gem；Express 走 cart 域 legacy（`carts.paymentSessions` + `storefront/src/lib/data/express-checkout-flow.ts` + `components/checkout/ExpressCheckoutButton.tsx` + `lib/utils/express-checkout.ts`）；金额权威已基本在后端，Express 前端 `toCents/buildLineItems` 是唯一重算点。Host App `backend/app/` 无支付代码。无并行支付域需防重复。P0 前已做 6 层跨层只读搜索（见支付现状分析.md 附 §11）。

## Step 1：Skill 咨询

| Skill 文件 | 状态 | 关键结论引用 |
| --- | --- | --- |
| `pallastrade-payments/SKILL.md` | ✅ 已读 | Payment 状态机 checkout→completed/failed/void/invalid；PaymentSession 状态机 pending→completed/failed/canceled/expired；Payment↔Session 靠 response_code/external_id 1:1（无正式 FK）；Stripe PaymentIntent 模式（5.6）external_id=pi_，Checkout Session 模式 external_id=cs_；Gateway preferences 明文 text 列（未加密）；PaymentCombination 设计约束「一个 session 只对应一个 payment」 |
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：Settings→Config→Events→DI→Admin/Ransack→Generators→Decorators→Extensions；行为变化优先 Events，结构性模型变更才用 Decorator；P0 属对既有 gem 模型加字段/关联/服务（框架内直接改，`PALLAS-CUSTOM:` 注释） |

## 任务类型

功能优化 / 安全加固（Payment Foundation Hardening，非重写）

## 需求描述

见 PRD §1-§3（P0-0..P0-7 八工作包：回归安全网、Session↔Payment 正式关联、Webhook Event Store+Dedup+Retry+Replay、Express 幂等加固、Express 金额服务端权威化、Secret 安全迁移、Contract/Error/Trace/Audit/Docs、Legacy Guardrail）。

## 影响范围

core gems（Payment/PaymentSession 模型 + 服务 + migration）、stripe gem（webhook/store/payment 创建）、api gem（webhook controller/serializer）、storefront（Express）、docs、`ai/skills/pallastrade-payments/SKILL.md`。

## 技术方案（初步）

按 P0 任务书工作包顺序逐个实施，每包：inspect→CURRENT_STATE→CHANGE_PLAN→FILE_CHANGE_LIST→DB_MIGRATION_PLAN→先补测试→实施→运行测试→RESULT→REMAINING_RISK。禁止越界（PaymentAttempt/Router/Adyen/金额模型迁移/状态机重写/Big Bang）。

## 风险点

- cs_ 模式 has_one 断裂是数据层核心风险（P0-1 先于 P0-2 处理）
- Webhook 可靠性改造（P0-2）须保留 HandleWebhook/Carts::Complete 业务幂等，只加"可靠性外壳"
- Secret 加密（P0-5）须先 Spike 再渐进迁移，禁止 destructive
- Express 双域并存（cart legacy），P0-3/4 只加固不重写 Standard

## 决策节点

⏸️ PRD/REQ 已按《P0任务.md》浓缩。请确认此范围理解正确（尤其 Scope Lock 与工作包顺序），确认后进入 P0-0 实施。
