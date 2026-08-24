# PRD-20260824-checkout-正向订单-逆向订单链路重构或优化-父子单结构-系统拆单-手动拆单-合并支付-buy-now-售后

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-08-24 |
| 来源 | 正向订单、逆向订单链路重构或优化：父子单结构/系统拆单/手动拆单/合并支付/Buy Now/售后 |
| 分类 | checkout（自动判定，命中「支付/订单」关键词） |
| 关联 Skill | pallastrade-checkout、pallastrade-payments、pallastrade-api-v3、pallastrade-storefront、pallastrade-admin、pallastrade-data-model、pallastrade-security |
| 关联 REQ | REQ-20260824-order-lifecycle.md（实施时回填） |
| 关联 PRD | PRD-20260823-checkout-多订单拆分与合并支付（仅作**基线参考**；旧实现不满足需求，本次**完整重设计**） |
| 需求类型 | 新功能（正向/逆向订单链路完整重构） |

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。本次查重通过（标题相似度 ≤0.3，无同题 PRD）。
> ⚠️ **方案定位**：PRD-20260823 标记为 done 的「拆单 / 合并支付」旧实现**不被视为可复用资产**——用户明确不满意旧实现，要求**完整方案**。
> 本次按用户需求对**整个正向订单（下单/拆单/合并支付/发货）与逆向订单（售后）生命周期**做统一重设计：
> 父子单结构（Order#parent_id 自引用）、系统拆单（支付后触发）、手动拆单（跨店铺/仓库）、合并支付（与父子单联动）、Buy Now、下单前置校验、库存校验与锁库存双模式、发货触发、父子单售后。
> 旧代码（PaymentGroup、Orders::Splitter、Checkout::SplitOrders）仅作为**基线参考**，是否沿用其模型/流程由本 PRD 完整方案决定，可整体替换。

## 1. 背景与目标

- **一句话需求原文**：正向订单、逆向订单链路重构或优化：父子单结构/系统拆单/手动拆单/合并支付/Buy Now/售后。
- **补充规则（用户追加）**：
  1. **订单确认页、收银台做成公用**（三条下单链路共用）。
  2. **父子单 ID 模型**：父订单与子订单的 ID 均唯一；父订单可对应多个子订单；**若只有一笔订单且未拆单，则该订单既是父订单也是子订单**。
  3. **校验机制**：下单必须校验库存。
  4. **锁库存机制**：支持**下单锁库存**与**支付锁库存**两种方式，**在管理后台配置**。
- **背景**：
  - PallasTrade 当前订单生命周期是**单笔订单封闭模型**：一次结账 = 一笔订单 = 一次支付；订单无父子关系；拆单能力（`Orders::Splitter` / `Checkout::SplitOrders`）只在结账时按仓库触发且默认关闭，合并支付（`PaymentGroup`）与订单结构完全脱节、且状态机出现过 failed/expired 裸错误；详情页无 Buy Now；下单无前置校验；售后仅绑定单笔订单。
  - **用户对旧实现（PRD-20260823 标记 done 的拆单/合并支付）不满意，要求完整方案**——本次不是给旧实现打补丁，而是按需求对**正向 + 逆向订单链路做统一重设计**：
    1. **父子单结构**：订单有明确的父子层级（父订单 ↔ 子订单，ID 各自唯一；未拆单时父=子），前台账户与管理后台均可查看。
    2. **公用确认页 + 收银台**：详情页 Buy Now / 购物车 / 订单模块付款三条链路**共用**订单确认页与收银台。
    3. **合并支付**：多笔未支付订单可合并支付；**合并支付成功后系统判断是否需要自动拆单**。
    4. **系统拆单**：支付后系统自动把一笔订单拆成多个子订单，拆分条件：**店铺、商品仓库地址、其它（可扩展）**。
    5. **手动拆单**：管理后台把一笔订单拆成多个子单，**支持拆分到不同店铺、仓库**。
    6. **库存校验 + 锁库存**：下单必须校验库存；锁库存支持**下单锁**与**支付锁**两种模式（后台配置）。
    7. **发货**：管理后台已付款订单有发货触发机制。
    8. **售后**：保持现有售后场景，结合父子单——前台用户与后台运营均可发起；**支持子订单售后 + 整个父订单售后**。
  - **前置条件**（下单必须先满足）：必须登录；黑名单用户禁止下单；支付/风控模块评估为高风险的用户禁止下单；未登录触发下单则跳转登录。
- **父子单模型裁定（用户规则 2 优先）**：
  - 采用 **`Order` 自引用父子模型（`Order#parent_id`，可空）**：父订单与子订单都是**真实订单**、ID 各自唯一。
  - 拆单后：父订单保留（作为父，可继续发货/售后），每个子订单 `parent_id` 指向父订单；一个父订单对应 **N 个子订单**。
  - 未拆单：单笔订单 `parent_id = nil` 且无子订单 → **该订单既是父订单也是子订单**（语义上：它是所在交易组的父，也是唯一成员子单；前端可同时标注「父订单 / 子订单」）。
  - 说明：此模型与 platform 6.0 规划中的独立 `OrderGroup` 容器不同（6.0 主张「父不是订单」）；**以用户需求为准**，采用订单自引用；`OrderGroup` 不做为本 PRD 主模型（如后续多供应商/B2B 需要可再评估）。
- **目标**：
  1. **完整父子单结构**：`Order#parent_id` 自引用，父订单 ↔ 多个子订单，ID 唯一；未拆单父=子；前台账户 + 管理后台均可查看父子关系与发货进度。
  2. **公用确认页 + 收银台**：三条下单链路（A 详情页 Buy Now / B 购物车 / C 订单模块付款）共用同一订单确认页与收银台。
  3. **下单前置校验**：登录强制、黑名单拦截、风控/支付高风险拦截，服务端强制执行。
  4. **合并支付 + 支付后自动拆单联动**：多笔未支付订单一次支付 → 支付成功后按策略判断是否拆单 → 子订单挂到父订单下。
  5. **系统拆单**：可配置策略（店铺/仓库地址/其它），结账时与支付后均可触发。
  6. **手动拆单**：支持跨店铺/仓库，子订单归入同一父订单，UI 提供预览与确认。
  7. **库存校验 + 锁库存**：下单校验可售库存；锁库存支持**下单锁 / 支付锁**两种模式，后台配置。
  8. **售后父子单化**：子单售后 + 父单售后，前台/后台均可发起。
  9. **发货触发**：管理后台已付款订单（含子订单）发货入口明确。
