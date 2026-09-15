# PRD-20260915-checkout-单页两段语义（Prepare → 报价确认 → Pay）

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 优化：Checkout 单页两段语义（Prepare 产出 Order 权威报价 + 页内报价确认） |
| 分类 | checkout（自动判定，关键词命中 2） |
| 关联 Skill | `pallastrade-prd`、`pallastrade-api-v3`、`pallastrade-storefront`、`pallastrade-data-model`、`pallastrade-testing` |
| 关联 REQ | 实施时回填 |
| 关联 PRD | PRD-20260913-checkout-txn-error-routing（报价变化路由）、PRD-20260914-checkout-quote-confirmation-loop（报价确认循环） |
| 需求类型 | 优化迭代 |
| 业务依据 | `豆包梳理业务需求/商城前台 Checkout + Transaction + Promotion + 履约完整方案.md` §0.1-1/2、§2、§19、§21、§22、§57.3、§57.4 |

## 1. 背景与目标

- **一句话需求原文**：优化：Checkout 单页两段语义（Prepare 产出 Order 权威报价 + 页内报价确认）
- **背景（代码事实）**：
  - `pallastrade_carts` 表**没有任何金额列**；`cart.rb` 注释明确「运费/税费不在 Cart 上计算——提交订单时由 `Carts::Submit` 在 Order 上」。
  - 前端 `cart_` 分支渲染 `UnifiedCheckout`（无 CheckoutView 投影）；`or_` 分支才拿服务端 `CheckoutView`（`(checkout)/checkout/[id]/page.tsx` L67–L90）。
  - 现网一次点击 Pay Now = `carts.update → carts.submit → transactions.create`（`/api/checkout/start`），即**最终金额（含税/运）在用户点击之后才产生**；变化仅靠 409 `quote_changed` 兜底。
- **问题**：存在「用户未确认最终金额即扣款」的风险（§0.1-2 明确禁止）；同时业务文档 §0.1-1 已冻结「报价权威只有 Order」。
- **目标**：**页面仍是单页**，服务端语义拆为两段——**Prepare**（提交 → Order 产出权威报价）→ **页内确认** → **Pay**（启动交易）。任何路径下，支付请求的金额都必须来自 Order 权威报价。
- **成功指标**：
  1. Pay 请求 100% 携带 Order 报价的 `price_version`（非页面估算）；
  2. 报价变化场景**零静默扣款**（`quote_changed` 与「页面展示金额 ≠ 实付金额」监控均为 0）；
  3. cart_ 首屏 → 可支付 P95 耗时劣化 ≤ 20%。

## 2. 用户故事 / 场景

- 作为**游客**，我希望点 Pay 后先看到含运费与税费的最终金额再确认，以便不出现「扣款比页面多」的情况。
- 作为**运营**，我希望报价变化时有明确确认记录，以便处理客诉与对账。

场景：

1. **正常流**：cart_ 页填地址/物流/优惠码 → 点 Pay Now → Prepare（submit 出 Order）→ 页内出现「金额确认」区（明细含税/运/抵扣）→ 点「确认并支付」→ Pay → 支付控件 → 结果页。
2. **边界**：页面停留导致报价过期 → Prepare 重算 → 金额变化 → 再次确认。
3. **异常 A**：Prepare 阶段库存不足/行项不可售 → 页内错误，**不建单**、不进入支付。
4. **异常 B**：Prepare 成功、Pay 失败 → 进入 `or_` 域（补付/恢复），**禁止再次 Prepare**（防重复建单）。
5. **异常 C**：Pay 携带版本与服务端不一致 → 409 + 报价 payload → 页内差异确认后重试（不跳结果页）。

## 3. 功能需求（FR）

