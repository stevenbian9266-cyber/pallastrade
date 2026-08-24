# PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台

| 元数据 | 值 |
|---|---|
| 状态 | done（已验证上线） |
| 创建日期 | 2026-08-24 |
| 来源 | 优化：1、商城前台 order 菜单下，增加订单状态选项卡，按照订单状态切换显示订单列表 2、待支付订单，可以单独支付、可以合并支付，流程是：点击支付、唤起收银台、选择支付方式、支付 |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-storefront、pallastrade-api-v3、pallastrade-payments |
| 关联 REQ | REQ-20260824-order-status-tabs-and-payment-cashier.md |
| 关联 PRD | PRD-20260823-checkout-多订单拆分与合并支付（合并支付基础，本 PRD 在此基础上增强） |
| 需求类型 | 优化迭代 |

> 🔒 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。本需求与 PRD-20260823（拆分与合并支付）相关但为**增量增强**（新增状态选项卡 + 单订单支付 + 收银台选择支付方式），相似度未达阻止阈值，作为新 PRD 关联原 PRD。

## 1. 背景与目标

- **一句话需求原文**：优化：1、商城前台 order 菜单下，增加订单状态选项卡，按照订单状态切换显示订单列表 2、待支付订单，可以单独支付、可以合并支付，流程是：点击支付、唤起收银台、选择支付方式、支付
- **背景**：当前商城前台订单页（`account/orders`）只有「待支付合并支付区块 + 已完成订单列表」两块静态内容，无状态分类；待支付订单只能通过勾选多个后「合并支付」，没有单个订单的「支付」入口；合并支付收银台（`combined-payment/[id]`）不展示支付方式列表，直接显示 Pay 按钮。
- **目标**：
  1. 订单列表按状态分选项卡（全部 / 待支付 / 待发货 / 已发货 / 已完成 / 已取消），可切换。
  2. 待支付订单支持**单独支付**与**合并支付**，统一收银台流程：点击支付 → 唤起收银台 → 选择支付方式 → 支付。
- **成功指标**：用户在订单页 3 步内完成一次支付；状态切换列表正确无串台；单订单与多订单支付均能走通 Stripe 并完成订单。

## 2. 用户故事 / 场景

- 作为商城顾客，我希望在订单列表按状态查看订单，以便快速找到待支付/待收货订单。
- 作为商城顾客，我希望每个待支付订单都能单独支付，也能勾选多个合并支付，并在收银台选择支付方式后完成支付。

场景：
- 正常：订单页 → 点「待支付」选项卡 → 看到待支付订单 → 点单个订单「支付」→ 收银台 → 选「Credit Card」→ 确认 → Stripe 填卡 → 支付成功 → 返回订单列表该订单已支付。
- 正常：订单页 → 勾选多个待支付订单 → 「Pay Together」→ 收银台（合计）→ 选支付方式 → 支付成功 → 全部订单完成。
- 边界：无待支付订单时，选项卡仍显示但列表为空提示。
- 异常：支付中途取消/3DS 重定向返回 → 订单仍待支付，可重新发起。

## 3. 功能需求（FR）

- FR-001：订单列表页增加状态选项卡（全部 / 待支付 / 待发货 / 已发货 / 已完成 / 已取消），默认「全部」；切换后按对应状态拉取并展示订单。
- FR-002：后端 Store API 订单列表 `scope` 参数扩展：`unpaid`（已有）、`processing`（已付款待发货：fulfillment_status ∈ pending/ready/partial 且非待支付）、`shipped`（fulfillment_status = shipped）、`canceled`（status = canceled）、`all`（全部）；默认保持 `complete`（已完成）。
- FR-003：待支付订单区块（CombinedPaymentPicker）每个订单增加「支付」按钮 → 为该订单创建 1 个订单的 PaymentGroup → 跳转收银台。
- FR-004：合并支付保留：勾选多个待支付订单 → 「Pay Together」→ 创建 PaymentGroup → 跳转收银台。
- FR-005：收银台（CombinedPaymentContent）增加「选择支付方式」步骤：展示可用支付方式（RadioGroup）→ 确认 → 创建 payment session → 显示 Stripe PaymentElement 表单 → 填卡支付。
- FR-006：支付成功后回到订单列表，订单状态更新为已支付；收银台显示成功态与返回入口。

## 4. 非功能需求（NFR）

- 性能：订单列表分页保持（limit 50），切换选项卡请求量小。
- 安全：支付组创建沿用现有校验（同用户/同货币/未支付/未在 active 组）；无新增权限面。
- 兼容：SDK 参数兼容（`scope` 顶层 + `q[scope]` 均支持，沿用现实现）。
- 可维护：状态映射（选项卡 → scope/谓词）集中在订单页与后端 controller，避免散落。

## 5. 验收标准（AC，与测试一一映射）

