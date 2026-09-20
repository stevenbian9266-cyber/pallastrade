# PRD-20260920-checkout-支付核心统一-厂商层-支付方式层-方式级路由-组合支付-订单失效期

| 元数据 | 值 |
|---|---|
| 状态 | implementing |
| 创建日期 | 2026-09-20 |
| 来源 | 新增：支付核心统一（厂商层 / 支付方式层 / 方式级路由 / 组合支付 / 订单失效期） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-payments（主）/ pallastrade-checkout / pallastrade-admin / pallastrade-api-v3 / pallastrade-storefront / pallastrade-i18n / pallastrade-testing / pallastrade-prd |
| 关联 REQ | REQ-20260920-payment-core-unification.md（实施时回填） |
| 关联 PRD | N/A |
| 需求类型 | 新功能 + 优化迭代（含体验修复：二次确认块／快捷区加载） |

## 1. 背景与目标

- **一句话需求原文**：把支付做成一套独立结构——预接 Stripe / Adyen / PayPal，厂商与厂商侧支付方式可开关，前台只按方式展示且同一方式只出现一次（方式级路由），支持多订单组合支付，并把 cart / 待付款订单 / 组合三条链路统一到一套配置、一套判定、一套读模型、一套编排。
- **背景**：
  1. 现状存在**两条投影、两条支付通道**（cart 通道不过滤、orders 通道过滤），导致"前台显示不一样""点了才知道不能用"；
  2. 支付配置散落在 provider metadata（JSON，无 schema/校验），**错配无法在后台暴露**；
  3. 多厂商能力缺失：只有"配置全集"，没有"每个方式归属哪家厂商"的**路由**；
  4. 组合支付（多来源 / 多订单）**尚无模型与分摊**，账本/退款/对账的 1:1 假设会被打破；
  5. 待付款订单**没有付款期限**（无限期占用库存与账本）；
  6. 前台存在两处体验问题：快捷支付区"加载后才渲染"、支付需"点击 Pay → 展开小计 → 再确认"两步。
- **目标**：交付可售卖的支付核心（厂商层 / 方式层 / 路由 / 编排 / 组合 / 生命周期），三条链路共用一套契约；后台配置最小化（厂商开关 + 方式开关 + 归属路由 + 组合策略 + 付款期限）。
- **成功指标**：
  - 后台可完成三家厂商接入与方式配置，错配在保存时被拒；
  - 三形态（inline / express / redirect）各有一条端到端支付成功路径；
  - 路由影子期**零行为变化**，生效后同一方式只出现一次；
  - 前台 CLS < 0.02，冷启动快捷区可见 < 1.5s；常规支付**一次点击**可达确认；
  - 组合支付 2 单 2 来源端到端通过，分摊合计恒等、退款归因正确；
  - 付款期限到期订单被正确取消（有 pending 授权者不误取消）。

## 2. 用户故事 / 场景

- 作为**商户**，我希望接入多家厂商并逐项开关支付方式，且能按市场与金额收窄，以便控制各市场的收款能力与成本。
- 作为**商户**，我希望指定"同一支付方式由哪家厂商承接"，以便前台不出现重复方式、后台可解释。
- 作为**买家**，我希望在结算页立即看到可用的支付方式（含钱包快捷入口），点击即支付，不必二次确认。
- 作为**买家**，我希望在订单支付页看到"多久内需付款"的倒计时与到期提醒，并能在允许的场景下修改地址/配送方式。
- 作为**买家**，我希望能把多张待付款订单与多个资金来源（礼品卡/余额/卡）合并支付。
- 作为**运营/客服**，我希望任何一笔支付都能回答"为什么是这家厂商"，并能按承运厂商/组合筛选对账与退款。

**边界场景**：金额变化、失效行、优惠调整、配送不可达、熔断、在线资格查询失败、redirect 回跳未确认、组合内某单阻断、组合过期、订单过期、已付款未发货改地址产生差额。

## 3. 功能需求（FR）

