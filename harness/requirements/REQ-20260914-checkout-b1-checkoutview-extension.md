# REQ-20260914-checkout-b1-checkoutview-extension

> 关联 PRD：`docs/prd/checkout/PRD-20260914-checkout-checkout-收尾收敛-b1-checkoutview-扩展-credits-capabilities-availa.md`
> 关联任务：TASK-20260914165350-4efc69a5 · Gate `GATE-2026-09-14T16-55-15`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `credits/capabilit/available_payment/billing_mode/checkout_view` | 仅 AI 域 admin 控制器与生成类型；无 checkout 视图实现 | 否（宿主层无需改） |
| App — views/decorators | `backend/app/` | 同上 | 无 | 否 |
| Core Gem — models | `pallastrade_core/app/models/` | `gift_card/store_credit/payment_methods` | `order/gift_card.rb`（`gift_card`、`gift_card_total`/display）、`order/store_credit.rb`（`total_applied_store_credit`/`display_total_applied_store_credit`、`covered_by_store_credit?`）、`order.rb#payment_methods`（active+front_end+`available_for_order?`） | 是（数据源已存在） |
| Core Gem — services | `pallastrade_core/app/services/pallastrade/order_checkout/` | `credits/capabilit/available_payment/billing_mode` | `view.rb`（现有投影缺这 4 组字段）、`readiness.rb`（ready/missing_requirements 已有） | 部分（需扩展 View） |
| API Gem — controllers | `pallastrade_api/app/controllers/` | `checkout` | `store/orders/checkout_controller.rb`（只读 show；mutation 走既有端点） | 是（无需新端点） |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | `store_credit/gift_card` | `payments_controller#available_store_credits`、`store_credits_controller` 等（后台自有用例，与本批无交互） | 否（不涉及） |
| Admin Gem — views | `pallastrade_admin/app/views/` | `gift_card_total/store_credit` | 后台礼品卡/余额页面（仅显示用途） | 否（不涉及） |
| Storefront | `storefront/src/` | `credit/gift/capabilities/available_payment` | `OrderPaymentContent.tsx`（缺礼卡/余额行、无 capabilities、支付方式依赖 Order 回退）、`UnifiedCheckout.tsx`（cart_ 页，归 B2） | 部分（需消费新字段） |
| Platform | `platform/packages/` | `checkout types` | `sdk/src/{types,zod}/generated/`（生成物，随契约再生） | 部分（再生成） |

### 搜索结论

- 能力载体（Order 列/方法、PaymentMethod 作用域、Readiness）**全部已存在**；本批为 **View + Serializer + Storefront 消费** 的增量扩展。
- 无需新表、新服务、新端点；零写路径改动。
- 防重复：`PRD-20260903-checkout-chk-p1-1a` 建立只读 CheckoutView（done），本批补 §17 缺口，非重复 PRD。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 定制优先级 Settings→Configuration→Events→Dependencies→Admin/Ransack→Generators→Decorators→Extensions；本批为既有服务/序列化扩展（不引入新定制模式），属最稳层级 |
| `ai/skills/pallastrade-admin/SKILL.md` | ⛔ 本次不涉及 | 本批零 admin 页面/控制器改动（后台余额/礼卡页面与本批无交互），按 §Decision Tree 无需该 Skill 结论 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⛔ 本次不涉及 | 不涉及商品/目录模型 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | Store API 契约：`X-PallasTrade-Api-Key` + 可选 `X-PallasTrade-Token`/JWT；checkout 域已有 `GET /orders/:id/checkout` 只读视图与 order 域 payment_sessions；序列化「customer-visible only / 金额 hide_prices 门控」约定 |
| `pallastrade-testing` | ✅ | ✅ 已读 | RSpec + Factory Bot（禁止 `Model.create`）；复用 pallastrade 工厂（`create(:order_with_line_items)` 等）；API 域用共享 context；「环境无关断言」教训适用 |
| `pallastrade-storefront` | ✅ | ✅ 已读 | 前端经 `@pallastrade/sdk` 服务端调用；`lib/pallastrade/config.ts` 的 8s 超时封装必须保留；组件测试走 vitest |
| `harness-prd` | ✅ | ✅ 已读 | 阶段 0-5：PRD 自动扩充 → 用户确认 → gate → 实施 → AC↔测试（`prd verify`）→ 知识同步门 |
| `pallastrade-decorators` | ⛔ | ⛔ | 不改既有类结构 |
| `pallastrade-dependencies` | ⛔ | ⛔ | 不替换核心服务 |
| `pallastrade-events-webhooks` | ⛔ | ⛔ | 无事件/订阅者改动 |
| `pallastrade-i18n` | ⛔ | ⛔ | 不新增文案键（复用既有 i18n key；如新增行文案沿用现有 key） |

