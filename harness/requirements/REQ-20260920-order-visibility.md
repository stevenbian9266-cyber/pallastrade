# REQ-20260920-order-visibility（订单可见性补齐）

> **关联 PRD**：`docs/prd/checkout/PRD-20260920-checkout-订单可见性补齐-后台列表显示未完成订单-支付失败就地入口-游客最近一笔订单入口.md`（状态 **approved**，2026-09-21 用户「实施」确认）
> **关联设计文档**：`docs/design/payment-convergence-stripe-only.md` §13 + §11 决策 10–12 + §11.1 硬约束 C-4 / C-6
> **任务**：`TASK-20260920180419-d8bbfdad` · Gate `GATE-2026-09-20T18-04-23`
> **风险等级**：critical（`harness risk check`）

> 所有任务先做 Step 0（跨层搜索），再按任务类型填写并等待用户确认。

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | order / visibility / submitted_at / 未支付订单 | 无 | ❌ 无（Host App 未覆盖订单可见性） |
| App — views/decorators | `backend/app/` | orders / account | 无 | ❌ 无 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | scope :complete / completed_at / submitted_at | `pallastrade/order.rb:294-296`（`scope :complete = where.not(completed_at: nil)`、`scope :incomplete`）；`order/checkout.rb:127,344`（`after_transition to: :complete, do: :create_user_record`，要求 `signup_for_an_account?`） | ⚠️ 部分：**无**「已提交未完成」作用域 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | build_order / user / token | `carts/submit.rb#build_order!`（`user: cart.user` → 游客订单 `user_id = NULL`；`token: cart.token` 游客凭证）；`orders/create_user_account.rb`（按 email 关联，仅 legacy state machine 调用） | ⚠️ 部分：建单已有；**可见性机制无** |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | orders scope / user_id / token | `v3/store/orders_controller.rb`（`OrderResolvable`，**含 `state=pending`**，凭 `X-PallasTrade-Token`）；`v3/store/customer/orders_controller.rb#scope`（`require_authentication!` + `where(user_id: current_user.id)`） | ⚠️ **不对称**：单订单游客可见、列表不可见 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | orders / scope / complete | `pallastrade/admin/orders_controller.rb#scope`（`action_name == 'index'` → `base_scope.complete`） | ❌ **口径过窄**（本次要修） |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | orders index / 筛选 | `pallastrade/admin/orders/index.html.erb` | ⚠️ 需加状态筛选 |
| Storefront | `storefront/src/` | account/orders / payment-failed / setCheckoutCookies | `app/…/account/orders/page.tsx`；`app/…/account/layout.tsx`（useAuth 门控）；`components/checkout/UnifiedCheckout.tsx`（`payment-failed` **无**指向订单的入口）；`lib/pallastrade/cookies.ts#setCheckoutCookies`（HttpOnly order id + token）；`app/…/(checkout)/payment-result/[id]/page.tsx`（**已对游客可用**，自带 `retryHref = /checkout/{orderId}`）；`lib/data/customer.ts#finalizeAuth`（只 `carts.associate`） | ⚠️ token 授权链**已有**；缺**发现入口** |
| Platform | `platform/packages/` | customer.orders.list / orders.get | SDK 既有类型 | ✅ 足够，**无需改** |

### 搜索结论

