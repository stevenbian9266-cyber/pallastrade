# PRD-20260920-checkout-订单可见性补齐-后台列表显示未完成订单-支付失败就地入口-游客最近一笔订单入口

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-20 |
| 来源 | 订单可见性补齐：后台列表显示未完成订单 + 支付失败就地入口 + 游客最近一笔订单入口 |
| 分类 | checkout（关键词命中 1，自动判定） |
| 关联 Skill | pallastrade-checkout、pallastrade-admin、pallastrade-api-v3 |
| 关联 REQ | REQ-20260920-order-visibility.md |
| 关联 PRD | N/A（`harness prd new` 查重未命中相似 PRD） |
| 需求类型 | 优化迭代 |
| 影响层 | ☐ App ☐ Core ☑ API ☑ Admin ☑ Storefront ☐ Platform |
| 风险等级 | critical（`harness risk check` 输出） |
| 关联设计文档 | `docs/design/payment-convergence-stripe-only.md` §13（订单可见性缺陷）+ §11 决策 10–12 + §11.1 硬约束 C-4 / C-6 |

## 0. 摘要（TL;DR）

- **一句话结论**：补齐三处**订单可见性**缺口 —— ① 后台订单列表默认显示未完成订单；② 支付失败时就地告诉顾客「订单已创建」并给入口；③ 游客凭 checkout token 找回「最近一笔」订单。**不改建单逻辑、不新增事件、不引入 email 回溯关联。**
- **交付物清单**：① `admin/orders_controller.rb#scope` 口径修正（+ 后台 orders spec）；② `UnifiedCheckout` 支付失败页内入口（+ en/zh-CN 文案 + 组件测试）；③ 新增无需登录的 `/orders/recent` 恢复入口（+ 测试）；④ 知识同步（checkout Skill / 设计文档 §13）。
- **不做的事（Out of Scope）**：❌ email 回溯关联（硬约束 **C-4**）；❌ 新增 `order.placed` 等订单类事件（硬约束 **C-7**）；❌ 改动游客订单列表 API 的鉴权口径；❌ 改建单/支付链路（Place Order 正名属切片 8，另开）。
- **前置依赖**：`docs/design/payment-convergence-stripe-only.md` §11 决策 10–12 已确认（2026-09-21）；无代码前置。

## 1. 背景与目标

### 1.1 现象 / 现状（含证据）

| # | 现象 | 证据（命令输出 / SQL / 代码位置 / 截图路径） |
|---|---|---|
| 1 | 顾客点支付后订单**确实已创建**，但在「我的订单」看不到 | 代码：`UnifiedCheckout.tsx#handlePayNow` 先 `await prepareOrder()`（= BFF `prepare` = `carts.update` + `carts.submit` 建单 + 切 `cart_`→`or_` cookie）→ `if (!prepared) return;` → 才 `start`；测试：`UnifiedCheckout.test.tsx` 断言 `prepare` 被调用 + `start` 携 `order_id: "or_123"`；DB：本地 7 张 `pending` 订单 `submitted_at` 均非空 |
| 2 | 后台订单列表看不到未完成订单 | 代码：`backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/orders_controller.rb#scope` —— `action_name == 'index'` 时 `base_scope.complete`；`Order` 的 `scope :complete = where.not(completed_at: nil)`（`pallastrade_core/app/models/pallastrade/order.rb:295`）。SQL 实测：`HIDDEN incomplete pending=7`、`HIDDEN incomplete paid=3` |
| 3 | 游客订单进不了「我的订单」（即使已登录） | 代码：`pallastrade_api/app/controllers/pallastrade/api/v3/store/customer/orders_controller.rb#scope` = `current_store.orders.where(user_id: current_user.id)` + `prepend_before_action :require_authentication!`；`Carts::Submit#build_order!` 用 `user: cart.user` → 游客购物车产出 `user_id = NULL`（SQL：`pending 且 guest = 6`）；页面 `storefront/src/app/[country]/[locale]/(storefront)/account/orders/page.tsx` 由 `account/layout.tsx`（客户端 `useAuth`）门控 |
| 4 | 注册/登录后不回溯关联游客订单 | 代码：`storefront/src/lib/data/customer.ts#finalizeAuth` 只做 `carts.associate`（关联**当前购物车**），不关联已建订单；skill 原文：*"registering later does not auto-link past guest orders"* |
| 5 | 支付失败后页内**无任何指向该订单的入口** | 代码：`UnifiedCheckout.tsx` 失败分支 `setPayError({ kind: "payment-failed", message })`；对比：`insufficient-stock` / `inventory-changed` / `reservation-expired` 均有按钮，唯独 `payment-failed` 没有 |

