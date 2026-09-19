# PRD-20260919-shipping-checkout-quote-preview

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-19 |
| 来源 | 用户原话：「checkout页面 order summary区块显示：Shipping Calculated at submit；Estimated taxes Calculated at submit 你觉得这合理吗？」→ 讨论收敛为「默认选中第一个配送方式 + 填地址前后由服务端估算运费/税费（AJAX 无刷新）」→「实施」 |
| 分类 | shipping（关键词命中） |
| 关联 Skill | `pallastrade-storefront` / `pallastrade-payments` / `pallastrade-api-v3` / `pallastrade-testing` / `pallastrade-checkout` |
| 关联 REQ | REQ-20260919-shipping-checkout-quote-preview.md |
| 关联 PRD | `PRD-20260919-checkout-order-summary-fee-read-model`（第 5 项 A2：三级读模型，"诚实降级"）与其研究文档 `docs/research/RESEARCH-20260919-checkout-cart-level-quote-feasibility.md`（A1 不可直接实现 + 触发条件）。**本 PRD 即触发条件 1（"确认页之前就要有权威金额"）的落地**，但采用**只读 dry-run 预览**而不是车级定价重构。 |
| 需求类型 | 优化迭代（前台 + 核心服务只读模式 + 新接口契约） |

## 1. 背景与目标

### 1.1 现象（用户可感知缺陷）

1. **同一页面自相矛盾**：第 3 节「配送方式」已显示每个方式的费率标签（`method.display_estimated_price`，如 `$5.00`），而右栏 Order Summary 的运费行却写「提交订单时计算」（`checkout.calculatedAtSubmit`）。
2. **默认无选中**：`shippingMethodId` 初值 = `cart.shipping_method_id ?? ""`（`UnifiedCheckout.tsx:482`），车未存过方式时单选全空，而 `canSubmit` 要求非空 → 顾客必须手点一次才能付款。
3. **header 国家没被用上**：`GET /api/v3/store/shipping_methods` 早已支持 `?country=`（PRD-20260916 F-2），但前台 `getShippingMethods()` 从不传参（`shopping-cart.ts:158-163`）。
4. **税费同样只写"提交时计算"**，即使税区在无地址时有 `Zone.default_tax` 兜底（`order.rb:527-531`）。

### 1.2 根因

- 车（`pallastrade_carts`）不持金额；权威运费/税只在 Order 管线产生（`Carts::Submit` → `create_proposed_shipments` → `ensure_available_shipping_rates` → 选中 `shipping_rate` → `set_shipments_cost`；`Order#create_tax_charge!`）。
- 第 5 项 A2 解决的是"**不骗人**"（未知→短标签），没有解决"**提前知道**"；研究文档结论：车级定价不可直接实现，但 dry-run 预览（A1-a）是可行候选。

### 1.3 目标

1. 方式列表按 **header 国家**过滤（用上已存在的 `?country=`，与页面显示口径一致）；
2. **服务端只读预览报价**：与 `Carts::Submit` **同源代码路径**（dry-run + 回滚），返回运费/税/折扣/应付的**估算**；
3. **默认选中由服务端决定**（管道口径：费率按成本升序、最便宜为默认），前台不再自己按名称挑第一个；
4. 地址/配送方式变更时 **AJAX 重取**（防抖 + 竞态保护 + 微加载态），无地址时用 header 国家作**临时地址**；
5. 不可计价的方式**显式给出原因**（如"填写地址后显示"），不可判定时保留既有诚实降级（`calculatedAtSubmit`）。

### 1.4 成功指标

- 结算页首次渲染后，右栏运费/税费**立即是金额**（在有可计价方式且存在税率时），不再出现"提交时计算"；
- 无地址 → 有地址的过程中，金额随地址更新且**不闪空/不闪 0**；
- `preview` 与同参数 `prepare` 的金额一致（除时间效应），由 spec 锁定；
- dry-run **零写库、零事件、零作业、零外呼**，由 spec 锁定。

## 2. 用户故事 / 场景

