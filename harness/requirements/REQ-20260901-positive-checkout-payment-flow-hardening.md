# REQ-20260901 — 正向下单与支付闭环架构强化

> Task：`TASK-20260901021947-06703155`  
> Gate：`GATE-2026-09-01T02-20-03`  
> 关联 PRD：`PRD-20260830-checkout-下单链路规范化统一化-场景a-b统一下单页-场景c收银台弹窗-参考阿里国际站`（确认后回写，不新建重复 PRD）  
> 外部基准：`C:\Users\17701\Downloads\电商四大下单支付场景业务流程落地规范文档（AI落地版）.md`

## Step 0：跨层搜索

关键词：`Cart/Carts::Submit/converted`、`Order/order.submitted/account orders`、`PaymentSession/PaymentIntent/payment result/retry/idempotency`、`Buy Now/CartDrawer/OrderCombinedPay`。

| 层 | 搜索路径 | 找到的关键实现 | 现状结论 |
|---|---|---|---|
| App | `backend/app/` | 仅生成的 PaymentSession / PaymentCombination TS 类型 | 无下单业务定制，不应在 Host App 复制核心能力 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | `Cart`、`CartItem`、`Carts::Submit`、`Carts::Complete`、`PaymentSession`、`PaymentCombination` | Cart/Order 已分表；提交服务会建正式订单并转换 Cart，但重复提交只报失败，`order.submitted` 仍在锁事务内发布；缺少“返回既有订单”的持久幂等语义 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | `CartsController#submit`、订单域 `PaymentSessionsController`、`Idempotent`、`Customer::OrdersController` | API 有缓存型 `Idempotency-Key` 与订单锁，但待支付订单被 `.complete` 排除；支付会话创建每次直接调用网关，未复用同订单活动会话 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | 订单地址/支付展示 | 不承担前台正向链路，本次保持不变 |
| Storefront | `storefront/src/` | `UnifiedCheckout`、`CardPaymentForm`、`OrderPaymentContent`、`PaymentCheckoutModal`、`order-placed` | 四入口基本存在；但 A/B/C 实际要点两次 Pay Now；结果页只显示成功；失败回 checkout；提交后的 RSC refresh 以跳转支付页规避，未形成一次支付闭环 |
| Platform | `platform/packages/` | SDK `carts.submit`、`orders.paymentSessions`、请求重试自动幂等头 | 端点已覆盖基础能力；若新增 checkout-start 复合响应，需要同步 SDK/OpenAPI，否则只补测试与文档 |

### 搜索结论

现有能力可复用约 80%，不需要重写网关、拆单、组合记账或退款。核心缺口集中在：

1. Cart→Order 与 PaymentSession 两段没有形成可恢复的业务幂等闭环。
2. Next.js Server Action 的 RSC refresh 使统一页无法可靠地“一次 Pay”完成客户端 PaymentIntent 确认，当前退化为跳到 `or_` 页再次点击。
3. 登录用户待支付订单不在个人中心订单数据源中，违背“订单创建后即可见、同步不阻塞支付”。
4. `/order-placed` 是成功页，不是成功/失败/取消共用的支付结果页。
5. 购物车仅结算选中商品时，需确保已下单商品不再出现在活动购物车，未选商品仍保留。

## Step 1：Skill 咨询证据

