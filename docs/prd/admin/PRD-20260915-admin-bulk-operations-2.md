# PRD-20260915-admin-bulk-operations-2

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》Batch B 切片一（用户授权原话：「那就以此为作为 PRD 理想输入，实施」，2026-09-15） |
| 分类 | admin（关键词命中 3：管理后台/后台/运营） |
| 关联 Skill | pallastrade-admin / pallastrade-catalog |
| 关联 REQ | REQ-20260915-bulk-operations-2.md |
| 关联 PRD | N/A（Batch A 见 `PRD-20260915-catalog-pdp-state-correctness`；Batch B-2 Catalog Health 另行立项） |
| 需求类型 | 新功能（管理后台运营效率） |

> 🔁 **查重**：`harness prd new` 通过。系列切分：Batch B-1 = 批量运营（本 PRD）；Batch B-2 = Catalog Health；Batch C/D 后续独立立项。

## 1. 背景与目标

- **背景**（审计：`harness/reviews/REVIEW-20260915-storefront-pdp-admin-products-audit.md` §3.6）：后台商品批量动作仅 7 个（状态/分类/标签），`tables.rb` 无价格/库存/渠道批量；Admin API 虽有 `bulk_add|remove_to_channels` 等端点，但 Rails Admin（商家日常入口）无对应能力 → 运营只能「逐个商品编辑」。
- **目标**：商品列表新增 5 个高频批量动作（Set Price、Adjust Price %、Adjust Inventory、Add/Remove Channels），全部走 **预览 → 确认 → 执行 → 结果汇总** 流程；权限不足/不适用对象逐项跳过并汇总提示，绝不静默失败。
- **成功指标**：① 5 个动作可在 admin 商品列表选中 ≥1 商品后完成端到端操作（含预览计数与结果 flash）；② 预览零写入（dry-run 断言）；③ 价格批量写入触发 PriceHistory 且不触碰 price_list 价格；④ 库存批量 clamp ≥0、跳过不追踪库存的产品。

## 2. 用户故事 / 场景

- 作为**运营**，我希望对选中商品统一改价或按 ±% 调价（指定币种），以便快速跟价/调价。
- 作为**运营**，我希望对选中商品在指定库存点批量增减库存（如盘点后 +10），以便修正盘差。
- 作为**运营**，我希望批量把商品发布/下架到指定渠道，以便多渠道运营。
- 作为**运营**，我希望执行前看到「将更新 N / 将跳过 M / 警告列表」，执行后看到汇总，以便有把握地批量操作。
- 边界：无该币种价格（skip）；库存不追踪（skip）；无权限（skip+警告）；负向调价后金额 < 0（skip+警告）；库存被 clamp 到 0（warning）；未选择渠道（阻断提交）。
- 异常：空选中（按钮不可达）；参数缺失（表单 required + 服务层兜底 skip 全部并警告）。

## 3. 功能需求（FR）

- **FR-001 批量定价（Set Price）**：对选中产品的**全部变体（含 master）**在指定币种下写入 base price（无则创建，有则覆盖 `amount`；不动 `compare_at_amount`）。
- **FR-002 批量按百分比调价（Adjust Price %）**：对已有 base price 按 `amount × (1 ± p%)` 调整（两位小数四舍五入）；无该币种价跳过；结果 < 0 跳过并计入警告。
- **FR-003 批量库存调整（Adjust Inventory）**：对选中产品的全部变体在**指定库存点**上 `count_on_hand += delta`（缺失 stock item 则创建），clamp ≥ 0；`track_inventory=false` 的变体/产品跳过。
- **FR-004 批量渠道上下架（Add/Remove Channels）**：把选中产品批量发布到 / 从所选渠道移除（`Channel#add_products/remove_products`）。
- **FR-005 预览与结果**：所有动作先进入 `*_preview`（零写入）渲染：选中数、将更新数、将跳过数、警告清单 + 确认按钮（携带相同参数的隐藏表单）；执行后 `redirect_back` + flash 汇总（updated/skipped）。
- **FR-006 权限与安全**：逐产品校验 `can?(:manage, Price/StockItem)` 与 `can?(:manage, ProductPublication)`，不满足者跳过并计入警告；价格写入必须走 `update!`（触发 `record_price_history` 回调，EU Omnibus）；**绝不触碰 price_list 价格**（仅 `base_prices`）；不新增接口面（不动 v3 API）。

## 4. 非功能需求（NFR）