### 1.2 根因

- 根因链（三处**独立**缺口，不可混为一谈）：
  1. **V1 游客订单不可见**：游客购物车无 `user` → `Carts::Submit#build_order!` 写 `user: cart.user` → 订单 `user_id = NULL` → `customer/orders_controller.rb#scope` 的 `where(user_id: current_user.id)` **永不匹配**；且 `/account/orders` 由 `account/layout.tsx` 要求登录。
  2. **V2 不回填**：`finalizeAuth` 只关联当前购物车，**无**「把既有游客订单认领到该用户」的机制；唯一自动关联点是 legacy state machine 的 `after_transition to: :complete, do: :create_user_record`（要求 `signup_for_an_account?`），新 `Carts::Submit` 流程不走它。
  3. **V3 后台口径过窄**：`admin/orders_controller.rb#scope` 在 index 用 `.complete`，而 `completed_at` 只在 `finalize!` 后写入 → `pending` 与「已支付未 finalize」全被过滤。
  **不对称裂缝**：单订单端点 `store/orders_controller.rb` 经 `OrderResolvable` **含 `state=pending`**（凭 `X-PallasTrade-Token`），而列表端点按 `user_id` → **同一订单单点能看、列表看不到**。

### 1.3 目标与成功指标

- **目标**：让「订单已创建」在**顾客侧**与**运营侧**都可被发现 —— 后台能看到未完成订单；顾客支付失败时当场知道订单号并可继续支付；游客事后有稳定入口找回最近一笔。
- **成功指标**（可量化、可复测）：

| 指标 | 现状 | 目标 | 复测方式 |
|---|---|---|---|
| 后台订单列表可见的未完成订单数（本地 dev） | 0（7 pending + 3 paid 不可见） | 10（全部可见；6 张 `cart` 草稿仍排除） | `SELECT count(*) FROM pallastrade_orders WHERE submitted_at IS NOT NULL` vs 后台列表 |
| 支付失败后页内指向订单的入口数 | 0 | ≥1（含订单号） | 组件测试断言 + E2E 点击 |
| 游客（未登录）找回最近一笔订单所需的点击步数 | 不可达 | 1（从 `/orders/recent` 直达结果页） | E2E 302 断言 |

### 1.4 非目标（明确不做）

| 不做 | 理由 | 若属后续需求，指向 |
|---|---|---|
| email 回溯关联（把同 email 且 `user_id` 为空的已提交订单认领给该用户） | 与既有设计相悖（skill 明确 "There is no number+email claim flow"），且存在 email 撞号把**他人**订单并入的风险 | 硬约束 **C-4**；如需，单独立项 + PRD 评审 |
| 新增订单类事件（`order.placed` 等） | `order.submitted` 已是同一时刻的语义等价事实源，新建 = 重复事实源 | 硬约束 **C-7** |
| 改游客订单**列表** API 的鉴权口径 | 会把 JWT 作用域打开，放大越权面 | 设计文档 §13.4 V-FIX-C（已选 C1，不做 C2） |
| 改建单 / 支付链路（BFF `prepare` → `place-order` 正名） | 属切片 8，与本需求正交 | 设计文档 §12（切片 8 展开） |
| 后台列表**状态筛选 UI**（原 FR-002） | 收敛后可见集合已排除 `cart` 草稿，噪音风险 R-1 可控；表格 DSL 无既有 `state` 可筛属性，需改 `pallastrade_admin_tables.rb` + select 选项 + 标签 + 渲染验证 | 后续 PRD（若运营反馈列表过长则提优先级） |

