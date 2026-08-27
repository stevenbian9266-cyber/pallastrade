# PRD-20260827-checkout-实施-p5-checkout-集成-自动拆单-合并支付收银台-buy-now-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-27 |
| 来源 | 需求：实施 P5 Checkout 集成（自动拆单 + 合并支付收银台 + Buy Now，flag 灰度） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-checkout、pallastrade-payments、pallastrade-api-v3、pallastrade-typescript-sdk、pallastrade-storefront、pallastrade-testing |
| 关联 REQ | REQ-20260827-order-lifecycle-p5.md（实施时回填） |
| 关联 PRD | N/A（承接 P4：合并支付载体服务层） |
| 需求类型 | 新功能（flag 灰度，逐 store 开关） |

---

## 1. 背景与目标

- **一句话需求原文**：需求：实施 P5 Checkout 集成（自动拆单 + 合并支付收银台 + Buy Now，flag 灰度）
- **背景**：P2 拆单引擎、P3 聚合派生、P4 合并支付服务层均已就绪但**未接入任何业务流程**。P5 是**完整闭环的正向链路落地**：
  - **自动拆单**：`Carts::Complete`（支付确认后）按策略自动把一笔订单拆成子订单（按仓库/店铺），父订单容器聚合展示；
  - **合并支付收银台**：账户订单模块多选待支付订单 → 一次 Stripe 扣款完成多笔订单；
  - **Buy Now**：商品详情页快捷下单（不污染购物车）。
  - 全部由 **feature flag 灰度**（`auto_split_orders` 默认 `[]` 关闭；组合端点/收银台按 store 开关），flag 关闭时完全回到单笔订单老流程。
- **目标**：打通「下单 → 自动拆单 → 合并支付 → 回调完成 → 订单列表父子视图」正向闭环。
- **成功指标**：flag 关闭零行为变化；flag 开启后自动拆单/合并支付/Buy Now 全链路可用；新增 spec + E2E 绿；既有单笔订单流程零回归。

## 2. 用户故事 / 场景

- 作为 **买家**，我希望下单后系统按仓库自动拆成多笔子订单，以便各仓库独立发货。
- 作为 **买家**，我希望把多笔待支付订单合并成一次付款，以便只输一次卡号。
- 作为 **买家**，我希望在商品页点「立即购买」直接进确认页，以便快速下单不污染购物车。
- 场景：
  - **S1（自动拆单）**：购物车含 A/B 两仓商品 → 下单支付 → `Carts::Complete` 后按 `ByStockLocation` 拆成 2 子订单（挂父订单，PaymentSplit 分摊）→ 订单列表显示父子。
  - **S2（合并支付）**：账户有 2 笔待支付订单 → 多选 → 组合收银台单次扣款 → 回调后 2 笔全部完成。
  - **S3（Buy Now）**：详情页 Buy Now → 仅当前商品确认页 → 支付 → 完成（购物车不变）。
  - **S4（flag 关闭）**：`auto_split_orders=[]` 且无组合入口 → 与升级前完全一致。

## 3. 功能需求（FR）

### P5a 自动拆单（backend）
- **FR-001**：`Config[:auto_split_orders]`（策略列表，默认 `[]`）控制自动拆单；store 可用 `preferred_auto_split_orders` 覆盖（按 store 灰度）。
- **FR-002**：`Carts::Complete` 在订单完成（支付确认后）执行自动拆单评估：按配置策略（`ByStockLocation` / `ByStore`）拆分已完成订单为子订单（挂父订单 + PaymentSplit 分摊 + OrderUpdater 重算）。**不在 cart 状态中途拆**。
- **FR-003**：拆单失败（库存/校验异常）**不影响订单完成**：`Rails.error.report` + 日志记录，订单保持完成态。

### P5b 合并支付收银台（backend API + SDK + storefront）
- **FR-004**：Store API `POST /api/v3/store/payment_combinations`——创建合并支付（`order_ids`（prefixed）+ `payment_method_id` → `PaymentCombinations::Create`），返回 `combination` + `payment_session`。
- **FR-005**：Store API 组合支付会话完成回调（复用 payment session 完成 + `PaymentCombinations::Complete` 双路径收敛）。
- **FR-006**：SDK 增加 `PaymentCombination` 类型 + `store.paymentCombinations.create/complete` 方法。
- **FR-007**：Storefront 账户订单列表（`/account/orders`）支持多选待支付订单 → 发起组合支付。
- **FR-008**：`(checkout)/combined-payment/[id]` 页面——Stripe Elements 单次扣款（金额=组合合计），复用 `confirm-payment` 回调。