- **成功指标**：
  - 三条链路 + Buy Now 全流程 E2E 通过（Stripe sandbox）。
  - 父子单展示正确性：拆单后前台/后台父子关系 100% 正确（RSpec + 组件测试）。
  - 前置校验：未登录下单 100% 重定向登录；黑名单/高风险用户 100% 拦截且无订单创建。
  - 库存校验：超卖防护（下单校验 + 锁库存后可用量计算正确，无超卖）。
  - 锁库存模式切换：后台切换「下单锁 / 支付锁」后行为正确（下单锁：创建订单即锁定；支付锁：仅支付成功锁定/扣减）。
  - 合并支付 → 支付后拆单联动：按配置条件拆分的子订单行项目/金额/库存/支付状态正确（service spec 覆盖）。
  - 全链路订单状态机无非法迁移（合并支付、拆单、发货、售后在各状态边界均受控）。

## 2. 用户故事 / 场景

- 作为**游客**，我希望未登录时点击下单能跳转登录，以便登录后继续购买。
- 作为**顾客**，我希望在商品详情页直接「立即购买」（Buy Now），以便跳过购物车快速下单。
- 作为**顾客**，我希望在账户里看到一次下单被拆成的多笔子订单及其父订单，以便清楚每笔订单的状态与发货进度。
- 作为**顾客**，我希望对子订单或整个父订单发起售后，以便按需退货退款。
- 作为**运营/客服**，我希望在管理后台看到父子单结构并分别发货、手动拆分（可到不同店铺/仓库），以便分仓处理。
- 作为**平台管理员**，我希望把黑名单用户与高风险用户挡在下单之外，以便降低欺诈与资损。
- 作为**平台管理员**，我希望配置支付后自动拆单规则，以便仓库/店铺不同时自动拆分。

场景列表：

- **S1（正常·链路 A）**：商品详情页 → 未登录点 Buy Now → 跳转登录 → 登录后回到确认页 → 收银台 → 结果页。
- **S2（正常·链路 B）**：购物车 → 勾选商品 → 订单确认页 → 收银台 → 结果页（含合并支付已有流程）。
- **S3（正常·链路 C）**：账户订单模块 → 状态选项卡 → 待付款订单 → 点「付款」→ 收银台 → 结果页。
- **S4（正常·父子单）**：下单后系统按仓库拆成 2 笔子订单 → 父订单保留 + 子订单 `parent_id` 指向父 → 自动进合并支付 → 一次支付 → 前台账户显示父子单关系。
- **S5（正常·Buy Now）**：详情页 Buy Now → 仅当前商品进入确认页（不影响购物车）。
- **S6（边界·合并支付后拆单）**：用户合并支付 2 笔订单 → 支付成功后系统按配置判断是否需要再拆（如某订单需按仓库拆）→ 拆分子订单并入父单关系。
- **S7（正常·手动拆单跨店）**：后台把一笔订单按行项目拆到不同店铺/仓库 → 子订单各自进入对应店铺发货流。
- **S8（正常·发货触发）**：后台已付款订单（子单或父单）→ 点击发货 → 进入 shipment 流程 → 状态推进。
- **S9（正常·子单售后）**：前台对某子订单发起售后 → 走 ReturnAuthorization 流程。
- **S10（正常·父单售后）**：前台对整个父订单（含全部子订单）发起售后 → 覆盖其下全部子订单。
- **S11（异常·黑名单）**：黑名单用户点击下单 → 拦截并提示，不创建订单。
- **S12（异常·风控）**：风控/支付模块评估高风险用户 → 下单被拦截并提示。
- **S13（异常·已取消订单）**：链路 C 中订单支付前被取消 → 付款入口置灰并提示。
- **S14（边界·拆单条件不满足）**：单店铺/单仓库下单 → 不拆单，正常单笔订单（父=子）。
- **S15（异常·库存不足）**：下单/确认时某商品可售库存不足 → 拦截并提示可售量，不创建订单。
- **S16（正常·下单锁库存）**：后台配置「下单锁库存」→ 订单确认提交即锁定库存（TTL 内有效，超时释放）。
- **S17（正常·支付锁库存）**：后台配置「支付锁库存」→ 下单仅校验，支付成功才锁定/扣减库存。
- **S18（异常·支付失败重试）**：支付失败 → 收银台提示并可重试（不重复扣款）；超时未支付订单标记过期并释放预留库存。
- **S19（正常·取消订单联动）**：客户/后台取消订单 → 库存释放 + 已支付退款 + 父子单联动 + 记录原因。
- **S20（正常·仅退款）**：客服对已发货订单发起不退货仅退款/部分退款。
- **S21（正常·换货）**：售后换货（同款/异款），库存与退款按换货规则处理。
- **S22（正常·物流跟踪）**：后台录入 tracking → 前台父子单视图可查各子订单物流状态。
- **S23（异常·防刷单）**：同用户高频下单/超量 → 风控拦截并记录事件。

## 3. 功能需求（FR）

### 阶段 0：下单前置校验（前置条件，全链路强制）
- **FR-001**：下单入口（Buy Now / 购物车结账 / 订单模块付款）统一前置校验：未登录 → 跳转登录页（登录后回跳原下单意图）。
- **FR-002**：用户黑名单：`PallasTrade::User` 增加黑名单标记（`blacklisted_at`），黑名单用户任何下单入口被拦截（服务端强制），提示文案不泄露敏感信息。
- **FR-003**：风控/支付模块高风险拦截：下单前调用风控评估（`PallasTrade::Risk` 服务：可配置规则钩子 + 默认实现），评估为高风险则拦截并记录事件；支付网关风险标记（如 Stripe risk_score）纳入判断。
- **FR-004**：前置校验统一返回结构（`code` + 可展示文案），前端按 `code` 渲染提示/跳转；校验在**服务端**执行，客户端不可绕过。