1. 作为**买家**，我进入结算页就应看到运费与税费的估算金额（而不是"提交时计算"），并且配送方式已被默认选中，我可以直接付款。
2. 作为**买家**，我只想改邮编/州，页面对应的金额应当**自动刷新**，不需要点任何"重新计算"。
3. 作为**买家（跨区购物）**，我在 `DE` 站点浏览但寄往 `US`：未填地址时按 `DE` 估算（可解释），填了 `US` 地址后立即按 `US` 重算。
4. 作为**买家**，某个配送方式在我填州之前**无法计价**，页面应告诉我"填写地址后显示"，而不是把它藏掉或显示 0。
5. **边界**：纯数字商品车 → 无配送方式，不渲染运费行（保持现状）。
6. **异常**：预览接口失败或不可判定 → 右栏回落到 `calculatedAtSubmit`（不得显示 0 或旧值冒充新值）。
7. **已确认报价之后**：地址/方式又变了 → 走既有 `quote_changed` / `checkout_version_conflict` 横幅，**不静默改价**（确认区始终展示权威值）。

## 3. 功能需求（FR）

- **FR-001（方式列表按 header 国家过滤）**：结算页服务端组件把路由段/市场国家传给 `getShippingMethods(country)`；Store API 调用带 `?country=<ISO>`。命中 zone 则过滤，命中不了回退全集（沿用既有语义，绝不因未建模国家而声称"不配送"）。
- **FR-002（服务端只读预览报价）**：新增 `PallasTrade::Carts::PreviewQuote`，通过 `Carts::Submit` 的 **dry-run 模式**（同一事务内计算 → 读金额 → `ActiveRecord::Rollback`）产出：
  `{ delivery_total, display_delivery_total, tax_total, display_tax_total, discount_total, display_discount_total, amount_due, display_amount_due, currency, selected_method_id, methods[] }`。
  preview 模式**必须显式跳过**：`cart.convert!`、successor cart 创建、`order.submitted` 事件发布；并保证不产生 PaymentSession/Transaction、不触发邮件/作业/外呼。
- **FR-003（方式集合与默认）**：预览返回的方法集合 = 「按 header 国家过滤后的展示集合」（`Shipping::Estimate.scoped_methods`），每项带 `cost`（可计价）或 `cost: null + reason: "address_required"`（缺州/邮编等）；`selected_method_id` = 管道默认（费率成本升序第一）或用户显式传入且仍可用的方式。
- **FR-004（前台接线与默认选中）**：`UnifiedCheckout` 首屏请求预览，**直接采用** `selected_method_id` 作为选中方式；右栏读模型升级为四级：**权威（prepare 后）→ 预览 → legacy → 短标签**；费用行展示 `Estimated shipping` / `Estimated taxes`。
- **FR-005（变更重取与竞态）**：地址字段/配送方式变更后 **400ms 防抖**重取；请求带 `requestId`，过期响应丢弃；请求期间保留旧数字 + 微加载态；`address_required` 的方式在被计价后自动进入可选集合。
- **FR-005a（不可计价的照实提示）**：预览返回 `reason: "address_required"` 的方式，在方式行内渲染「填地址后显示」提示（`checkout.methodNeedsAddress`，5 语言），**不再用静态估价标签冒充金额**，也不把方式藏掉；换到 zone 覆盖的国家/补全地址后同一方式自动变为带 `cost`。（用户 2026-09-19 明确确认实施）
- **FR-006（契约与 SDK）**：Store API 新增 `POST /api/v3/store/carts/:id/preview_quote`（cart token 授权，与其它 cart 端点一致）；SDK 增加 `carts.previewQuote(...)`；BFF 新增 `POST /api/checkout/preview`（同源校验，与 prepare/start 同模式）；同步 `backend/public/api-docs/store.yaml` 与 SDK 类型（`harness generated:check`）。

## 4. 验收标准（AC）