| Skill | 状态 | 本次采用的关键结论 |
|---|---|---|
| `pallastrade-prd` | 已读 | 相似需求必须回写原 PRD；PRD/REQ 明确确认后才能实施 |
| `pallastrade-customization` | 已读 | 业务计算优先复用服务/依赖注入；副作用才用事件；避免复制核心实现 |
| `pallastrade-checkout` | 已读 | 新 Cart 与正式 Order 已分表；支付完成复用幂等 `Carts::Complete`；Buy Now 使用独立 Cart |
| `pallastrade-payments` | 已读 | PaymentSession 是现代支付边界；Stripe PaymentIntent 使用 `pi_` client secret；Webhook 是最终兜底且完成必须幂等 |
| `pallastrade-security` | 已读 | 所有订单读取/支付必须 `current_store + current_user/token` 作用域；金额服务端计算；卡数据只能进 Stripe Elements |
| `pallastrade-data-model` | 已读 | Cart/Order、Payment/PaymentSession、PaymentCombination 职责不可混淆；API 只用前缀 ID |
| `pallastrade-api-v3` | 已读 | Store API 是不可信客户端边界；订单归属、统一错误结构、幂等头和 SDK 契约必须保留 |
| `pallastrade-storefront` | 已读 | 客户可见流程在 Storefront，金额/订单/支付规则在后端；Card Elements 可在无 client secret 时预渲染；客户端不得接触服务端密钥 |
| `pallastrade-events-webhooks` | 已读 | 订单可见性不能依赖异步事件；事件只做缓存/外部同步副作用；事务内发布事件可能早于提交 |
| `pallastrade-dependencies` | 已读 | 新服务调用既有服务必须走依赖入口，不能绕过可替换实现 |
| `pallastrade-testing` | 已读 | 关键服务与授权写 RSpec 回归，前端交互写 RTL/Vitest，最终以真实 E2E 和日志/DOM 证据验收 |
| `pallastrade-i18n` | 已读 | 新结果态和重试文案必须同步所有 Storefront locale |
| `pallastrade-performance` | 已读 | 支付 webhook/事件优先级高；外部同步不得进入下单主事务；不缓存客户 Cart/Order |

`pallastrade-admin`、`pallastrade-catalog` 已评估为非本次实现层；Admin 仅做六层兼容检查，Catalog 不改变商品/价格规则。

## 需求标题

结合四大电商下单支付场景，强化 PallasTrade 正向下单、支付、重试与结果闭环。

## 任务类型

功能优化 / 关键链路架构改造（critical）。

## 业务场景与统一语义

| 场景 | 入口 | 下单语义 | 支付语义 |
|---|---|---|---|
| A | PDP Add to Cart → CartDrawer Checkout | 进入统一订单确认页，Pay Now 时创建一次订单 | 在同一次用户动作中完成支付，不再要求第二次 Pay |
| B | PDP Buy Now | 创建独立 Cart，进入同一统一确认页 | 同 A |
| C | 购物车页勾选商品 → Checkout | 仅选中商品进入确认；已下单商品离开活动购物车，未选商品保留 | 同 A |
| D | 个人中心选择 1/N 笔订单 → Pay selected | **绝不创建新订单** | 弹窗支付既有订单；多笔复用 PaymentCombination/PaymentSplit |

所有场景成功、失败、取消最终进入统一支付结果页。失败重试只能创建新的支付尝试或复用活动会话，必须复用原订单。

## 推荐目标架构

### 1. 业务真相与编排边界

```text
Cart(active)
  └─ Pay Now / checkout-start（同一业务命令）
       ├─ 事务 A：Carts::Submit（Cart 锁 + 服务端重算 + 创建/返回同一 Order）
       ├─ 提交后：发布 order.submitted（异步副作用，不阻塞）
       └─ 阶段 B：PaymentSessions::Start（Order 锁 + 创建/复用活动会话）
            └─ 返回 Order + PaymentSession + provider client data

Browser Stripe Elements
  └─ confirmCardPayment
       ├─ success → complete session（Webhook 双通道幂等）→ result/success
       ├─ failed  → result/failed → retry original Order
       └─ cancel  → result/canceled → retry/continue shopping
```

- 数据库 Order 是订单真相；个人中心直接按 `current_store + user_id` 查询 `submitted_at/completed_at` 订单，不做“复制订单表”的异步同步。
- `order.submitted` 仅用于邮件、缓存、ERP/Webhook 等异步副作用，必须在订单事务提交后发布。
- 不新增 Order state，遵守 `platform/docs/plans/6.0-cart-order-split.md`。