### 切片 P0 · 配置面（厂商 / 方式 / 范围 / 组合策略 / 付款期限）
- **FR-001 厂商三态**：厂商支持 `enabled / disabled / suspended`；熔断自动进入且可到期恢复，停用无自动恢复；全部变更有审计。
- **FR-002 厂商接入字段**：按适配器声明渲染凭证字段（Stripe / Adyen / PayPal 差异见设计文档 §2.2），test/live 环境隔离，连接验证通过方可启用。
- **FR-003 能力声明**：适配器声明 `capabilities`（方式 / 交易 / 退款 / 争议 / 认证 / 结算 / 国家 / 币种 / 金额 / 幂等），后台只能**收窄**不能放宽。
- **FR-004 账户配置同步**：支持从 PSP 同步"账户已开通方式/币种/国家"（无接口者手工录入兜底），并高亮"能力支持但账户未开通"的差异。
- **FR-005 方式配置（厂商×方式）**：可配置 `method_key / provider_code / form(inline|express|redirect|manual) / display_name（多语言）/ active / position / group / icon / 金额区间 / capture_mode / requires_3ds / redirect 参数 / note`。
- **FR-006 范围与 Market 绑定**：**币种由 Market 派生（只读）**；国家默认继承 `market.countries` 且**只能排除**；方式级勾选 `markets[]`；金额区间按市场币种解释；启用时做兼容性校验（静态能力 ∩ 账户 ∩ market）。
- **FR-007 组合策略配置**：组合支付开关、单批次最大订单数、是否允许跨市场、组合有效期。
- **FR-008 付款期限配置**：付款期限（按店 / 按市场覆写）、到期前提醒开关与时点、**提醒渠道仅邮件**、过期是否允许补付（默认否）。

### 切片 P1 · 读模型与前台渲染
- **FR-009 唯一读模型**：两条通道（cart / orders）共用同一装配器输出 `PaymentOfferView{method_key, display_name, group, position, form, state, reason, requires_authentication, client_config, availability{stage, context_complete}}`。
- **FR-010 三形态渲染**：前台按 `form` 渲染 —— inline（自绘卡）/ express（钱包，唯一需要客户端设备判定）/ redirect（跳转）/ manual（说明行）。
- **FR-011 快捷区瞬时渲染**：支付区首帧渲染固定高度骨架；预连接并预加载 `js.stripe.com`；publishable key 随首屏 payload；元素就绪原位替换（CLS < 0.02）。
- **FR-012 一次点击直达**：删除"点击 Pay 展开小计 + 二次确认"；合计与明细常显；**仅当金额发生变化时**才显示变化块并要求确认。

### 切片 P2 · 资格求值
- **FR-013 在线资格**：`资格 = 在线查询(PSP) ?? 静态能力 ∩ 账户配置`；带缓存（金额分桶，TTL 5–15min）、超时 ≤1.2s、失败降级为 `provisional`。
- **FR-014 Start 前复判**：创建支付会话前服务端再次求值，以服务端结果为准。

### 切片 P3 · 路由
- **FR-015 方式级归属**：每个方式选出唯一承运厂商；后台可配置优先级（可按市场覆写）。
- **FR-016 排序与硬门**：硬门（厂商三态 / 方式范围 / 资格 / 认证）→ 排序 `(priority_tier, cost_tier, health_tier, tie_break)`；成本不可判定时不猜（`UNKNOWN` 排最后）。
- **FR-017 稳定性与留痕**：决策绑定结账会话（同会话结果稳定）；写入 `routing_decision`（输入快照 / 候选 / 档位 / pick / fallbacks / 策略版本）。
- **FR-018 影子模式与预览**：`shadow` 只记录不生效；后台 Preview 用同一读模型回答"顾客看到什么 + 选谁 + 为什么"。

### 切片 P4 · 生命周期与可修改性
- **FR-019 付款期限与倒计时**：订单写入 `payment_due_at`（后台可配），页面/列表展示倒计时（>1h 灰 / ≤1h 琥珀 / ≤5min 红），过期切换为"已超时取消"态。
- **FR-020 邮件提醒**：到期前按配置时点发送邮件提醒，可关闭，发送留痕。
- **FR-021 过期作业**：`ExpireUnpaidOrdersJob` 幂等取消过期未付款订单、释放库存预留、发 `order.expired`；**存在进行中会话或 pending 授权时不取消**并告警。
- **FR-022 三场景可修改性**：未付款可改地址/配送/账单；**已付款未发货可改地址（差额流程）、配送仅差额=0 或走差额流程**；已付款已发货只读。
- **FR-023 差额流程**：Δ>0 生成补款单（未补款拦截发货）；Δ<0 走部分退款；Δ=0 仅更新；全部写订单时间线。