### 阶段 1：父子单结构（Order#parent_id 自引用）
- **FR-005**：`Order` 增加可空自引用 `parent_id`（FK → orders.id）+ `parent` / `children` 关联；**父订单与子订单均为真实订单、ID 各自唯一**（沿用 `or_` 前缀）。
- **FR-006**：拆单后：父订单保留（作为父，状态/支付/发货正常），子订单 `parent_id` 指向父订单；一个父订单对应 **N 个子订单**。
- **FR-007**：**未拆单时父=子**：单笔订单 `parent_id = nil` 且无子订单 → 该订单语义上**既是父订单也是子订单**；Store/Admin API 与前台/后台展示均体现此语义（可同时标注「父订单 / 子订单」）。
- **FR-008**：一次下单（结账完成）创建的订单即父订单（未拆单）或父订单+子订单（拆单后）；`split_from_id` 保留为展示用来源引用。
- **FR-009**：Store API：订单列表/详情返回父子关系（`parent_id`/`children_ids`/`is_parent`/`is_child`/兄弟摘要）；新增 `GET /api/v3/store/orders/:id/children` 与 `GET /api/v3/store/orders/:id/parent`（父订单详情：成员订单、合计、支付/发货/售后状态）。
- **FR-010**：Admin API + UI：订单详情页展示**父子树**（父订单 → 子订单 / 子订单 → 父订单），可按父子关系过滤订单列表；父订单详情聚合页（成员、支付、发货、售后汇总）。

### 阶段 2：下单链路 + Buy Now + 公用确认页/收银台
- **FR-011**：商品详情页新增「Buy Now」按钮：点击创建仅含当前商品（+数量）的快捷下单，进入**公用订单确认页**（不污染购物车）；未登录走 FR-001 跳转登录并回跳。
- **FR-012**：**订单确认页做成公用**：详情页 Buy Now / 购物车结账 / 订单模块付款 三条链路统一进入**同一订单确认页**（地址/配送/商品清单/金额），由路由参数区分来源（`?from=buy_now|cart|order`）。
- **FR-013**：**收银台做成公用**：确认页之后统一进入**同一收银台**（支付方式选择 + 支付表单 + 合并支付）；链路 C 的单订单付款与多订单合并支付复用同一收银台组件。
- **FR-014**：链路 C：账户订单模块按状态选项卡展示；待付款订单「付款」→ 单订单进入公用确认页/收银台，多订单勾选进入合并支付（同样落在公用收银台）。

### 阶段 3：库存校验 + 锁库存（后台配置）
- **FR-015**：**下单校验库存**：订单确认/提交时对每个行项目校验可售库存（`available = count_on_hand − active_reservations − allocated`，复用 `Stock::Quantifier`），不足则拦截并提示可售量；不可售/无库存商品不可下单。
- **FR-016**：**锁库存两种模式（后台配置）**：`PallasTrade::Config[:stock_reservation_strategy] = :order | :payment`（店铺级可覆盖）。
  - **下单锁库存（`:order`）**：订单创建（确认提交）即创建 `StockReservation` 锁定库存（复用 `StockReservations::Reserve`），TTL 内有效、结账活动续期、过期释放。
  - **支付锁库存（`:payment`）**：下单仅校验不锁定；**支付成功**时才创建 `StockReservation` 或直接扣减（`StockMovement`），防止下单后长时间占库存。
- **FR-017**：库存释放/扣减一致性：订单取消/超时释放预留；支付成功按模式转实扣；父子订单场景下库存按行项目归属正确分摊（父/子订单各自持有其行项目的库存预留与扣减）。

### 阶段 4：合并支付（完整重设计）
- **FR-018**：合并支付载体重新设计：多笔未支付订单（可同一父订单下、可跨父订单）组成一次**支付单**；支付单只关心「收了多少钱、覆盖哪些订单」，与父子结构解耦；状态机明确（`pending → processing → succeeded`，`failed/canceled/expired`），**任何非法迁移返回业务错误而非裸状态机错误**（吸取旧 PaymentGroup failed/expired 裸 422 教训）。
- **FR-019**：合并支付金额服务端计算（仅未支付订单计入），同 store/同用户/同币种才可合并；部分订单已支付/已取消/已过期自动剔除并重算。
- **FR-020**：合并支付成功后**立即触发拆单评估**（阶段 5 策略）：对支付覆盖的每笔订单判断是否需要自动拆单。
- **FR-021**：合并支付与拆单的资金分摊：支付成功的订单若被拆分，其已付金额/支付记录按行项目正确分摊到子订单（子订单标记已付、不重复支付）；幂等可重入。

### 阶段 5：系统拆单（支付后自动拆单 + 结账拆单，完整重设计）
- **FR-022**：拆单策略可配置（`PallasTrade::Config[:auto_split_orders]`，取代旧的 `auto_split_orders_by_warehouse` 布尔开关）：支持**按店铺 / 按商品仓库地址 / 其它（扩展点）** 分组；每个策略可配置启用与触发时点。
- **FR-023**：**支付成功后自动拆单**（核心诉求）：单笔订单支付成功 或 合并支付成功 → 对订单执行拆单评估 → 需拆则按策略分组生成多个子订单 → 挂到父订单下（`parent_id`）→ 行项目/库存/金额/支付状态正确分摊 → 发布事件。
- **FR-024**：**结账时自动拆单**（可选配置）：结账完成时同样执行拆单评估（与支付后拆单共用策略引擎），拆出子订单后进入合并支付。
- **FR-025**：拆单引擎统一入口（`PallasTrade::Orders::Splitter` 重构）：`split(order, groups, options)` 支持目标店铺/仓库、设置 `parent_id`、分摊已付金额、幂等；拆单结果事件 `order.splitted`（父订单/子订单）。
- **FR-026**：拆单条件不满足时不拆（单店/单仓），保持单笔订单（父=子）。

### 阶段 6：手动拆单（跨店铺/仓库）
- **FR-027**：Admin `POST /api/v3/admin/orders/:id/split` 扩展：支持指定目标店铺（`store_id`）与目标仓库（`stock_location_id`），同店/同仓保持原有行为。
- **FR-028**：跨店铺拆单重算：子订单按目标店铺重算价格/税率/配送方式（行项目迁移 + OrderUpdater）；目标店铺无该商品/无可用配送返回明确错误。
- **FR-029**：手动拆分子订单 `parent_id` 指向原订单（同一父订单）；Admin UI 展示拆分预览（目标店铺/仓库/行项目/金额）与确认。
- **FR-030**：Admin UI 订单详情「拆分订单」入口增强：目标店铺/仓库选择、行项目数量、预览与确认。

### 阶段 7：发货触发
- **FR-031**：管理后台已付款订单（含子订单）「发货」触发机制：订单详情明确入口 → 进入 shipment 流程（`ship`），父子单场景下可对子订单单独发货。
- **FR-032**：发货状态在父子单视图中体现（父订单展示各子订单发货进度）。

