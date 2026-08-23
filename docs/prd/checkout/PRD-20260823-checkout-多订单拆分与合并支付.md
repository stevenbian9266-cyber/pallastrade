# PRD-20260823-checkout-多订单拆分与合并支付

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-23 |
| 来源 | 我想实现用户的订单时候会因为一些原因比如仓库或者其它原因会拆成多个订单。用户可以对多笔订单合并支付。 |
| 分类 | checkout（自动判定，命中「支付/订单」关键词） |
| 关联 Skill | pallastrade-payments、pallastrade-checkout、pallastrade-api-v3、pallastrade-storefront、pallastrade-admin |
| 关联 REQ | REQ-20260823-xxx.md（实施时回填） |
| 关联 PRD | N/A（查重通过，全新需求） |
| 需求类型 | 新功能 |

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。本次查重通过，无相似 PRD，确属全新需求。

## 1. 背景与目标

- **一句话需求原文**：我想实现用户的订单时候会因为一些原因比如仓库或者其它原因会拆成多个订单。用户可以对多笔订单合并支付。
- **背景**：PallasTrade 当前是「一次结账 = 一笔订单 = 一次支付」。`PaymentSession`（`ps_`）与 `Payment`（`py_`）都 `belongs_to :order`（单笔订单，必填），Stripe Checkout Session 也是逐订单创建（`create_payment_session(order:)`）。当购物车商品分属不同仓库/配送中心需分批发货，或后台需要把一笔大单按行项目拆成多笔时，现有模型无法表达；用户也只能逐笔为订单付款，无法一次合并支付。6 层跨层搜索确认：**当前仓库无任何拆单/合并支付能力**（`order_routing` 的 `minimize_splits` 只是选仓规则，`inventory_unit.split` / 发货 `split` 是行项目/发货拆分，均非订单级拆分）。
- **目标**：
  1. **订单拆分**：结账时按仓库（stock_location）等规则自动把购物车拆成多笔订单；后台可手动按行项目拆分订单。
  2. **合并支付**：用户可把多笔未支付订单组成「支付组（PaymentGroup）」，一次 Stripe 支付完成全部订单；拆分产生的订单自动进入同一支付组。
- **成功指标**：
  - 合并支付组内所有订单在 webhook 到达后 100% 进入 `complete` 状态（幂等 + 可重试）
  - 单笔订单支付路径不受影响（回归零失败）
  - 拆单 + 合并支付全流程在 Stripe sandbox E2E 通过

## 2. 用户故事 / 场景

- 作为顾客，我希望购物车因仓库不同被拆成多笔订单后只需付一次款，以便不用逐笔付款。
- 作为客服/运营，我希望在后台把一笔大单按行项目拆成多笔订单，以便按仓库/渠道分别处理发货。
- 作为顾客，我希望在我的账户里勾选多笔待支付订单合并支付，以便减少支付次数。

场景列表：

- **S1（正常·结账自动拆单）**：购物车含 A 仓商品 + B 仓商品 → 结账拆成订单 A、订单 B → 自动生成支付组 → Stripe 一次支付 → 两笔订单同时 `complete`。
- **S2（正常·账户合并支付）**：用户账户有多笔历史未支付订单 → 勾选 2 笔 → 合并支付页 → Stripe 一次支付 → 两笔都 `complete`。
- **S3（边界·零金额）**：支付组金额为 0（全被 store credit/gift card 覆盖）→ 不创建 Stripe 会话，直接标记完成。
- **S4（异常·订单状态变化）**：支付组中某订单在支付前被取消/已退款 → 应从支付组移除并重算金额；若组为空则取消支付组。
- **S5（异常·webhook 重复）**：Stripe webhook 重复到达 → 幂等处理，不重复完成订单、不重复创建 Payment。
- **S6（边界·部分已付）**：支付组中部分订单已支付 → 仅未支付订单计入支付金额，已付订单保持原状。
- **S7（边界·币种）**：不同币种订单**不能**合并支付（支付组必须同币种同 store 同用户）。
- **S8（异常·支付失败）**：Stripe 支付失败/取消 → 支付组 `failed`/`canceled`，所有订单保持未支付状态，可重试。

## 3. 功能需求（FR）