### 切片 P5 · 组合支付
- **FR-024 组合模型**：`PaymentCombination{orders[N], sources[M]}`（多来源 + 多订单同属组合；单订单单来源为退化形态）。
- **FR-025 承运约束**：组合内 gateway 来源**必须同一厂商**（首个来源锁定承运）；换厂商需拆分组合（「改为单独支付」）。
- **FR-026 分摊与归因**：`(order, source) → allocated_minor`，合计恒等、尾差由最大项吸收、部分退款不超已收；退款/争议/对账按分摊归因。
- **FR-027 阻断与失败**：任一订单阻断 → **整批拒绝** + 「仅支付可用单」；某来源失败 → `partially_paid`；组合过期释放占用与承运锁定。

### 切片 P6 · 成本与三家接入
- **FR-028 成本路由**：费率模型（含跨境与转换加点）参与排序，模式渐进（`priority_only → priority_cost → priority_cost_health`），启用前需影子验证。
- **FR-029 成本分摊**：整笔手续费按分摊比例摊到各订单（报表标注口径）。
- **FR-030 三家端到端**：Stripe / Adyen / PayPal 按各自能力边界跑通 会话 → 支付 → 退款 → webhook（含 redirect 回跳与结果确认、结算导入、争议 webhook）。

## 4. 非功能需求（NFR）