### 阶段 8：售后（保持现有流程 + 父子单化）
- **FR-033**：保持现有售后链路（ReturnAuthorization → CustomerReturn → Reimbursement → Refund）与前台/后台入口。
- **FR-034**：子订单售后：前台/后台可对**单个子订单**发起售后。
- **FR-035**：父单售后：前台/后台可对**整个父订单（含全部子订单）** 发起售后 → 展开为其下全部子订单的售后（批量创建 ReturnAuthorization），金额/退款按子订单归集；幂等。
- **FR-036**：售后视图展示归属（子订单 / 父订单）；后台可按父订单查看售后汇总。

### 阶段 9：结算与支付增强（独立站标配衔接）
- **FR-037**：**多支付方式收银**：公用收银台支持多种支付方式（Stripe 信用卡 / 数字钱包 Apple Pay·Google Pay / BNPL·本地支付扩展点 / COD 货到付款可选），后台配置启用与顺序；未配置的方式不展示（复用 `PallasTrade.payment_methods` 体系）。
- **FR-038**：**税费与运费衔接**：确认页/收银台展示税费与运费（服务端计算，复用 `TaxRate`/adjuster 与 shipment 运费计算）；**拆单后税费/运费随行项目与配送正确分摊到各子订单**（总额守恒）。
- **FR-039**：**促销优惠拆单分摊**：订单级优惠（优惠码/促销折扣）在拆单时按行项目金额比例分摊到子订单，总额守恒、不重复计算、不丢失（复用 `Adjustable::Adjuster::Promotion` 扩展）。
- **FR-040**：**支付失败重试与超时**：支付失败可重试（幂等、不重复扣款）；未支付订单超时（TTL 可配置）标记过期并释放预留库存；支付中（processing）断点可恢复。
- **FR-041**：**订单取消联动**：客户（未支付/未发货）与后台均可取消订单；取消联动**库存释放**（按锁库存模式）、**退款**（已支付走 Refund）、**父子单**（父取消→子订单联动处理 / 仅取消指定子订单）、记录取消原因（复用 `OrderCancellation`）。

### 阶段 10：订单服务与体验（独立站标配）
- **FR-042**：**订单备注**：客户下单备注 + 后台内部备注（内部备注不对客户可见），父子单可分别备注。
- **FR-043**：**订单状态时间线/审计**：记录订单状态变更历史（时间/动作/操作者/从→到），前台展示关键节点（下单/支付/发货/完成），后台完整审计。
- **FR-044**：**订单通知**：下单/支付成功/发货/完成/售后等邮件通知（复用 `EmailTemplate`），父子单场景按子订单独立通知（复用现有邮件体系 + i18n）。
- **FR-045**：**地址校验与编辑**：下单时地址格式/邮编/国家支持校验（复用 `Address` 校验），确认页可编辑收货地址。
- **FR-046**：**支付信息展示**：结果页与订单详情展示支付方式/金额/交易号（脱敏），父子单分别展示各自支付信息。

### 阶段 11：逆向订单增强（独立站标配）
- **FR-047**：**仅退款 / 部分退款**：不退货直接退款（客服/后台发起，复用 Reimbursement 链）；支持部分行项目退款。
- **FR-048**：**换货（Exchange）**：售后换货（同款换 / 异款换），与子订单/父订单售后联动（复用 `Exchange` 模型）。
- **FR-049**：**退货物流**：退货地址配置、退货运单号/跟踪号录入、退货签收；前台可查退货物流状态。
- **FR-050**：**RMA 编号**：售后单（RA/CR）唯一编号（前缀），前台/后台可查询。

### 阶段 12：履约与批量（独立站标配）
- **FR-051**：**物流跟踪展示**：发货录入 tracking number + 物流商（复用 `shipment.tracking`），前台父子单视图可查各子订单物流。
- **FR-052**：**批量操作**：后台批量发货 / 批量取消 / 批量导出订单（CSV，含父子单维度）。

### 阶段 13：风控增强（独立站标配）
- **FR-053**：**下单频率/数量限制**：风控规则（FR-003 扩展）支持下单频率限制与单次数量上限（防刷单）；评估维度扩展（IP / 设备指纹 / 地址风险），命中拦截并记录事件。

## 4. 非功能需求（NFR）

- **安全**：前置校验（登录/黑名单/风控）服务端强制执行，客户端不可绕过；拦截提示不泄露敏感规则；金额一律服务端计算（沿用支付规范）。
- **幂等**：支付后拆单、合并支付完成、售后批量创建均幂等可重入（重复事件不重复拆/不重复建/不重复支付）。
- **状态机健壮性**：支付单/订单/售后各状态机非法迁移返回**业务错误**（结构化 `code` + 文案），绝不裸抛状态机错误或写脏 errors（吸取旧 PaymentGroup 422 教训）。
- **兼容**：`split_from_id`、单笔订单结账路径向后兼容；新增列均为可空 FK；旧 `PaymentGroup` 数据通过迁移升级到新支付单设计。
- **性能**：父子单查询避免 N+1（`includes`）；父订单子订单数上限（默认 50，可配置）；库存查询走 `Quantifier` 缓存。
- **可维护性**：拆单策略与风控评估走可配置扩展点（Config + Service 注入）；能力沉淀进 checkout/payments/admin/storefront Skill。
- **数据一致性**：拆分/合并/售后操作在事务内完成；跨店铺拆单涉及价格重算时以目标店铺规则为准并在结果中注明差异。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：未登录访问下单入口（Buy Now/结账/付款）→ 重定向登录页，登录后回跳原下单意图（request/component 测试）。
- **AC-002 ← FR-002**：黑名单用户调用下单 API → 返回拦截（403/422 + code），数据库不产生订单（request spec）。
- **AC-003 ← FR-003**：风控评估高风险用户下单 → 拦截并记录事件；规则钩子可注入自定义实现（service spec）。
- **AC-004 ← FR-004**：拦截结果含 `code` + 文案，前端按 code 渲染；服务端强制不可绕过（component + request spec）。
- **AC-005 ← FR-005**：`Order#parent_id` 可空自引用 FK + `parent`/`children` 关联；父/子订单 ID 各自唯一（model spec + schema）。
- **AC-006 ← FR-006**：拆单后父订单保留、子订单 `parent_id` 指向父；一个父订单可对应多个子订单（model/service spec）。
- **AC-007 ← FR-007**：未拆单单笔订单 `parent_id=nil` 且无子订单 → API/展示体现「父=子」（request/component 测试）。
- **AC-008 ← FR-008**：一次下单创建的订单即父订单（未拆单）或父+子（拆单后）；`split_from_id` 保留（service spec）。
- **AC-009 ← FR-009**：Store API 订单响应含父子关系（`parent_id`/`children_ids`/`is_parent`/`is_child`）；`GET /orders/:id/children` 与 `/orders/:id/parent` 正确（request spec）。
- **AC-010 ← FR-010**：Admin 订单详情展示父子树、可按父子关系过滤、父订单聚合页（admin 测试）。
- **AC-011 ← FR-011**：详情页 Buy Now 点击后进入公用确认页且不改购物车（component 测试）。
- **AC-012 ← FR-012**：三条链路（Buy Now/购物车/订单付款）进入**同一订单确认页**（组件复用断言）（component/E2E）。
- **AC-013 ← FR-013**：确认页后统一进入**同一收银台**；单订单付款与合并支付复用同一收银台组件（component/E2E）。
- **AC-014 ← FR-014**：链路 C 待付款订单「付款」进入收银台并完成支付（E2E/组件测试）。
- **AC-015 ← FR-015**：下单/确认提交时行项目库存校验：可售量不足拦截并提示；不可售商品不可下单（service/request spec）。
- **AC-016 ← FR-016**：锁库存两种模式后台可配置：`:order` 下单即锁；`:payment` 支付成功才锁/扣减（service + config spec）。
- **AC-017 ← FR-017**：取消/超时释放预留；支付成功按模式转实扣；父子订单库存按行项目正确分摊（service spec）。
- **AC-018 ← FR-018**：支付单状态机明确，非法迁移返回业务错误（非裸状态机 422）；多笔订单合并支付成功（service/request spec）。
- **AC-019 ← FR-019**：合并支付金额服务端计算；已付/已取消/已过期订单自动剔除并重算（service spec）。
- **AC-020 ← FR-020**：合并支付成功后触发拆单评估（service spec）。
- **AC-021 ← FR-021**：支付后拆单资金分摊正确：子订单继承已付状态、不重复支付、幂等可重入（service spec）。
- **AC-022 ← FR-022**：拆单策略可配置（店铺/仓库/扩展），取代旧布尔开关（service spec）。
- **AC-023 ← FR-023**：支付成功后自动拆单：子订单行项目/库存/金额/支付状态正确、`parent_id` 指向父订单（service spec）。
- **AC-024 ← FR-024**：结账时自动拆单（可选配置）与支付后拆单共用策略引擎（service spec）。
- **AC-025 ← FR-025**：拆单引擎统一入口支持目标店铺/仓库、设置 `parent_id`、幂等；发布 `order.splitted` 事件（service + subscriber spec）。
- **AC-026 ← FR-026**：单店/单仓下单不拆单（父=子）（service spec 回归）。
- **AC-027 ← FR-027**：Admin split API 支持 `store_id`/`stock_location_id`（request spec）。
- **AC-028 ← FR-028**：跨店铺拆单子订单按目标店铺重算价格/税率/配送；目标店无商品返回明确错误（service spec）。
- **AC-029 ← FR-029**：手动拆分子订单 `parent_id` 指向原订单；Admin UI 展示拆分预览（service + admin 测试）。
- **AC-030 ← FR-030**：Admin 订单详情拆分入口含目标店铺/仓库/行项目选择与预览确认（admin 测试）。
- **AC-031 ← FR-031**：后台已付款订单（含子订单）可触发发货，shipment 状态正确推进（request/feature spec）。
- **AC-032 ← FR-032**：父子单视图展示各子订单发货进度（组件/admin 测试）。
- **AC-033 ← FR-033**：现有售后链路与入口保持可用（回归测试）。
- **AC-034 ← FR-034**：可对单个子订单发起售后（request spec）。
- **AC-035 ← FR-035**：可对整个父订单（含全部子订单）发起售后 → 批量创建其下全部子订单的 ReturnAuthorization，金额/退款按子订单归集、幂等（service spec）。
- **AC-036 ← FR-036**：售后记录展示归属子订单/父订单；后台可按父订单查看售后汇总（admin 测试）。
- **AC-037 ← FR-037**：收银台按后台配置展示多种支付方式（卡/钱包/BNPL/COD），未配置方式不显示（component + request spec）。
- **AC-038 ← FR-038**：确认页/收银台税费与运费服务端计算；拆单后税费/运费分摊正确、总额守恒（service spec）。
- **AC-039 ← FR-039**：订单级优惠拆单分摊正确（金额比例分摊、总额守恒、不重复）（service spec）。
- **AC-040 ← FR-040**：支付失败可重试不重复扣款；未支付订单超时过期并释放预留；processing 断点可恢复（service/request spec）。
- **AC-041 ← FR-041**：客户/后台取消订单 → 库存释放（按模式）+ 退款（已支付）+ 父子单联动 + 记录原因（service spec）。
- **AC-042 ← FR-042**：客户备注与内部备注分开存储，内部备注对客户不可见（model/request spec）。
- **AC-043 ← FR-043**：订单状态变更历史记录完整；前台展示关键节点、后台完整审计（model/admin 测试）。
- **AC-044 ← FR-044**：下单/支付/发货/完成/售后邮件通知触发（复用 EmailTemplate）；父子单按子订单独立通知（request/subscriber spec）。
- **AC-045 ← FR-045**：下单地址格式/邮编校验；确认页可编辑收货地址（component/request spec）。
- **AC-046 ← FR-046**：结果页与订单详情展示支付方式/金额/脱敏交易号；父子单分别展示（component 测试）。
- **AC-047 ← FR-047**：不退货直接退款（仅退款）与部分行项目退款可用（service/request spec）。
- **AC-048 ← FR-048**：售后换货（同款/异款）可用，与父子单售后联动（service spec）。
- **AC-049 ← FR-049**：退货地址配置、退货运单号/跟踪号录入、退货签收，前台可查（request/admin 测试）。
- **AC-050 ← FR-050**：售后单（RA/CR）有唯一编号，前台/后台可查询（model/request spec）。
- **AC-051 ← FR-051**：发货录入 tracking + 物流商；前台父子单视图可查各子订单物流（component/request spec）。
- **AC-052 ← FR-052**：后台批量发货/批量取消/CSV 导出可用（admin/feature spec）。
- **AC-053 ← FR-053**：风控支持下单频率/数量限制与 IP/设备/地址维度，命中拦截并记录（service spec）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | split / 父子单 / buy now / blacklist / risk / stock / 售后 | 无匹配（本项目自定义层无相关实现） | ❌ 需新建/引 core |
| Core | `pallastrade_gems/pallastrade_core/app/` | `split_from_id`、`Splitter`、`auto_split`、`parent_order`、`ReturnAuthorization`/`CustomerReturn`/`Reimbursement`、`blacklist`、`risk`、`StockReservation`/`Quantifier`/`AvailabilityValidator` | `orders/splitter.rb`（行项目拆分）、`checkout/split_orders.rb`（结账按仓自动拆）、`payment_group.rb`（pg_ 支付组）、`return_authorization.rb`/`customer_return.rb`/`reimbursement.rb`/`refund.rb`（售后链）、`stock_reservation.rb`（res_ 锁库存）、`stock/quantifier.rb`（可用量）、`stock_reservations/{reserve,release,extend}.rb`、`line_item.rb`（Stock::AvailabilityValidator）、`promotion.rb#blacklisted?`（促销黑名单，非用户级） | ⚠️ 拆单/合并支付/售后/锁库存基础已具备；**Order#parent_id 自引用父子结构**、用户黑名单、风控评估、支付后拆单、锁库存双模式需新建/改造 |
| API | `pallastrade_gems/pallastrade_api/app/` | `payment_groups`、`orders/:id/split`、`returns`、`customers/me/orders`、`stock_reservations` | `store/payment_groups_controller.rb`、`store/payment_groups/*`（合并支付）、`admin/payment_groups_controller.rb`、admin `orders` split 端点、store `customers/me/orders`（状态选项卡 scope）、admin `stock_reservations_controller.rb` | ⚠️ 合并支付/拆单/锁库存管理端点已具备；需新增父子关系端点（children/parent）、前置校验、售后父子单端点 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `split_order`、`shipments#ship`、`payment_groups`、`return`、`stock` | `orders_controller.rb#split_order`、`shipments_controller.rb#ship`（发货已具备）、`views/pallastrade/admin/payment_groups`、售后管理（ReimbursementTypes 等）、库存/库存预留管理页 | ⚠️ 发货/手动拆单/售后/库存管理已具备；需补父子树展示、跨店拆单 UI、锁库存模式配置页 |
| Storefront | `storefront/src/` | `checkout`、`cart`、`products/[slug]`、`account/orders`、`combined-payment`、`buy now` | `(checkout)/checkout/[id]/`（确认页+收银台）、`(checkout)/confirm-payment/[id]/`、`(checkout)/order-placed/[id]/`、`(storefront)/cart/`、`products/[slug]/ProductDetails.tsx`（**无 Buy Now**）、`account/orders`（状态选项卡+付款）、`account/combined-payment/[id]`（合并收银台） | ❌ 详情页无 Buy Now；确认页/收银台需抽公用；未登录跳转、黑名单/风控提示、父子单展示需新建 |
| Platform | `platform/packages/` | `OrderGroup`、`paymentGroup`、`order`、`buyNow`、`risk`、`stockReservation` | `sdk` 订单/支付组类型；`platform/docs/plans/6.0-multi-vendor-marketplace.md`（**OrderGroup 独立模型裁定**——本 PRD 以用户规则 2 为准改用 `Order#parent_id` 自引用）、`6.0-stock-reservations.md`（锁库存规划）、`6.0-returns-exchanges-claims.md`（售后升级规划） | ⚠️ SDK 需补父子关系/前置校验/锁库存配置类型；6.0 规划作参考，父子模型以用户需求为准 |