- **AC-001 ← FR-001**：结算页请求方式列表时带 `country`；传 `DE` 时返回集合 ⊆ 全集且 ⊆ `scoped_methods(store, 'DE')`；未建模国家回退全集（不报错、不空集）。
- **AC-002 ← FR-002**：预览返回的 `delivery_total/tax_total/amount_due` 与**同参数** `Carts::Submit`（prepare）产出的订单金额一致（同源断言）；无地址时 `tax_total` 来自默认税区、非 nil（当默认税区存在税率时）。
- **AC-003 ← FR-002/FR-005（零副作用）**：dry-run 期间与之后 —— 订单行数 0 增、`Order` 计数 0 增、`PallasTrade::Event` 0 增、ActiveJob 队列 0 增、支付会话 0 增、购物车状态仍 `active`（未 `converted`）、礼品卡/店铺余额余额不变。
- **AC-004 ← FR-003/FR-004**：首屏 `selected_method_id` 非空且等于管道默认（成本最低）；右栏运费/税费显示金额而非 `calculatedAtSubmit`；无地址场景标 `Estimated`。
- **AC-005 ← FR-003**：州级 zone 限制的方式在缺州时返回 `cost: null + reason: "address_required"`；填写州后同一方式变为带 `cost`（在 zone 命中前提下）。
- **AC-006 ← FR-004/FR-005**：地址变更后右栏金额更新（且请求次数受防抖约束）；乱序响应不会覆盖较新结果；接口失败/`null` 时回落 `calculatedAtSubmit`，不显示 0。
- **AC-007 ← FR-006**：`POST /api/v3/store/carts/:id/preview_quote` 在 `store.yaml` 有定义、SDK 有类型方法、`generated:check` 通过；BFF 拒绝非同源请求（403）。
- **AC-008（回归）**：两段语义（prepare→确认→pay）、钱包 canonical、账单透传、费用读模型（A2）与 i18n 键守护测试全绿。

## 5. 跨层搜索记录（6 层）

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | `dry_run` / `preview_quote` / `shipping_method_id` | 仅序列化类型 `PallasTradeApiV3ShoppingCart`（含 `shipping_method_id`） | 不适用（应用层不承载定价） |
| Core | `pallastrade_core/app/` | `dry_run` / `preview` / `shipping_method_id` | **house 模式**：`Products::BulkOperation#preview → run(dry_run: true)`、`BulkChannelAssignment/BulkInventoryAdjust/BulkMediaRemoval`、`Disputes::Recover(dry_run:)`；`Carts::Update` 支持 `shipping_method_id` 落车；`Carts::Submit` 为唯一建单路径；`Stock::Estimator` 用 `ShippingMethod#include?(address)` 过滤费率 | **部分**：无车级预览 → 本 PRD 新增（沿用 `run(dry_run:)` 约定） |
| API | `pallastrade_api/app/` | `preview` / `shipping_methods` | `ShippingMethodsController#index`（支持 `?country=`）、`admin/orders/refund_calculations`（既有 preview 端点范式）、`carts_controller` 白名单含 `shipping_method_id` | 否 → 需新增端点（对齐 refund_calculations 的 preview 命名习惯） |
| Admin | `pallastrade_admin/app/` | `preview` / `shipping` | 无相关 | 不适用 |
| Storefront | `storefront/src/` | `preview` / `estimated` / `quote` | `lib/checkout-quote.ts`（权威报价形状）、`lib/checkout/server.ts`、`app/api/checkout/{prepare,start}`（BFF 同源 Route Handler 范式）、`getShippingMethods()`（**未传 country**）、`UnifiedCheckout` 费用行四级读模型雏形 | 否 → 主战场（FR-004/FR-005） |
| Platform | `platform/packages/` | `preview` / `shippingMethods` | SDK `shippingMethods.list`（支持 options）、`carts.update/submit` | 否 → 需扩 `carts.previewQuote` |

**结论**：新增能力集中在 ①core 只读预览（沿用 `dry_run:` 约定）②API 预览端点 ③SDK 方法 ④前台接线；**不得**新增定价实现（必须复用 Order 管线），不得让前端算钱（AP-002/金额契约）。