> ℹ️ 硬约束 **C-6**（「若要收紧必须走筛选，不得改回 `.complete`」）是**对未来变更的约束**，不要求本次就建筛选 UI。

## 2. 用户故事 / 场景

| # | 角色 | 场景 | 期望 | 类型 | 优先级 |
|---|---|---|---|---|---|
| S-1 | 运营 | 打开 `/admin/orders` 找「顾客点了支付但没付成」的单 | 列表里能看到该订单（含 `pending` 与已支付未 finalize） | 正常 | P0 |
| S-2 | 顾客（游客） | 卡被拒后仍停在结账页 | 页内看到「订单 `R…` 已创建」+ 可点的「查看订单 / 继续支付」 | 正常 | P0 |
| S-3 | 顾客（游客） | 关掉页面，稍后想回来付 | 有一个无需登录的稳定入口找回最近一笔订单 | 正常 | P1 |
| S-4 | 顾客 | 反复点击支付、卡均被拒 | 订单**只有一张**（幂等），入口始终指向它 | 边界 | P0 |
| S-5 | 游客 | 从未下过单却打开 `/orders/recent` | 空态页 + 「去购物车」链接，**不报错、不 500** | 边界 | P0 |
| S-6 | 游客 | checkout cookie 已过期 / 指向的订单已不存在 | 空态页（不泄露“该订单存在与否”的差异） | 异常 | P1 |
| S-7 | 顾客 | 登录后再看「我的订单」 | **仍看不到游客时下的单**（本需求不做回溯关联，属已知限制） | 异常 | P1 |

> 要求：「类型」列至少各出现一次 **边界** 与 **异常**。

## 3. 功能需求（FR）

| FR | 描述（可验收） | 优先级 | 落点（文件 / 层） |
|---|---|---|---|
| FR-001 | 后台订单列表（`index`）改为显示「**已提交**」或「已完成」订单：`submitted_at IS NOT NULL OR completed_at IS NOT NULL`，以**排除**`state=cart` 草稿；与前台 `customer/orders_controller#scope` 的口径**一致** | P0 | Admin · `pallastrade_admin/app/controllers/pallastrade/admin/orders_controller.rb#scope` |
| FR-002 | ~~后台订单列表提供状态筛选~~ **移出本次范围** —— 理由：收敛后的可见集合已比「全部」窄（已排除 `cart` 草稿），噪音风险 R-1 可控；且表格 DSL 无既有 `state` 可筛属性（`filterable: true` 的只有 `number` / `payment_state`），新增需改 `pallastrade_admin_tables.rb` + select 选项 + 标签 + 渲染验证 → 归入后续 | P2（降级） | 后续 PRD（见 §1.4） |
| FR-003 | 支付失败（`payError.kind === "payment-failed"`）时，页内除错误文案外，**额外**展示「订单 `<编号>` 已创建」与两个入口：「查看订单」→ `/payment-result/{orderId}`、「继续支付」→ 同页（不清空已填信息） | P0 | Storefront · `storefront/src/components/checkout/UnifiedCheckout.tsx` |
| FR-004 | 新增**无需登录**的稳定入口 `/orders/recent`：读 HttpOnly checkout cookie（order id + token），有则 302 → `/payment-result/{orderId}`，无/失效则渲染空态页（含「去购物车」链接） | P1 | Storefront · 新路由 + `lib/pallastrade/cookies.ts#getCheckoutOptions` |
| FR-005 | 新增用户可见文案（en + zh-CN 同步）：订单已创建提示、查看订单、继续支付、空态文案 | P0 | Storefront · `storefront/messages/*`（或项目既有 i18n 位置） | |