- **性能**：CLS < 0.02；冷启动快捷区可见 < 1.5s；资格查询 ≤1.2s 且不阻塞首帧。
- **安全**：仅下发 publishable 级凭据；凭证 reveal 需权限 + 审计；webhook 签名校验 + 隔离重放；`billing_details` 仅存在于 payment method 级。
- **兼容**：读模型字段保持超集，旧客户端无感；配置为 JSON + `schema_version`（不做大迁移）。
- **可维护**：配置只能收窄；所有状态/范围/凭证变更可审计；作业幂等；资金路径改动需可回滚。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件 | 验证 |
|---|---|---|---|
| AC-001 | FR-001 | 三态切换正确、熔断可自动恢复、停用不自动恢复，均有审计 | admin-rspec |
| AC-002 | FR-003/005 | 启用未声明方式/越界配置 → 保存被拒 | admin-rspec |
| AC-003 | FR-006 | 币种只读派生；国家只能排除；市场新增国家自动跟随 | admin-rspec |
| AC-004 | FR-006 | 兼容性校验：能力∩账户∩market 为空 → 禁止启用 | admin-rspec |
| AC-005 | FR-009 | 两条通道输出同一读模型字段（含 form/state/reason） | api contract spec |
| AC-006 | FR-010 | 三形态渲染正确；express 才有设备判定 | storefront-test |
| AC-007 | FR-011 | 首帧有骨架；CLS < 0.02 | 视觉/E2E |
| AC-008 | FR-012 | 常规路径一次点击发起支付；金额变化时才需确认 | storefront-test + E2E |
| AC-009 | FR-013 | 在线查询失败 → 降级静态能力并标 provisional（入口不消失） | payment-core-rspec |
| AC-010 | FR-014 | Start 使用服务端复判结果（与前台不一致时以服务端为准） | payment-core-rspec |
| AC-011 | FR-015/016 | 同一方式只出现一次；硬门与排序可复算 | payment-routing-rspec |
| AC-012 | FR-016 | 成本不可判定时不参与成本排序（不猜） | payment-routing-rspec |
| AC-013 | FR-017 | 同会话重复决策同结果；留痕含输入快照与策略版本 | payment-routing-rspec |
| AC-014 | FR-018 | shadow 不改变前台；Preview 输出与前台同源 | payment-routing-rspec + 后台 |
| AC-015 | FR-019 | 倒计时与 `payment_due_at` 同源；阈值配色正确 | storefront-test + E2E |
| AC-016 | FR-021 | 过期订单被取消并释放预留；含 pending 授权者不被取消 | payment-lifecycle-rspec |
| AC-017 | FR-020 | 邮件按配置时点发送；关闭后无发送记录 | payment-lifecycle-rspec |
| AC-018 | FR-022/023 | 三场景可修改性正确；Δ=0 无资金记录；Δ≠0 产生补款/退款并留痕 | payment-lifecycle-rspec |
| AC-019 | FR-024/025 | 组合可含多单多来源；跨厂商被拒 | payment-combination-rspec |
| AC-020 | FR-026 | 分摊合计恒等；部分退款不超已收；退款/争议归因正确 | payment-combination-rspec |
| AC-021 | FR-027 | 阻断整批拒绝；「仅支付可用单」可用；过期释放占用 | payment-combination-rspec |
| AC-022 | FR-028/029 | 成本模式开启后按成本排序；费用按分摊摊到订单 | payment-routing-rspec + 报表 |
| AC-023 | FR-030 | 三家各自端到端（含 redirect 回跳与 webhook 确认） | 三家 E2E spec |
| AC-024 | NFR | 生成契约一致（OpenAPI + SDK 类型） | `harness generated:check` |
| AC-025 | NFR | 后台文案 5 语言键集一致；导航子项一致 | `admin-i18n-rspec` + nav-validate |

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | payment_preflight / quote_gate / expected_amount_due | 0 命中 | 不需要改动 |
| Core | `pallastrade_gems/pallastrade_core/app/` | PaymentMethod / payment_option_entries / Availability::Resolver / CircuitBreaker / ThreeDSecure / Transactions::Start / OrderCheckout::Revalidate | `models/pallastrade/payment_method.rb`、`services/pallastrade/payments/**`、`services/pallastrade/order_checkout/revalidate.rb` 等 | 部分满足：需扩展能力声明/范围/路由 |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_method_serializer / checkout_serializer / payment_preflight | `serializers/.../payment_method_serializer.rb`、`.../checkout/checkout_serializer.rb`、`orders/payment_preflight_controller.rb`、`config/routes.rb` | 部分满足：需合并为单一读模型 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_methods / payment_costs / payment_fee_policies / navigation | `views/.../payment_methods/**`、`config/initializers/pallastrade_admin_navigation.rb`（Fund 组 + Settings 下 payment_methods）、`config/routes.rb` | 部分满足：需新增 Routing / Preview / Terms 页面 |
| Storefront | `storefront/src/` | PaymentSection / WalletPaymentButtons / ExpressCheckoutButton / wallet-availability / order-payable | `components/checkout/{UnifiedCheckout,OrderPaymentContent,PaymentSection,WalletPaymentButtons,ExpressCheckoutButton,TopExpressPay,CardPaymentForm}.tsx`、`lib/checkout/wallet-availability.ts`、`lib/utils/stripe.ts`、`lib/data/{cart,order-payment}.ts` | 部分满足：需接入读模型/三形态/一次点击/骨架 |
| Platform | `platform/packages/` | paymentPreflight / StoreOrdersPaymentPreflight / store-client | `sdk/src/store-client.ts`、`sdk/src/types/generated/StoreOrdersPaymentPreflight.ts` | 部分满足：契约需扩展字段 |

**结论**：六层均已有支付相关实现（约七成本方案所需资产存在）；**需新建**：能力声明与范围校验、`RoutingPolicy/RoutingDecision`、`PaymentCombination`（多来源+多订单）+ 分摊、付款期限与过期作业、后台 Routing/Preview/Terms 三页；**需改造**：两条投影合并、前台三页渲染、路由接入 `Transactions::Start`。

## 7. 技术影响

- **新增**：厂商能力/账户配置模型、范围（Market 绑定）、方式 `form` 与校验、路由（策略 + 决策留痕）、组合（模型 + 分摊）、付款期限与提醒、后台三个新页面。
- **改造**：`PaymentMethodSerializer` 与 `CheckoutSerializer` 合并到统一装配器；`Transactions::Start` 接入路由与承运归属；`PaymentSession` 增加 form/redirect 字段；前台三页与支付区组件。
- **不动**：`OrderCheckout::Revalidate`、`Carts::{Submit,PreviewQuote}`、账本与对账、退款与争议核心、webhook 治理、`client_config`、订单列表/详情 Pay 入口。