- **FR-001　Prepare 端点**：新增 `POST /api/checkout/prepare`（BFF）：执行 `carts.update` + `carts.submit`，返回 `{ order_id(or_), view(CheckoutView), price_version, checkout_version }`；**不得**创建 `PaymentSession`、不得启动 Transaction。
- **FR-002　页内报价确认态**：`UnifiedCheckout` 在 Prepare 成功后进入确认态，展示 Order 权威金额明细（商品/运费/税/折扣/抵扣/应付）；确认态之前**禁止**发起 Pay。
- **FR-003　Pay 携带版本**：`POST /api/checkout/start` 改为**只做 Pay**——要求 `expected_checkout_version` + `expected_price_version`（来自 Prepare 返回的 view）；缺失即 422。
- **FR-004　版本冲突**：服务端版本不符 → 409 `quote_changed` / `checkout_version_conflict` + 当前报价 payload；页面展示新旧差异并要求再次确认（复用既有 quote-confirmation 组件行为）。
- **FR-005　上下文切换**：Prepare 成功后页面业务上下文即切换为订单（`or_`）；后续所有动作只作用于该订单（补付/恢复），不得再次 Prepare。
- **FR-006　兼容**：`or_` 页（`OrderPaymentContent`）行为不变；legacy 端点与既有 `cart_` 直连客户端保持可用（P0-7：不为 legacy 增加能力，也不破坏兼容）。
- **FR-007　可观测**：埋点/指标 `checkout.prepare`、`checkout.pay`、`checkout.quote_changed`、`checkout.amount_delta`（页面展示金额 vs 实付金额差的分布）。

## 4. 非功能需求（NFR）

- **不变更** canonical 交易链（`Start → Freeze → Reserve → Payment → Commit → Finalize`）与库存预留语义。
- **API 变更 additive**：不删除既有字段；`/api/checkout/start` 的入参新增必填版本字段需有过渡策略（灰度期允许缺失但记 warn）。
- **性能**：Prepare 复用既有 submit 路径，不新增额外重算（`OrderCheckout::Recalculate` 只跑一次）。
- **兼容**：移动端吸底 Pay 条、Express 钱包入口（B4 已 canonical 化）不得回退到 legacy 会话。
- **可维护**：两段语义在 BFF 层显式表达，不把状态藏在 409 错误分支里。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：调用 prepare 后返回 `or_` 订单 + CheckoutView（含 `amount_due`、税、运、抵扣、`price_version`），且 `pallastrade_payment_sessions` **无新增记录**（RSpec 断言）。
- **AC-002 ← FR-002**：cart_ 页确认态展示 Order 权威金额（含税/运）；确认态之前点击 Pay **不发出** `transactions.create`（Vitest + 网络断言）。
- **AC-003 ← FR-003**：Pay 请求体包含 `expected_price_version` / `expected_checkout_version`；缺失时后端 422（request spec）。
- **AC-004 ← FR-004**：版本不符时返回 409 + 报价 payload，页面展示差异并要求再次确认（复用既有测试 + 新增差异渲染断言）。
- **AC-005 ← FR-005**：Prepare 成功后页面上下文切换为 `or_`，刷新页面不回到 Prepare（E2E/组件测试）；重复点击支付不产生第二条订单（DB 断言订单数 = 1）。
- **AC-006 ← FR-001 异常**：Prepare 阶段库存不足返回结构化错误且**未建单**（订单数不变），页面停留 cart_。
- **AC-007 ← FR-006**：`or_` 页支付与补付路径回归通过（既有 `pallastrade-testing` 约定的组件测试）；legacy 守护测试（B5 六端点）不回归。
- **AC-008 ← FR-007**：三个指标可从埋点/日志查询（人工核验 + 单元断言埋点调用）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | checkout / prepare | 仅生成物（`app/javascript/types/serializers/PallasTradeApiV3Payment*` 等） | ❌ 无业务实现（需在 gem/核心层改） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `OrderCheckout`、`Carts::Submit`、`Order#price_version`、`payment_required?` | `services/pallastrade/carts/submit.rb`、`services/pallastrade/order_checkout/{view,recalculate,refresh}.rb`、`models/pallastrade/order.rb`、`models/pallastrade/cart.rb` | ⚠️ 已有 submit/view/refresh；**缺** prepare 语义与页面契约 |
| API | `pallastrade_gems/pallastrade_api/app/` | checkout / transactions / carts submit | `store/carts/{submit}`、`store/orders/{transactions,payment_sessions}`、`checkout_serializer.rb` | ⚠️ 有 `/carts/:id/submit` 与 `/orders/:id/transactions`；**缺** prepare 的 BFF 契约与版本必填 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | checkout / order | `orders_controller`、`order_concern` | ✅ 不受影响 |
| Storefront | `storefront/src/` | `UnifiedCheckout`、`/api/checkout/start`、quote_changed | `components/checkout/UnifiedCheckout.tsx`、`app/api/checkout/start/route.ts`、`lib/data/order-payment.ts`、`app/[country]/[locale]/(checkout)/checkout/[id]/page.tsx` | ⚠️ 已有 409 页内确认分支；**缺** 显式 Prepare 与确认态 |
| Platform | `platform/packages/` | CheckoutView / Order types | SDK 生成类型（`CheckoutView`、`Order`、`PaymentSession`） | ⚠️ 需新增 `prepare` 相关类型（additive） |

**结论**：无需新建后端能力，核心是「把既有 `carts.submit` 暴露为 Prepare 契约 + 前端增加确认态 + Pay 强制携带版本」。防重复判定：与 `PRD-20260914-checkout-quote-confirmation-loop` 不重复（后者解决 409 分支体验，本 PRD 解决**报价权威的产生时机**）。

## 7. 技术影响

- **后端**：`pallastrade_api` 新增 BFF 侧调用契约（或由 storefront BFF 直连既有 `/carts/:id/submit` + `GET /orders/:id/checkout`，**优先此方案**：零后端改动）；`/api/checkout/start` 入参加版本必填（灰度）。
- **前端**：`UnifiedCheckout` 新增确认态；`app/api/checkout/start/route.ts` 拆为 prepare/pay 两段；`lib/data/order-checkout.ts` 复用。
- **数据**：无表结构变更；`orders.price_version` / `checkout_version` 复用。
- **接口**：若改动 store.yaml 需 `harness generated:check`。
- **影响面**：`harness affected --base dev`（实施时执行）。

## 8. 测试计划

| 测试文件 | 类型 | 覆盖 AC |
|---|---|---|
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | Vitest（更新） | AC-002、AC-004、AC-005 |
| `storefront/src/app/api/checkout/__tests__/prepare-route.test.ts`（新增） | Vitest | AC-001、AC-003、AC-006 |
| `storefront/src/lib/checkout/__tests__/legacy-payment-sessions-guard.test.ts` | Vitest（回归） | AC-007 |
| `backend/spec/services/pallastrade/payment_sessions/start_spec.rb` | RSpec（更新：版本必填） | AC-003 |
| `backend/spec/requests/pallastrade/api/v3/store/carts/submit_spec.rb` | RSpec（回归） | AC-006 |
| 埋点单测（新增） | Vitest | AC-008 |

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`（若 `/api/checkout/start` 入参变更）
- [ ] Skill：`ai/skills/pallastrade-storefront/SKILL.md`（Checkout 数据流章节）、`ai/skills/pallastrade-api-v3/SKILL.md`（订单/结账端点）
- [ ] 业务方案文档：§19/§21/§22/§57.3 由 `[目标]` 更新为 `[已实施]`
- [ ] `harness/scenarios/scenarios.json`（若新增能力场景）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（据业务方案 §0.1-1/2 与审计结论） | AI |
| 2026-09-15 | 0.2 | 用户授权自主决策 → 开工；切片 1（BFF 两段语义）完成并提交 `48239a9c`（prepare 建单不建会话 / start 的 Pay-only 形态） | AI |
| 2026-09-15 | 1.0 | 切片 2（页内确认区 + 5 语言文案 + 组件测试适配）完成，提交 `c98a3221`；AC-001/003/005 由 BFF 测试覆盖、AC-002/005-UI 由组件测试覆盖；tsc 0 错、9 文件 81 例全绿 | AI |