## 4. 非功能需求（NFR）

| 维度 | 要求 | 验证方式 |
|---|---|---|
| 性能 | 后台列表查询数**不随行数增长**（保留既有 `collection_includes` 预加载）；放宽 scope 不得引入 N+1 | 列表渲染时比对查询数（既有 admin orders spec 惯例） |
| 安全 | ① `/orders/recent` **仅**凭 HttpOnly checkout cookie 授权，**不得**接受 URL/查询参数指定 order id（防越权枚举）；② 空态与「订单不存在」**不可区分**（不泄露存在性）；③ 后台 scope 放宽**不得**跨店（保留 `current_store` 收窄）与越权（保留 `accessible_by(current_ability, :index)`） | 请求 spec：伪造 order id 参数 → 仍空态；跨店订单 → 后台不可见 |
| 兼容 | 既有后台筛选/搜索（Ransack）行为不变；`show` 分支不受影响 | 回归既有 admin orders spec |
| 可维护性 | 前后台**共用同一可见性口径**（`submitted_at` 非空 ∪ 已完成），避免再次漂移 | 代码注释互相指向 + 本 PRD §11 D-1 |
| 可观测性 | 不新增埋点（本需求为可见性修复，非行为变更）；支付失败提示已由既有错误通道承担 | 不适用（无新增事件/指标） |

> 不涉及的维度写「不适用」+ 理由，**不得整行留空**。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件（可执行） | 测试落点（文件） | 状态 |
|---|---|---|---|---|
| AC-001 | FR-001 | 建 1 张 `pending` 订单 + 1 张 `paid` 但未 finalize 订单 → 两者**均**出现在 `/admin/orders` | `backend/spec/requests/pallastrade/admin/orders_visibility_spec.rb`（新增） | ☐ |
| AC-002 | FR-001 | 建 1 张 `state=cart`（`submitted_at` 为 NULL）→ **不**出现在 `/admin/orders`（不污染草稿） | 同上 | ☐ |
| AC-003 | FR-001 | 账本回归：可见集合 == `orders.where(submitted_at: ..).or(complete)` 的集合（与前台口径一致） | 同上 | ☐ |
| AC-004 | FR-002 | ~~带状态筛选参数访问 → 仅返回该状态~~ | — | ⏭ **移出本次**（随 FR-002） |
| AC-005 | FR-003 | 卡被拒（`confirmResult.error`）→ 页内出现含订单编号的「订单已创建」文案 + 「查看订单」链接 href == `/payment-result/{orderId}` | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`（更新） | ☐ |
| AC-006 | FR-003 | 同上场景：**零 PATCH、零跳转**（既有 AC-003 回归不破） | 同上 | ☐ |
| AC-007 | FR-003 | 连续两次被拒 → 订单**只有一张**，入口始终指向同一 `order_id`（幂等） | 同上（复用既有两段语义 mock） | ☐ |
| AC-008 | FR-004 | 未登录 + cookie 内含有效 checkout 订单 → `GET /orders/recent` 返回 **302** 且 `Location` 以 `/payment-result/` 开头 | `storefront/src/app/orders/recent/__tests__/page.test.tsx`（新增） | ☐ |
| AC-009 | FR-004 | 未登录 + **无** cookie → **200** 空态页，包含「去购物车」链接，**不** 500 | 同上 | ☐ |
| AC-010 | FR-004 | 提供伪造 `?order_id=` 查询参数 → **仍按空态处理**（不接受外部指定 id） | 同上 | ☐ |
| AC-011 | FR-005 | en / zh-CN 键集一致，且无未翻译 key | `pnpm --filter pallastrade-storefront check:locales`（既有脚本） | ☐ |

> 不允许用「人工检查一下」充当 AC；每条 AC 必须有测试落点或明确的手工证据形式。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | submit / order / visibility | 无 | ❌ 无（Host App 未覆盖订单可见性） |
| Core | `pallastrade_gems/pallastrade_core/app/` | build_order / user_id / submitted_at | `services/pallastrade/carts/submit.rb`（建单，`user: cart.user`）；`models/pallastrade/order.rb:294-296`（`scope :complete = where.not(completed_at: nil)`）；`models/pallastrade/order/checkout.rb:127,344`（`after_transition to: :complete, do: :create_user_record`） | ⚠️ 部分：建单已有；**可见性机制无** |
| API | `pallastrade_gems/pallastrade_api/app/` | orders scope / user_id / token | `v3/store/customer/orders_controller.rb#scope`（JWT + `where(user_id: current_user.id)`）；`v3/store/orders_controller.rb`（`OrderResolvable`，**含 `state=pending`**，凭 token） | ⚠️ **单订单**已含 pending；**列表**不含游客 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | orders / scope / complete | `controllers/pallastrade/admin/orders_controller.rb#scope`（index → `base_scope.complete`） | ❌ **口径过窄**（本需求要修） |
| Storefront | `storefront/src/` | account/orders / payment-failed / setCheckoutCookies | `app/…/account/orders/page.tsx`、`app/…/account/layout.tsx`（useAuth 门控）、`components/checkout/UnifiedCheckout.tsx`（`payment-failed` 无入口）、`lib/pallastrade/cookies.ts#setCheckoutCookies`（HttpOnly order id + token）、`app/…/(checkout)/payment-result/[id]/page.tsx`（**已对游客可用**，自带补付 `retryHref`）、`lib/data/customer.ts#finalizeAuth` | ⚠️ token 授权与结果页**已有**；缺**发现入口** |
| Platform | `platform/packages/` | customer.orders.list / orders.get | SDK 类型（`customer.orders.list`、`orders.get`） | ✅ 类型足够，**无需改** |

