# PRD-20260828-admin-p6-admin-手动拆单-父子树-ui-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-28 |
| 来源 | 需求：P6 Admin 手动拆单 + 父子树 UI（flag 灰度） |
| 分类 | admin（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260828-admin-p6-admin-手动拆单-父子树-ui-flag-灰度

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-28 |
| 来源 | 需求：P6 Admin 手动拆单 + 父子树 UI（flag 灰度） |
| 分类 | admin（自动判定） |
| 关联 Skill | pallastrade-admin / pallastrade-api-v3 / pallastrade-checkout / pallastrade-data-model |
| 关联 REQ | REQ-20260828-order-lifecycle-p6.md |
| 关联 PRD | N/A（全新需求，`prd new --force` 创建，与 P5 查重 40% 但为独立阶段） |
| 需求类型 | 新功能 |

> 🔁 **查重回写**：`harness prd new` 命中相似 P5 PRD（40%），P5 已完成（done），P6 为独立阶段，经 `--force` 新建。

## 1. 背景与目标

- **一句话需求原文**：需求：P6 Admin 手动拆单 + 父子树 UI（flag 灰度）
- **背景**：P1（父子单结构）→ P2（`Orders::Splitter` 统一拆单引擎）→ P3（父子金额/支付状态派生）→ P4（合并支付载体）→ P5（Checkout 集成：自动拆单 + 合并支付收银台 + Buy Now）已完成。当前**缺少 Admin 侧手动拆单入口**（自动策略未命中/分仓/定制发货场景下运营需人工拆分），且后台**无父子关系可视化**（运营无法追踪父订单的成员/金额/发货/支付聚合）。
- **目标**：Admin 可在订单详情手动把部分行项目拆成子订单（复用 P2 `Orders::Splitter` 能力层）；后台展示父子树 + 父订单聚合视图。全程 feature flag 灰度，默认关闭。
- **成功指标**：
  - 手动拆单全流程（入口 → 选行项目 → 金额预览 → 确认 → 父子树可见）≤ 3 步
  - 拆分前后总额守恒（Σ子订单 + 父订单剩余 == 原订单总额）由单测强制断言
  - flag 关闭时 Admin/API 零行为变化

## 2. 用户故事 / 场景

- 作为运营，我希望在订单详情把部分行项目手动拆成子订单，以便按仓库/渠道/定制需求分批发货。
- 作为运营，我希望在父订单页看到全部成员订单及金额/发货/支付汇总，以便追踪整体履约。
- 作为运营，我希望在子订单页一键回到父订单，以便理解订单来源。
- 场景列表：
  - 正常：completed 订单，勾选 2 个行项目拆出 → 生成子订单（`parent_id` 指向源订单），源订单保留剩余行项目
  - 边界：全部行项目拆出 → 源订单成为空行项目父容器（P3 聚合值展示）；单行项目部分数量拆分（行项目级数量）
  - 异常：订单已取消 → 不可拆；无行项目 → 不可拆；非法行项目 id → 剔除后无有效分组 → 明确业务错误；相同 groups 重复提交 → 不产生重复子订单；`store_id` 与源订单不同 → 明确业务错误（跨店暂不支持）
  - flag 关闭：API 404 / Admin 无入口，行为与 P5 前完全一致

## 3. 功能需求（FR）

- FR-001：Admin API `POST /api/v3/admin/orders/:id/split`。参数：`groups`（必需，`Hash<group_key → line_item_ids>`，支持 `li_` 前缀或整型）、`parent_order_id`（可选，默认源订单自身为父）、`stock_location_id`（可选，为子订单建默认 shipment 的仓库）、`store_id`（P6 仅允许 == 源订单 store）。复用 `PallasTrade::Orders::Splitter.call(order:, groups:, parent_order:)`。flag 关闭返回 404。
- FR-002：拆单前置校验（服务端）：订单存在、未取消、有行项目；行项目属于该订单；`store_id` ≠ 源订单 store → 明确业务错误（跨店暂不支持）；幂等——行项目已迁移到子订单后重复提交 → 明确业务错误，不产生重复子订单。错误统一 `code + message`，无裸 422。
- FR-003：拆分结果：成功返回 `data: { parent, children }`（parent 与 children 均含 P1 父子字段 + P3 聚合值）；父订单与子订单金额/支付/发货状态正确刷新。
- FR-004：Admin 订单详情「拆分订单」入口：header dropdown 菜单项，flag 开启 + `can?(:split, order)` 才显示；flag 关闭/无权限不显示。
- FR-005：拆分 UI（Rails view）：行项目勾选分组（拆出组 → 子订单，其余留父订单）+ 可选目标仓库下拉 + 金额预览（拆出组小计 vs 父订单剩余）+ 确认提交；提交后重定向到父订单详情（或子订单）。
- FR-006：父子树展示：父订单详情显示 children 卡片列表（子订单号 / 金额 / 支付状态 / 发货状态 / 链接 + `combined_*` 聚合汇总）；子订单详情显示父订单 banner（链接回父）；Admin 订单列表 Ransack 支持父子过滤（`q[parent_id_null]` / `q[parent_id_not_null]`）。

## 4. 非功能需求（NFR）

- 性能：单次拆分请求（含事务 + 金额重算）< 2s；列表过滤走索引。
- 安全：仅 Admin 角色 + `can?(:split, order)`；所有查询过 `current_store` scope（防跨店数据泄漏）；`store_id` 校验防越权。
- 兼容：flag 默认关闭；不影响 P5 自动拆单 / P4 合并支付 / 单笔订单老流程；`FulfilmentChanger`（现有发货拆分）不受影响。
- 可维护：拆单单一入口复用 `Orders::Splitter`（不新建服务）；UI partial 遵循现有 admin 结构（Tailwind class，禁 inline style）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：flag 关闭时 `POST /api/v3/admin/orders/:id/split` → 404；flag 开启 + 合法 `groups` → 200 + `data{parent, children}`。
- AC-002 ← FR-002：已取消 / 无行项目订单 → 明确业务错误（`code + message`），不执行拆分。
- AC-003 ← FR-002：非法行项目 id 剔除后无有效分组 → 明确业务错误。
- AC-004 ← FR-002：相同 `groups` 二次提交 → 明确业务错误，不产生重复子订单（幂等）。
- AC-005 ← FR-002：`store_id` ≠ 源订单 store → 明确业务错误（跨店暂不支持），不部分执行。
- AC-006 ← FR-003：拆分后总额守恒（Σ子订单 total + 父订单剩余 total == 原订单 total）；completed 订单已付金额按行项目比例生成子订单 `PaymentSplit`。
- AC-007 ← FR-004：flag 开启 + 有权限 → 订单详情 dropdown 显示「拆分订单」；flag 关闭或无权限 → 不显示。
- AC-008 ← FR-005：拆分页可勾选行项目、显示金额预览、确认提交后重定向，且子订单在父子树中可见。
- AC-009 ← FR-006：父订单详情渲染 children 卡片（金额/支付/发货/链接）；子订单详情渲染父 banner；Admin 列表可按父子过滤。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | split / parent_id / children | 无业务代码（仅 `backend/app/javascript/types/serializers/*.ts` 旧 typelizer 生成物，未跟踪）；admin 功能均在 gem | ❌ 无需在此层实现（走 gem） |
| Core | `pallastrade_gems/pallastrade_core/app/` | Splitter / SplitStrategies | `services/pallastrade/orders/splitter.rb`（P2：`call(order:, groups:, parent_order:)` → success(children)/failure；行项目迁移 + order 级调整分摊 + 已付金额 PaymentSplit 分摊 + `order.splitted` 事件）；`split_strategies/{base,by_store,by_stock_location}.rb`（自动策略，手动拆单不走） | ✅ 能力层已就绪，P6 直接复用 |
| API | `pallastrade_gems/pallastrade_api/app/` | split / orders | `admin/orders_controller.rb`（create/update/complete/cancel/approve/resume/resend_confirmation，**无 split**）；`admin/orders/fulfillments_controller.rb#split` 是**发货拆分**（既有能力，勿混淆）；`config/routes.rb` `resources :orders, concerns: :custom_fieldable` member actions | ❌ 需新增 `POST split` 端点 + 路由 + serializer 复用（P1/P3 父子字段已就位） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | orders / split | `controllers/pallastrade/admin/orders_controller.rb`（show/edit/cancel/resend/destroy）；`views/.../orders/show.html.erb`（partial 组织：header/line_items/shipments/payments/refunds/...）；`_header.html.erb`（`page_actions_dropdown` 操作入口）；`_line_items.html.erb`（行项目表格）；`config/initializers/pallastrade_admin_navigation.rb`（订单导航，已有 P6 注释就位） | ❌ 需新增拆分入口 + 拆分视图 + 父子树 partial |
| Storefront | `storefront/src/` | is_parent / children_ids / parent_id | 账户订单 `OrderCombinedPay` 用 `is_child` 过滤（P5）；无父子树展示 | ❌ P6 为 Admin 侧，不涉及 |
| Platform | `platform/packages/` | admin-sdk | 无 admin-sdk 包（仅 cli / sdk / sdk-core / docs） | ❌ P6 不涉及 platform 代码 |