**结论**：
- **基线参考（旧实现不视为可复用资产，按完整方案重设计）**：
  - `PaymentGroup`（合并支付）——状态机/边界处理需按 FR-018~021 重设计（非法迁移返回业务错误、支付后拆单联动）。
  - `Orders::Splitter` / `Checkout::SplitOrders`（拆单）——需重构为统一拆单引擎（FR-025）：策略化、支付后触发、跨店铺、设置 `parent_id`、资金分摊、幂等。
  - 锁库存基础（`StockReservation`/`Quantifier`/`Reserve`/`Release`）——保留底层能力，新增**下单锁/支付锁双模式配置**（FR-016）。
  - 售后链（RA/CR/Reimb/Refund）与 Admin 发货（shipments#ship）——作为底层能力保留，补父子单维度。
- **需新建（本次核心增量）**：① `Order#parent_id` 自引用父子结构（父=子语义）+ 前台/后台展示；② Buy Now + 公用确认页/收银台；③ 下单前置校验（登录/黑名单/风控）；④ 合并支付重设计 + 支付后拆单联动；⑤ 系统拆单策略引擎；⑥ 跨店铺手动拆单；⑦ 下单库存校验 + 锁库存双模式配置；⑧ 父单维度售后。
- **防重复判定**：与 PRD-20260823 为「基线参考 → 完整重设计」关系（非继承复用）；父子模型采用 **`Order#parent_id` 自引用**（以用户规则 2 为准，与 6.0 OrderGroup 独立容器裁定不同，已在 §1 说明）。

## 6.5 独立站标准能力自检（跨境电商独立站视角）

对照主流跨境电商独立站（Shopify / BigCommerce / WooCommerce）订单生命周期标配能力，逐项判定本次覆盖范围：