### 6.1 防重复判定

- **已有能力**：（Storefront）游客订单的**单点**访问链路已完整 —— `setCheckoutCookies` 写入 HttpOnly order id + token → `/payment-result/[id]` 凭 `getOrderForCheckout` 渲染 → 自带 `retryHref = /checkout/{orderId}` 补付；（API）单订单端点 `OrderResolvable` **已含 `state=pending``。
- **需要新建**：（Admin）列表口径修正 + 状态筛选；（Storefront）支付失败页内入口、`/orders/recent` 恢复路由、新文案。
- **结论**：**不是重复建设** —— 本需求不重建访客订单访问机制（已存在且正在用），只补「**能被发现**」与「**后台口径对齐**」两件事。

### 6.2 AP-SEARCH 反模式自检

| 反模式 | 本次是否触犯 | 说明 |
|---|---|---|
| AP-SEARCH-1 提前停止（找到第一个就收工） | ✅ 未触犯 | 在 API 层找到「单订单已含 pending」后，**继续**逐层核实，才发现「列表端点按 user_id」的不对称裂缝（§1.2） |
| AP-SEARCH-2 名称不匹配（改用领域概念再搜一次） | ✅ 未触犯 | 按领域概念（订单可见性 / 我的订单 / account orders / 未支付订单）而非类名搜；`orders_controller.rb` 在 admin / store / store/customer 三层**同名不同职**，已逐层读源码区分 |
| AP-SEARCH-3 层间假设（每层独立验证，不连推） | ✅ 未触犯 | 未从「core 有 `scope :complete`」推定「admin 也这样用」，而是**分别**读了 `admin/orders_controller.rb#scope` 与 `customer/orders_controller.rb#scope` |

## 7. 技术影响

### 7.1 变更面（文件级）

