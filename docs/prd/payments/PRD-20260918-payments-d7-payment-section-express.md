# PRD-20260918-payments-d7-payment-section-express

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-18 |
| 来源 | 需求：D7 支付区收尾（入口级支付列表 + 钱包快付 + 三页共用支付区） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments` / `pallastrade-checkout` / `pallastrade-storefront` / `pallastrade-api-v3` / `pallastrade-security` / `pallastrade-testing` |
| 关联 REQ | REQ-20260918-d7-payment-section-express.md |
| 关联 PRD | 依赖 D1（`PRD-20260915-admin-管理后台支付配置选项化-…`，已 done）、D8（适用范围引擎，已 done）、D15c（3DS 闸门，已 done）、D16 切片1（入口展示元数据，已 done）；本批是业务方案 §78-D7 的落地 |
| 需求类型 | 功能优化 |

---

## 1. 背景与目标

- **一句话需求原文**：`需求：D7 支付区收尾（入口级支付列表 + 钱包快付 + 三页共用支付区）`
- **用户报障（本次触发）**：商家在后台把 Stripe 配成 `card / apple_pay / google_pay` 三个入口后，**前台 checkout 页只显示一行**（显示的是当前生效入口），**看不到 Apple Pay / Google Pay 快付入口**；只有在后台把前一个入口关掉时，才会「逐个」显示其它入口。
- **业务方案依据**：§78-D7 验收锚点「三页面共用支付组件；移动吸底可用；前台列表与 Start 同源」；§61–§62（支付区组件化）；§76.1（`available_payment_methods[]` 字段扩展：`group` / `position`；方法行含图标/文案）；§29（Express **不得**成为第二条 Checkout Flow，必须走同一条链）。

### 现状（6 层搜索结论见 §6，此处给根因）

| 层 | 事实 |
|---|---|
| Core | `PaymentMethod#effective_payment_option` = `effective_payment_options.first`（**单数**读模型，D16 引入）；`#option_identifier(kind)` = `"pm_x:card"` 已存在 |
| Core | `Order#payment_methods` 返回 **provider 记录集合**（不是入口集合）；`Payments::Availability::Resolver.available_options` 已是**入口级**唯一求值点 |
| Core | `PaymentSessions::Start.call(..., option_kind:)` **已支持入口级同源校验**（不传 = 零回归）；`Transactions::Start` 透传 |
| API | `PaymentMethodSerializer` 把 `method_key` / `display_name` 取 **effective（首个入口）**、`kind` / `frontend_kind` 取 **default 入口** → **一个 provider 在投影里只剩一个入口身份** |
| Admin | 已能配置多入口（`metadata['options']`：`kind/active/position/frontend_kind/display_name`），但**前台消费不到** |
| Storefront | `UnifiedCheckout.tsx:1217` 与 `OrderPaymentContent.tsx:677` 都是 `paymentMethods.map(...)` → **一 provider 一行**；钱包按钮组件 `ExpressCheckoutButton`（Stripe `ExpressCheckoutElement`）**只在购物车抽屉** `CartDrawer.tsx:267` 使用，checkout 页未接入 |

**根因一句话**：**下发面有入口概念（D1/D8），但投影面把入口折叠成了「一个 provider 一个生效入口」，消费面（前台）也没有按 `frontend_kind` 分派渲染** —— 三处缺口叠加，表现为「配了三个入口，前台只剩一个，且关掉才轮换」。

- **目标**：① 前台支付列表按**入口**呈现（一入口一行，顺序 = 后台 `position`）；② `express` 入口在 checkout 页以**钱包按钮**形态出现并可用；③ `option_kind` 全链路传递（选择即同源校验，杜绝「看得到、付不了」）；④ 支付区组件抽取为三页共用（cart_ 单页结账 / or_ 订单支付页 / 购物车抽屉）。

---

## 2. 用户故事 / 场景