- **已有能力**：游客订单的**单点**访问链完整（`setCheckoutCookies` → `/payment-result/[id]` 凭 `getOrderForCheckout` 渲染 → 自带补付入口）；API 单订单端点已含 `state=pending`。
- **需要新建**：Admin 列表口径修正 + 状态筛选；Storefront 支付失败页内入口、`/orders/recent` 恢复路由、新文案。
- **防重复判定**：**不是重复建设** —— 不重建游客订单访问机制，只补「能被发现」与「后台口径对齐」；**0 新增 API 端点、0 migration、0 新事件**。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 本次**不走自定义决策树第 1–7 级**：不改 core 模型/服务、不加 decorator/extension；属对既有 admin gem 控制器与前台组件的**就地修改**（决策树第 8 级），无升级合并冲突面 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | ① 「面包屑由导航配置自动推导（P6 起统一单一 sidebar 树）」→ 本次**不新增后台页面**，仅改既有 orders 列表的 `#scope` 与筛选，面包屑**自动不变**；② 「资金类后台页应挂到 Fund 下（不要塞进 Orders）」→ 本次不新增页面，不涉及 |
| `ai/skills/pallastrade-checkout/SKILL.md` | ✅ 已读 | §"Guest checkout vs logged-in" 原文：*"After completion, the guest's order token remains the credential for viewing the order — `GET /api/v3/store/orders/:id` with the `X-PallasTrade-Token` header. … **There is no number+email claim flow, and registering later does not auto-link past guest orders.**"* → **本 REQ 的 D-3（取 C1 不做 C2）与 §1.4 非目标即据此**；同时确认「游客订单列表不可见」是**既有设计**而非本次引入的缺陷，故定位为「补发现入口」而非「改鉴权」 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ❌ 不涉及 | ✅ 已读 | 本 REQ **不改任何 API 端点/序列化器/OpenAPI**（§7.2 契约影响 = 全不变）；`/orders/recent` 是 Next.js 路由而非 API |
| `pallastrade-decorators` | ❌ 不涉及 | — | 不改 core 类结构 |
| `pallastrade-dependencies` | ❌ 不涉及 | — | 不替换核心服务实现 |
| `pallastrade-events-webhooks` | ❌ 不涉及 | ✅ 已读 | 硬约束 **C-7**：不新增订单类事件（`order.submitted` 已是建单提交后的语义等价事实源） |
| `pallastrade-storefront` | ✅ 涉及 | ✅ 已读 | 结账页/支付区约定：失败态**页内提示、零跳转**（PRD-20260919-checkout-express-always-visible AC-003/004）；本次新增入口必须**不破坏**该口径（AC-006 锁定） |
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 后端 RSpec（`backend/spec/requests/**`）+ 前台 Vitest（`storefront/src/**/__tests__/*.test.tsx`）；每条 AC 必须落测试，测试内标注完整 PRD-ID + AC-x |
| `pallastrade-i18n` | ✅ 涉及 | ✅ 已读 | 用户可见文案必须 en + zh-CN 双向键集一致；前台用 `pnpm --filter pallastrade-storefront check:locales` 校验（AC-011） |

---

## 需求标题

订单可见性补齐：后台列表显示未完成订单 + 支付失败就地入口 + 游客最近一笔订单入口

## 任务类型

功能优化（可见性修复）

## 需求描述

用户报告「点击支付按钮后看不到订单」。经取证：**订单确实已创建**（代码/测试/DB 三重证据），问题是三处**可见性**缺口：

1. 后台订单列表用 `base_scope.complete`（`completed_at IS NOT NULL`），而 `completed_at` 只在 `finalize!` 后写入 → 本地 7 张 `pending` + 3 张「已支付未 finalize」订单在 `/admin/orders` **完全不可见**。
2. 前台 `/account/orders` 按 `user_id` 作用域且要求登录，而 `Carts::Submit` 用 `user: cart.user` → 游客订单 `user_id = NULL` → **永不入列**；注册/登录也不回溯关联。
3. 支付失败时前台只 `setPayError({kind:"payment-failed"})`，**没有任何指向该订单的入口**。

用户 2026-09-21 确认设计文档 §11 决策 10–12（后台默认全显 + 状态筛选；支付失败就地入口；游客取 C1），并批准本 PRD 实施。

## 影响范围（harness affected 输出）

> 立项基线（工作树含并行会话改动，仅说明工具链可用）；实施完成后重跑回填。

```json
{ "filesChanged": 26, "affectedComponents": ["backend", "harness"], "errors": [], "estimatedTests": 78 }
```

## 技术方案（初步）

- **FR-001（Admin）**：`orders_controller.rb#scope` 的 `index` 分支由 `base_scope.complete` 改为 `base_scope.where.not(submitted_at: nil).or(base_scope.complete)` —— 与前台 `customer/orders_controller#scope` 口径**完全一致**；**排除** `state=cart` 草稿（本地 6 张）。保留 `current_store` 与 `accessible_by(current_ability, :index)` 两个收窄调用**不动**。
- **FR-002（Admin）**：列表加状态筛选（复用既有 Ransack/集合筛选机制），默认「全部」。
- **FR-003（Storefront）**：`UnifiedCheckout` 的 `payment-failed` 分支渲染「订单 `<编号>` 已创建，尚未支付」+ 链接到 `/payment-result/{orderId}`（该页已对游客可用且自带补付入口）→ **零后端改动**。
- **FR-004（Storefront）**：新增无需登录的 `/orders/recent`：读 HttpOnly checkout cookie，有效则 302 → `/payment-result/{orderId}`，否则空态页。**只读 cookie，不接受任何请求参数指定 id**（防越权枚举）。
- **FR-005**：新文案 en + zh-CN 同步。

