# 支付系统收敛方案（仅 Stripe / Check / StoreCredit）

> 需求来源：运营原话 ——「支付厂商只保留 stripe，其它一概不留，代码已经实现的我也要移除，现在结构越来越复杂了」。
> 设计原则：**一条记录 = 一个收款渠道**。取消「厂商 vs 入口」双层结构与「多家厂商竞争一个支付方式」的全部求值；把入口从「需要被求值的对象」降级为「Stripe 账户事实 + 一个开关」。
> 关联 PRD：`PRD-20260915-admin-管理后台支付配置选项化…`（本页既有 PRD，收敛后需回写）、`PRD-20260920-checkout-支付核心统一…`（拟作废的抽象来源）
> 文档状态：**待评审**（未开工；第 11 节 3 项待确认）

---

## 0. 一页总览

```
┌───────────────── 收敛前（为「多厂商竞争」设计）─────────────────┐
│  厂商 provider（capability 声明）                                │
│    └─ 入口 option（rule_set 四维 + 熔断 + 3DS 能力）             │
│         └─ 收窄：能力 ∩ 账户 ∩ 市场                              │
│              └─ 路由 P3：这个方式由「哪家厂商」承接               │
│                   └─ Availability::Resolver（唯一求值点）        │
└──────────────────────────────────────────────────────────────────┘
                              ↓ 收敛
┌───────────────── 收敛后（三条渠道各司其职）─────────────────────┐
│  Stripe（在线收款：卡 / 钱包 / 本地支付方式）                    │
│      └─ 方式列表 = Stripe 账户启用 ∩ 本店开关   ← 只剩「事实+开关」│
│  Check（线下支票，人工确认）                                     │
│  StoreCredit（店铺余额抵扣）                                     │
│         ↓ 三者都不竞争；前台只按「一行一种方式」展示              │
│  Availability::Resolver（保留：环境隔离 + 3DS + 入口启用过滤）    │
└──────────────────────────────────────────────────────────────────┘
```

**四个删除动作**：① 厂商层抽象（P0-A/P0-B）② 方式级路由（P3）③ 适用范围四维（D8）④ 熔断（D11）—— 其中 ①③④ 有生产消费点，②**零生产消费点**（最干净）。

---

## 1. 现状病灶（为什么要收敛）

| 病灶 | 具体表现 | 根因 |
|---|---|---|
| **概念双层** | 「厂商」与「入口」两层，后台要运营**手填**「我账户开通了哪些方式」（`metadata['account']`） | 为「能力 ∩ 账户 ∩ 市场」收窄而建；单渠道下无对比对象 |
| **隐形门控** | `optionized`：不勾任何入口 → 前台回落默认入口；勾了任一 → 0 入口即 0 前台 | 状态迁移靠勾选框隐式触发，运营无从理解 |
| **恒等式路由** | P3「这个支付方式由哪家厂商承接」——只有一家时结果恒为它自己 | 为多厂商抢单而建 |
| **无人竞争的规则** | D8 四维 `rule_set`（市场/国家/Zone/币种）逐入口配置 | 为「不同渠道在不同市场」而建 |
| **页面堆叠** | Stripe 编辑页曾同时挂：诊断卡 + 账户手填表单 + 路由预览 + 范围四维 + 熔断卡 + 凭据卡 + Webhook | 逐切片叠加，缺少一次总体规划 |
| **名字混淆** | 后台列表里「Credit Card」实为 `Gateway::Bogus`（假网关），与「Credit Card (Stripe)」只差括号 | 种子/测试数据直接进了运营视图 |

---

## 2. 目标架构

### 2.1 三条渠道的分工与边界

| 渠道 | 类型 | 有外部 API？ | 有 key？ | 有 webhook？ | 前台形态 |
|---|---|---|---|---|---|
| **Stripe** | 第三方网关（`PallasTradeStripe::Gateway`） | ✅ | ✅ | ✅ | 卡表单 / 钱包按钮 / 重定向（按方式） |
| **Check** | 框架内置结算方式（`PaymentMethod::Check`） | ❌ | ❌ | ❌ | 「线下支票」选项，下单后待人工确认 |
| **StoreCredit** | 框架内置结算方式（`PaymentMethod::StoreCredit`） | ❌ | ❌ | ❌ | 「用余额抵扣」 |

> **关键认知**：Check / StoreCredit **不是「支付厂商」**，是 core 自带的「结算方式」。它们与 Stripe **不竞争**——一笔订单可以「余额抵扣 + 差额 Stripe」。

### 2.2 概念归位表