| 文件 | 动作（新增 / 修改 / 删除） | 说明 |
|---|---|---|
| `backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/orders_controller.rb` | 修改 | `#scope` 的 `index` 分支由 `base_scope.complete` 改为「`submitted_at` 非空 ∪ 已完成」（FR-001）；补状态筛选（FR-002） |
| `backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/orders/index.html.erb`（及部分视图） | 修改 | 状态筛选控件（若采用） |
| `backend/spec/requests/pallastrade/admin/orders_visibility_spec.rb` | 新增 | AC-001..004 |
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | 修改 | `payment-failed` 分支补订单号 + 两个入口（FR-003） |
| `storefront/src/app/[country]/[locale]/orders/recent/page.tsx` | 新增 | 游客「最近一笔」恢复入口（FR-004）；**具体路由路径见 §12 Q-1** |
| `storefront/messages/{en,zh-CN}*.json`（或项目既有 locale 位置） | 修改 | 新文案（FR-005） |
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | 修改 | AC-005..007 |
| `storefront/src/app/[country]/[locale]/orders/recent/__tests__/page.test.tsx` | 新增 | AC-008..010 |

### 7.2 契约影响

| 契约 | 是否变化 | 说明 | 同步动作 |
|---|---|---|---|
| OpenAPI（`store.yaml` / `admin.yaml`） | ❌ **不变** | 未新增/修改 Store/Admin API 端点（`/orders/recent` 是 Next.js 路由，非 API） | 无需（实施后仍跑 `generated:check` 确认） |
| SDK 类型 | ❌ **不变** | 不新增 SDK 方法；复用既有 `orders.get` | 无需 |
| 数据库 schema / migration | ❌ **不变** | **零 migration**（`submitted_at` / `completed_at` 列已存在） | 无需 |
| 事件（`order.submitted` 等） | ❌ **不变** | 硬约束 **C-7**：不新增订单类事件 | 无需 |
| 后台导航 | ❌ **不变** | 沿用既有「订单」菜单项，不新增页面 | 仍需跑 `pallastrade:admin:nav_validate` |

### 7.3 依赖与前置

- 仅依赖**既有**列（`pallastrade_orders.submitted_at` / `completed_at`）与**既有** HttpOnly checkout cookie（`setCheckoutCookies`）；无新依赖、无外部服务、无环境变量。
- 跨需求前置：设计文档 §11 决策 10–12 已确认（已完成）。

### 7.4 影响面（`harness affected` 输出）

> 本 PRD 尚未实施；下列为立项时（工作树含并行会话改动）的**基线**输出，仅用于说明工具链可用性。**实施完成后必须重跑并回填真实影响面**。

```
$ harness affected --base origin/dev
{
  "filesChanged": 26,
  "affectedComponents": ["backend", "harness"],
  "errors": [],
  "estimatedTests": 78
}
```

## 8. 测试计划

### 8.1 新增 / 更新测试

| 文件 | 动作 | 覆盖 AC |
|---|---|---|
| `backend/spec/requests/pallastrade/admin/orders_visibility_spec.rb` | 新增 | AC-001 / AC-002 / AC-003 / AC-004 |
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | 更新 | AC-005 / AC-006 / AC-007 |
| `storefront/src/app/[country]/[locale]/(checkout)/orders/recent/__tests__/page.test.tsx` | 新增 | AC-008 / AC-009 / AC-010（共 4 例：跳转 / 空态 / 非法 cookie 值 / 外部参数被忽略） |
| `storefront/messages/{en,de,es,fr,pl}.json` | 更新 | AC-011（`check-locale-parity`） |

### 8.2 AC ↔ 测试映射

- 标记规则：测试文件内须写 **完整 PRD-ID + AC-x 同一行**（如 `# PRD-YYYYMMDD-xxx AC-001`）；
  只写 `AC-001` 或批次别称**不算覆盖**。
- 收尾复核：`harness prd verify --id <PRD-ID>`

### 8.3 验证器（`harness verify <name>`）

| 验证器 | 用途 | 耗时 |
|---|---|---|
| `harness verify storefront-test` | 前台组件与路由测试（AC-005..011） | ≤ 15 min |
| `harness check --profile quick` | 后端 Ruby 改动最小验证（AC-001..004 对应 spec 在此范围内） | ≤ 5 min |
| `pnpm --filter pallastrade-storefront check:locales` | en / zh-CN 键集一致 | ≤ 1 min |
| `pallastrade:admin:nav_validate` | 后台导航一致性回归 | ≤ 1 min |

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [ ] 关联设计文档（`docs/design/*.md`）回填

