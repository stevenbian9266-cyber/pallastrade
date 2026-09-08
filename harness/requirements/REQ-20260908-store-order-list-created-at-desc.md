# REQ-20260908-store-order-list-created-at-desc

> 关联 PRD：`docs/prd/checkout/PRD-20260908-checkout-商城前台-order-模块-订单列表排序按订单创建时间由近到远排序.md`
> 任务：TASK-20260908050645-2e30e1a5 · Gate：GATE-2026-09-08T05-07-37

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | order list / customer orders / sort | 无（host app 无 store 订单列表控制器） | ❌ 无现成能力 |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ |
| Core Gem — models | `.../pallastrade_core/app/models/` | order default_scope / order( | `order.rb`：无 default_scope；`reverse_chronological` 为 completed 优先（非纯 created_at 倒序）；ransackable 白名单不含 `created_at` | ❌ |
| Core Gem — services | `.../pallastrade_core/app/services/` | 订单列表 | 无相关服务 | ❌ |
| API Gem — controllers | `.../pallastrade_api/app/controllers/` | customers/me/orders / sort | `customer/orders_controller.rb`（scope 无排序，PALLAS-CUSTOM 文件）；`resource_controller.rb`（通用 sort + `apply_collection_sort` 扩展点）；先例 `customer/gift_cards_controller.rb` `.order(created_at: :desc)` | ⚠️ 部分——需在 OrdersController 补默认排序 |
| Admin Gem — controllers | `.../pallastrade_admin/app/controllers/` | 订单列表排序 | 后台订单列表排序与 store API 无关 | ❌ 不涉及 |
| Admin Gem — views | `.../pallastrade_admin/app/views/` | 同上 | 无 | ❌ 不涉及 |
| Storefront | `storefront/src/` | account/orders / OrderList / sort | `orders/page.tsx`（`getOrders({limit:50})` 不带 sort）；`OrderList.tsx`（按服务端顺序渲染，无客户端重排） | ⚠️ 仅消费服务端顺序，不需改 |
| Platform | `platform/packages/` | OrderListParams / customer orders | SDK `customer.orders.list`（sort 透传，默认不带） | ❌ 不需改 |

### 搜索结论

订单历史排序能力**无现成实现**。唯一需改点：API Gem `customer/orders_controller.rb`（已是 PALLAS-CUSTOM 文件）——复用框架 `apply_collection_sort` 扩展点提供默认 `created_at desc, id desc`（客户端显式 `sort` 仍优先）。前端 `OrderList` 无客户端重排，纯消费服务端顺序。dev 库实测 21 笔可见订单当前无 ORDER BY、返回顺序混杂。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：修改控制器行为可用 Decorator 或直接扩展；本文件属 `pallastrade_gems`（团队产品、Git 跟踪，标注 PALLAS-CUSTOM），订单历史排序属该 API 端点的确定性契约 → 直接在既有 PALLAS-CUSTOM 控制器加默认排序，不新建服务/不改 model default_scope |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | Store API 列表端点返回 `{data, meta}`；排序支持 `sort`（JSON:API `-field` → `q[s]`）且**仅白名单属性可排序**（`Order#created_at` 不在白名单 → 不在本次启用客户端排序）；order store serializer 不输出 `created_at`（排序在后端完成，不影响响应字段）；`customers/me/orders` 必须保持 store+user 归属边界 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | PRD 驱动流程：draft → 用户确认(approved) → gate+REQ → AC↔测试映射 → 知识同步门 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-decorators` | 否 | — | 不需装饰 Order/Controller（控制器本身即宿主可改的 PALLAS-CUSTOM 文件） |
| `pallastrade-storefront` | 否 | — | 前端零改动（OrderList 按服务端顺序渲染） |
| `pallastrade-testing` | 否 | — | 按项目 RSpec 约定（request spec + factory `:order`）补充用例即可 |

---

## 需求标题

商城前台 order 模块：订单列表按订单创建时间由近到远排序

## 任务类型

功能优化（默认排序行为修复）

## 需求描述

`GET /api/v3/store/customers/me/orders` 当前 scope 无任何 ORDER BY，返回顺序不确定（实测混杂，非创建时间倒序）。目标：订单历史默认按 `created_at desc, id desc` 返回（最新订单在前），前端 `/account/orders` 即刻正确呈现；客户端显式 `sort` 参数仍优先（框架契约不破坏）。

## 影响范围（harness affected 输出）

- 唯一行为文件：`backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/customer/orders_controller.rb`（新增 `apply_collection_sort` override）
- 测试：`backend/spec/requests/api/v3/store/customer_orders_controller_spec.rb`
- 无 DB / 路由 / serializer / SDK / 前端变更；无响应 schema 变化。

## 技术方案（初步）

在 `customer/orders_controller.rb` 的 `protected` 段新增：

```ruby
# 订单历史默认按创建时间由近到远；客户端显式 sort（q[s]/sort 参数）仍优先（order 仅作兜底追加，tie-break 用 id desc）。
def apply_collection_sort(collection)
  collection.order(created_at: :desc, id: :desc)
end
```

理由（决策树）：该控制器文件已是 PALLAS-CUSTOM（宿主直接改 gem 文件的项目惯例），改动最小、确定性最强、全消费者受益；不采用 storefront 传参方案（`created_at` 不在 ransack 白名单，且仅修一处默认排序更彻底）。

## 风险点

- 最高风险：低。仅追加默认 ORDER BY，不改变过滤/鉴权/响应结构；`created_at`/`id` 有索引。
- 回滚难度：低（单方法删除即可）。
- 并行工作区污染：工作区含他任务（REV-P6-7）未提交 payment 文件，本任务提交时只 `git add` 自身文件，防止误提交他人改动（README.md 为共享索引，含两任务各自行）。

## 决策节点

> ✅ 用户已明确确认「实施」（2026-09-08），PRD 状态 approved。以下进入实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby API 行为 | `customer/orders_controller.rb` | docker 容器 RSpec（customer_orders_controller_spec + 关联回归） | | ⬜ |
| Ruby 语法 | 同上 | `ruby -c` / rubocop（容器） | | ⬜ |
| 接口回归 | store.yaml 无 schema 变化 | `harness generated:check`（评估） | | ⬜ |
| 端到端 | dev 部署后 | `GET /customers/me/orders` 顺序断言（rails runner / API） | | ⬜ |

### 验证结论

<!-- 实施后填写 -->