### 阶段 1：合并支付（核心）
- **FR-001**：新增 `PallasTrade::PaymentGroup` 模型（前缀 `pg_`），`has_many :orders`、`has_many :payment_sessions`；含 `total`、`currency`、`status` 状态机（`pending → processing → completed`，`failed`/`canceled`）；发布生命周期事件。
- **FR-002**：Store API 支持创建支付组（`POST /api/v3/store/payment_groups`，入参多笔订单 id），服务端校验：同 store、同用户、同币种、订单均未完成支付、未过期。
- **FR-003**：Store API 支持为支付组创建 Stripe Checkout Session（`POST /api/v3/store/payment_groups/:id/payment_sessions`），金额 = 组内未支付订单合计，金额在服务端计算。
- **FR-004**：webhook（`payment_intent.succeeded` / `checkout.session.completed`）按支付组完成**所有**订单（幂等，可重试；不破坏现有单订单 webhook 路径）。
- **FR-005**：Storefront 账户「我的订单」页支持勾选多笔待支付订单 → 「合并支付」入口 → 合并支付页（展示全部订单金额合计）。
- **FR-006**：合并支付完成页展示所有订单结果（成功/失败），失败订单可再次合并支付。

### 阶段 2：结账自动拆单
- **FR-007**：结账完成时按仓库（stock_location）自动把购物车拆成多笔订单，各自携带 line items / shipments / totals；原始购物车（父订单）完成，子订单进入待支付。
- **FR-008**：拆分后自动生成支付组并进入合并支付流程（FR-003/004 复用）。
- **FR-009**：拆分规则可配置（默认按仓库；扩展点支持其他规则，如渠道/发货方式）。

### 阶段 3：后台手动拆单
- **FR-010**：Admin API `POST /api/v3/admin/orders/:id/split` 按行项目/数量拆分订单（未支付订单）。
- **FR-011**：Admin UI 订单详情页提供「拆分订单」操作，可指定行项目拆分数量与目标仓库。
- **FR-012**：Admin 可查看支付组详情（成员订单、金额、支付状态），可按支付组过滤订单列表。

## 4. 非功能需求（NFR）

- **安全**：支付金额一律服务端计算（不信任客户端提交）；合并支付仅限本人/同 store 订单；Stripe 密钥走环境变量（`ENV['STRIPE_SECRET_KEY']` / credentials），**绝不写入源码**（AGENTS.md §8）。
- **幂等**：webhook 处理与支付组完成操作幂等可重入；Stripe webhook 是支付真相来源（skill 约定）。
- **兼容**：单笔订单支付路径（`PaymentSession.order` 必填）不受影响；`PaymentSession` 增加可空 `payment_group_id`，向后兼容。
- **性能**：拆单/支付组创建在事务内完成；支付组订单数量上限（默认 50，可配置）。
- **可维护性**：新增能力沉淀进 `pallastrade-payments` / `pallastrade-checkout` Skill；API 文档 + SDK 类型同步。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`PaymentGroup` 模型存在，前缀 `pg_`，`has_many :orders`、`has_many :payment_sessions`，状态机事件可用（RSpec model spec）。
- **AC-002 ← FR-002**：创建支付组 API 成功返回 `pg_` id；不同币种 / 非本人 / 已完成订单被拒并返回 422（request spec）。
- **AC-003 ← FR-003**：为支付组创建 Stripe 会话返回 `ps_` 会话，金额 = 组内未支付订单合计（service + request spec，Stripe 用 sandbox/stub）。
- **AC-004 ← FR-004**：webhook `payment_intent.succeeded` 到达后支付组内所有订单 `complete`；重复 webhook 不重复完成、不重复建 Payment（spec）。
- **AC-005 ← FR-005**：账户订单页可勾选多笔待支付订单并进入合并支付页，金额合计正确（storefront 组件测试 + Vitest）。
- **AC-006 ← FR-006**：合并支付完成页展示全部订单结果（组件测试）。
- **AC-007 ← FR-007**：结账时 A 仓 + B 仓商品自动拆成 2 笔订单，各自 totals/shipments 正确（service spec）。
- **AC-008 ← FR-008**：拆分后自动生成支付组并复用合并支付流程（service spec）。
- **AC-009 ← FR-009**：拆分规则按仓库可配置（spec）。
- **AC-010 ← FR-010**：Admin split API 按行项目拆分成功，金额/库存正确（request spec）。
- **AC-011 ← FR-011**：Admin 订单详情页有「拆分订单」入口且可完成拆分（admin 测试）。
- **AC-012 ← FR-012**：Admin 可查看支付组详情与订单过滤（admin 测试）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | split / 拆单 / warehouse / 仓库 / combine / 合并支付 / payment_group / multi-order | 无匹配 | ❌ 无已有能力 |
| Core | `pallastrade_gems/pallastrade_core/app/` | 同上 | `order_routing/`（`minimize_splits` 为选仓规则）、`inventory_unit.split`（退货拆分）、`stock_location`（`KINDS` 含 warehouse）、`payment.rb` / `payment_session.rb`（单订单绑定） | ❌ 无订单拆分/合并支付 |
| API | `pallastrade_gems/pallastrade_api/app/` | 同上 | `store/carts/payment_sessions_controller.rb`（单购物车→单会话）、`admin/orders/fulfillments_controller.rb#split`（发货级拆分） | ❌ 无多订单支付 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 同上 | `shipments_controller#split`（发货拆分）、`dashboard_controller`（vendor 子订单计数） | ❌ 无订单拆分 UI / 支付组 |
| Storefront | `storefront/src/` | 同上 | 单购物车结账流（`CheckoutPageContent`、`PaymentSection`、`confirm-payment/[id]`）、账户订单页（`account/orders`） | ❌ 无合并支付 |
| Platform | `platform/packages/` | 同上 | SDK `paymentSessions`（单 cart 嵌套资源）、Stripe 文档（marketplace split 为 Enterprise 平台级） | ❌ 无此能力 |