| # | 角色 | 故事 |
|---|---|---|
| 1 | 买家 | 在结账页同时看到「信用卡 / Apple Pay / Google Pay」三个入口，且 Apple Pay / Google Pay 是**钱包按钮**（一次点击完成），不再需要在后台关掉卡支付才能看见 |
| 2 | 商家 | 在后台用 `position` 排序入口，前台顺序与后台一致；启用/停用入口即时反映到前台（无需改代码） |
| 3 | 买家 | 点钱包按钮 → 走同一条链（提交购物车/订单 → 交易 → 会话 → 确认 → 结果页），**不产生**第二条 checkout 流程 |
| 4 | 商家 | 高风险订单（D15c 认证需求）下，钱包入口**不出现**（服务端已过滤），且前台不自行猜测 |
| 5 | 运营 | 钱包入口不可用（设备不支持 / 未配置）时，该按钮**不渲染**，其余入口照常可用（不阻塞结账） |

---

## 3. 功能需求（FR）

| # | 需求 | 说明 |
|---|---|---|
| FR-001 | **入口级投影（additive）** | 每个可见 provider 的投影项新增 `entries[]`（服务端展开）：`option_id`（`"pm_x:card"`）、`method_key`（kind）、`display_name`、`frontend_kind`、`group`（`card`/`wallet`/`redirect`/`manual`）、`position`、`requires_authentication`（可选）。**入口集合必须来自 `Resolver.available_options`**（与 `Start` 同一求值点，含 D8 范围 / D11 熔断 / D15c 认证闸门） |
| FR-002 | **provider 级 `group` / `position`** | provider 投影项补 `group`（取生效入口的组）与 `position`（首个生效入口 position），满足 §76.1；老字段语义不变 |
| FR-003 | **前台按入口渲染（cart_ 页）** | `UnifiedCheckout` 支付区按入口出条目：`inline` → 保持现有卡表单；`express` → 渲染钱包按钮；`manual` → 展示说明行（线下收款） |
| FR-004 | **钱包按钮接入 checkout（or_ 订单页）** | `OrderPaymentContent` 对 `express` 入口渲染钱包按钮：选择后创建 **PaymentIntent 模式**会话（带 `option_kind`）→ 挂载 `ExpressCheckoutElement`（client_secret）→ 确认 → 完成会话 → 结果页。**不得**为此新增第二条流程（复用 `express-canonical` 的错误落点与结果页路由） |
| FR-005 | **`option_kind` 全链路传递** | `createOrderPaymentSession` / cart 会话创建均支持 `option_kind`；后端 `PaymentSessions::Start` 已有入口级校验 → 拒绝时 422 `payment_option_not_available`（**不建会话**），前台按既有「刷新列表 + 重选」约定处理 |
| FR-006 | **支付区组件抽取（三页共用）** | 抽 `PaymentSection`：输入「入口列表 + 选中入口 + 各形态渲染槽」，供 cart_ 单页结账 / or_ 订单页 / 购物车抽屉复用；**不得**让客户端按 `kind/frontend_kind` 自行隐藏入口（隐藏=不出现由服务端 Resolver 决定） |
| FR-007 | **移动吸底 Pay 条** | 移动端（< lg）订单支付页显示吸底 Pay 条（金额 + 主按钮），滚动时恒可见；与页内 Pay 按钮同一 handler（不复制支付逻辑） |

---

## 4. 非功能需求（NFR）

| # | 约束 |
|---|---|
| NFR-001 | **同源硬约束**：入口可用性只能来自服务端 `Resolver`；前台零筛选逻辑（SKILL 已写死此红线） |
| NFR-002 | **零回归**：未选项化 provider 仍出 **1 条 entry**（= 默认入口），投影与渲染行为与今天一致 |
| NFR-003 | **零资金副作用**：本批不得改变支付执行语义（会话创建/完成链路不变），只增加「选哪个入口」与渲染形态 |
| NFR-004 | **契约 additive**：只新增字段；`generated:check` 零漂移（OpenAPI + SDK 类型 + platform 副本） |
| NFR-005 | **查询数恒定**：入口展开不得引入 N+1（入口来自内存中的 metadata，不额外查库） |
| NFR-006 | **可测**：入口投影/排序/分组、钱包按钮渲染条件、`option_kind` 传递与拒绝分支，均有 spec 断言 |

---

## 5. 验收标准（AC，与测试一一映射）