## 风险点

| 风险 | 缓解 | 回滚难度 |
|---|---|---|
| 放宽后台 scope 导致**跨店/越权**（R-2，影响高） | 保留 `current_store` + `accessible_by` 不动；AC 加跨店用例 | 低（单方法一行回退） |
| `/orders/recent` 被用于**枚举他人订单**（R-3，影响高） | 只读 HttpOnly cookie，不接受外部 id（AC-010 锁定）；空态与「不存在」不可区分 | 低（删路由 + 移除入口） |
| 历史垃圾单涌入后台（R-1） | scope 限定「已提交 ∪ 已完成」而非全部；提供筛选 | 低 |
| 新入口让顾客**误以为已付款**（R-4） | 文案明确「尚未支付」；不改状态图标语义；AC-006 保证零跳转 | 低 |

> 最高风险：R-2 / R-3（均为**权限类**，影响高、概率低）。**无数据写入**，故回滚 = `git revert`，无数据恢复动作。

## 决策节点

⏸️ **用户已于 2026-09-21 明确回复「实施」** → PRD 状态置 `approved`，进入实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Admin 控制器（Ruby） | `pallastrade_admin/.../orders_controller.rb#scope` | `bundle exec rspec spec/requests/pallastrade/admin/orders_visibility_spec.rb` | **3 examples, 0 failures**（AC-001/002/003） | ✅ |
| 后台订单可见性 spec | `backend/spec/requests/pallastrade/admin/orders_visibility_spec.rb` | 同上 | 覆盖 pending 可见 / paid-未 finalize 可见 / cart 草稿不可见 / 与前台 predicate 一致 | ✅ |
| 前台组件 | `storefront/src/components/checkout/UnifiedCheckout.tsx` | `npx vitest run src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | **52 tests passed**（含新用例 AC-005/006/007：入口 href / 只建一次单 / 零跳转零 PATCH） | ✅ |
| 前台新路由 | `storefront/src/app/[country]/[locale]/(checkout)/orders/recent/page.tsx` | `npx vitest run ".../orders/recent/__tests__/page.test.tsx"` | **4 tests passed**（AC-008/009/010 + 非法 cookie 值守卫） | ✅ |
| 文案（5 locale） | `storefront/messages/{en,de,es,fr,pl}.json` | `npx tsx scripts/check-locale-parity.ts` | **All locale files are in sync**（checkout 200→204 / orders 53→56） | ✅ |
| 后台导航 | 不变 | `pallastrade:admin:nav_validate` | **nav:validate OK — 0 warning(s)** | ✅ |
| 类型检查 | — | `npx tsc --noEmit` | ⚠️ **有报错，但均为既有**（`OrderPaymentContent.tsx` / `lib/data/order-payment.ts` 的 `StoreOrdersPaymentPreflight` 未从 SDK 导出）；本次改动文件（`UnifiedCheckout.tsx`）**不在报错列表**，新增 0 错 | ⚠️ 既有 |
| **FR-002 状态筛选** | — | — | **移出本次范围**（降 P2，理由见 PRD §1.4）—— 故 AC-004 随之移出 | ⏭ |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题（page_title / 页面头 h3） | `/admin/orders`（既有页，仅改 scope + 筛选） | ⬜ | 不改标题 |
| ② 面包屑（含图标；`skip_breadcrumb_derivation` 控制器需手写） | 同上 | ⬜ | 导航自动推导，不新增页面 → 预期不变 |
| ③ 页面操作按钮（page_actions）与返回路径正常 | 同上 | ⬜ | 不改 |
| ④ POST/PATCH/DELETE 链接/按钮用 `data: { turbo_method: ... }` | 状态筛选若用表单 → 走 GET，不涉及 | ⬜ | 筛选一律 GET |

### 验证结论

<!-- 实施后回填：逐项命令 + 结果（通过/失败 + 原因 + 修复） -->
