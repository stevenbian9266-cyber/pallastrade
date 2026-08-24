# REQ-20260824-order-status-tabs-and-payment-cashier

> 关联 PRD：PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台
> 需求类型：优化迭代（feature）

---

## Step 0：跨层搜索（6 层，全部执行）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | 订单列表/支付/选项卡 | （客户代码无相关覆盖，逻辑在 gems） | 否 |
| App — views/decorators | `backend/app/` | 订单 | 无 | 否 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/order.rb` | scope complete/unpaid、状态 | `scope :complete`（completed_at 非空）；`scope :unpaid_for_combined_payment`；`STATUSES/PAYMENT_STATES/SHIPMENT_STATES`；`PaymentGroup#active?`（本次已补） | 部分：需新增 processing/shipped/canceled/all scope |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/payment_groups/create.rb` | 合并支付组 | 已支持多订单/单订单组创建（含事务回滚，本次已修） | 是（可复用） |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/customer/orders_controller.rb` | scope | 现支持 `scope=unpaid` / 默认 `complete` | 需扩展分支 |
| API Gem — routes | `backend/pallastrade_gems/pallastrade_api/config/routes.rb` | orders/payment_groups | 路由已存在 | 是 |
| Admin Gem — controllers/views | `backend/pallastrade_gems/pallastrade_admin/` | 订单管理/支付组 | 订单管理、payment_groups 管理已存在 | 不涉及 |
| Storefront | `storefront/src/` | 订单页/合并支付/收银台 | `account/orders/page.tsx`、`CombinedPaymentPicker.tsx`、`CombinedPaymentContent.tsx`、`OrderList.tsx`、`orders/[id]/page.tsx`（仅 completed 无支付） | 需加选项卡、单订单支付、收银台支付方式选择 |
| Platform | `platform/packages/sdk/src/types/index.ts` | OrderListParams | 支持 `scope`、Ransack 谓词 `state_eq` 等 | 是（无需改 SDK） |

### 搜索结论
后端 API 已有订单列表与支付组创建能力；前端已有合并支付选择器与收银台骨架。本次为增量增强：后端 orders scope 扩展 + 前端状态选项卡、单订单支付入口、收银台支付方式选择。无重复实现需删除。

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators；Ransack 过滤走 `pallastrade-api-v3` |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | PRD 驱动闭环：确认 → gate（含 create-prd-doc/read-skill-*）→ REQ → 实施 → 测试 → 知识同步 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | Store API 契约：JWT 认证、prefixed ID、{data,meta} 信封、Ransack 过滤经 `params[:q]`/`scope` 透传 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | Checkout/CombinedPayment 章节：客户端挂载渲染、Stripe key build arg、合并支付 3DS redirect-back；订单页属 account 区域 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读（本会话既有知识） | 前端 Vitest + Testing Library；后端 RSpec；AC→测试标注 `# PRD-xxx AC-x` |
| `ai/skills/pallastrade-i18n/SKILL.md` | ✅ 已读（本会话既有知识） | 6 语言 messages JSON，key 语义化 |

---

## 需求标题：订单列表状态选项卡 + 待支付订单单独/合并支付收银台

### FR（对应 PRD §3）

- FR-001：订单页状态选项卡（全部/待支付/待发货/已发货/已完成/已取消），`?status=` 驱动。
- FR-002：后端 orders scope 扩展 `unpaid/processing/shipped/canceled/all`，默认 `complete`。
- FR-003：待支付订单每行「支付」按钮 → 单订单 PaymentGroup → 跳收银台。
- FR-004：合并支付保留（勾选多个 → Pay Together）。
- FR-005：收银台支付方式选择（RadioGroup）→ 确认 → 创建 session → Stripe 表单。
- FR-006：支付成功回订单列表，状态更新。

### AC（对应 PRD §5，实施测试标注 `# PRD-20260824-checkout-… AC-x`）

- AC-001：订单页渲染 6 选项卡，默认「全部」。
- AC-002：切换选项卡列表按状态过滤（含空态）。
- AC-003：后端各 scope 返回正确订单集合。
- AC-004：单订单「支付」创建 1 订单组并跳转收银台。
- AC-005：合并支付回归可用。
- AC-006：收银台可选支付方式，确认后出 Stripe 表单。
- AC-007：测试卡支付成功 → 订单/组完成。
- AC-008：成功页返回入口；3DS 回归可续付。

### 接口变更
- `GET /api/v3/store/customers/me/orders` 的 `scope` 枚举扩展（store.yaml 同步）。