| # | 验收标准 |
|---|---|
| AC-001 | 选项化 provider 配 `card(position 1)/apple_pay(2)/google_pay(3)` → 投影 `entries[]` 顺序 = `card, apple_pay, google_pay`，每项含 `option_id`/`method_key`/`display_name`/`frontend_kind`/`group` |
| AC-002 | 未选项化 provider → `entries[]` 长度为 1（默认入口），`group` 按 kind 映射，行为与 D16 一致 |
| AC-003 | 停用（`active: false`）入口不出现在 `entries[]`；D8 范围规则过滤掉的入口同样不出现 |
| AC-004 | D15c：高风险订单下 `express` 入口（未声明 3DS 能力）不出现在 `entries[]`，且 provider 项 `requires_authentication` 为真时前台给出提示文案 |
| AC-005 | provider 级 `group`/`position` 与首个生效入口一致 |
| AC-006 | 前台（cart_ 页）按入口出条目：`inline` 入口 → 卡表单；`express` 入口 → 钱包按钮容器；`manual` → 说明行 |
| AC-007 | 前台（or_ 页）选择 `express` 入口 → 创建会话请求带 `option_kind`；会话为 PaymentIntent 模式；钱包确认后跳结果页 |
| AC-008 | `option_kind` 被服务端拒绝（不可用入口）→ 422 `payment_option_not_available`，**不建会话**，前台刷新列表并提示 |
| AC-009 | 移动视口下 or_ 页出现吸底 Pay 条，金额与页内一致，点击与页内按钮同一 handler |
| AC-010 | 无 `entries[]` 的旧响应（回退路径）→ 前台回落「一 provider 一行」（向后兼容，不炸） |

---

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 结论 |
|---|---|
| App（`backend/app/`） | 无支付区/支付方式覆盖文件（decorator/subscriber 均无相关命中）；宿主 `locales` 已有 checkout/payment 文案域 |
| Core（`pallastrade_core/app/`） | `payment_method.rb`：`payment_options` / `available_payment_options` / `effective_payment_options` / `effective_payment_option` / `option_identifier` / `option_display_name` / `frontend_visible?`（**入口读模型已齐备**）；`order.rb:916#payment_methods`（provider 集合）；`order_checkout/view.rb:117#available_payment_methods`；`payment_sessions/start.rb:16`（`option_kind:` 入口级校验已就绪）；`payments/availability/resolver.rb:29#available_option_kinds` |
| API（`pallastrade_api/app/`） | `payment_method_serializer.rb`（provider 单入口身份）、`store/checkout/checkout_serializer.rb:146-153`（`available_payment_methods[]` payload）、`store/{carts,orders}/payment_sessions_controller.rb`（Start 调用点，可加 `option_kind`） |
| Admin（`pallastrade_admin/app/`） | `payment_methods/_options.html.erb`（入口表已有 `position` / `frontend_kind` 列）、`payments_helper.rb#payment_options_for`（后台展示回落）→ 本批**后端已具备**，无需改后台 |
| Storefront（`storefront/src/`） | `UnifiedCheckout.tsx:1203-1240`（cart_ 支付区）、`OrderPaymentContent.tsx:668-700`（or_ 支付区）、`ExpressCheckoutButton.tsx`（钱包按钮，cart 绑定）、`lib/checkout/express-canonical.ts`（错误落点/结果页）、`CartDrawer.tsx:267`（唯一既有钱包入口） |
| Platform（`platform/packages/`） | `sdk/src/types/generated/{PaymentMethod,StoreCheckoutCheckout}.ts`（需随契约 additive 更新）；admin-sdk 无需变更 |

---

## 7. 技术影响

| 层 | 文件 | 变更 |
|---|---|---|
| Core | `payment_method.rb` | 新增入口级投影辅助（`payment_option_entries` / `option_group(kind)`），**复用**既有读模型 |
| Core | `order_checkout/view.rb` | `available_payment_methods` 改为输出「provider + `entries[]`」 |
| API | `payment_method_serializer.rb` / `store/checkout/checkout_serializer.rb` | 增 `entries[]`（+ provider 级 `group`/`position`） |
| API | `store/{carts,orders}/payment_sessions_controller.rb` | 接受 `option_kind` 透传 `Start` |
| Storefront | 新增 `PaymentSection.tsx` + `WalletPaymentButtons.tsx` | 入口级渲染与钱包按钮 |
| Storefront | `UnifiedCheckout.tsx` / `OrderPaymentContent.tsx` | 接入 `PaymentSection`；or_ 页吸底 Pay 条 |
| 契约 | `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml` + SDK 生成类型 | `contracts.sh` 再生成 |

