# REQ-20260915 — 管理后台商品批量运营 2.0（批量价格 / 库存 / 渠道 + 预览确认）

> 关联 PRD：`docs/prd/admin/PRD-20260915-admin-bulk-operations-2.md`
> 任务：TASK-20260915095643-61e14769 ｜ Gate：GATE-2026-09-15T09-57-XX（以实际为准）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | bulk / price | 无宿主实现 | 不适用（零宿主改动） |
| App — views/decorators | `backend/app/` | bulk | 无 | 不适用 |
| Core Gem — models | `pallastrade_core/app/models/` | `count_on_hand` / `base_prices` / `add_products` | `stock_item.rb`（L59 `adjust_count_on_hand`、L65 `set_count_on_hand`）、`price.rb`（`base_prices` 作用域、`after_save :record_price_history`）、`channel.rb`（L57 `add_products`、L102 `remove_products`） | **写路径齐备**（无需改模型） |
| Core Gem — services | `pallastrade_core/app/services/` | bulk / prepare | `products/prepare_nested_attributes.rb`（L151 `can_update_prices?`、L159 `can_update_stock_items?` 权限范式） | 复用权限判定；**新增 3 个批量服务** |
| API Gem — controllers | `pallastrade_api/app/controllers/` | bulk | admin products_controller（bulk_status_update / add\|remove_to_categories / add\|remove_from_channels / bulk_destroy） | 已有协议范式；本任务**不动 API** |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | bulk | `bulk_operations_controller.rb#new`、`concerns/bulk_operations_concern.rb`（`bulk_collection` / `handle_bulk_operation_response`）、`products_controller.rb`（4 个 bulk 动作样板） | **框架就绪** → 扩展 |
| Admin Gem — views | `pallastrade_admin/app/views/` | bulk | `bulk_operations/new.html.erb`、`forms/_taxon_picker|_tag_picker|_confirmation`、`shared/_bulk_modal.html.erb` | 表单/预览范式就绪 |
| Storefront | `storefront/src/` | — | — | 不涉及 |
| Platform | `platform/packages/` | — | — | 不涉及 |

### 搜索结论

- 模型写路径（价格/库存/渠道）与权限判定范式全部已存在，**零迁移**；缺口集中在 Rails Admin 操作面。
- 批量 UI 框架（tables 注册 + turbo 模态 + 表单 partial）可直接扩展，无需新 JS 控制器。
- 防重复：Admin API 的 bulk 端点面向外部消费者，本任务只补 Rails Admin（商家入口），不重复建设 API。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：优先 `PallasTrade.admin.tables.<key>.add ...`（Admin 扩展）——本任务正是该路径，不走 decorator/引擎替换 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | ① 表格定制入口 `PallasTrade.admin.tables.products.add/update/remove`；② admin 页面三要素（标题/面包屑/操作按钮）+ Turbo 约定（`data: { turbo_method: }`）；③ 视图注入点 `render_admin_partials` |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | ① `Product#default_variant` 语义（master 回退）；② metafields/媒体与本任务无关；③ 价格改动若批量 `update_all` 会绕过 PriceHistory 回调（必须逐行 `update!`） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 不动 v3 API |
| `pallastrade-decorators` | ⬜ 不涉及 | — | 零后端装饰器 |
| `pallastrade-dependencies` | ⬜ 不涉及 | — | 无服务替换 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 批量写不新增事件 |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 前台零改动 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | 后端 = RSpec + Factory Bot；admin request spec 需 `stub_authorization!` + 登录（参照 `spec/requests/pallastrade/admin/payment_methods_spec.rb`） |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已读 | admin 文案在 `pallastrade_admin/config/locales/en.yml`（bulk_ops.products 结构），新增键需与既有 title/body 结构一致 |

---

## 需求标题

管理后台商品批量运营 2.0：批量价格（Set / ±%）、批量库存（按库存点 ±）、批量渠道上下架，全部走预览确认。

## 任务类型

新功能（管理后台）

## 需求描述

运营在商品列表选中商品后，可执行 5 类批量动作；每个动作先预览（将更新/将跳过/警告），确认后执行并返回汇总；权限不足或不适用对象逐项跳过且汇总提示。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 31,
  "affectedComponents": ["ai", "backend", "harness"],
  "estimatedTests": 93
}
```

> 注：`harness affected` 内部对 `origin/main...HEAD` 取 diff；本仓 dev-only 无 main（见 AGENTS §0.4），该条 error 不影响组件/测试估算。

## 技术方案（初步）

- 决策树层级：**Admin 扩展（tables.add_bulk_action）+ Core 服务对象**——零迁移、零 API 变更。
- 服务三件：`BulkPriceUpdate`（mode: set / adjust_percent）、`BulkInventoryAdjust`、`BulkChannelAssignment`（mode: add / remove）；统一 `preview` / `call`。
- 控制器：6 个动作（3 组 preview/execute）；预览渲染 `bulk_dialog` 内的确认视图。
- 权限：逐产品 `can?(:manage, Price/StockItem/ProductPublication)`，不满足 → 跳过 + 警告计数。

## 风险点

- 最高风险：批量价格写入放大（逐变体 `save!`）；缓解：仅 `base_prices`、选中 >500 时警告提示。
- 回滚难度：低（纯代码，无迁移；revert 即可）。

## 决策节点

> ⏸️ 用户已授权（2026-09-15 原话：「那就以此为作为 PRD 理想输入，实施」，且后续「继续」推进）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core 服务（3 个） | `pallastrade_core/app/services/pallastrade/products/bulk_*.rb` | `harness verify admin-products-bulk-rspec --task …` | 17 examples, 0 failures（2026-09-15 10:07，容器 `pallastrade-web-1`；覆盖创建/更新、币种大写、round(2)、clamp、跳过原因） | ✅ |
| Admin 控制器/路由/表格/视图/i18n | `pallastrade_admin/**` | 同上（请求规格覆盖 302 + 落库断言） | 17 例含 302+flash、preview 零写入、计数一致、逐条权限跳过、`PallasTrade.t` i18n 断言、5 个 kind 模态渲染 | ✅ |
| 文档/知识 | Skill / scenarios / harness.config / AGENTS / PRD | `harness doc-impact` + `sync-check --ack` | admin Skill（Bulk Ops 2.0 章节）/ GS-129（130/130 valid）/ verifier 注册（23 个）/ AGENTS §6 行 / PRD 状态 done；doc-impact 待采集（见验证结论） | ✅ |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题 | 批量模态（`bulk_dialog`） | ✅ | 模态 title/body 来自 `BulkAction`（tables 注册的 label/body，`admin.bulk_ops.products.title|body.*`） |
| ② 面包屑 | 不适用（模态无面包屑） | N/A | 列表页面包屑已存在 |
| ③ 页面操作按钮 | 预览/确认按钮 | ✅ | `turbo_save_button_tag`（`_preview.html.erb`：计数 dl + warnings + 确认提交） |
| ④ POST/PATCH/DELETE 链接用 `data: { turbo_method: }` | 批量动作按钮 | ✅ | 走既有 `bulk_action_link`（`setBulkAction` + `_method`）；预览→执行用 `form_tag(..., method: :put)` 渲染隐藏 `_method`，无新增裸链接 |

### 验证结论

<!-- 收尾时回填 -->

- **测试**：`admin-products-bulk-rspec` → 17 examples / 0 failures（请求规格覆盖 AC-001~010 + 模态接线；预览零写入、计数一致、逐条跳过、302+flash 均已断言）。
- **i18n 环境事实**（已写入 Skill）：admin 引擎翻译须经 `PallasTrade.t(key, default: nil)` 解析；裸 `I18n.exists?` 在本环境对引擎键（含既有键）返回 false，故 AC-010 断言按应用入口书写。
- **知识同步**：admin Skill / GS-129 / verifier / AGENTS §6 全部落盘；scenarios 130/130 valid；verifier 注册数 23。
- **遗留**：浏览器点选冒烟未作为门禁（首版以请求规格为准）；`harness doc-impact --base origin/dev` 在提交后统一采集。
- **未越界声明**：不动 v3 API / OpenAPI / SDK；无 DB 迁移；无宿主 `backend/app/` 改动。
