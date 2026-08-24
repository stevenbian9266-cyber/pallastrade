# REQ-20260824-order-lifecycle

> 关联 PRD：PRD-20260824-checkout-正向订单-逆向订单链路重构或优化-父子单结构-系统拆单-手动拆单-合并支付-buy-now-售后（v0.4 approved）
> 任务：TASK-20260824135606-96de471e（critical） / Gate GATE-2026-08-24T13-56-18（refactor）

## 需求标题
正向订单、逆向订单链路重构：父子单结构（Order#parent_id）、系统拆单（支付后触发）、手动拆单（跨店铺/仓库）、合并支付（与拆单联动）、Buy Now、下单前置校验（登录/黑名单/风控）、库存校验与锁库存双模式、发货触发、售后父子单化、独立站标配增强。

## 任务类型
新功能（完整重构，refactor gate）

## 跨层搜索结论（详见 PRD §6，6 层已全清）
- **core 已有（复用/改造）**：`Orders::Splitter`、`Checkout::SplitOrders`、`PaymentGroup`、`StockReservation/Quantifier/Reserve/Release/Extend`、`ReturnAuthorization→CustomerReturn→Reimbursement→Refund`、`Exchange`、`OrderCancellation`、`EmailTemplate`、`TaxRate`/adjuster、`shipment.tracking`
- **API 已有**：store/admin `payment_groups`、admin `orders/:id/split`、admin `stock_reservations`
- **Admin 已有**：`split_order`、`shipments#ship`、售后管理、库存管理
- **Storefront 已有**：checkout/confirm-payment/order-placed/cart/account orders（选项卡+付款）/combined-payment；**无 Buy Now**
- **需新建（本次核心）**：`Order#parent_id` 自引用父子结构、下单前置校验（黑名单/风控）、公用确认页/收银台、锁库存双模式、支付后拆单引擎、跨店手动拆单、父单售后、多支付方式/取消/时间线/仅退款/换货/退货物流/RMA/批量/防刷风控

## Skill 咨询摘要（refactor gate 无强制 read-skill check；实施时按领域读取）
- `pallastrade-payments`：支付单状态机、PaymentGroup 基线、Refund/Reimbursement 链
- `pallastrade-checkout`：下单链路、Checkout::SplitOrders、拆单策略
- `pallastrade-data-model`：Order/模型约定（base_class、prefixed_id、可空 FK）
- `pallastrade-storefront`：组件规范（禁 inline style/禁裸 fetch）、useTranslations t 依赖陷阱
- `pallastrade-api-v3`：v3 API 约定（scope current_store、prefixed id、list 分页）
- `pallastrade-security`：黑名单/风控/危险操作
- `pallastrade-shipping-fulfillment`：shipment/物流跟踪/退货

## 实施范围（按 PRD 阶段 0~13，FR-001~053）
见 PRD §3/§5（FR/AC 全表）。核心模型变更：
1. `orders.parent_id`（可空自引用 FK）+ `parent/children` 关联 + 父=子语义
2. `pallastrade_users.blacklisted_at`（黑名单标记）
3. `pallastrade_risk_events`（风控事件）
4. 锁库存策略配置 `stock_reservation_strategy = :order|:payment`
5. 支付单（PaymentGroup）状态机加固（非法迁移业务错误）
6. 拆单引擎重构（策略化/跨店/资金分摊/幂等）
7. 售后父子单（父单批量 RA）
8. 多支付方式收银、订单备注/时间线、仅退款/换货/退货物流/RMA、批量操作、防刷风控

## 验证策略
- 后端：RSpec（本地 docker `docker exec -w /rails pallastrade-web-1 bundle exec rspec`）
- 前端：Vitest + Testing Library
- E2E：Stripe sandbox + 浏览器（dev.pallastrade.cn）
- 知识同步：payments/checkout/data-model/storefront/admin/security/shipping Skill + scenarios.json + api-docs

## 风险点
- 父子单模型与 6.0 OrderGroup 裁定差异（以用户需求为准，PRD §1 已记录）
- 支付后拆单的资金/库存分摊正确性（需 service spec 覆盖）
- 旧 PaymentGroup 数据迁移（支付单重设计）
- 跨店铺拆单价格重算（目标店铺规则）