| 概念 | 收敛前 | 收敛后 | 动作 |
|---|---|---|---|
| 厂商能力声明 | `provider_capability`（provider 类方法 + 推导） | — | 🗑️ 删 |
| 账户配置 | `metadata['account']` + `Providers::Account.write!`（手填/同步） | — | 🗑️ 删（Stripe 的「账户事实」直接体现在方式列表） |
| 收窄 | `provider_effective_scope`（能力∩账户） | — | 🗑️ 删 |
| 三态 | `provider_state`（enabled/disabled/suspended，停用粘性） | 原生 `active` 布尔 | 🔄 改 |
| 诊断 | `provider_diagnostics` + 诊断卡 | — | 🗑️ 删 |
| 方式级路由 | `Routing::{Decide,Policy,Summary}` | — | 🗑️ 删 |
| 适用范围 | `rule_set`（market/country/zone/currency）+ 后台四维编辑 | — | 🗑️ 删（**契约变更**） |
| 熔断 | `CircuitBreaker` + `Health::Metrics` + 24h 指标卡 | — | 🗑️ 删 |
| 入口（option） | `metadata['options']`，需被 Resolver 求值 | `metadata['options']`，**只承载「开关 + 显示名 + 排序」** | 🔄 降级 |
| 隐形门控 | `optionized` | 显式：**入口可见 = `active` 为真** | 🔄 改 |
| 环境隔离 | `environment = test` 不进前台 | 不变 | ✅ 保留 |
| 3DS 认证 | `D15c`（策略 + `force_3ds` + 下发） | 不变 | ✅ 保留 |
| 前台密钥下发 | `D10`（`client_config` 只给 publishable） | 不变 | ✅ 保留 |
| 入口展示 | `D16`（每行前台显示名） | 不变 | ✅ 保留 |
| 凭据健康 + Webhook | `D9`（轮换/到期/reveal + 签名密钥） | 不变 | ✅ 保留 |

### 2.3 数据落点

| 数据 | 落点 | 变化 |
|---|---|---|
| 本店开关 / 显示名 / 排序 | `payment_methods.private_metadata['options']`（`[{kind, active, display_name, position, frontend_kind}]`） | ✅ 沿用（去掉 `rule_set`） |
| Stripe 账户已启用方式 | **不落库**（每次进页面/点同步时从 Stripe 读，只读缓存于请求内） | 🔄 从「手填 metadata」改为「实时读 Stripe」 |
| 最近一次连接检查 | `metadata['last_test_connection']` | ✅ 沿用 |
| 环境 | `payment_methods.environment`（原生列） | ✅ 沿用 |
| 停用 | `payment_methods.active`（原生列） | 🔄 从 `State.disable!` 改回原生 |
| ~~`metadata['account']`~~ | — | 🗑️ 删除后旧值保留但不再读 |
| ~~`options[].rule_set`~~ | — | 🗑️ 删除后旧值保留但不再读（**不迁移**） |

---

## 3. 正向履约（Forward Fulfillment）

### 3.1 全景流程图

```mermaid
flowchart TB
  A["浏览商品 /cart /products/[slug]"] --> B["加入购物车 /cart"]
  B --> C{"结算 /checkout"}
  C --> D["填写收货地址 + 选配送方式"]
  D --> E["服务端只读预览报价 /api/checkout/preview"]
  E --> F["支付区渲染<br/>（服务端下发入口集合）"]
  F --> G{"顾客选择支付方式"}
  G -->|Stripe 卡| H1["卡表单 → PaymentIntent<br/>（需要时 3DS 挑战）"]
  G -->|Stripe 钱包| H2["Apple Pay / Google Pay<br/>express 按钮"]
  G -->|Check| H3["线下支票<br/>下单后待人工确认"]
  G -->|StoreCredit| H4["余额抵扣<br/>（不足则差额走 Stripe）"]
  H1 & H2 --> I["一次点击：Prepare → 金额未变则直达 Pay"]
  H4 --> I
  I --> J["Stripe 收款<br/>PaymentIntent / Checkout Session"]
  J --> K{"支付结果"}
  K -->|成功| L["/order-placed/[id] 下单成功"]
  K -->|需要 3DS| M["跳转银行挑战"] --> J
  K -->|失败| N["/payment-result/[id] 失败页<br/>页内提示 + 可重试"]
  H3 --> O["订单 awaiting_payment"]
  L --> P["订单 paid → 备货"]
  O --> Q["运营确认收款"] --> P
  P --> R["发货 shipped"] --> S["收货 completed"]
  N -.->|未支付订单| T["/account/orders/[id] → 补付"]
  T -.-> C
  S --> U["逆向见 §4"]
```

### 3.2 时序图 A：纯 Stripe 在线支付（含 3DS）

```mermaid
sequenceDiagram
  autonumber
  participant U as 顾客
  participant SF as Storefront (/checkout)
  participant BFF as BFF (/api/checkout/*)
  participant API as Store API v3
  participant CORE as Core 支付域
  participant ST as Stripe

  U->>SF: 打开结账页
  SF->>BFF: POST /api/checkout/preview（地址/配送/账单模式）
  BFF->>API: 只读预览报价（dry_run）
  API->>CORE: prepare 同参数算价（零副作用）
  CORE-->>API: 金额 + 报价快照
  API-->>BFF: 预览金额
  Note over BFF,API: 预览 = 同参数 prepare 金额**逐字段一致**

  U->>SF: 选「卡支付」
  SF->>BFF: POST /api/checkout/prepare
  BFF->>API: 创建/更新订单（幂等提交）
  API->>CORE: PaymentSessions::Start（入口级门禁）
  CORE->>CORE: Availability::Resolver 过滤入口<br/>（环境隔离 / 3DS / 启用过滤）
  CORE->>ST: 建 PaymentIntent（或 Checkout Session）
  ST-->>CORE: client_secret
  CORE-->>API: 会话 + client_secret
  API-->>BFF: 报价 + 会话
  BFF-->>SF: 金额未变 → 一次点击直达 Pay

  U->>SF: 点 Pay
  SF->>ST: stripe.confirmPayment（客户端确认）
  opt 需要认证
    ST-->>U: 3DS 挑战（银行页）
    U->>ST: 完成挑战
  end
  ST-->>SF: 确认结果
  ST->>API: webhook payment_intent.succeeded
  API->>CORE: 解析事件 → Payment 落账 → 订单 paid
  SF->>SF: 跳 /order-placed/[id]
```

