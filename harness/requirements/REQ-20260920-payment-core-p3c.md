# REQ-20260920-payment-core-p3c（P3-C 后台路由预览）

> Gate：（P3-C feature gate）｜ 关联 PRD：`docs/prd/checkout/PRD-20260920-checkout-…md`（P3 切片）
> 前置：P3-A（决策核心 `9c2b74b2`）/ P3-B（策略写入 + 预览服务 `a8dc148b`）

## Step 0：跨层搜索（6 层）

关键词：`routing` / `summary` / `provider_diagnostics` / `payment_option_entries`

| 层 | 路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 无实现 | ❌ |
| Core | `pallastrade_core/app/` | `payments/routing/summary.rb`（P3-B 预览服务，本期**复用不改逻辑**） | ✅ 已具备 |
| API | `pallastrade_api/app/` | 零契约变化 | ❌ 不涉及 |
| Admin | `pallastrade_admin/app/` | `views/.../payment_methods/_provider_diagnostics.html.erb`（P0-A/B 卡片、账户表单）+ `helpers/.../payments_helper.rb#provider_diagnostics` | ⚠️ 扩展（同一卡片内加只读区块，零新页面/零导航） |
| Storefront | `storefront/src/` | 不改 | ❌ |
| Platform | `platform/packages/` | 无契约变化 | ❌ |

**结论**：只加「展示层」——把 `Summary.for_store` 的结果投影到既有厂商编辑页，回答「这个方式现在由谁承接、我在第几位、为什么没被选中」。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ | 后台展示走 helper + partial；不改写路径 |
| `pallastrade-payments` | ✅ | 预览**必须显式标注** `order_gates: 'skipped'`（P3-B 铁律）—— 页面文案要写清"未做订单级判定" |
| `pallastrade-admin` | ✅ | 复用既有卡片与 class（`card`/`badge`/`form-text`），`data-testid` 作测试锚点；无新 Stimulus |
| `harness-prd` | ✅ | PRD 在册，P3-C 为切片推进 |

## 需求

在「支付方式」编辑页的厂商配置卡内新增**只读**「路由预览」区块：

1. 展示当前策略：模式（off / shadow / priority-only）+ `order_gates: skipped` 提示（明确"未做订单级判定，不代表可付"）。
2. 逐「支付方式」一行：方式 → 当前承接厂商（或"无候选"）、本厂商的位次与依据（优先序 / 位置）、若未承接则给出 reason。
3. 只列**本厂商参与**的方式（candidates 或 rejected 中出现），避免页面噪音。
4. 零写入、零网络、零资金副作用；无 store 或策略未配置时整块不渲染（`nil` → 视图跳过）。

## AC

| AC | 判定 | 验证 |
|---|---|---|
| AC-1 | 卡片渲染 `[data-testid="provider-routing-preview"]`，含模式标签与 `order_gates` 提示文案 | 请求 spec |
| AC-2 | 每个参与方式一行（`[data-testid="provider-routing-row-<kind>"]`），承接厂商名与位次/依据正确 | 请求 spec |
| AC-3 | 未被选中的厂商行显示 reason（如 `provider_disabled`）且不显示"承接" | 请求 spec |
| AC-4 | 不参与的方式不出现（不噪音） | 请求 spec |
| AC-5 | en ↔ zh-CN 键集相等 | `harness verify admin-i18n-rspec` |

## 测试计划

`harness verify payment-providers-rspec`（既有诊断卡请求规格新增 4 例）+ `harness verify payment-routing-rspec` + `harness verify admin-i18n-rspec`