- **性能**：单次批量按选中集合线性执行；价格查询按币种预过滤（`base_prices.with_currency`）；单请求内完成（首版不考虑超大批量异步化，>500 选中时提示后续分批——文案警告）。
- **兼容**：既有 7 个批量动作行为不变；`bulk_collection` 复用 `accessible_by(:update)` 语义。
- **可测试性**：核心逻辑下沉到三个服务对象（`PallasTrade::Products::BulkPriceUpdate / BulkInventoryAdjust / BulkChannelAssignment`），预览与执行为同一服务的 `preview` / `call` 两个入口（计数一致可断言）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：Set Price 为所有变体（含 master）写入指定币种 base price；无价变体被创建；结果计数 updated/skipped 正确。
- AC-002 ← FR-006：Set Price 不影响 price_list 价格行（值不变）。
- AC-003 ← FR-006：开启 `track_price_history` 时，改价产生 `PriceHistory` 行。
- AC-004 ← FR-002：Adjust % 按 ±% 计算（四舍五入 2 位）；无价变体跳过；负结果跳过并计入警告（不落库）。
- AC-005 ← FR-003：Adjust Inventory 在指定库存点增减；缺失 stock item 创建；clamp ≥ 0；不追踪库存的产品跳过并计入警告。
- AC-006 ← FR-004：Add/Remove Channels 正确发布/移除（ProductPublication 存在性断言）。
- AC-007 ← FR-005：`*_preview` 零写入（价格/库存/渠道 before-after 全等）且返回与执行一致的将更新/将跳过计数。
- AC-008 ← FR-006：无权限产品被跳过且计入警告，其余照常执行。
- AC-009 ← FR-005：执行后重定向回列表（302）并带汇总 flash。
- AC-010 ← FR-005：（i18n 完整性）新增 title/body/form/preview/result/warnings 键在 `pallastrade_admin` 的 en.yml 齐备。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | bulk | 无 | 不适用（宿主零改动） |
| Core | `pallastrade_core/` | price / stock_item / channel / PrepareNestedAttributes | `price.rb`（`base_prices`、`after_save :record_price_history`）、`stock_item.rb`（`adjust_count_on_hand/set_count_on_hand`）、`channel.rb`（`add_products/remove_products`）、`prepare_nested_attributes.rb`（`can_update_prices?/can_update_stock_items?` 权限范式） | **写路径齐备**（新增 3 个批量服务） |
| API | `pallastrade_api/` | bulk | admin `products_controller`（status/categories/channels/destroy bulk） | 已有对应协议范式；本 PRD 不动 API |
| Admin | `pallastrade_admin/` | bulk_operations | `BulkOperationsConcern`（`bulk_collection`/`handle_bulk_operation_response`）、`BulkOperationsController#new`（读 `BulkAction`）、`tables.add_bulk_action`（label/body/form_partial/action_path/condition）、`bulk_operations/forms/*_picker`、turbo 模态（`bulk_dialog` frame + `setBulkAction`） | **框架就绪** → 扩展 5 个动作 + 预览步骤 |
| Storefront | `storefront/src/` | — | — | 不涉及 |
| Platform | `platform/packages/` | — | — | 不涉及（无 SDK/类型变更） |

**结论**：能力缺口在 Rails Admin 的操作面；后端模型写路径、权限范式与批量 UI 框架均已具备 → 只需新增服务 + 控制器动作/路由 + 表单/预览视图 + i18n。

## 7. 技术影响

- **Core 服务（新增）**：`pallastrade_core/app/services/pallastrade/products/bulk_price_update.rb`、`bulk_inventory_adjust.rb`、`bulk_channel_assignment.rb`（三者同一接口：`preview` / `call` 返回计数与警告）
- **Admin（改动）**：
  - `app/controllers/pallastrade/admin/products_controller.rb`（+6 个动作：3 组 preview/execute）
  - `config/routes.rb`（products collection +6 PUT 路由）
  - `config/initializers/pallastrade_admin_tables.rb`（+5 个 `add_bulk_action`）
  - `app/views/pallastrade/admin/bulk_operations/forms/_price_form.html.erb`、`_inventory_form.html.erb`、`_channels_form.html.erb`、`_preview.html.erb`（新；预览 partial 渲染计数 + warnings + 确认表单）
  - `config/locales/en.yml`（bulk_ops.products 新键：5 动作 title/body + form/preview/result/warnings 段）
- **规格（新增）**：`backend/spec/requests/pallastrade/admin/products_bulk_operations_spec.rb`（17 例：AC-001~010 + 模态接线 2 例）
- **无 DB 迁移、无 v3 API 变更**（无 OpenAPI/SDK 同步）
- **知识同步**：`pallastrade-admin` Skill（Bulk Operations 章节）、`scenarios.json`（GS-129）、`harness.config.mjs`（新 verifier `admin-products-bulk-rspec`）+ AGENTS.md §6 行
- **风险**：价格批量写放大（每变体 save!）→ 首版限制选中规模（>500 警告）；回滚 = revert 提交（无数据迁移）

## 8. 测试计划

- 新增：`backend/spec/requests/pallastrade/admin/products_bulk_operations_spec.rb`
  - 覆盖 AC-001（set price 创建/更新 + 计数）、AC-002（price_list 不受影响）、AC-003（PriceHistory）、AC-004（调整与跳过/负值）、AC-005（库存增减/创建/clamp/跳过）、AC-006（渠道发布/移除）、AC-007（preview 零写入 + 计数一致）、AC-008（权限跳过）、AC-009（302 + flash）、AC-010（i18n 键齐备，经 `PallasTrade.t` 断言）、模态接线（`/admin/bulk_operations/new` 对 5 个 kind 渲染 mode/currency/amount/percent/delta/stock_location_id/channel_ids 字段）
- 注册 verifier：`admin-products-bulk-rspec`（`harness verify admin-products-bulk-rspec --task <id>`）
- 手动（可选）：本地 admin 浏览器点选验证 —— 属 UI 冒烟，不作为门禁证据（首版以请求规格为准，浏览器验证记录进 REQ）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-admin/SKILL.md`（Bulk Operations 2.0：五部件表 + 六条不变量 + verifier 指引）
- [x] `harness/scenarios/scenarios.json`（GS-129：预览优先批量运营；`harness eval-ai --scenarios` → 130/130 valid）
- [x] `harness.config.mjs`（verifier `admin-products-bulk-rspec`）+ `AGENTS.md` §6 表格行
- [x] API 文档：**已评估，无需更新**（不动 v3 API）
- [x] SDK/反模式/任务规则：**已评估，无需更新**
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch B-1：FR-001~006 / AC-001~010） | AI |
| 2026-09-15 | 1.0 | 实施完成：3 个 core 批量服务 + admin 6 动作/6 路由/5 个 `add_bulk_action`/4 视图/en 键；规格 17 例全绿（verifier `admin-products-bulk-rspec`）；知识同步（admin Skill + GS-129 + verifier 注册 + AGENTS §6）→ 状态 done | AI |