### 3.3 时序图 B：余额抵扣 + Stripe 差额（组合支付）

```mermaid
sequenceDiagram
  autonumber
  participant U as 顾客
  participant SF as Storefront (/combined-payment/[id])
  participant API as Store API v3
  participant CORE as Core 支付域
  participant SC as StoreCredit 账本
  participant ST as Stripe

  U->>SF: 结账（购物车含余额选项）
  SF->>API: 应用余额（Carts::ApplyStoreCredit）
  API->>SC: StoreCredit#authorize（冻结额度，记 StoreCreditEvent）
  SC-->>API: 授权号
  API-->>SF: 剩余应付 = 订单总额 − 余额

  alt 剩余应付 = 0
    SF->>API: 无需外部支付
    API->>CORE: 余额全额支付 → 订单 paid
  else 剩余应付 > 0
    SF->>API: 走 Stripe 支付差额（同 §3.2 时序）
    API->>ST: PaymentIntent（金额 = 差额）
    ST-->>API: 成功
    API->>CORE: 组合支付：多条 Payment 绑定同一订单
  end
  Note over CORE,SC: 组合支付的资金事实 = 多条 Payment 记录（数据层保留）
```

### 3.4 时序图 C：线下支票 Check

```mermaid
sequenceDiagram
  autonumber
  participant U as 顾客
  participant SF as Storefront
  participant CORE as Core 支付域
  participant AD as 运营（后台 /admin/orders）

  U->>SF: 结账并选「Check」
  SF->>CORE: PaymentMethod::Check#purchase
  Note over CORE: Check 的 authorize/purchase/capture/void<br/>全部是 simulated_successful_billing_response<br/>（无外部调用，直接返回成功）
  CORE-->>SF: 订单 awaiting_payment（待确认收款）
  SF-->>U: 下单成功页（提示：等待确认）

  AD->>CORE: 收到支票 → 后台确认收款
  CORE->>CORE: Payment capture → 订单 paid
  CORE-->>AD: 订单进入正常履约
```

### 3.5 时序图 D：钱包快捷支付（Apple Pay / Google Pay）

```mermaid
sequenceDiagram
  autonumber
  participant U as 顾客
  participant SF as Storefront（首屏骨架 → 原位替换）
  participant BFF as BFF
  participant CORE as Core 支付域
  participant ST as Stripe

  Note over SF: 首帧渲染固定高度骨架 + preconnect/preload js.stripe.com<br/>（P1-a；CLS < 0.02）
  SF->>BFF: /api/checkout/preview（拿 publishable key）
  BFF-->>SF: client_config（**只给 publishable**，D10）
  SF->>ST: loadStripe(pk, { developerTools: { assistant: { enabled: false } } })
  SF->>SF: ExpressCheckoutElement 就绪 → 只切透明度（原位替换）

  U->>SF: 点 Apple Pay / Google Pay
  SF->>BFF: POST /api/checkout/start（带 option_kind = 点击的钱包）
  BFF->>CORE: PaymentSessions::Start（服务端**同源复算**）
  CORE->>ST: 建 PaymentIntent（express）
  ST-->>SF: 钱包 sheet → 指纹/FaceID 确认
  ST->>CORE: webhook → Payment 落账 → 订单 paid
```

### 3.6 时序图 E：未支付订单补付

```mermaid
sequenceDiagram
  autonumber
  participant U as 顾客
  participant SF as Storefront (/account/orders/[id])
  participant API as Store API v3
  participant RV as OrderCheckout::Revalidate
  participant CORE as Core 支付域

  U->>SF: 打开未支付订单 → 点「继续支付」
  SF->>API: 补付重验（dry_run: true）—— **零副作用**
  API->>RV: 复核商业事实
  RV->>RV: 失效行剔除 / 库存重预留 / 锁价窗续窗 / 优惠复核
  alt 全部有效且金额未变
    RV-->>API: 可付，金额一致
    API-->>SF: 直接进支付
  else 金额变化
    RV-->>API: quote_changed + changes[]
    API-->>SF: **显示变化 + 让顾客确认**（不偷偷换价）
  else 全面失效
    RV-->>API: no_payable_items
    API-->>SF: 明确阻断 + 说明
  end
```

### 3.7 正向的退出点与异常分支

| 分支 | 触发 | 行为 |
|---|---|---|
| 金额变化 | 预览与 prepare 不一致 | 显示「旧 → 新」变化块，要求顾客确认（不自动扣款） |
| 3DS 挑战 | 风控要求认证 | 跳银行页；失败 → 支付结果页失败态 |
| 支付失败 | 卡被拒 / 网络 | **零跳转、零 PATCH**，页内提示 + 可重试 |
| 支付超时 | 会话过期 | 订单仍 awaiting_payment → 可补付（§3.6） |
| 订单失效 | 库存/优惠失效 | 补付重验阻断；订单可取消（§4.2） |
| 入口被后台关闭 | 运营改开关 | 前台即时不出现；**已建会话不受影响** |