**结论**：
- API 文档（`store.yaml` / `admin.yaml` + `platform/docs/api-reference/`）：**已评估，无需更新** —— 本需求不改任何 API 端点/字段（§7.2）。
- Skill 文档：**需更新** `ai/skills/pallastrade-checkout/SKILL.md`（在 Guest checkout vs logged-in 一节补「游客订单可见性 = token，列表不可见为**已知限制**」+ 新增 `/orders/recent` 入口）；`pallastrade-admin` Skill 补后台订单列表口径变更。
- README / Agent / 样式规范：**已评估，无需更新**（不涉及样式 token、不涉及 Agent 命令）。
- 反模式库 / 任务规则 / 场景库：**需更新** `harness/scenarios/scenarios.json`（新增订单可见性场景，因改动了 Skill 文件）。
- 本 PRD 状态 + `docs/prd/README.md` 索引：**收尾时更新**（五处同时核对）。
- 关联设计文档：**需回填** `docs/design/payment-convergence-stripe-only.md` §13.4（V-FIX-A/B/C1 由「建议」改为「已实施」+ 指向本 PRD）。

## 10. 风险与回滚

| # | 风险 | 概率 | 影响 | 缓解 | 回滚 |
|---|---|---|---|---|---|
| R-1 | 放宽后台 scope 后**历史垃圾单**（如遗留 `cart` 草稿、测试单）涌入列表，运营噪音 | 中 | 中 | scope 限定为「`submitted_at` 非空 ∪ 已完成」而非「全部」；提供状态筛选（FR-002） | 把 `#scope` 改回 `base_scope.complete`（单方法、一行回退） |
| R-2 | 后台列表放宽后**意外跨店/越权**（漏掉 `current_store` 或 `accessible_by`） | 低 | **高** | 保留两个既有收窄调用**不动**；AC 加跨店用例 | 同上回退 |
| R-3 | `/orders/recent` 被用来**枚举他人订单**（若接受外部 id） | 低 | **高** | **只**读 HttpOnly cookie，**不**接受任何请求参数指定 order id（AC-010 锁定）；空态与“不存在”不可区分 | 下线该路由（删文件 + 移除入口链接） |
| R-4 | 支付失败页内新增入口让顾客**误以为已付款** | 中 | 中 | 文案明确「订单已创建，**尚未支付**」；不改变现有状态图标/颜色语义；§5 AC-006 保证零跳转 | 隐藏该入口（文案保留） |
| R-5 | 新文案 en / zh-CN 不同步 → 后台 i18n 或前台 locale 检查红 | 中 | 低 | 同批提交两份 locale；跑 `check:locales` | 回退语言文件 |
| R-6 | 仅修「支付失败」，而**其他失败分支**（未知 code / `toast` 路径）仍无入口，用户仍困惑 | 中 | 中 | §12 Q-1 待定：是否统一把「订单已存在」类失败都指向同一入口 | 局部回退到只处理 `payment-failed` |

**回滚方式**：
1. 代码：`git revert <本 PRD 实施提交>` —— Admin scope 与 Storefront 入口各自独立，可**分层回滚**。
2. 数据：**零数据变更**（不改 schema、不写业务数据），无需数据恢复。
3. 紧急开关：若无时间 revert，可先移除前台入口链接（`/orders/recent` 路由可暂时保留但无入口）。

## 11. 决策记录（ADR 简版）