### P5c Buy Now（storefront）
- **FR-009**：商品详情页 Buy Now——创建含当前商品的临时订单直接进入确认页（**不污染购物车**），复用公用确认页/支付流程。

## 4. 非功能需求（NFR）

- **flag 灰度**：`auto_split_orders` 默认 `[]` 关闭；组合端点/收银台/Buy Now 按 store 开关；关闭时单笔订单老流程零变化。
- **幂等**：重复创建组合/重复回调安全（`PaymentCombinations` 幂等已具备）。
- **一致**：自动拆单沿用 P2 Splitter 语义（总额守恒、PaymentSplit 分摊）。
- **性能**：自动拆单在 `Carts::Complete` 事务后执行（失败不阻塞订单完成）。
- **可维护**：沿用服务层 + flag 机制（`Config` / store `preferred_*`）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`auto_split_orders` 默认 `[]` 时订单完成不拆分（零行为变化）。
- **AC-002 ← FR-002**：配置策略后订单完成自动拆分为子订单（挂父订单 + PaymentSplit 分摊 + 金额守恒）。
- **AC-003 ← FR-003**：自动拆单异常时订单保持完成态（不失败/不回滚）。
- **AC-004 ← FR-004**：`POST /payment_combinations` 校验同 store/用户/币种、未支付订单，返回 combination + session（金额=Σ amount_due）。
- **AC-005 ← FR-005**：组合支付会话完成回调 → 所有成员订单完成。
- **AC-006 ← FR-006**：SDK `paymentCombinations.create` 存在且类型/请求路径正确。
- **AC-007 ← FR-007/008**：账户订单多选 → 组合收银台 → 单次扣款 → 回调 → 订单全部完成且列表显示父子视图。
- **AC-008 ← FR-009**：Buy Now 仅当前商品进确认页，购物车不变。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 自动拆单, payment_combinations | 无 | 否——P5 接线在 Core/API，App 无重复 |
| Core | `pallastrade_gems/pallastrade_core/app/` | Carts::Complete, Splitter, PaymentCombinations | `carts/complete.rb`（完成入口）、`orders/splitter.rb`（P2）、`payments/payment_combinations/{create,complete}.rb`（P4）、`payments/combination_settle_job.rb` | **已就绪**——P5 只需在 Carts::Complete 加拆单 hook |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_sessions, combination | `store/carts/payment_sessions_controller.rb`（单订单 session 端点） | 部分——**需新建组合端点** + 序列化器 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 拆单, combination | 无 | 否——P5 不动 Admin（P6 手动拆单） |
| Storefront | `storefront/src/` | PaymentSection, OrderList, confirm-payment, Buy Now | `components/checkout/PaymentSection.tsx`、`components/account/OrderList.tsx`、`app/.../(checkout)/confirm-payment/`、`lib/data/payment.ts`（session 流程）、`app/.../account/orders/` | 部分——**需新建合并支付收银台 + Buy Now**，复用 PaymentSection/confirm-payment |
| Platform | `platform/packages/sdk/` | paymentSessions, PaymentCombination | `src/store-client.ts`（`carts.paymentSessions` CRUD）、`types/generated/PaymentSession.ts` | 部分——**需加 PaymentCombination 类型/方法** |

**结论**：后端能力（拆单/合并支付服务）已就绪，P5 聚焦**接线**：Carts::Complete 拆单 hook（Core）、组合端点（API）、SDK 类型/方法（Platform）、合并支付收银台 + Buy Now（Storefront）。无跨层重复能力。

## 7. 技术影响