### 2. 幂等与并发

- `Carts::Submit` 在 `cart.with_lock` 内重新检查状态：
  - active：创建订单、转换 Cart；
  - converted 且已有来源订单：返回该订单（幂等 replay）；
  - 非法/无订单：返回稳定业务错误。
- API 的 `Idempotency-Key` 继续作为请求层快速重放，但业务正确性不依赖 Rails.cache。
- `PaymentSessions::Start` 在订单锁内按 `order + payment_method + mode + active status` 复用会话；失败/取消/过期才新建支付尝试。
- Stripe 创建 PaymentIntent/Checkout Session 使用稳定、操作级 idempotency key，覆盖“网关成功但本地响应丢失”的网络重试窗口。
- 金额、币种、订单归属每次由服务端复核；客户端金额仅展示。

### 3. Storefront 一次 Pay 的技术落点

- Stripe Classic Elements 继续在确认页直接渲染，不提前创建订单或 PaymentIntent。
- 为避免 Server Action 完成后的 RSC refresh 抢占 `cart_` 页面，`checkout-start` 使用同源 BFF Route Handler（服务端持有 SDK 配置，校验 Origin/CSRF），客户端只调用本域命令，不暴露 `pk_`/JWT/cart token。
- BFF 调用后端幂等提交与支付会话启动，返回 `order + session`；客户端立即 `confirmCardPayment`，无第二次 Pay。
- 若 BFF/网关在订单已创建后失败，响应必须带可恢复的 `order_id`；页面转统一结果页，不能回空购物车。
- `order-placed` 保留兼容入口并重定向/复用统一 `payment-result` 展示。

### 4. 购物车选中商品

- 原 Cart 作为本次 checkout 快照，提交后转 converted，确保同一确认上下文只生成一个订单。
- 若存在未选商品，提交服务创建/返回一个 successor active Cart 并仅迁移未选商品；Storefront 更新 cart cookie。这样“已下单商品移除、未选商品保留”与一 Cart 一订单幂等同时成立。
- Buy Now Cart 无未选商品，不产生 successor Cart，也不污染普通购物车。

### 5. 统一结果页

- 新入口：`/payment-result/[targetId]`，支持 `or_` 与 `pcom_`。
- 展示状态以服务端 Order/PaymentSession/PaymentCombination 为准，URL query 仅作提示，不能决定成功态。
- 成功：订单号/金额/支付方式 + Continue Shopping → products。
- 失败：失败原因（安全映射）+ Retry Payment；Retry 复用原订单。
- 取消/待处理：明确状态 + Retry/Continue；异步支付可短轮询后再给出 pending。
- D 场景弹窗支付成功/失败/取消也进入该结果页；组合支付失败时成员订单不重建。

## 影响范围

`npx harness affected --base origin/main` 当前报告 478 个历史变更文件、5 个组件、约 1434 个测试；该数字包含 dev 分支既有提交，不代表本任务增量。本任务增量预计：

- Core：Cart 提交幂等、支付会话 start/reuse 编排、事件发布时机。
- API：提交/支付会话契约、customer orders 可见范围，必要时 checkout-start 响应。
- Stripe：稳定 provider idempotency key。
- Storefront：BFF checkout-start、UnifiedCheckout 一次 Pay、统一结果页、D 弹窗结果跳转、successor cart cookie。
- SDK/OpenAPI：仅在公共 Store API 响应变化时生成同步。
- Docs/Skills/Scenarios：按知识同步矩阵更新。

## 验收标准（确认后回写原 PRD 的 AC-001～AC-010）

