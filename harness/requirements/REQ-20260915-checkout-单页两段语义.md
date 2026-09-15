# REQ-20260915-checkout-单页两段语义

> 关联 PRD：`docs/prd/checkout/PRD-20260915-checkout-单页两段语义-prepare-产出-order-权威报价-页内报价确认.md`
> 业务依据：`豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md` §0.1-1/2、§2、§19、§21、§57.3、§57.4

## Step 0：跨层搜索（6 层）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | checkout / prepare | 仅生成物（`app/javascript/types/serializers/PallasTradeApiV3*`） | ❌ 无业务实现（本任务不需后端改动） |
| Core — models | `pallastrade_core/app/models/` | cart / order / price_version | `cart.rb`（**无金额列**，注释：运费税费不在 Cart 计算）、`order.rb`（`amount_due`、`payment_required?`、`price_version`） | ✅ 权威报价已存在（Order 侧） |
| Core — services | `pallastrade_core/app/services/` | submit / checkout view / payment session | `carts/submit.rb`、`order_checkout/{view,recalculate,refresh}.rb`、`payment_sessions/start.rb`（order 作用域，收 `expected_version`/`expected_price_version`） | ✅ 能力齐备，缺「Prepare 契约」 |
| API | `pallastrade_api/app/controllers/` | carts#submit / orders#transactions | `store/carts/submit`、`store/orders/transactions` | ✅ 既有端点可直接复用（零后端改动） |
| Admin | `pallastrade_admin/app/` | checkout / order | `orders_controller`、`order_concern` | ✅ 不受影响 |
| Storefront | `storefront/src/` | UnifiedCheckout / checkout/start / quote | `components/checkout/UnifiedCheckout.tsx`、`app/api/checkout/start/route.ts`、`lib/checkout-quote.ts`、`(checkout)/checkout/[id]/page.tsx`（cart_→UnifiedCheckout / or_→OrderPaymentContent） | ⚠️ 有 409 页内确认分支；**缺** 显式 Prepare 与确认态 |
| Platform | `platform/packages/` | CheckoutView / Order types | SDK 生成类型（`CheckoutView`/`Order`/`OrderTransactionStart`） | ✅ 无需新增类型 |

### 搜索结论

后端能力齐备（`carts.submit` + `orders.transactions.create` 已支持报价版本），本任务**零后端代码改动**；
缺的是「把 submit 暴露为 Prepare 契约 + Pay 只做交易启动 + 页面在支付前展示 Order 权威金额」。
与 `PRD-20260914-checkout-quote-confirmation-loop` 不重复：后者解决 409 分支体验，本需求解决**报价权威的产生时机**。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级 1–8：本任务属「修改已有前端流程」，**不走** gem 直改/装饰器（优先级 6/8）；改动落在 `storefront/src/`（Host App 层），符合「优先级 1：能改已有就直接改」 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | §Checkout：「Totals always come from the API」+ money 契约「raw 判逻辑、display 仅渲染，禁止 parseFloat(display_*)」——本任务确认区只渲染 `display_*`，不参与计算 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §4 阶段 2：gate → REQ → 实施；§5：每个 AC 必须有测试覆盖 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | 部分（仅 Storefront BFF 内部调用） | ✅ 已读要点 | BFF 不向页面暴露 SDK 凭证/guest token；错误信封 `{ error: { code, message }, order_id?, quote? }` |
| `pallastrade-storefront` | ✅ | ✅ | 同上（Checkout 章节 + B4 Express canonical 约束：钱包继续走合并语义） |
| `pallastrade-testing` | ✅ | ✅ | 前端测试放 `src/**/__tests__/*.test.ts(x)`（Vitest），测试头部标注 PRD/AC |
| `pallastrade-admin` / `pallastrade-catalog` | ❌ 不涉及 | — | 本任务不改后台与商品域 |
| `pallastrade-i18n` | ⏭ 切片 2 | — | UI 确认区文案需 5 语言（en/de/es/fr/pl），随 UI 切片一并提交 |

---

## 需求标题

优化：Checkout 单页两段语义（Prepare 产出 Order 权威报价 + 页内报价确认）

## 任务类型

功能优化（结账流程语义修正，P0：§0.1-1/2 冻结项）

## 本次实施范围（切片 1：BFF 两段语义）

- `storefront/src/lib/checkout/server.ts`（新增）：抽出 `sameOrigin` / `errorBody` / `errorResponse` / `readQuote` 与请求-响应类型，供 Prepare/Pay 共用。
- `storefront/src/app/api/checkout/prepare/route.ts`（新增）：`carts.update` + `carts.submit` → 返回 `{ order_id, order, quote }`；**不创建 PaymentSession / Transaction**。
- `storefront/src/app/api/checkout/start/route.ts`（改造）：`order_id` → Pay-only（`orders.transactions.create` + 版本透传，`session_required=false` 不建交易）；`cart_id` → 保留钱包合并语义。
- 测试：`prepare/__tests__/route.test.ts`（4）、`start/__tests__/pay-only.test.ts`（2）。

## 未完成（切片 2）

`UnifiedCheckout` 页内「最终金额确认区」+ i18n 5 语言 + 组件测试（AC-002 / AC-004 / AC-005-UI）。
切片 1 已回归验证：既有 3 个结账测试文件 54 例 + 新增 6 例 = 6 文件 65 例全绿。

## 用户确认

用户于 2026-09-15 明确回复「**自主决策**」，授权按 AI 推荐顺序实施本 PRD（R3/R7 的显式确认等价项）。