- **backend（Core）**：`services/pallastrade/carts/complete.rb`——完成事务后执行自动拆单（flag 控制）；`config/initializers/pallastrade.rb`——`Config[:auto_split_orders]` 默认 `[]`；Store 增加 `preferred_auto_split_orders`（Preferable 列 + 迁移）。
- **backend（API）**：新增 `controllers/.../store/payment_combinations_controller.rb`（`POST create`）+ `serializers/.../payment_combination_serializer.rb` + routes + `backend/public/api-docs/store.yaml`（`generated:check` 验证）。
- **platform（SDK）**：`src/types/generated/PaymentCombination.ts` + `src/zod/generated/` + `src/store-client.ts`（`paymentCombinations.create/complete`）+ 类型导出 + 测试。
- **storefront**：`lib/data/payment-combination.ts`（创建/完成）、`(checkout)/combined-payment/[id]/page.tsx` + 组件（复用 StripePaymentForm/confirm-payment）、账户订单多选（`components/account/OrderList.tsx` 扩展）、商品详情 Buy Now（`lib/data/` 快捷下单 + 详情页按钮）。
- **数据库**：新增迁移（store `preferred_auto_split_orders`，可 down）。
- **影响面**：`harness affected --base origin/main` 实施时确认。

## 8. 测试计划

- **backend（新增）**：
  - `backend/spec/services/pallastrade/carts/auto_split_spec.rb`（AC-001/002/003）
  - `backend/spec/requests/api/v3/store/payment_combinations_controller_spec.rb`（AC-004/005）
- **SDK（新增）**：`platform/packages/sdk/tests/payment-combinations.test.ts`（AC-006）
- **storefront（新增/更新）**：`components/account/__tests__/` 多选测试、`combined-payment` 页面组件测试、Buy Now 组件测试（AC-007/008）
- **E2E**：`storefront/e2e/` 下单→自动拆→合并支付→回调→订单列表父子视图（AC-002/005/007）
- **运行**：`harness check --profile quick` + 相关 rspec（docker exec pallastrade-web-1）+ `pnpm test`（sdk/storefront）+ `harness generated:check`

## 9. 文档同步清单（知识同步门）

- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引（P5 已建索引，状态随提交更新）
- [x] `ai/skills/pallastrade-checkout/SKILL.md`（新增「自动拆单 + Buy Now（P5）」）
- [x] `ai/skills/pallastrade-payments/SKILL.md`（新增「Store API（P5）」：组合端点 + 收银台）
- [x] API 文档：`backend/public/api-docs/store.yaml`（新增 `/payment_combinations` POST/GET + PaymentCombination schema）；`generated:check` 通过
- [x] SDK：`@pallastrade/sdk` 新增 `PaymentCombination` 类型 + `paymentCombinations.create/get`（typelizer + zod + 类型导出）
- [x] 升级方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md`（P5 段标记完成）
- [x] 其他 sync-check 命中项（历史变更）已评估，与 P5 无关无需更新

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-27 | 0.1 | 初稿：P5 Checkout 集成（自动拆单 + 合并支付收银台 + Buy Now，flag 灰度） | AI |
| 2026-08-27 | 0.2 | 实施完成：P5a 自动拆单（Carts::Complete hook + flag）+ P5b 合并支付（组合 API + SDK + 收银台 + 多选）+ P5c Buy Now；后端 30 + SDK 160 + storefront 211 测试全绿；gate GATE-2026-08-27T15-27-14 关闭；同步 skill/api-docs/升级方案 | AI |

## 1. 背景与目标

- **一句话需求原文**：<用户输入原文>
- **背景**：为什么做、解决什么问题
- **目标**：期望达成的结果
- **成功指标**：可量化指标（如：导入 1 万 SKU 耗时 < 60s）

## 2. 用户故事 / 场景

- 作为 <角色>，我希望 <能力>，以便 <价值>
- 场景列表（正常流 + 边界 + 异常）

## 3. 功能需求（FR）

- FR-001：<可验收的功能描述>
- FR-002：...

## 4. 非功能需求（NFR）

- 性能 / 安全 / 兼容 / 可维护性

## 5. 验收标准（AC，与测试一一映射）

> ⚠️ 以下为示例，正式内容请删除注释标记并替换为真实 AC：
- <!-- AC-001 ← FR-001：<可验证的判定条件> -->
- <!-- AC-002 ← ... -->

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | | | |
| Core | `pallastrade_gems/pallastrade_core/app/` | | | |
| API | `pallastrade_gems/pallastrade_api/app/` | | | |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | | | |
| Storefront | `storefront/src/` | | | |
| Platform | `platform/packages/` | | | |

**结论**：哪些层已有能力 / 哪些需新建 / 防重复判定

## 7. 技术影响

- 涉及组件 / 文件 / 依赖 / 数据库 / 接口
- 影响面（`harness affected --base origin/main` 输出）

## 8. 测试计划

- 新增测试文件（路径清单）
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射（AC-xxx → 测试文件）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |
