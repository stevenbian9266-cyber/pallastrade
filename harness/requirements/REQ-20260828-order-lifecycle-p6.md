# REQ-20260828-order-lifecycle-p6 — Admin 手动拆单 + 父子树 UI（flag 灰度）

> 对应 PRD：`docs/prd/admin/PRD-20260828-admin-p6-admin-手动拆单-父子树-ui-flag-灰度.md`
> Task：`TASK-20260828130550-527009aa` ｜ Gate：`GATE-2026-08-28T13-06-03`（Risk: critical）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | split / parent_id / children | 无业务代码（仅 `backend/app/javascript/types/serializers/*.ts` 旧 typelizer 生成物，未跟踪） | ❌ 无需在此层实现（走 gem） |
| Core — services | `pallastrade_core/app/services/` | Splitter / SplitStrategies | `orders/splitter.rb`（P2 统一拆单引擎：`call(order:, groups:, parent_order:)`）；`orders/split_strategies/{base,by_store,by_stock_location}.rb` | ✅ 复用（能力层已就绪） |
| API — controllers | `pallastrade_api/app/controllers/` | split / orders | `admin/orders_controller.rb`（无 split）；`admin/orders/fulfillments_controller.rb#split`（发货拆分，既有能力） | ❌ 需新增 admin split 端点 |
| API — routes | `pallastrade_api/config/routes.rb` | resources :orders | `resources :orders, concerns: :custom_fieldable`（member: complete/cancel/approve/resume/resend_confirmation） | ❌ 需加 `post :split` |
| Admin — controllers/views | `pallastrade_admin/app/` | orders / split | `orders_controller.rb`（show/edit/cancel）；`views/.../orders/show.html.erb`（partial 组织）；`_header.html.erb`（page_actions_dropdown）；`_line_items.html.erb`；导航 initializer（P6 注释就位） | ❌ 需新增拆分入口 + 拆分视图 + 父子树 partial |
| Storefront | `storefront/src/` | is_parent / children_ids | 账户订单 OrderCombinedPay 用 is_child 过滤（P5） | ❌ P6 为 Admin 侧，不涉及 |
| Platform | `platform/packages/` | admin-sdk | 无 admin-sdk 包 | ❌ 不涉及 |

### 搜索结论

Core 拆单引擎（P2 `Orders::Splitter`）已具备且是唯一拆单入口；API 缺 admin split 端点；Admin 缺拆分 UI 与父子树 partial。**不新建拆单服务**，直接复用 `Orders::Splitter`，避免重复实现。

---

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions。P6 用 `PallasTrade::Config`/store preference 做 flag（第 2 档），Admin UI 用「Add a section / form field」+ 直接改 gem 视图（AGENTS.md：Admin views 直接改 `pallastrade_admin/app/views/` 加 `# PALLAS-CUSTOM:` 注释）。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | Admin = Rails engine（ERB + Stimulus + Turbo + Tailwind）；自定义视图在 `pallastrade_admin/app/views/`；partials 通过 `PallasTrade.admin.partials.<page> << '...'` 扩展；`orders/show.html.erb` 有 `order_page_header_partials` / `order_page_sidebar_partials` / `order_page_body_partials` 扩展点。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 阶段 0-1：`prd new`（自动查重）→ 6 层搜索 → 模板扩充 → 用户确认（"确认"/"认可"/"实施"）→ 状态 approved → 才开 gate 实施。 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | Admin API 模式：`scoped_resource :orders` + `authorize!` + `with_order_lock` + `render_service_error(result.error)`；member action 模式（complete/cancel/approve/resume）；P1 已为 OrderSerializer 加 parent_id/children_ids/is_parent/is_child/is_single。 |
| `pallastrade-checkout` | ✅ | ⬜（沿用 P5 已读结论） | 拆单只在线路收敛点执行（Carts::Complete 自动 + Admin 手动）；子订单不重走 checkout 状态机；父订单为空容器不进入 finalize!。 |
| `pallastrade-testing` | ✅ | ⬜（沿用既有约定） | RSpec request spec + feature spec；admin API 用 `spec/requests/api/v3/admin/`；Admin UI 用 `spec/features/admin/`。 |

---

## 需求标题

Admin 手动拆单（订单详情拆分部分行项目到子订单）+ 父子树展示（父订单聚合 / 子订单父链接 / 列表父子过滤），feature flag 灰度。

## 任务类型

新功能（flag 默认关闭）

## 需求描述

1. **Admin API**：`POST /api/v3/admin/orders/:id/split`——接收 `groups`（分组 → 行项目 id）、可选 `parent_order_id`、可选 `stock_location_id`、可选 `store_id`（P6 仅允许 == 源订单 store）。复用 `PallasTrade::Orders::Splitter`。flag 关闭 404；错误 `code + message`；幂等。
2. **Admin UI**：订单详情 dropdown「拆分订单」入口（flag + `can?(:split, order)`）→ 拆分页（行项目勾选、目标仓库、金额预览、确认）→ 提交后重定向父订单详情。
3. **父子树**：父订单详情 children 卡片聚合（金额/支付/发货/链接）；子订单详情父 banner；Admin 订单列表 Ransack 父子过滤。
4. **flag**：`store.preferred_manual_split_enabled` / `Config[:admin_manual_split_enabled]`，默认 false。

## 验收标准

- AC-001~006 → `backend/spec/requests/api/v3/admin/orders_split_spec.rb`
- AC-007~008 → `backend/spec/features/admin/orders_split_spec.rb`
- AC-009 → `backend/spec/features/admin/order_parent_child_tree_spec.rb`

详见 PRD §5。

## 实施要点

- **pallastrade_api**：`admin/orders_controller.rb` +`split` action（`with_order_lock` + `Splitter.call` + `render_service_error`）；`config/routes.rb` member +`post :split`；api-docs `admin.yaml` +端点。
- **pallastrade_admin**：`orders_controller.rb` +`split`（GET 表单页）/`split_create`（POST 执行）；`views/.../orders/split.html.erb`（表单 + 金额预览）；`_parent_child_tree.html.erb`；`_header.html.erb` dropdown 入口；locales；ability `:split`。
- **pallastrade_core**：`store.rb` preference `manual_split_enabled`；`configuration.rb` preference `admin_manual_split_enabled`；`initializers/pallastrade.rb` 默认 false。
- **无新迁移**；**不新建拆单服务**（复用 Splitter）。

## 测试计划

- 新增 `backend/spec/requests/api/v3/admin/orders_split_spec.rb`、`backend/spec/features/admin/orders_split_spec.rb`、`backend/spec/features/admin/order_parent_child_tree_spec.rb`
- 回归 P2 `orders/splitter_spec.rb`

## 文档同步

- `backend/public/api-docs/admin.yaml`（split 端点）→ `generated:check`
- Skill：pallastrade-admin / pallastrade-api-v3 / pallastrade-checkout / pallastrade-data-model
- 升级方案 P6 段标记完成；PRD §9/§10；docs/prd/README.md 索引