- AC-001（→ FR-001）：订单页渲染 6 个状态选项卡，默认「全部」。
- AC-002（→ FR-001）：切换选项卡后列表仅显示对应状态订单（含空态提示）。
- AC-003（→ FR-002）：后端 `scope=unpaid|processing|shipped|canceled|all|complete` 各返回正确订单集合。
- AC-004（→ FR-003）：待支付订单每行有「支付」按钮；点击后创建含 1 订单的组并跳转收银台。
- AC-005（→ FR-004）：勾选多个订单「Pay Together」仍可创建组并跳转收银台（回归）。
- AC-006（→ FR-005）：收银台展示支付方式列表并可选择；确认后出现 Stripe 表单。
- AC-007（→ FR-005）：用测试卡 4242 完成支付 → 订单/组标记已完成 → 返回订单列表状态更新。
- AC-008（→ FR-006）：支付成功页有返回订单列表入口；3DS 重定向返回后订单仍可续付（回归 PRD-20260823）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 订单列表/支付 | （客户代码无覆盖，逻辑在 gems） | 无 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/order.rb` | scope complete/unpaid_for_combined_payment、STATUSES/PAYMENT_STATES/SHIPMENT_STATES | `complete` = completed_at 非空；`unpaid_for_combined_payment`；`scope :active`（PaymentGroup） | 需扩展 processing/shipped/canceled/all scope |
| API | `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/customer/orders_controller.rb` | scope 参数 | 现支持 unpaid / 默认 complete；Ransack q | 需加分支 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/` | 订单管理/拆单 | payment_groups 管理、订单管理已存在（拆分/合并支付基础） | 不涉及 |
| Storefront | `storefront/src/app/[country]/[locale]/(storefront)/account/orders/page.tsx` + `storefront/src/components/account/CombinedPaymentPicker.tsx`、`CombinedPaymentContent.tsx`、`OrderList.tsx`、`orders/[id]/page.tsx` | 订单页/合并支付/收银台 | 现有待支付区块（合并勾选）+ 完成订单列表；订单详情页仅 completed 无支付 | 需加选项卡、单订单支付、收银台支付方式选择 |
| Platform | `platform/packages/sdk/src/types/index.ts`（OrderListParams） | Ransack 谓词 | 支持 `scope`、`state_eq`、任意 q 键 | 可复用，无需改 SDK |

## 7. 测试计划

- 后端：`orders_controller_spec` 覆盖 scope 各分支；`PaymentGroups::Create` 单订单组回归。
- 前端（Vitest）：
  - 订单页状态选项卡渲染与切换（mock getOrders 返回不同状态）。
  - `CombinedPaymentPicker` 单订单「支付」按钮 → 创建单订单组并跳转。
  - `CombinedPaymentContent` 支付方式选择 → 确认 → Stripe 表单出现（现有 CombinedPaymentContent.test.tsx 扩展）。
- E2E：完整单订单支付 + 合并支付（Stripe 测试卡 4242 + 3DS 4000002500003155）。
- 验收：每个 AC 映射测试标注 `# PRD-20260824-checkout-… AC-x`。

## 8. 接口变更与文档同步清单

- `backend/public/api-docs/store.yaml`：orders 列表 `scope` 枚举补充（unpaid/processing/shipped/canceled/all/complete）。
- `platform/docs/api-reference/`：同步 scope 文档。
- `ai/skills/pallastrade-storefront/SKILL.md`：订单页选项卡、待支付单订单支付、收银台选择支付方式。
- `ai/skills/pallastrade-api-v3/SKILL.md`：orders scope 扩展。
- `harness/scenarios/scenarios.json`：新增 Eval Scenario（GS-041）。
- `docs/prd/README.md`：索引登记本 PRD。

## 9. 实施要点（草案，确认后细化）

1. 后端 `orders_controller#scope` 扩展 scope 分支（processing/shipped/canceled/all）。
2. 前端订单页：server 端按 `searchParams.status` 拉取对应订单 + 选项卡 UI（client 组件切换或链接）。
3. `CombinedPaymentPicker`：每行加「支付」按钮（单订单组）。
4. `CombinedPaymentContent`：加支付方式选择（RadioGroup）→ 确认 → createGroupPaymentSession → Stripe 表单。
5. i18n：orders 命名空间补状态/按钮文案（6 语言）。
6. 按 gate 流程实施 + evidence + 部署 dev 验证。

## 10. 知识同步门结论（实施后填写）

| 资产 | 结论 |
|---|---|
| `backend/public/api-docs/store.yaml` | ✅ 已更新：orders 列表新增 `scope` 参数（all/unpaid/processing/shipped/canceled，默认 completed），SDK 示例同步 |
| `platform/docs/api-reference/store.yaml` | ✅ 已同步（复制后端 store.yaml） |
| `platform/packages/sdk` 类型 | ✅ `OrderListParams.scope?: string` 显式类型 + 重建 dist（scope 已是 PASSTHROUGH_KEYS） |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已更新：状态选项卡 + 单订单支付 + 收银台支付方式选择小节 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | 已评估，无需更新：SKILL 的 "scope" 指 API key 权限 scope，非本列表过滤参数；orders 过滤已记录在 store.yaml/SDK 类型 |
| `harness/scenarios/scenarios.json` | ✅ 已新增 GS-041（订单状态选项卡 + 单独/合并支付收银台） |
| `platform/packages/README.md` | ✅ 已更新 List params scope 说明 |
| 组件测试 | ✅ `OrderStatusTabs.test.tsx`、`CombinedPaymentPicker` 单支付用例、`CombinedPaymentContent` 支付方式选择用例 |
| 后端测试 | ✅ 新增 `spec/requests/api/v3/store/customer/orders_spec.rb`（scope 分支 7 用例，服务器部署后运行） |
| 反模式 | 已评估：无 AP-001/002/006/009 违规；`payNow`/`paySingle` 复用 SDK client |
| `docs/prd/README.md` | ✅ 索引已登记 |

- [x] Skill / README / Agent / 样式规范 / 技术规范 / 反模式 / 场景库 / API 文档逐项处理
- [x] `harness sync-check --ack`

## 回写记录（harness prd update）

| 日期 | 来源 | 操作者 |
|---|---|---|
| 2026-08-24 | docs/prd/checkout/PRD-20260824-checkout-订单列表状态选项卡-待支付订单单独-合并支付收银台.md | AI |
