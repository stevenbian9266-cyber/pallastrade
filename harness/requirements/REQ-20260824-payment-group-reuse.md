# REQ-20260824-payment-group-reuse

> 关联 PRD：PRD-20260824-checkout-合并支付复用已有支付组继续支付-订单已在支付组时不报错
> 需求类型：优化迭代（feature）

---

## Step 0：跨层搜索（6 层，全部执行）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | payment_group / 支付组 | 无（客户代码无支付组逻辑） | 否（不涉及） |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/payment_group.rb` | active? / 状态机 / expires_at | `active?`（pending/processing 且未过期）；状态机 pending→processing/completed/failed/canceled/expired；`scope :active` | 部分：`active?` 可直接复用 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/payment_groups/create.rb` | validate_orders! / order_in_active_group | `validate_orders!` 第 6 项 `order_in_active_group`（订单在 active 组即失败）；创建时未设 `expires_at` | **需修改**：改为幂等复用 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/payment_groups_controller.rb` | order_in_active_group | 错误映射表含 `order_in_active_group` | 无需改（Create 不再产生该错误，映射保留） |
| API Gem — routes | `backend/pallastrade_gems/pallastrade_api/config/routes.rb` | payment_groups | 路由已存在 | 是 |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/` | payment_group | `admin/payment_groups_controller.rb` + index/show 视图（只读管理） | 不涉及 |
| Storefront | `storefront/src/` | createPaymentGroup / CombinedPayment | `components/account/CombinedPaymentPicker.tsx`（paySingle/payNow → createPaymentGroup → router.push 收银台） | 无需改：后端返回已有组即自动跳转 |
| Platform | `platform/packages/sdk/` | paymentGroups.create | `sdk/src/store-client.ts` POST /payment_groups 返回 PaymentGroup | 无需改：接口契约不变 |

### 搜索结论
唯一需改 Core 层 `PaymentGroups::Create`（幂等复用）+ 后端 spec。前端/SDK/Admin/API 契约均不变。无重复实现。

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：行为修正属业务逻辑改动；PaymentGroups::Create 已是 gem 内 PALLAS-CUSTOM 服务，直接修改为正确层（Gem Modification） |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | PRD 驱动闭环：确认 → gate（create-prd-doc/read-skill-*）→ REQ → 实施 → 测试 → 知识同步门 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | Payment Groups 章节："Membership 校验：same store/user/currency；no canceled / already-paid / **already-in-active-group** orders"——需将 already-in-active-group 从拒绝改为幂等复用；状态机 pending→processing→completed + failed/canceled/expired |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读（本会话既有知识） | Store API：JWT 认证、prefixed ID、错误信封 `{error:{code,message}}` |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读（本会话既有知识） | CombinedPaymentPicker/Content 客户端跳转收银台；后端返回组 id 即可续付 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读（本会话既有知识） | 后端 RSpec service spec；AC→测试标注 `# PRD-xxx AC-x` |

---

## 需求标题：合并支付复用已有支付组继续支付（订单已在支付组时不报错）

### FR（对应 PRD §3）

- FR-001：`PaymentGroups::Create` 不再因订单已在 active 组失败，存在 active 组时返回该组（幂等）。
- FR-002：存在多个 active 组时复用**最近创建**的组（created_at 最大）。
- FR-003：本次所选订单（含其它组/未入组）全部并入被复用组，`amount` 重算。
- FR-004：并入时校验货币一致（订单 currency == 目标组 currency），否则 `mixed_currency`。
- FR-005：其余校验（not_found/not_owned/canceled/already_paid）保持回归。
- FR-006：前端/SDK 无需改动。

### AC（对应 PRD §5，测试标注 `# PRD-20260824-checkout-合并支付复用已有支付组继续支付-订单已在支付组时不报错 AC-x`）

- AC-001：已有 active 组 → success 且 group.id 等于已有组。
- AC-002：重复调用不新建组（组数量不变）。
- AC-003：跨 2 个 active 组 → 返回最近组，全部订单并入。
- AC-004：混合（部分已入组）→ 返回已有组，未入组订单并入，amount=组内全部订单之和。
- AC-005：货币不一致 → `mixed_currency`。
- AC-006：已支付/已取消/非本人/未知订单 → 原错误回归。
- AC-007：无 active 组 → 正常创建（回归）。
- AC-008：前端命中已有组时跳转该组收银台继续支付（浏览器验证）。

### 测试计划

- 更新 `backend/spec/services/pallastrade/payment_groups/create_spec.rb`：AC-001~007 用例。
- 前端：`CombinedPaymentPicker.test.tsx` 回归（行为不变）。
- 部署 dev 后浏览器验证 AC-008。