**不做**（明确排除）：不引入新的入口表（继续用 `metadata['options']`）；不改支付执行语义（会话/交易/资金链路零改动）；不为钱包新增第二条流程。

---

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 服务 | `spec/models/pallastrade/d7_payment_option_entries_spec.rb` | AC-001/002/003/005 |
| 服务 | `spec/services/pallastrade/order_checkout/d7_entries_spec.rb` | AC-001/003/004（含 D8/D15c 过滤后的入口集合） |
| 序列化 | `spec/serializers/pallastrade/api/v3/store/checkout/d7_entries_spec.rb` | AC-001/005 + 契约字段 |
| 请求 | `spec/requests/api/v3/store/d7_payment_session_option_kind_spec.rb` | AC-007/008（`option_kind` 透传 + 拒绝不建会话） |
| 前端 | `storefront/src/components/checkout/__tests__/PaymentSection.test.tsx` | AC-006/010 |
| 前端 | `storefront/src/components/checkout/__tests__/WalletPaymentButtons.test.tsx` | AC-007（会话创建带 option_kind、确认后跳结果页） |
| 前端 | `storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`（既有文件扩展） | AC-009 吸底条 |

**验证器**：新增 `d7-payment-section-rspec`（后端 4 文件 + 既有 D1/D8/D15c/D16 回归）+ 前端 `storefront-test`。

---

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：入口级投影与钱包分派（含「投影面不得折叠入口」的既有教训）
- [x] `ai/skills/pallastrade-checkout/SKILL.md`：`option_kind` 选择语义与拒绝分支
- [x] `ai/skills/pallastrade-storefront/SKILL.md`：`PaymentSection` / 钱包按钮 / 吸底 Pay 条
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`：`entries[]` 契约字段
- [x] `AGENTS.md` §6：`d7-payment-section-rspec` 行
- [x] `harness/scenarios/scenarios.json`：GS-183（「配了三个入口，前台只显示一个」）
- [x] `docs/prd/README.md` 索引（`prd-status-sync --fix`）
- [x] 评估（无需更新）：`platform/packages/README.md`（**已更新**：D7 条目）、`pallastrade-typescript-sdk Skill`（**已更新**：`option_kind` 与入口级投影）、`根 README` / `pallastrade-prd Skill` / `copilot-instructions.md`（reviewed-no-change）、`.env.example` / `pallastrade-deployment Skill` / 部署 README（not-applicable：零环境变量、零部署流程变化）
- [ ] 业务方案 §78-D7 回写（本地文档，不入提交）

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-18 | 初稿（D7；业务方案 §78-D7 / §61–§62 / §76.1 / §29；根因＝入口在投影面被折叠为 `effective_payment_option` + 前台无 `frontend_kind` 分派 + 钱包组件只在购物车抽屉） |
| 2026-09-18 | **实施完成 → done**：core 入口级读模型（`payment_option_entries` / `option_group` / `option_frontend_kind`）+ checkout 投影 `entries[]`/`group`/`position`（Resolver 同源过滤）+ `option_kind` 三通道透传（cart legacy / orders 会话 / durable `Transactions::Start`）+ 前端 `PaymentSection`（入口级外壳，旧响应回落单入口）+ `WalletPaymentButtons`（or_ 页钱包快付，复用 canonical 错误落点）+ cart 页复用既有 `ExpressCheckoutButton` + 移动吸底 Pay 条 + BFF/数据层 `option_kind`；契约 `store.yaml` 三端点 + Typelizer/SDK 手写类型同步（`generated:check` 零漂移）；验证器 **`d7-payment-section-rspec`**（后端 4 文件 + 交易/会话回归）与 `storefront-test` 全绿；GS-183。 |