## 8. 测试计划（verifier）

| 切片 | verifier | 覆盖 |
|---|---|---|
| P0 | `payment-providers-rspec`（新，已注册） | 三态/能力/范围校验/账户同步差异 |
| P1 | `storefront-test` + `payment-core-rspec`（新） | 三形态渲染/读模型同源/一次点击 |
| P2 | `payment-core-rspec` | 在线资格 + 降级 + Start 复判 |
| P3 | `payment-routing-rspec`（新） | 硬门/排序/确定性/影子/不猜 |
| P4 | `payment-lifecycle-rspec`（新） | 付款期限/提醒/过期保护/三场景与差额 |
| P5 | `payment-combination-rspec`（新） | 多单多来源/承运约束/分摊/阻断/部分成功 |
| P6 | 三家 E2E + `payment-routing-rspec` | redirect 闭环/结算导入/成本排序 |

## 9. 文档同步清单（知识同步门）

**P0-A 已处理（2026-09-20）**

- [x] `ai/skills/pallastrade-payments/SKILL.md`：新增「厂商层（PAY-CORE P0-A）」章节（能力声明 / 账户配置 / 收窄 basis / 三态与粘性 / 零资金副作用 / 诊断卡 / 验证入口）
- [x] `AGENTS.md §6`：新增验证器行 `payment-providers-rspec`
- [x] `harness/scenarios/scenarios.json`：新增 GS-198（厂商层诚实化）
- [x] `harness.config.mjs`：注册 `payment-providers-rspec`（4 枚规格）
- [x] `docs/prd/README.md` 索引（状态 draft → implementing，`prd-status-sync` 复检通过）
- [x] 后台 i18n 双语（gem `en.yml` + `backend/config/locales/admin_payment_methods.zh-CN.yml`，`admin-i18n-rspec` 通过）

**已评估，无需更新**

- `ai/skills/pallastrade-prd/SKILL.md`：本切片未改变 PRD 流程、模板或命令 → 无需更新
- `.github/copilot-instructions.md`：未新增强制规则/命令、未改 R0–R9 语义 → 无需更新
- `ai/skills/pallastrade-admin/SKILL.md`：本次仅在既有 `payment_methods` 编辑页新增一个只读 partial（无新页面、无新导航、无新 Stimulus 控制器、无样式 token 变化）→ 无需更新
- `ai/skills/pallastrade-checkout/SKILL.md` / `pallastrade-api-v3` / `pallastrade-storefront` / `pallastrade-i18n`：本切片零契约变化、零前台改动 → 无需更新

**后续切片待办**

- [ ] `ai/skills/pallastrade-checkout/SKILL.md`：三条链路与读模型契约（P1）
- [ ] `ai/skills/pallastrade-admin/SKILL.md`：后台菜单（Settings → Payments）与新增页面（P0-B/P3）
- [ ] `ai/skills/pallastrade-storefront/SKILL.md`：三形态渲染/骨架/一次点击（P1）
- [ ] `ai/skills/pallastrade-api-v3/SKILL.md` + `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/` + SDK 类型（接口变更时，P1/P3）
- [ ] `docs/design/payment-core.md`：设计归档（v10 方案全文）


## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-20 | 0.1 | 初稿：基于 v10 总体方案拆出 FR-001..FR-030 与 AC-001..AC-025，映射 P0–P6 七切片 | AI |
| 2026-09-20 | 0.2 | 用户确认「实施吧」→ 状态转 implementing。P0 拆为 **P0-A（厂商层地基）** 与 P0-B（后台配置写路径 + 组合策略 + 付款期限）。P0-A 已交付：`payments/providers/{config,state,validate}.rb` + `PaymentMethod#provider_{capability,account_config,effective_scope,state,diagnostics}` + 后台只读诊断卡（`[data-testid="provider-diagnostics"]`），验证器 `payment-providers-rspec`（37 例）。**本切片不改写路径**（静默归一保持现状），强制拒绝属 P0-B | AI |
