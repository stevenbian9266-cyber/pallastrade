# PRD-20260908-checkout-商城前台-order-模块-订单列表排序按订单创建时间由近到远排序

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-08 |
| 来源 | 优化：商城前台 order 模块，订单列表排序按订单创建时间由近到远排序 |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-api-v3 / pallastrade-storefront |
| 关联 REQ | REQ-20260908-store-order-list-created-at-desc.md（实施时回填） |
| 关联 PRD | N/A（`harness prd new` 查重通过，无相似 PRD） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：优化：1、商城前台 order 模块，订单列表排序按订单创建时间由近到远排序
- **背景**：
  - 商城前台「我的订单」列表（`/account/orders`）读取 `GET /api/v3/store/customers/me/orders`（`limit: 50`，不带 sort）。
  - 后端 `customer/orders_controller.rb#scope` 仅做 store+user 归属过滤与「已提交（submitted）或已完成（complete）」过滤，**无任何 ORDER BY** → 数据库按堆序/插入序返回，顺序不确定。
  - **dev 库实测取证**（用户 zhijunzhijun66.bian@gmail.com，21 笔可见订单）：当前无排序返回前几条为 08-29、08-30、08-29…（混杂，非创建时间倒序）；期望 `created_at desc` 后首条应为 09-07 的 R046789018、其次 09-06 的 R916762118。
  - 前端 `OrderList.tsx` 按服务端返回顺序渲染（无客户端重排）→ 问题源头 = API 默认排序缺失。
- **目标**：订单历史列表默认按订单创建时间 `created_at` 由近到远（倒序）返回，商城前台即刻呈现最新订单在前。
- **成功指标**：`GET /customers/me/orders`（不带 sort）返回第 1 条 = 该用户最近创建的可见订单；同一秒创建以 `id desc` 稳定排序、分页不抖动。

## 2. 用户故事 / 场景

- 作为商城顾客，我希望「我的订单」里最新下的单排在最上面，以便快速找到最近订单并跟踪支付/发货状态。
- 场景：
  - 正常流：顾客拥有多笔已完成 + 已支付未完成订单 → 打开订单列表 → 按创建时间由近到远排列。
  - 边界：同一秒创建多笔订单 → 以 `id desc` 稳定排序，不抖动。
  - 边界：客户端显式传 `sort`（如 `-number`）→ 尊重客户端排序（框架既有 sort 契约不被破坏）。
  - 异常：空列表 / 订单不属于当前用户 → 返回空（既有归属过滤不回归）。

## 3. 功能需求（FR）

- FR-001：`GET /api/v3/store/customers/me/orders` 默认按订单创建时间倒序（`created_at desc, id desc`）返回。
- FR-002：默认排序仅作「客户端未传 sort 时的兜底」；客户端显式 `sort` 参数仍优先（沿用 ResourceController 通用 sort 契约），默认排序退化为次级 tie-break。

## 4. 非功能需求（NFR）

- 性能：`created_at` / `id` 均为索引列，倒序排序无额外代价；分页（pagy）在排序后截取。
- 兼容：不改响应 schema / 字段 / 分页结构；不改鉴权与归属范围；前端无需改动。
- 可维护：复用框架 `apply_collection_sort` 扩展点（注释说明），不在 scope 硬编码 SQL 片段。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：同一用户 3+ 笔可见订单（混合「已提交未支付」与「已完成」，created_at 依次递增）→ `GET /customers/me/orders` → `data[].id` 顺序 == created_at 倒序。
- AC-002 ← FR-001：倒序后仍只返回该 store+user 的可见订单（归属/状态过滤不回归：另一用户/另一店铺订单不出现）。
- AC-003 ← FR-002：同一列表请求带 `sort=-number` → 结果按 number 倒序（客户端排序优先于默认 created_at 排序）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | order / customer list / sort | 无（host app 无 store 订单列表控制器） | ❌ 无现成能力 |
| Core | `pallastrade_gems/pallastrade_core/app/` | order default_scope / scope / order( | `models/.../order.rb`：无 default_scope；有 `reverse_chronological`（completed 优先，非纯 created_at 倒序）；ransackable 白名单不含 `created_at` | ❌ 无纯 created_at 倒序默认 |
| API | `pallastrade_gems/pallastrade_api/app/` | customers/me/orders / sort | `customer/orders_controller.rb`（scope 无排序，已是 PALLAS-CUSTOM 文件）；`resource_controller.rb`（通用 sort 参数 + `apply_collection_sort` 扩展点）；同域先例 `customer/gift_cards_controller.rb` `.order(created_at: :desc)` | ⚠️ 部分——需在 OrdersController 补默认排序 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 订单列表排序 | 后台订单列表排序与 store API 无关 | ❌ 不涉及 |
| Storefront | `storefront/src/` | account/orders / OrderList | `orders/page.tsx`（`getOrders({limit:50})`）；`OrderList.tsx`（按服务端顺序渲染，无客户端重排） | ⚠️ 仅消费服务端顺序，不需改 |
| Platform | `platform/packages/` | OrderListParams / customer orders | SDK `customer.orders.list` 透传 sort（默认不带） | ❌ 不需改 |

**结论**：无重复实现。修复点在 API 层 `customer/orders_controller.rb`，用框架 `apply_collection_sort` 扩展点提供默认 `created_at desc, id desc`（客户端显式 sort 仍优先）。前端与 SDK 无需改动。

## 7. 技术影响

- 涉及文件：
  - `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/customer/orders_controller.rb`（新增 `apply_collection_sort` override）
  - `backend/spec/requests/api/v3/store/customer_orders_controller_spec.rb`（追加排序回归用例）
- 无 DB 迁移 / 无路由变更 / 无序列化字段变更 / 无 SDK 类型变更。
- 影响面：仅 store 端顾客订单历史读取路径；admin 订单列表、guest 单笔查询不受影响。
- 接口契约：响应结构不变；仅默认顺序变为确定性的 created_at 倒序（行为修复，非契约变更）。

## 8. 测试计划

- 更新 `backend/spec/requests/api/v3/store/customer_orders_controller_spec.rb`：
  - 用例 A（AC-001）：同用户多笔可见订单（混合 submitted + completed，created_at 递增）→ 断言返回 `data[].id` 为 created_at 倒序。
  - 用例 B（AC-002）：跨用户/跨店铺订单不进入结果（保持既有归属断言 + 顺序断言）。
  - 用例 C（AC-003）：带 `sort=-number` → 按 number 倒序（客户端排序优先）。
- AC 映射：AC-001/002/003 → `customer_orders_controller_spec.rb`。
- 回归：PRD-20260830-checkout AC-008 归属/可见性既有用例保持全绿。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml` —— 评估：仅默认排序行为修复，无 schema/参数变化 → 预计 reviewed-no-change
- [ ] Skill 文档：`pallastrade-api-v3` / `pallastrade-storefront` —— 评估后按需记录（预计 reviewed-no-change，可选补充说明默认排序语义）
- [ ] 场景库 scenarios.json —— 若 Skill 无变化则无需新增（记录 reviewed-no-change）
- [ ] README / Agent 文件 / 样式规范 / 技术规范 —— 不涉及
- [ ] 反模式库 / 任务规则 —— 不涉及
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（定位 API 默认排序缺失；dev 库实测取证） | AI |