---

## 需求标题

Checkout 收尾收敛 B1：CheckoutView 扩展（credits/capabilities/available_payment_methods/billing_mode）与 or_ 页消费

## 任务类型

功能优化（接口 additive 变更 + 前台消费）

## 需求描述

or_ 补付页目前缺少「礼品卡 / 店铺余额」金额行，支付方式列表依赖 Order 序列化回退，编辑能力无服务端依据。本批把 4 组只读字段（credits / capabilities / payment.available_payment_methods / billing_mode）补进 CheckoutView 并由页面消费，使页面数据源收敛到服务端权威视图（方案 §17/§28）。

## 影响范围（harness affected 输出）

`harness affected` 输出（实施时补）：受影响组件 = Store API Checkout 序列化、or_ 页渲染、SDK 类型；不涉及 DB 迁移与写路径。

## 技术方案（初步）

1. `OrderCheckout::View` 增加 4 组只读方法（组合既有 Order 列/方法与 `order.payment_methods`），`INCLUDES` 增补 `:gift_card` 防 N+1；
2. `CheckoutSerializer` 以 typelize 对象字面量输出（金额按 `hide_prices` 门控）；
3. `OrderPaymentContent.tsx` 消费：credits 行渲染、支付方式视图优先、capabilities 控制、billing_mode 初始态；
4. 契约再生成（typelizer + api-docs）并跑 `generated:check`。

## 风险点

- 最高风险：契约再生成（SDK types/zod）与 OpenAPI schema 漂移 → 以 `generated:check` 为准；回滚难度低（additive 字段，可单独回退本批提交）。
- 语义风险：`billing_mode` 为派生值（地址相等性判定）→ 仅用于初始态提示，不作写路径依据。

## 决策节点

> ⏸️ 用户已于 2026-09-14 会话明确指令：「根据《…完整方案.md》，拆解出任务节奏，输出非常细致的 PRD，然后开始实施任务」——即对「按方案拆解并实施」的明确授权；PRD/REQ 呈现后直接进入实施。

---

## 阶段③：实施后验证（不可跳过）

> ⚠️ 每项改动都必须有对应的最低验证。

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 后端（View/Serializer） | `order_checkout/view.rb`、`checkout_serializer.rb` | `npx harness verify chk-p1-1a-rspec --task <id>` | ✅ EVD-20260914171840-910ce286f6（verifier 全绿） | ✅ |
| 前端（or_ 页） | `storefront/src/components/checkout/OrderPaymentContent.tsx` | `npx harness verify chk-p1-4b-storefront --task <id>` | ✅ EVD-20260914171925-1a1be6ebb0（OrderPaymentContent 15+5 例全绿） | ✅ |
| 契约 | `backend/public/api-docs/store.yaml`、`platform/docs/api-reference/`、`sdk generated/dist` | `npx harness generated:check` | ✅ no drift detected（typelize + api-docs + 副本同步） | ✅ |
| 其它 | 前端静态检查 | `biome check` + `tsc --noEmit` | ✅ 均通过（SDK dist 重建 + storefront junction 刷新后） | ✅ |
| 其它 | PRD/README 状态 | `node scripts/ci/prd-status-sync.mjs --check` | 待执行 | ⬜ |
| 声明无需验证 → 原因：_____ | — | — | — | — |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

**本批不涉及 admin 页面** —— 无 admin 视图/控制器改动，三项检查豁免（记录在案）。

### 验证结论

- 后端：`chk-p1-1a-rspec` 验证器全绿（含 view_spec / checkout_serializer_spec / checkout_controller_spec / 订单域回归）；新增 20 例中 B1 相关 14 例全部通过。
- 前端：`chk-p1-4b-storefront` 全绿（OrderPaymentContent 20 例：15 旧 + 5 新）；`biome check` 与 `tsc --noEmit` 通过。
- 契约：`generated:check` = no drift（typelizer 类型 + api-docs schema + platform 副本 + SDK dist 重建）。
- 零写路径改动：未触碰数据库迁移、状态机、PaymentSession 创建。