---

## 4. 逆向履约（Reverse Fulfillment）

### 4.1 全景流程图

```mermaid
flowchart TB
  R0["逆向入口"] --> R1{"订单状态"}
  R1 -->|未支付| C1["取消订单<br/>零资金动作"]
  R1 -->|已授权未捕获| C2["Void 授权<br/>释放额度"]
  R1 -->|已捕获| C3["退款"]
  R1 -->|顾客发起| C4["退货 / 部分退"]
  R1 -->|银行发起| C5["争议 / 拒付"]

  C1 --> Z1["库存释放 + 订单 canceled"]
  C2 --> Z1
  C3 --> Z2{"退款审批策略<br/>（D14：阈值内自动 / 超阈值双人批）"}
  C2 --> Z2
  Z2 -->|自动| E1["Refunds::Request（durable requested）"]
  Z2 -->|待批| E0["/admin/refund_approvals 双人复核"] --> E1
  E1 --> E2["Refunds::ExecuteJob（后台执行）"]
  E2 --> E3{"退款去向"}
  E3 -->|原路| E4["Stripe Refund"]
  E3 -->|退成余额| E5["ReimbursementType::StoreCredit<br/>生成 StoreCredit 账本条目"]
  E4 --> F1["资金事实落账 + 对账"]
  E5 --> F1
  C4 --> Z2
  C5 --> G1["Disputes::HandleProviderEvent<br/>（无 payment_session，以 Payment/Charge 为锚）"]
  G1 --> G2["证据快照 + 期限分档（D14b）"]
  G2 --> G3{"结果"}
  G3 -->|胜诉| H1["funds_reinstated → 资金回补 + 对账"]
  G3 -->|败诉| H2["funds_withdrawn → 损失落账"]
  G3 -->|超期未举证| H3["策略门控自动 lost（默认关闭）"]
  F1 & H1 & H2 --> I["Reconciliations::* 差异入队 / 自动销案"]
```

### 4.2 时序图 F：未支付取消

```mermaid
sequenceDiagram
  autonumber
  participant U as 顾客或运营
  participant API as Store API / Admin
  participant OC as Orders::Cancel
  participant INV as 库存预留
  participant CORE as Core 支付域

  U->>API: 取消订单
  API->>OC: 取消编排
  OC->>OC: OrderCancellation 状态机
  OC->>CORE: 检查是否存在资金动作
  Note over CORE: 未支付 → **零退款**
  OC->>INV: 释放库存预留
  OC-->>API: 订单 canceled
  Note over OC: 全程**不得**触碰 Payment / 账本
```

### 4.3 时序图 G：已授权未捕获取消（Void）

```mermaid
sequenceDiagram
  autonumber
  participant AD as 运营
  participant CORE as Core 支付域
  participant ST as Stripe
  participant OC as Orders::Cancel

  AD->>CORE: 取消订单（已授权未捕获）
  CORE->>ST: void 授权（释放额度）
  ST-->>CORE: 已释放
  CORE->>OC: 订单 canceled
  Note over CORE: **零退款**（从未捕获，无资金移动）
  OC->>OC: 释放库存预留
```

### 4.4 时序图 H：已捕获退款（全额 / 部分）

```mermaid
sequenceDiagram
  autonumber
  participant AD as 运营
  participant AP as Refunds::Policy（D14 审批）
  participant RQ as Refunds::Request
  participant JB as Refunds::ExecuteJob
  participant ST as Stripe
  participant LED as 账本 / 对账

  AD->>AP: 发起退款（金额 / 原因）
  AP->>AP: 阈值与策略归一
  alt 阈值内
    AP->>RQ: 自动放行
  else 超阈值
    AP-->>AD: 待双人批准（/admin/refund_approvals）
    AD->>AP: 第二人批准（SoD，禁止同一人）
    AP->>RQ: 放行
  end
  RQ->>RQ: 写 durable `requested`（**幂等键 request_key**）
  RQ-->>AD: 已受理（不阻塞）
  Note over RQ,JB: 铁律：**资金副作用必须发生在 durable 行之后**（AP-010）
  JB->>ST: Refund.create（原路退回）
  ST-->>JB: 退款成功
  JB->>LED: 资金事实落账 + 对账差异入队
  Note over JB,LED: 部分退款按 REV-P6-3 的分摊规则分摊到订单行
```

### 4.5 时序图 I：退款退成 StoreCredit

```mermaid
sequenceDiagram
  autonumber
  participant AD as 运营
  participant RT as ReimbursementType::StoreCredit
  participant SCL as StoreCredit 账本
  participant CUS as 顾客

  AD->>RT: 退款时选择「退成店铺余额」
  RT->>SCL: 生成 StoreCredit + StoreCreditEvent（可追溯来源）
  SCL-->>CUS: 余额到账（前台 /account/gift-cards 可见）
  Note over RT,SCL: 无外部网关调用；资金留在店内闭环
  CUS->>CUS: 下次结账用余额抵扣（见 §3.3）
```

### 4.6 时序图 J：争议 / 拒付（Chargeback）

```mermaid
sequenceDiagram
  autonumber
  participant ST as Stripe
  participant API as Store API（webhook）
  participant DS as Disputes::HandleProviderEvent
  participant EV as 证据引擎（D14b）
  participant AD as 运营（/admin/disputes_ops）
  participant REC as 对账

  ST->>API: charge.dispute.created（**无 payment_session**）
  API->>DS: 以 Payment/Charge 为锚解析
  DS->>DS: 资金入账并落账（DSP-P7-3）
  DS->>EV: 证据快照（DSP-P7-4）
  EV->>EV: 期限分档 + 提醒（DSP-P7-5；`dispute.evidence_deadline_tier` 事件）
  EV-->>AD: 期限看板 / 提醒历史

  AD->>DS: 提交证据（危险操作，需权限）
  ST->>API: charge.dispute.closed
  alt 胜诉
    ST->>DS: charge.dispute.funds_reinstated
    DS->>REC: 资金回补 → 对账
  else 败诉
    ST->>DS: charge.dispute.funds_withdrawn
    DS->>REC: 损失落账 → 对账差异入队
  end
  Note over EV: 超期未举证：策略门控自动 lost（**默认关闭**，单轮上限）
```

### 4.7 逆向的资金 / 库存 / 台账一致性（三条铁律）

| 铁律 | 内容 | 现状 |
|---|---|---|
| **① durable 先行** | 退款一律 `Refunds::Request`（durable `requested`）→ `ExecuteJob` 后台执行；**禁止**在业务事务内同步调用网关（AP-010） | ✅ 已实现 |
| **② 库存与资金独立收敛** | 取消/退货先释放预留或做 Restock 决策；**资金动作与库存动作各自幂等**，不互相阻塞 | ✅ 已实现（`StockReservations::Release` / REV-P6-5） |
| **③ 对账是最终裁判** | 所有逆向的资金事实都要能被 `Reconciliations::*` 对到；差异入队可运营 | ✅ 已实现（D13 系列） |

---

## 5. 前台页面架构

### 5.1 路由与页面清单

| 路由 | 组 | 作用 | 支付相关组成 |
|---|---|---|---|
| `/cart` | storefront | 购物车 | 商品行 / 小计 / 「去结算」；顶部快捷支付（`TopExpressPay`）常显 |
| **`/checkout`** | (checkout) | **结账页（主）** | 地址 / 配送 / **支付区** / 合计明细（常显） |
| `/checkout/[id]` | (checkout) | 转换后购物车恢复路由 | 同上（`cart_` → `or_…` 恢复） |
| **`/combined-payment/[id]`** | (checkout) | **组合支付页** | 余额抵扣 + 多笔支付编排 |
| `/order-placed/[id]` | (checkout) | 下单成功 | 订单摘要 / 下一步 |
| **`/payment-result/[id]`** | (checkout) | **支付结果** | 成功 / 失败态（失败**页内提示，不跳转**） |
| `/account/orders` | storefront | 订单列表 | 状态 + 未支付订单的补付入口 |
| `/account/orders/[id]` | storefront | 订单详情 | 支付状态 / **补付**（走 §3.6 重验）/ 退款进度 |
| `/account/credit-cards` | storefront | 已存卡 | Stripe 客户档 |
| `/account/gift-cards` | storefront | 礼品卡 / 余额 | StoreCredit 余额展示 |

**BFF**：`/api/checkout/{prepare,preview,start,coupon,preflight,newsletter}` + `/api/webhooks/pallastrade`

### 5.2 结账页组成（组件树）

```
/checkout  page.tsx
├─ StripeResourceHints            （preconnect/dns-prefetch/preload js.stripe.com，仅当有 Stripe 且首屏有 publishable）
├─ OrderSummaryPanel（**常显**：合计 + 明细）
├─ AddressForm / ShippingSelector
├─ BillingModeSelector（Stripe 已收集 > 独立账单 > 同收货）
├─ **PaymentSection**             ← 支付区主体
│   ├─ WalletButtonSkeleton       （首帧固定高度骨架 h-12，列数 = maxColumns）
│   ├─ ExpressCheckoutElement     （常挂载，就绪只切透明度 = 原位替换）
│   │   └─ 钱包按钮（Apple Pay / Google Pay …… 服务端下发哪些就有哪些）
│   ├─ 「or」分隔线                （位置恒定，不因加载态跳变）
│   └─ CardPaymentForm            （卡表单）
│       └─ [Pay Now / 确认并支付]  （金额未变 = 一次点击直达）
├─ QuoteChangeBlock               （**仅当金额确实变化**：旧 → 新 + 确认块）
└─ PaymentResultInline            （失败态：页内提示，零跳转）
```

### 5.3 支付区的前台口径（硬约束）

| 约束 | 内容 | 来源 |
|---|---|---|
| 入口集合**服务端定** | 客户端**不得**按 `kind`/`frontend_kind` 自行筛选（否则「看得到、付不了」） | D8 §66.5 同源硬约束 |
| 顺序 | 按后台 `position` | D1 |
| 显示名 | `display_name ?? name` | D16 |
| 密钥 | 只收服务端下发的 publishable；**无 env 回落** | D10 |
| 金额变化 | 只在**确实变化**时让顾客确认；无基准不阻断 | P1-a |
| 失败 | 确认失败 → 零 PATCH / 零跳转，页内提示 | 结账失败体验 |

### 5.4 收敛对前台的净影响

| 变化 | 前台影响 |
|---|---|
| 删范围 `rule_set` | **无**（你已明确不做；旧数据保留但不生效） |
| 删熔断 | 去掉「入口被自动置灰」这一态 —— 运营需手动关 |
| 删能力∩账户收窄 | **无**（改由「Stripe 账户事实 ∩ 本店开关」直接决定） |
| 删 `optionized` | **行为更可预期**：入口可见 = 开关为真，不再有隐形回落 |
| 删路由 / 厂商层 | **无**（前台从不显示厂商名） |

---

## 6. 后台页面架构

### 6.1 导航与页面清单（收敛后）

**设置 → 支付方式（`/admin/payment_methods`）** —— 本方案的主战场

**Fund（资金域，`/admin/fund`）** —— 收敛**不影响**下列页面（它们消费的是资金事实，不是厂商抽象）：

| 页面 | 路由 | 与收敛的关系 |
|---|---|---|
| 交易排障台 | `/admin/transactions` | 无关（含 D2 人工裁决） |
| Payment Ops | `/admin/payments` | 无关 |
| 组合支付 | `/admin/payment_combinations` | 无关（数据层保留） |
| 退款 Ops / 退款审批 | `/admin/refunds` `/admin/refund_approvals` | 无关（D14） |
| 争议控制台 / 期限看板 / 拒付率 | `/admin/disputes_ops` `/admin/dispute_rates` | 无关（D14b/c） |
| 对账差异 / 结算台账 | `/admin/reconciliation_cases` `/admin/payouts` | 无关（D13） |
| 支付成本 / 费率策略 | `/admin/payment_costs` `/admin/payment_fee_policies` | 无关（D13c） |
| 风控 / 名单 / 规则 | `/admin/payment_risk` `/admin/risk_lists` `/admin/risk_rules` | 无关（D15） |

> **要点**：收敛**只动「支付方式的配置面」**，资金域的运营页一概不动。

### 6.2 `/admin/payment_methods` 列表页

```
┌─ 支付方式 ──────────────────────────────────────────────┐
│  ⠿  [图标] Store Credit   [可见性▾]  [启用●]   [编辑]   │
│  ⠿  [图标] Check          [可见性▾]  [启用●]   [编辑]   │
│  ⠿  [图标] Stripe         [可见性▾]  [启用●]   [编辑]   │
└─────────────────────────────────────────────────────────┘
┌─ 可用的支付方式 ────────────────────────────────────────┐
│  （空 —— 收件后仅 Stripe 系，且已装）                    │
└─────────────────────────────────────────────────────────┘
```

**变化**：删除 Adyen / PayPal / Bogus 后，列表**只剩 3 条**；「可用」区为空。

### 6.3 Stripe 详情页（最终形态）

```
/admin/payment_methods/pm_xxx/edit      ← 专用版面（provider_page_partial_name）
┌─ ① Stripe 连接 ─────────────────────────────────────────┐
│  Publishable Key  ••••••••••16 OOI8   [编辑]            │
│  Secret Key       ••••••••••16 JUnl   [编辑]            │
│  （Apple Pay 域名等 provider 自有字段）                  │
│  环境              [Live (production) ▾]                │
│  [测试连接]  最近检查：✅ Yes · credentials_present · …  │
│  [从 Stripe 同步]  上次同步：2026-09-21 10:12           │
└─────────────────────────────────────────────────────────┘
┌─ ② 支付方式 ───────────────────────────────────────────┐
│  方式           Stripe 账户   本店开关   前台显示名      │
│  Card           ✅ 已启用      [●—]      Card           │
│  Apple Pay      ✅ 已启用      [●—]      Apple Pay      │
│  Google Pay     ✅ 已启用      [—●]      —              │
│  Klarna         ✅ 已启用      🔒         当前版本不支持  │
│  Link           ✅ 已启用      🔒         当前版本不支持  │
│  Amazon Pay     ✅ 已启用      🔒         当前版本不支持  │
│  Affirm         ❌ 未启用      🔒         [去 Stripe 开启]│
└─────────────────────────────────────────────────────────┘
┌─ ③ 显示设置 ───────────────────────────────────────────┐
│  名称 / 可见性 / 自动捕获 / 启用                          │
└─────────────────────────────────────────────────────────┘
┌─ ④ 凭据健康 + Webhook ─────────────────────────────────┐
│  凭据分级 / 轮换 / 到期 / [查看明文(审计)]               │
│  Webhook 地址（可复制）+ 签名密钥（只读掩码）             │
└─────────────────────────────────────────────────────────┘
```

**② 的四象限口径**（`Stripe 账户事实 × 本地实现能力`）：

| 本地实现 | Stripe 账户 | 行状态 | 开关 |
|---|---|---|---|
| ✅ | ✅ | 可开 | **可切换** → 直接决定前台 |
| ✅ | ❌ | 置灰 | 🔒 + 「去 Stripe 后台开启」 |
| ❌ | ✅ | 置灰 | 🔒 + 「当前版本不支持该方式」 |
| ❌ | ❌ | 折叠区 | 🔒 |

> 你 Stripe 账户实际开着 8 种（`amazon_pay / apple_pay / card / cashapp / google_pay / kakao_pay / klarna / samsung_pay`），本地能渲染 3 种 → **5 种可见但开不了**（而不是现在的完全看不见）。

**页面删除项**：诊断卡、账户配置手填表单、路由预览（S1 已删）、熔断卡、适用范围四维、3DS 能力列。