| 能力域 | 独立站标配能力 | 现状 / 本次处理 | 范围判定 |
|---|---|---|---|
| 下单链路 | 详情页直接购买 / 购物车 / 再次购买 | Buy Now（FR-011）+ 购物车结账 + 订单模块付款（FR-014） | ✅ 本次 |
| 订单确认 | 地址 / 配送 / 税费 / 优惠 / 金额确认 | 公用确认页（FR-012）+ 税费运费展示（FR-038）+ 地址校验编辑（FR-045） | ✅ 本次 |
| 收银台 | 多支付方式 / 数字钱包 / BNPL / 本地支付 / COD | 公用收银台（FR-013）+ 多支付方式（FR-037） | ✅ 本次 |
| 订单结构 | 订单拆分 / 合并 / 父子层级 | `Order#parent_id` 父子单 + 系统拆单 + 手动拆单 + 合并支付 | ✅ 本次 |
| 库存 | 校验 / 预留 / 扣减 / 超卖防护 | 下单校验（FR-015）+ 锁库存双模式（FR-016/017） | ✅ 本次 |
| 支付 | 失败重试 / 超时 / 幂等 / 部分支付 | 重试与超时（FR-040）+ 支付单重设计（FR-018~021） | ✅ 本次 |
| 取消 | 客户/后台取消 + 退款 + 库存释放 + 原因 | FR-041（复用 OrderCancellation） | ✅ 本次 |
| 优惠 | 优惠码 / 促销（订单级）→ 拆单分摊 | FR-039（复用 Promotion adjuster） | ✅ 本次 |
| 税费 | 销售税 / VAT（已有）→ 拆单分摊 | FR-038（复用 TaxRate/adjuster） | ✅ 本次衔接 |
| 物流 | tracking / 物流商（已有）→ 父子单展示 | FR-051（复用 shipment.tracking） | ✅ 本次衔接 |
| 通知 | 邮件通知（已有）→ 父子单独立通知 | FR-044（复用 EmailTemplate） | ✅ 本次衔接 |
| 售后 | 退货 / 退款 / 仅退款 / 部分退款 / 换货 / RMA / 退货物流 | FR-033~036 + FR-047~050（复用 RA/CR/Reimb/Refund/Exchange） | ✅ 本次 |
| 订单服务 | 备注 / 状态时间线 / 支付信息脱敏展示 | FR-042 / 043 / 046 | ✅ 本次 |
| 履约 | 批量发货 / 批量取消 / CSV 导出 | FR-052 | ✅ 本次 |
| 风控 | 黑名单 / 高频防刷 / IP·设备·地址维度 | FR-002 / 003 + FR-053 | ✅ 本次 |
| 发票 PDF | 自动发票 / 下载 | 未纳入本次 | 🔵 后续扩展 |
| 争议 / 拒付 | chargeback 工作流 | 未纳入（支付网关层） | 🔵 后续扩展 |
| 订阅 / 预购 | 周期订阅 / 预购 | 未纳入（`6.0-preorders.md` 另有规划） | 🔵 后续扩展 |
| 多地址配送 | 一单多地址 | 未纳入 | 🔵 后续扩展 |
| 多币种结算 | 展示币种 vs 结算币种 | 现有多币种基础上本次不扩展 | 🔵 后续扩展 |

**自检结论**：
- 本次以「正向 + 逆向订单生命周期重构」为边界，覆盖独立站标配的**核心能力**；底层已具备的税费 / 物流 / 通知 / 换货 / 取消等通过 FR 衔接复用，不重复实现。
- 🔵 标注扩展项（发票 PDF / 争议拒付 / 订阅预购 / 多地址 / 多币种结算）与本次链路重构解耦，建议作为后续独立 PRD。

## 7. 技术影响

- **新增模型 / 迁移**：
  - `orders.parent_id`（可空自引用 FK，`index`）——父子单结构；`orders.split_from_id` 保留
  - 用户黑名单标记（`pallastrade_users.blacklisted_at`，可空）
  - `pallastrade_risk_events`（风控拦截事件日志）
  - 支付单（合并支付载体）状态机按 FR-018 重设计（迁移或改造 `payment_groups` 表）
  - 锁库存策略配置（`PallasTrade::Config[:stock_reservation_strategy]` + 店铺级覆盖）
- **Core 层**：
  - `Order` 增加 `parent_id`/`parent`/`children` 关联与作用域（`is_parent`/`is_child`/父=子语义）
  - **拆单引擎重构**：`PallasTrade::Orders::Splitter`（统一入口：策略分组 / 目标店铺仓库 / 设置 `parent_id` / 资金分摊 / 幂等）
  - 拆单策略注册：`PallasTrade::Config[:auto_split_orders]`（按店铺 / 仓库地址 / 扩展），结账 + 支付后两时点触发
  - 合并支付载体按 FR-018~021 重设计（非法迁移业务错误、支付后拆单联动、资金分摊）
  - 新服务 `PallasTrade::Checkout::Guard`（登录/黑名单/风控前置校验）+ `PallasTrade::Risk`（评估钩子）
  - 库存：下单库存校验（复用 `Stock::Quantifier`）；锁库存双模式（下单锁/支付锁）策略化封装（复用 `StockReservations::Reserve/Release`）
  - 售后：父订单级售后批量服务（展开子订单 RA，幂等）
- **API 层**：
  - Store：`GET /api/v3/store/orders/:id/children` 与 `GET /api/v3/store/orders/:id/parent`；订单响应含父子关系；前置校验拦截响应结构（`code`）；合并支付端点按新设计调整；支付方式列表 / 订单备注 / 时间线 / 售后单（RMA）端点
  - Admin：`orders/:id/split` 扩展 `store_id`/`stock_location_id`；父子关系过滤；锁库存模式配置；取消联动 / 批量操作 / CSV 导出 / 仅退款·换货·退货物流 / 风控规则配置端点
  - 同步 `backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`
- **Storefront**：
  - 详情页 Buy Now 按钮 + 快捷下单（不改购物车）
  - **公用订单确认页 + 公用收银台**（三条链路复用；`?from=buy_now|cart|order`）
  - 登录跳转拦截（前置校验）与黑名单/风控提示页
  - 账户订单/详情父子单展示（父=子标注）；合并支付收银台按新支付单设计适配
- **Admin UI**：
  - 订单详情父子树 + 父订单聚合页 + 跨店拆分 UI（预览）+ 发货入口强化 + 售后父子单视图 + 拆单策略配置 + 锁库存模式配置
- **Platform**：`@pallastrade/sdk` 补父子关系 / 前置校验 / 合并支付新契约 / 锁库存配置 / 售后父子单类型与客户端方法
- **影响面**：涉及 core / api / admin / storefront / sdk 多包，实施时运行 `harness affected --base origin/main` 确认。

## 8. 测试计划