**结论**：6 层均无「订单拆分 / 合并支付」能力，确属全新功能，无重复实现风险。主要改造点为 `PaymentSession`/`Payment` 与单笔订单的强绑定关系 → 引入 `PaymentGroup` 作为多订单支付载体。

## 7. 技术影响

- **新增模型 / 迁移**：
  - `pallastrade_payment_groups`（前缀 `pg_`，`has_prefix_id`）
  - `orders.payment_group_id`（可空 FK）+ `orders.split_from_id`（可空，记录手动拆分来源）
  - `payment_sessions.payment_group_id`（可空 FK，向后兼容单订单路径）
- **Core 层**：
  - 新模型 `PallasTrade::PaymentGroup`（状态机 + 事件）
  - `PallasTrade::Order` 增加 `payment_group` / `split_from` 关联与作用域
  - 新服务 `PallasTrade::Orders::Splitter`（按行项目拆分）
  - 结账完成流程（`Carts::Complete` / `Checkout::Complete`）支持自动拆单钩子
  - `PallasTrade::Payments::HandleWebhook` 支持支付组上下文
- **Stripe gem**（`pallastrade_stripe`）：
  - `Gateway#create_payment_session` 支持 `payment_group:` 上下文（合计金额、跨订单行项目）
  - `CompleteOrderFromSessionJob` / webhook handlers 支持按支付组完成所有订单
- **API 层**：
  - Store：新增 `payment_groups` 资源（create/show + 嵌套 payment_sessions）
  - Admin：`orders/:id/split` + `payment_groups` 资源
  - 同步 `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`
- **Storefront**：账户订单页多选合并支付 + 合并支付页 + 完成页
- **Admin UI**：订单详情拆分操作 + 支付组查看
- **影响面**：实施时运行 `harness affected --base origin/main` 确认（涉及 core/API/admin/storefront/stripe 多包）

## 8. 测试计划

- **新增测试**：
  - `backend/spec/models/pallastrade/payment_group_spec.rb`（AC-001）
  - `backend/spec/services/pallastrade/orders/splitter_spec.rb`（AC-007/009/010）
  - `backend/spec/services/pallastrade/payments/complete_payment_group_spec.rb`（AC-004）
  - `backend/spec/requests/api/v3/store/payment_groups_spec.rb`（AC-002/003）
  - `backend/spec/requests/api/v3/admin/orders_split_spec.rb`（AC-010）
  - Stripe gem：`spec/services/create_payment_session_group_spec.rb`、webhook 组完成 spec（AC-003/004）
  - Storefront：`__tests__/OrderList.combined-payment.test.tsx`、`combined-payment` 页测试（AC-005/006）
  - Admin：订单拆分 feature spec（AC-011/012）
- **更新测试**：
  - `payment_sessions_controller` 相关 spec（确保单订单路径回归通过）
  - storefront `e2e/checkout.spec.ts`（拆单合并支付流程）
- **AC 映射**：实施时在测试头部标注 `# PRD-20260823-checkout-多订单拆分与合并支付 AC-x`。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/store.yaml` + `admin.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] SDK 类型：`pnpm --filter @pallastrade/sdk generate:types`（payment_groups 资源）
- [ ] Skill：`pallastrade-payments`、`pallastrade-checkout`、`pallastrade-api-v3`、`pallastrade-storefront`、`pallastrade-admin`
- [ ] 各层 CLAUDE.md（模型/接口约定变更）
- [ ] `.env.example`（Stripe 密钥占位说明）
- [ ] 反模式库 / 任务规则 / 场景库（如新增模式）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-23 | 0.1 | 初稿：跨层搜索完成（6 层无已有能力）、确认全新功能、定义 3 阶段 FR/AC | AI |
| 2026-08-23 | 0.2 | 用户确认（approved）→ task/gate/REQ → 实施完成：PaymentGroup 模型+服务、Stripe 组支付、Store/Admin API、Storefront 合并支付页、Admin 拆单 UI、RSpec+Vitest、API 文档 | AI |