| # | 决策 | 备选方案 | 选择理由 | 日期 |
|---|---|---|---|---|
| D-1 | 后台列表可见性口径改为「**`submitted_at` 非空 ∪ 已完成**」 | A) 直接去掉 `.complete`（显示全部）；B) 保留 `.complete`、另开筛选页；C) 本方案 | **A 会把 6 张 `cart` 草稿灌进列表**（Order 同表购物车，见 §1.1 现象 2）；C 与前台 `customer/orders_controller#scope` **口径完全一致**，消除跨层漂移 | 2026-09-21 |
| D-2 | 支付失败入口**指向** `/payment-result/{id}`，而非新建页面 | A) 新建补付页；B) 指向 `payment-result` | `payment-result/[id]` **已对游客可用**（凭 HttpOnly cookie）且**已自带** `retryHref = /checkout/{orderId}` 补付入口 —— 零后端改动（设计文档 §13.4 V-FIX-B） | 2026-09-21 |
| D-3 | 游客订单找回取 **C1**（token 入口），**不做 C2**（email 回溯关联） | A) C1；B) C2 | 用户 2026-09-21 拍板「12 项全按建议」；C2 与 skill 既有设计相悖（"There is no number+email claim flow"）且有 email 撞号风险 → 硬约束 **C-4** | 2026-09-21 |
| D-4 | **不新增**订单类事件 | A) 新增 `order.placed`；B) 不加 | `order.submitted` 已在建单提交后发布，是**同一时刻**的语义等价事实源 → 硬约束 **C-7** | 2026-09-21 |
| D-5 | 本需求**不动**建单与支付链路 | A) 顺带做切片 8（`prepare` → `place-order` 正名）；B) 拆开 | 两者正交；同批改会污染回滚面与验收边界（§1.4） | 2026-09-21 |

> 与用户拍板相关的决策**必须**记录用户原话或明确指令。

## 12. 开放问题

| # | 问题 | 影响 | 状态（open / resolved） | 结论 |
|---|---|---|---|---|
| Q-1 | `/orders/recent` 的**路由路径**与入口位置（购物车页 / 404 页 / 仅直接 URL？） | 影响 FR-004 的落点与测试路径 | **open** | 待用户确认；不影响其余 FR（可先做 FR-001..003） |
| Q-2 | 支付失败以外的分支（未知 code 的 `toast` 路径）是否也统一给「订单已创建」入口 | 影响 R-6 与用户体验一致性 | **open** | 建议先做 `payment-failed`（订单已建且用户停在页内），其余分支保持现状 |
| Q-3 | 后台状态筛选的默认值（「全部」vs「未支付」） | 影响运营第一屏 | **resolved** | 采用「**全部**」（= FR-001 口径），硬约束 **C-6** |

> 开工前所有 `open` 必须清零，或转为 §10 的风险项。**Q-1 / Q-2 不影响 FR-001..003 开工**（可按上述建议默认值先做）。

## 13. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-20 | 0.1 | 初稿（`harness prd new` 创建骨架 → 按 `docs/prd/_TEMPLATE.md` 6 节旧模板扩充） | AI |
| 2026-09-21 | 0.2 | 按**细化后的 14 节模板**（§0–§13）重写：补摘要 / 现象+证据（5 条，均带代码位置或 SQL）/ 根因链 / 非目标 / 场景表（含边界与异常）/ NFR 逐维度 / AC 带测试落点 / AP-SEARCH 自检 / 契约影响 / 风险与回滚 / 决策记录（D-1..D-5）/ 开放问题（Q-1..Q-3） | AI |
| 2026-09-21 | 1.0 | **实施完成（除 FR-002 外）**：FR-001（后台 scope，AC-001/002/003 ✅）、FR-003（支付失败入口，AC-005/006/007 ✅）、FR-004（`/orders/recent`，AC-008/009/010 ✅）、FR-005（文案，AC-011 ✅）。**FR-002/AC-004 移出本次范围**（降为 P2，理由见 §1.4）。另**修正 FR-005 的错误假设**：storefront 实际只有 `de/en/es/fr/pl` **无 zh-CN**（zh-CN 是后台 admin 的约定），已改为 5 locale 全同步 | AI |