### 6.4 Check / StoreCredit 详情页

| 卡片 | Check | StoreCredit |
|---|---|---|
| 显示设置（名称/可见性/启用） | ✅ | ✅ |
| **支付方式**（入口列表） | ❌ 无入口 | ❌ 无入口 |
| 连接 / 凭据 / Webhook | ❌ | ❌ |

> 这两个是「开关型结算方式」，页面极简。

### 6.5 订单页的支付区块（`/admin/orders/:id`）

| 区块 | 收敛后 |
|---|---|
| 支付记录（多条 `Payment`） | 保留 |
| 退款 / 争议入口 | 保留 |
| 成交快照（促销分摊） | 保留 |
| ~~厂商诊断/收窄依据~~ | 🗑️ 删 |

### 6.6 页面架构总图

```mermaid
flowchart LR
  subgraph FE["商城前台"]
    CART["/cart"] --> CK["/checkout"] --> CP["/combined-payment/[id]"]
    CK --> OP["/order-placed/[id]"]
    CK --> PR["/payment-result/[id]"]
    ACC["/account/orders/[id]"] -.补付.-> CK
  end
  subgraph AD["管理后台"]
    PM["/admin/payment_methods"] --> SP["Stripe 详情页"]
    PM --> CSP["Check / StoreCredit 详情页"]
    OD["/admin/orders/:id"] --> RF["/admin/refunds"]
    OD --> DS["/admin/disputes_ops"]
    RF --> RA["/admin/refund_approvals"]
    RC["/admin/reconciliation_cases"]
    PY["/admin/payouts"]
  end
  CK <-->|"prepare/preview/start"| API["Store API v3"]
  API <--> CORE["Core 支付域"]
  CORE <--> ST["Stripe"]
  ST -->|webhook| API
  CORE --> RC & PY
```

---

## 7. 删除清单（逐文件）

### A. 第三方厂商连根拔

| 目标 | 动作 |
|---|---|
| `backend/pallastrade_gems/pallastrade_adyen/` | 整目录删 |
| `backend/pallastrade_gems/pallastrade_paypal_checkout/` | 整目录删 |
| `platform/payments/pallastrade_{adyen,paypal_checkout}/` | 两份镜像删 |
| `backend/Gemfile` | 删 2 行（`pallastrade_adyen` / `pallastrade_paypal_checkout`） |
| `PallasTrade::Gateway::Bogus` | **出注册表**（后台不可选/不可新建）；**类保留**（大量测试造数依赖） |
| dev 库 `Credit Card`（Bogus）+ `chk` | 清记录 |

### B. 厂商层抽象（Q2-①）

| 目标 | 位置 |
|---|---|
| 服务 | `core/app/services/pallastrade/payments/providers/{config,state,validate,account}.rb` |
| 模型方法 | `payment_method.rb`：`provider_capability_declaration` / `provider_capability` / `provider_account_config` / `provider_effective_scope` / `provider_state` / `provider_diagnostics` |
| 网关声明 | `pallastrade_stripe/gateway.rb`：`self.provider_capability` |
| 后台 | `_provider_diagnostics.html.erb`；`payments_helper.rb` 的 `provider_diagnostics*` 系列 + `provider_account_form` |
| 动作/路由 | `payment_methods_controller#update_provider_account` / `#sync_provider_account`；`routes.rb` 两行 |
| i18n | `admin.payment_methods.provider_diagnostics.*`（en + zh-CN） |
| 测试 | `providers/{config,validate,state,account}_spec.rb`、`payment_provider_diagnostics_spec.rb`、`payment_provider_account_spec.rb` |
| 验证器 | `payment-providers-rspec` + `AGENTS.md §6` 对应行 |
| 消费点修正 | `disputes/build_evidence_snapshot.rb` 的 `provider_capability?` → 改为直接判断 `is_a?(PallasTradeStripe::Gateway)` |
| **停用改法** | `active` 原生布尔（去掉 `State.disable!` 的粘性三态） |

### C. 方式级路由（Q2-②，零生产消费点）

`core/app/services/pallastrade/payments/routing/{decide,policy,summary}.rb`、`spec/services/.../routing/{decide,policy_write}_spec.rb`、验证器 `payment-routing-rspec`、skill 段落、`AGENTS.md §6` 该行、`store.private_metadata['payment_routing']` 旧值（保留不读）。

### D. 适用范围 `rule_set`（Q2-③，**契约变更**）

| 目标 | 位置 |
|---|---|
| 引擎 | `payments/availability/{rule_set,evaluator}.rb` |
| 模型 | `payment_option_rule_set` / `payment_option_scope_summary` |
| 求值 | `Availability::Resolver` 的范围分支 |
| 后台 | `_options.html.erb` 的 `scope` 列；`payments_helper.rb` 的 `payment_option_scope_*` 4 个 helper；控制器 `merged_payment_option_rule_set` |
| 契约 | admin `payment_method_serializer` 的 `rule_set`/`scope_summary`；**OpenAPI（`backend/public/api-docs/admin.yaml`）+ `platform/docs/api-reference/`**；SDK 类型（`platform/packages/sdk/src/types`，含 `rule_set` 字段） |
| 前端类型 | `backend/app/javascript/types/serializers/PallasTradeApiV3AdminPaymentMethod.ts` |
| 测试 | d8 相关用例、resolver 的范围分支用例 |
| 验证器 | `d8-availability-rspec` + `AGENTS.md §6` 该行 |

