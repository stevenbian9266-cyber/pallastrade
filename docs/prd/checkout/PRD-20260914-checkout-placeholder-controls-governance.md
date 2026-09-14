# PRD-20260914-checkout-placeholder-controls-governance

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | research `RESEARCH-20260913-checkout-plan-review-and-decision` §9.3 P1「占位功能治理（§47：Add-ons / Save Info / Marketing / SMS）」；用户指令「继续」授权按本文决策实施 |
| 分类 | checkout |
| 关联 Skill | pallastrade-storefront（结算组件/i18n 约定）/ pallastrade-api-v3（newsletter 契约） |
| 关联 REQ | REQ-20260914-checkout-placeholder-controls-governance.md |
| 关联 PRD | 无重复（查重通过）；CheckoutView 扩展（同 §9.3 P1）经评估**不做**，见 §1.3 |
| 需求类型 | 优化（体验诚实性：消除「假控件」） |

## 1. 背景与目标

### 1.1 实测现状（storefront，2026-09-14）
结算页 `UnifiedCheckout` 有 **4 个占位控件**，行为与外观不一致：

| 控件 | 现状 | 问题 |
|---|---|---|
| Marketing opt-in（`UnifiedCheckout` L318-321 / L902+） | 本地 `useState`，注释明写 "backend subscription API not integrated" | 勾了**没有任何效果**（用户预期被订阅） |
| SMS opt-in（`AddressFormFields.showSmsOptIn`） | 同上（仅本地 state） | 同上 |
| Save Info（`SaveInfoSection.tsx`） | 点 Save → 本地 `status='saved'`，**未持久化** | 显示「已保存」但下次仍需重填 |
| Add-ons / Worry-Free（`AddOnsSection.tsx`） | 选中仅切换本地 state，注释 "not integrated yet" | 卡片可点选，看起来可购买 |

### 1.2 后端能力核对（6 层检索结论，见 §6）
- **Marketing：后端已具备** —— `POST /api/v3/store/newsletter_subscribers`（+`/verify`）与客户字段 `accepts_email_marketing`；SDK `newsletterSubscribers.subscribe/verify` 已有 ✓ → **可接线**。
- **SMS / Add-ons：后端完全不存在**（全仓无 `sms/twilio`；无 AddOn 模型/定价管线）→ 现阶段**无法接线**。
- **Save Info：无持久化语义**（地址簿保存属既有账户能力，与「结算页一键保存」不是同一件事）→ 现阶段不做。

### 1.3 同期评估结论（CheckoutView 扩展 —— 不做）
§9.3 P1「CheckoutView 扩展（credits/capabilities/available_payment_methods/billing_mode）」经评估**边际价值低、不做**：
- `available_payment_methods`：Order/Checkout 序列化层已暴露 `payment_methods`，结算页已消费（`OrderPaymentContent`）；
- `credits`：`store_credit_total/display_store_credit_total` 已在订单载荷并由 `OrderTotals` 渲染；
- `capabilities`：`ready` + `missing_requirements`（CHK-P1-3 Readiness）已是同一语义；
- `billing_mode`：购物车侧已建模并在 `PATCH /carts` 生效（PRD-20260913-checkout-billing-mode）。
→ 仅剩「形式统一」，收益不抵改动面（DTO/序列化/契约文档/前端重构）。结论记入 research §9.3。

### 1.4 目标
消除「假控件」：**能接线的接线，不能接线的隐藏**（保留组件与文案，一键可恢复），让结算页不再对用户做出无效承诺。

## 2. 用户故事 / 场景
- 作为**顾客**，我勾选「订阅优惠信息」后应当真的被订阅（或至少能查到记录）；我点「保存信息」不该看到虚假的「已保存」。
- 作为**运营**，我不希望页面上有看起来可购买、实际无后端的增值服务选项（法律/信任风险）。
- 场景：① 游客 + 勾选 Marketing → 下单成功且订阅生效；② 未勾选 → 不订阅；③ 订阅接口失败 → **不阻断下单**，仅记录/提示；④ SMS / Save Info / Add-ons 默认不渲染；⑤ 开关打开时组件可恢复渲染（回滚友好）。

## 3. 功能需求（FR）
- **FR-001（Marketing 接线）**：结算提交时，若 `marketingOptIn === true` 且邮箱有效 → 经 BFF（服务端 SDK）调用 `newsletterSubscribers.subscribe(email)`；已登录用户额外设置 `accepts_email_marketing`（customer 更新）。**best-effort**：失败只记录日志/非阻断提示，**绝不影响下单结果**。
- **FR-002（占位开关）**：新增显式开关 `SHOW_PLACEHOLDER_SECTIONS = false`（`UnifiedCheckout` 内常量或模块常量）：为 false 时**不渲染** Add-ons / Save Info / SMS 三处；组件文件保留，翻成 true 即恢复（回滚成本 = 一个常量）。
- **FR-003（i18n）**：保留既有文案键（`checkout.addOns*`、`checkout.saveInfo*`、`checkout.sms*` 等），以便恢复；不新增不需要的键。
- **FR-004（知识同步）**：storefront Skill 记录「占位开关约定 + Marketing 接线契约」；research §9.3 更新（P1 占位治理 → done；CheckoutView 扩展 → 评估不做）；场景库新增 GS-116。
- **FR-005（范围外）**：真正实现 Add-ons 定价管线、SMS 通道、结算页 Save-Info 持久化（各自另立 PRD）；不改结算主流程（下单/支付/库存语义）。