| AC | 验收结果 |
|---|---|
| AC-001 | A/B/C 三入口均进入同一个确认页，地址/商品/物流/支付方式/订单摘要齐全，Stripe 表单直接可见 |
| AC-002 | A/B/C 用户只点击一次 Pay Now；订单只创建一次，并完成支付或进入明确结果态，不再跳 `or_` 页要求二次 Pay |
| AC-003 | C 仅结算选中商品；已下单商品从活动购物车移除，未选商品保留；服务端金额与快照一致 |
| AC-004 | D 单笔/多笔均使用收银台弹窗，弹窗不含地址/物流且从不调用 Cart submit/创建 Order |
| AC-005 | D 单笔支付复用原订单；成功后订单 paid，失败/取消仍是同一订单 |
| AC-006 | D 多笔使用一个 PaymentCombination + Payment + PaymentSplit 分摊，成员订单不重建，完成/补偿幂等 |
| AC-007 | 相同/并发 Cart submit 返回同一 Order；相同订单活动 PaymentSession 被复用；网关网络重试不重复创建支付意图 |
| AC-008 | 登录用户创建订单后即可在个人中心看到；列表、详情、支付均按 current_store + user/token 服务端隔离 |
| AC-009 | 成功/失败/取消进入统一结果页；失败 Retry Payment 复用原订单；Continue Shopping 指向 products |
| AC-010 | 前端 complete、Webhook、网络重试任意顺序均不重复扣款、不重复创建订单、不回退状态 |

## 测试与证据计划

- Ruby service/request specs：Cart 重复/并发提交、事件提交后发布、活动 PaymentSession 复用、ownership、待支付订单列表、Stripe provider idempotency。
- SDK/Vitest：复合响应（若公共 API 变化）、幂等头与错误恢复。
- Storefront RTL/Vitest：A/B/C 一次 Pay、D 不调用 submit、successor cart、统一结果三态与 Retry 原订单。
- Storefront Playwright：四入口真实支付沙箱；至少覆盖成功、卡拒付、取消、双击/重试、Webhook 与前端双完成。
- 客观证据：Rails 200/201/302 日志、DB 查询证明同 Cart 仅一 Order/同活动支付尝试复用、成功/失败/取消 DOM 快照或截图。
- critical recovery：实施前记录 feature flag/回滚提交、旧 `/checkout/or_` 与 `/order-placed` 兼容路径；完成前验证恢复方案。

## 风险点

1. 支付网关外部调用不能与数据库事务做原子提交，必须使用 Saga + 持久幂等/可恢复返回，而不是扩大数据库事务。
2. Server Action/RSC refresh 竞态已有生产故障历史；一次 Pay 方案必须通过 BFF 或等价的无 RSC 刷新边界验证。
3. successor Cart 涉及 cookie 与登录用户 current-cart 发现，需同时验证游客/登录用户。
4. 组合支付“资金成功、订单完成部分失败”继续遵循资金优先 + 补偿队列，不改成全局回滚。
5. 不能用 email 兜底匹配订单；不能用前端过滤掩盖越权数据。

## 决策节点

推荐按上述方案继续：**同一确认页一次 Pay + 后端两阶段幂等编排 + 同源 BFF 避免 RSC 竞态 + 统一结果页 + 待支付订单直接可见 + successor Cart 保留未选商品**。

> ⏸️ 请明确回复“确认”或“实施”后，AI 才会回写原 PRD、生成本 Task 的 visual/ui/interaction/tech-design 与 recovery plan，并提交 Go/No-Go 设计确认；在第二次设计确认前不修改业务代码。

## 阶段③：实施后验证

| 改动类型 | 最低验证 | 状态 |
|---|---|---|
| Ruby/Core/API/Stripe | 定向 RSpec + `harness check --profile quick` + payment sandbox | 待实施 |
| Storefront | Vitest/RTL + typecheck/Biome + `harness e2e storefront` | 待实施 |
| API/SDK（如变化） | `harness generated:check` + SDK tests | 待实施 |
| 全部 | anti-pattern、supervise diff、doc-impact、knowledge/evidence verify | 待实施 |