## 6. 技术影响

- 核心（gem 源码直接改，标 `# PALLAS-CUSTOM`）：
  `pallastrade_core/app/services/pallastrade/carts/submit.rb`（+ `dry_run:`）、
  新增 `pallastrade_core/app/services/pallastrade/carts/preview_quote.rb`、
  `pallastrade_core/app/models/pallastrade/address.rb`（+ `pricing_only`：**定价专用临时地址**，
  跳过姓名/街道/城市/邮编/州 的完备性校验——实施中发现 `Address` 的完备性校验让
  「只有 header 国家」无法进入金额管线，而伪造州会让州级 zone 被错误命中，故选显式开关）。
- API：`pallastrade_api/config/routes.rb` + `.../store/carts_controller.rb#preview_quote`（子路由，纯哈希投影，无新 serializer）。
- 前台：`storefront/src/lib/data/shopping-cart.ts`（`getShippingMethods(country)`）、`app/api/checkout/preview/route.ts`、`components/checkout/UnifiedCheckout.tsx`（默认选中 + 四级读模型 + 防抖/竞态/微加载）、`messages/*.json`（`estimatedShipping` / `previewUpdating` ×5）、`lib/__tests__/checkout-i18n-keys.test.ts`。
- 平台：`platform/packages/sdk` 新增 `carts.previewQuote` **且** `shippingMethods.list(params, options)` 首个参数变为 `{ country }`（既有调用点已同步）+ 重建 `dist`。
- 契约：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`；`harness generated:check`。
- 数据库：**无迁移**（预览只读）。

## 7. 测试计划（AC ↔ 测试）

| AC | 测试 |
|---|---|
| AC-001 | 前台：`getShippingMethods` 单测（带 country 透传）；后端：`ShippingMethodsController` 请求 spec（country 过滤 + 回退全集） |
| AC-002 | 新增 `harness verify checkout-preview-quote-rspec`：preview 与 prepare 同参数金额一致（同源断言） |
| AC-003 | 同 verifier：dry-run 前后计数断言（Order/Event/Job/PaymentSession 0 增、cart 仍 active、礼品卡余额不变） |
| AC-004/AC-005 | verifier（`selected_method_id` = 最便宜；`address_required` → 带 cost）+ 前台组件测试（默认选中、Estimated 文案、reason 渲染） |
| AC-005（行内提示） | 前台组件测试：`methods[].reason === 'address_required'` 时行内显示 `methodNeedsAddress`（`data-testid="shipping-reason-<id>"`）且不再显示静态估价标签；i18n 键守护覆盖 5 语言 |
| AC-006 | 前台测试：防抖（fake timers）、乱序响应丢弃（`requestId`）、失败回落 `calculatedAtSubmit` |
| AC-007 | `harness generated:check` + BFF 单测（403 非同源 / 200 形状） |
| AC-008 | 既有回归：`storefront-test` + 两段语义/钱包/账单/i18n 相关 spec |

**验证命令**：`npx harness verify checkout-preview-quote-rspec --task <ID>`、`npx harness verify storefront-test --task <ID>`、`npx harness generated:check`。

## 8. 非目标（Non-goals）

- 不改成"车级权威定价"（P2 车级报价快照 + `price_version`），本 PRD 只做**只读估算**；
- 不修改 `prepare` 建单语义与支付链路（预览不建单、不建支付会话）；
- 不引入第二套运费/税计算实现（必须复用 Order 管线，这是本 PRD 的硬约束）；
- 不做"地址自动补全/校验"，不新增地址字段；
- 不调整配送方式的排序规则（仍沿用 `order(:name)`；**默认选中**由服务端"最便宜"口径决定）。

## 9. 风险与守卫

| 风险 | 守卫 |
|---|---|
| dry-run 泄漏副作用（事件/作业/状态推进） | preview 显式跳过 `convert!`/successor/`publish_submitted_event`；spec 断言零副作用（AC-003） |
| 预览与真实提交漂移 | 同源调用（同一 `Carts::Submit`）+ AC-002 一致性断言 |
| 无地址时算不出运费（`include?(nil)` → false） | 用 header 国家作临时地址（`shipping_method.rb:47-54` 的硬约束）；州级 zone 显式 `address_required` |
| 「临时地址」被伪造成完整地址（伪州命中州级 zone → 承诺用户拿不到的方式） | `Address#pricing_only` 只跳过**完备性校验**，不造假州/城市；州级 zone 因此自然miss → 逐方式 `address_required` |
| 当前地址下什么都算不出时预览报错 → 结算页崩 | `Order#warnings` 的 `delivery_unavailable` 是结构化信号（不靠文案匹配）→ 返回 200 + 金额全 `null` + `unavailable_reason` |
| 请求风暴/竞态 | 400ms 防抖 + `requestId` 丢弃过期响应（尚未加 TTL 缓存——首版不做，见 §8） |
| 金额口径被前端篡改 | 前端零算钱；只渲染 `display_*`；含税价（`included_in_price`）不重复加 |
| 已确认后静默改价 | 沿用 `expected_checkout_version` / `quote_changed` 通道；预览**不写入**任何权威字段 |