- **新增测试**：
  - `backend/spec/models/pallastrade/order_spec.rb`（父子关联：parent/children/父=子语义 AC-005/006/007/008）
  - `backend/spec/services/pallastrade/checkout/guard_spec.rb`（AC-001/002/003/004）
  - `backend/spec/services/pallastrade/risk_spec.rb`（AC-003/053）
  - `backend/spec/services/pallastrade/checkout/stock_guard_spec.rb`（下单库存校验 AC-015）
  - `backend/spec/services/pallastrade/stock_reservations/strategy_spec.rb`（锁库存双模式 AC-016/017）
  - `backend/spec/services/pallastrade/orders/splitter_spec.rb`（重构后引擎：策略/跨店/资金分摊/优惠税费运费分摊/幂等/设置 parent_id AC-023/025/027/028/029/038/039）
  - `backend/spec/services/pallastrade/checkout/split_orders_spec.rb`（策略化 + 支付后 AC-022/023/024/026）
  - `backend/spec/services/pallastrade/payments/payment_group_spec.rb`（重设计支付单：状态机/非法迁移/资金分摊/重试 AC-018/019/020/021/040）
  - `backend/spec/services/pallastrade/payments/payment_methods_spec.rb`（多支付方式收银 AC-037）
  - `backend/spec/services/pallastrade/orders/cancel_spec.rb`（取消联动：库存/退款/父子单 AC-041）
  - `backend/spec/services/pallastrade/orders/status_timeline_spec.rb`（状态时间线 AC-043）
  - `backend/spec/services/pallastrade/returns/group_return_spec.rb`（父单售后 AC-035）
  - `backend/spec/services/pallastrade/returns/refund_only_spec.rb`（仅退款/部分退款 AC-047）
  - `backend/spec/services/pallastrade/returns/exchange_spec.rb`（换货 AC-048）
  - `backend/spec/requests/api/v3/store/orders_children_parent_spec.rb`（AC-009）
  - `backend/spec/requests/api/v3/admin/orders_split_spec.rb`（跨店 AC-027/028）
  - `backend/spec/requests/api/v3/store/payment_groups_spec.rb`（重设计契约 AC-018/019）
  - `backend/spec/requests/api/v3/store/payment_methods_spec.rb`（AC-037）
  - `storefront/src/components/product/__tests__/BuyNowButton.test.tsx`（AC-011）
  - `storefront/src/components/checkout/__tests__/SharedCheckoutPage.test.tsx`（公用确认页/收银台 AC-012/013）
  - `storefront/src/app/**/orders/__tests__/ParentChildView.test.tsx`（父子单展示 AC-010/032/051）
  - `storefront/src/components/checkout/__tests__/PaymentMethodSelector.test.tsx`（多支付方式 AC-037）
- **更新测试**：
  - `backend/spec/services/pallastrade/payment_groups/create_spec.rb`（按新支付单设计重构 AC-018/020/021）
  - `backend/spec/requests/api/v3/store/customer/orders_spec.rb`（响应含父子关系 AC-009）
  - `backend/spec/models/pallastrade/stock_item_spec.rb` / `stock/quantifier_spec.rb`（可用量含预留 AC-015/016）
  - `backend/spec/models/pallastrade/shipment_spec.rb`（tracking 录入 AC-051）
  - `backend/spec/models/pallastrade/order_cancellation_spec.rb`（取消联动 AC-041）
  - `storefront` 现有 checkout / cart / orders / combined-payment 测试（链路回归 + 前置校验 + 公用页 AC-001/012/013/014）
  - `backend/spec/requests/.../returns*`（售后回归 AC-033/034/036/047/048/049/050）
- **AC 映射**：AC-001~053 → 上述文件逐一覆盖；无测试的 AC 不允许标记 done。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/*.yaml`（父子关系端点 / split 扩展 / 锁库存配置 / 支付方式列表 / 订单备注·时间线 / 仅退款·换货·退货物流·RMA / 批量操作·CSV / 风控规则 / 前置校验响应 / 售后父子单）
- [ ] Skill：`pallastrade-checkout`（下单链路 + 前置校验 + 拆单策略 + 公用确认页/收银台）、`pallastrade-payments`（支付单重设计 + 多支付方式）、`pallastrade-admin`（父子树 + 跨店拆分 + 发货 + 锁库存配置 + 批量操作）、`pallastrade-storefront`（Buy Now + 公用页 + 父子单展示 + 多支付方式选择）、`pallastrade-data-model`（Order#parent_id 父子模型）、`pallastrade-security`（黑名单/风控/防刷）、`pallastrade-shipping-fulfillment`（物流跟踪 + 发货触发）、`pallastrade-events-webhooks`（订单通知 + 拆单事件）、`pallastrade-taxation`（税费拆单分摊）
- [ ] SDK：`platform/packages/sdk` 类型 + README（`@pallastrade/sdk` orders 父子关系 / stockReservation 配置 / paymentMethods / 售后单）
- [ ] 6.0 规划联动：`platform/docs/plans/6.0-multi-vendor-marketplace.md`（OrderGroup 裁定 vs 用户采用 parent_id 的差异说明）、`6.0-stock-reservations.md`（锁库存双模式对齐）、`6.0-returns-exchanges-claims.md`（售后父子单对齐）
- [ ] 场景库：`harness/scenarios/scenarios.json`（GS 新增：下单前置校验 / Buy Now / 父子单 / 支付后拆单 / 库存校验与锁库存双模式 / 多支付方式 / 取消联动 / 仅退款换货 / 父单售后 / 防刷单）
- [ ] 反模式库 / 任务规则（如涉及新规则）
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态流转
- [ ] `harness/requirements/REQ-20260824-order-lifecycle.md`（实施时生成）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-24 | 0.1 | 初稿：6 层跨层搜索 + FR/AC（按旧实现「复用」视角） | AI |
| 2026-08-24 | 0.2 | **完整重设计**：用户明确不满意旧拆单/合并支付实现；移除「复用已 done」预设；FR 重构为 7 阶段 32 条；AC 同步 32 条；NFR 增状态机健壮性 | AI |
| 2026-08-24 | 0.3 | **新增 4 条用户规则**：① 订单确认页/收银台公用（FR-012/013）；② 父子单改 **Order#parent_id 自引用**（父/子 ID 唯一、未拆单父=子，替代 OrderGroup，FR-005~010）；③ 下单校验库存（FR-015）；④ 锁库存双模式（下单锁/支付锁，后台配置，FR-016/017）；FR 扩为 8 阶段 36 条，AC 同步 36 条；跨层搜索补库存层 | AI |
| 2026-08-24 | 0.4 | **独立站标准能力自检查漏补缺**：新增 §6.5 自检对照表；FR 扩为 13 阶段 53 条（新增：多支付方式收银 FR-037、税费运费拆单分摊 FR-038、促销拆单分摊 FR-039、支付失败重试/超时 FR-040、取消联动 FR-041、备注/时间线/通知/地址校验/支付展示 FR-042~046、仅退款/换货/退货物流/RMA FR-047~050、物流跟踪/批量操作 FR-051/052、防刷单风控维度 FR-053）；AC 同步 53 条；明确税费/物流/通知/换货/取消等底层能力为「复用衔接」 | AI |