**结论**：Core 拆单引擎（P2 `Orders::Splitter`）已具备且为唯一拆单入口；API 缺 admin split 端点；Admin 缺拆分 UI 与父子树 partial。**不新建拆单服务**，复用 `Orders::Splitter`，避免重复实现（AP-SEARCH 防重复判定）。

## 7. 技术影响

- **pallastrade_api**：`admin/orders_controller.rb`（+`split` action）、`config/routes.rb`（`member { post :split }`）、serializer（复用 P1/P3 父子字段，无需改）、`backend/public/api-docs/admin.yaml`（+split 端点）。
- **pallastrade_admin**：`orders_controller.rb`（+`split` GET / `split_create` POST，或直接 +`split`）、`views/pallastrade/admin/orders/split.html.erb`（拆分表单）、`_parent_child_tree.html.erb`（父子树 partial）、`_header.html.erb`（dropdown 入口）、`locales/en.yml`（拆分文案）、`ability`（`can? :split`）。
- **pallastrade_core**：`store.rb`（`preference :manual_split_enabled, :boolean, default: false`）、`configuration.rb`（`preference :admin_manual_split_enabled, :boolean, default: false`）、`config/initializers/pallastrade.rb`（`config.admin_manual_split_enabled = false`）。
- **数据库**：无新迁移（P1 迁移已含 `parent_id`/`split_from_id` 等全可空列）。
- **影响面**：`harness affected --base origin/main`（实施时运行确认）。

## 8. 测试计划

- 新增测试文件：
  - `backend/spec/requests/api/v3/admin/orders_split_spec.rb`（AC-001~006：flag 404 / 校验 / 成功拆分组 / 幂等 / 跨店错误 / 总额守恒 + PaymentSplit）
  - `backend/spec/features/admin/orders_split_spec.rb`（AC-007~008：入口显示条件 + 拆分页流程 + 提交重定向）
  - `backend/spec/features/admin/order_parent_child_tree_spec.rb` 或 view spec（AC-009：父子树 partial 渲染）
- 更新测试文件：无（回归 P2 `orders/splitter_spec.rb` 全绿即可）。
- 覆盖的 AC 映射：AC-001~006 → `orders_split_spec.rb`（request）；AC-007~008 → `features/admin/orders_split_spec.rb`；AC-009 → `features/admin/order_parent_child_tree_spec.rb`。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/admin.yaml`（`POST /api/v3/admin/orders/:id/split` + 参数/响应 schema）→ `generated:check` 通过
- [x] Skill 文档：`pallastrade-admin`（手动拆单 + 父子树 UI）、`pallastrade-api-v3`（split 端点）、`pallastrade-checkout`（ManualSplit 语义 + flag）、`pallastrade-data-model`（沿用 P3 聚合，无需更新）
- [x] 升级方案 `docs/research/RESEARCH-20260826-order-lifecycle-upgrade-plan.md` P6 段标记完成
- [x] 本 PRD 状态 done + `docs/prd/README.md` 索引（done）
- [x] 反模式库 / 任务规则 / 场景库：评估无需更新（无新模式，P6 为 Admin 侧新入口）
- [x] README / Agent 文件 / 样式规范：评估无需更新（沿用既有 Admin ERB + Tailwind 规范）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-28 | 0.1 | 初稿：P6 Admin 手动拆单 + 父子树 UI（flag 灰度）；6 层跨层搜索完成 | AI |
| 2026-08-28 | 0.2 | 实施完成：Admin API `POST /orders/:id/split`（flag 404 + 跨店/已发货拒拆 + 幂等）+ `Orders::ManualSplit` 编排（子订单补 completed + 建 shipment 运费留父订单）+ Admin UI（dropdown 入口 / 拆分页 / 父子树 partial / 列表过滤）；后端 35 例 + P4/P1/P3 回归 35 例全绿；quick/generated:check 通过；同步 admin/api-v3/checkout Skill + api-docs + 升级方案 | AI |