## 10. 知识同步清单

- [x] `ai/skills/pallastrade-storefront/SKILL.md`——新增「结算页预估运费/税费」段（数据源/BFF、防抖与竞态、默认选中、四级读模型、`reason` 渲染、测试与**独立 `previewMock`** 约定）
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`——新增端点段（请求/响应/降级/零副作用/错误码/SDK 同步）
- [x] `platform/packages/README.md`——SDK 方法段（`carts.previewQuote` + `shippingMethods.list(params, options)` 签名变更 + dist 重建提醒）
- [x] `ai/skills/pallastrade-payments/SKILL.md`——**已评估，无需更新**：本 PRD 不新增支付路径/网关字段，「估算 vs 权威」边界已由 §6/§9 与 storefront/api-v3 两段覆盖；金额仍来自同一 Order 管线
- [x] `ai/skills/pallastrade-typescript-sdk/SKILL.md`——**已评估，仅需补一行**：`shippingMethods.list` 签名变更与 `previewQuote` 已在同文件的资源清单段落写清（见 commit）
- [x] `ai/skills/pallastrade-prd/SKILL.md`——**已评估，无需更新**（PRD 模板/分类/查重机制未变）
- [x] `harness/requirements/REQ-20260919-shipping-checkout-quote-preview.md`、本 PRD 状态、`docs/prd/README.md` 索引
- [x] `harness.config.mjs` 新增 `checkout-preview-quote-rspec` + `AGENTS.md` §6 验证矩阵行
- [x] `harness/scenarios/scenarios.json` 新增 GS-195（196/196 有效）
- [x] API 契约：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（`generated:check` → no drift）
- [x] `.github/copilot-instructions.md`——**已评估，无需更新**（R0-R8 强制项未变；本任务未改流程规则）
- [x] 知识同步门：`harness sync-check --id PRD-20260919-shipping-checkout-quote-preview` → 逐项评估后 `--ack`

## 11. 变更日志

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-19 | 0.1 | 初稿（approved）：用户确认「实施」；范围 = 方式列表按 header 国家过滤 + dry-run 只读预览 + 默认选中 + 前台四级读模型 | AI |
| 2026-09-19 | 1.0 | 实施完成（AC-001~AC-008）：`Address#pricing_only`（不伪造地址）+ 无法配送时的降级契约 + 前端防抖/竞态/微加载 + 四语言新键；验证：`checkout-preview-quote-rspec` 28 例绿、`storefront-test` 绿、`generated:check` 无漂移、GS-195 | AI |
| 2026-09-19 | 1.1 | dev 实测修正：① 预览不再要求先填邮箱（dry-run 占位邮箱，真实提交仍拦截）；② 不可计价方式行内提示「填地址后显示」（FR-005a，用户确认）；验证：后端 9 例 + 前台 51 例绿 | AI |