### E. 熔断（Q3）

`payments/circuit_breaker/**`、`payments/health/metrics.rb`、`payment_method.rb` 的 `breaker_state` / `soft_disabled?` / `soft_disable!` / `soft_enable!`、`_breaker.html.erb`、`soft_disable`/`soft_enable` 动作与路由、`D11CircuitBreakerSweepJob`、5 个 spec、验证器 `d11-circuit-breaker-rspec` + `AGENTS.md §6` 该行、`Availability::Resolver` 的熔断分支。

### F. 顺带

- **丢弃 S3 未提交 WIP**（载体 `Providers::Account` 属删除面）
- `harness.config.mjs` 删 4 个验证器
- 各 skill 中对应小节改「已废弃」或删除
- `scenarios.json`：为「收敛」新增 1 个 GS 场景

---

## 8. 保留清单（不能碰）

| 保留 | 理由 |
|---|---|
| `PaymentSessions::Start`（含入口级门禁 422 `payment_option_not_available`） | 建会话唯一入口 |
| `Availability::{Resolver,Context}`（**去掉范围/熔断分支**） | 前台与建会话的**同一求值点**；且承载 D9 环境隔离 + D15c 3DS |
| D9 环境隔离 | test 不进前台 |
| D15c 3DS 策略与下发 | 未要求删 |
| D10 前台密钥下发 | 只给 publishable |
| D16 入口展示元数据 | 你要的「一行一种方式」 |
| D7 入口级支付区 | 前台支付区 |
| 凭据健康 + Webhook 卡 | Q3 确认保留 |
| 退款/争议/对账/账本全套 | 资金事实，与厂商层无关 |
| 组合支付数据层（多条 `Payment`） | 业务线 |
| `platform/payments/pallastrade_stripe/` 镜像 | Stripe 本身保留（镜像同步属治理决策，另行处理） |

---

## 9. 实施切片（每步跑绿再进下一步）

| # | 切片 | 内容 | 验证器 |
|---|---|---|---|
| **0** | 清算 | 丢弃 S3 WIP、关 gate | — |
| **1** | 删路由 | P3 全套（零消费点） | 下线 `payment-routing-rspec` |
| **2** | 删熔断 | D11 全套 | 下线 `d11-circuit-breaker-rspec` |
| **3** | 删厂商层 | Providers::* + 诊断卡 + 账户表单；停用改 `active` | 下线 `payment-providers-rspec` |
| **4** | 删范围 | `rule_set` + 后台 scope + **契约同步** | 下线 `d8-availability-rspec`；`generated:check` |
| **5** | 删第三方厂商 | Adyen/PayPal + 镜像 + Gemfile + Bogus 出注册表 | 全量 check |
| **6** | 后台收敛 | Stripe 页最终形态；列表只剩 3 条；Check/StoreCredit 极简页 | `admin-payment-methods-rspec`、`admin-theme-rspec`、`admin-i18n-rspec` |
| **7** | 知识同步 | AGENTS.md / skills / scenarios / PRD 回写 | `doc-impact`、`sync-check` |

---

## 10. 风险与代价

| 风险 | 说明 | 缓解 |
|---|---|---|
| **契约变更** | 删 `rule_set`/`scope_summary` 影响 OpenAPI + SDK 类型 + 前台类型 | 切片 4 单独做，跑 `generated:check` |
| **数据残留** | `metadata['account']`、`options[].rule_set`、`payment_routing` 旧值保留但不读 | 显式声明**不迁移**；如需可加一次性清理任务 |
| **测试面大** | D8/D11/P0/P3 的 spec 共约 15 个文件 | 按切片逐个下线；每步跑全量确认 |
| **AGENTS.md/验证器同步** | 删验证器要同步 §6 与 `harness.config.mjs` | 每切片一并提交 |
| **回滚** | 删除量大 | 每切片独立提交 → `git revert` 单切片即可回退 |
| **`Availability::Resolver` 误删** | 整体删会塌「选得上、付不了」防线 | **只删两个分支**，本体与同源约束不动 |

---

## 11. 待确认项（开工前必须定）

| # | 问题 | 我的建议 |
|---|---|---|
| **1** | `Availability::Resolver` **只删范围/熔断两个分支，不删本体** —— 同意吗？ | ✅ 同意即可（删本体将同时失去「环境隔离」与「3DS 闸门」） |
| **2** | `optionized` 隐式门控**一并删掉**，改为显式「入口可见 = `active` 为真」 —— 同意吗？ | ✅ 同意（消除隐形状态迁移） |
| **3** | `rule_set` 是**契约变更**（动 OpenAPI + SDK + 前台类型）—— 接受这个代价吗？ | ✅ 接受则切片 4 单独提交 |
| **4** | `Gateway::Bogus`：**类保留、出注册表**（后台不再可选）—— 还是**连类一起删**（会牵动大量测试造数）？ | 建议前者 |
| **5** | dev 库里 `Credit Card`（Bogus）与 `chk` 两条**记录**清掉 —— 同意吗？ | ✅ 同意（名字最易混淆） |

> 确认 1–5 后，从切片 0 + 1 开始。