## 4. 非功能需求（NFR）
- **不阻断主路径**：订阅 I/O 失败不得改变下单结果（与 `order.submitted` 后置原则一致）。
- **零后端 schema 变更**：复用既有 newsletter/customer API。
- **可逆**：占位治理通过单一开关回滚。
- **i18n/格式**：改动后必须跑 `pnpm check` + `pnpm typecheck` + `pnpm test`（CI 红线教训）。

## 5. 验收标准（AC，与测试一一映射）
- **AC-001** ← FR-002：默认（开关 false）不渲染 Add-ons / Save Info / SMS（vitest）。
- **AC-002** ← FR-001：勾选 Marketing 提交 → BFF 订阅接口被调用（含邮箱）；未勾选 → 不被调用（vitest）。
- **AC-003** ← FR-001：订阅接口失败 → 下单流程不受影响（页面仍进入支付/结果态，无错误阻断）（vitest）。
- **AC-004** ← FR-002：开关为 true 时三处占位重新可见（vitest，保证可逆）。
- **AC-005** ← FR-004：Skill/研究文档/场景库同步（doc 证据，记录于 §9；非测试型 AC，`prd verify` 不计）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 结果 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | newsletter / marketing / sms | 无宿主层实现 | — |
| Core | `pallastrade_core/app/` | `NewsletterSubscriber` / addon / sms | `NewsletterSubscriber.subscribe`（+verify）存在；**无** AddOn / SMS 模型 | Marketing ✓ / 其余 ✗ |
| API | `pallastrade_api/app/` | newsletter / customers / sms | `store/newsletter_subscribers_controller.rb`（subscribe/verify）；`store/customers_controller.rb`（`accepts_email_marketing`）；**无** sms/addon 端点 | Marketing ✓ / 其余 ✗ |
| Admin | `pallastrade_admin/app/` | marketing / sms / addon | 无 sms/addon；客户营销字段在管理员可编辑 | — |
| Storefront | `storefront/src/` | placeholder / opt-in | `AddOnsSection.tsx`（占位）、`SaveInfoSection.tsx`（未持久化）、`UnifiedCheckout.tsx`（marketing/sms 本地 state）、`AddressFormFields.tsx`（`showSmsOptIn`） | **本次改动点** |
| Platform | `platform/packages/` | newsletter | SDK `newsletterSubscribers.subscribe/verify` + 生成类型 | 可直接复用 |

**结论**：1 项可接线（Marketing）、3 项需隐藏（SMS/Save Info/Add-ons）；改动集中在 storefront + 1 个新增 BFF 路由。

## 7. 技术影响
- **修改**：`storefront/src/components/checkout/UnifiedCheckout.tsx`（开关 + 接线 + 提交路径）、`storefront/src/components/checkout/CheckoutFormFields.tsx`/`AddressFormFields`（sms 传参归零）、相关 vitest 用例、`ai/skills/pallastrade-storefront/SKILL.md`、`harness/scenarios/scenarios.json`、research §9.3
- **新增**：`storefront/src/app/api/checkout/newsletter/route.ts`（BFF，服务端 SDK；游客订阅）
- **数据库**：无迁移
- **接口**：复用 `POST /api/v3/store/newsletter_subscribers`（无契约变更）

## 8. 测试计划
- **更新/新增**：`UnifiedCheckout.test.tsx`（AC-001/002/003/004）、新增 BFF route 单测
- **命令**：`pnpm test` + `pnpm check`（biome）+ `pnpm typecheck`
- **dev 实测**：结算页提交一单（勾选 Marketing）→ 后台 `NewsletterSubscriber` 出现该邮箱；未勾选 → 不出现
- **AC 映射**：见 §5（测试内以 `PRD-20260914-checkout-placeholder-controls-governance AC-xxx` 注释关联）

## 9. 文档同步清单（知识同步门）—— 结论

| 资产 | 状态 | 结论 |
|---|---|---|
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已更新 | 「结算页占位开关 + Marketing 接线（best-effort，不阻断下单）」约定 |
| `harness/scenarios/scenarios.json` | ✅ 已更新 | GS-116（占位治理 + 不阻断订阅） |
| `docs/research/RESEARCH-20260913-…` §9.3 | ✅ 已更新 | P1 占位治理 → done；CheckoutView 扩展 → 评估不做（含理由） |
| OpenAPI ×2 | ✅ 已评估，无需更新 | 复用既有 newsletter 端点，无契约变化 |
| SDK / platform | ✅ 已评估，无需更新 | `newsletterSubscribers.subscribe` 已存在 |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新 | 未引入禁止模式 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 实施：`SHOW_PLACEHOLDER_SECTIONS=false` 隐藏 Add-ons/Save Info/SMS；新增 BFF `POST /api/checkout/newsletter` 并在提交时 best-effort 接线 Marketing；规格 4 例 + BFF 单测；Skill/GS-116/research §9.3 同步 | AI |
