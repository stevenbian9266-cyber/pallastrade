# PRD-20260917-catalog-bulk-media

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 一句话需求「实施」；用户在工作区选定「**批量移除媒体（Bulk Media）**」← `豆包梳理业务需求/商品升级方案.md` §5.1 |
| 分类 | catalog |
| 关联 Skill | pallastrade-admin、pallastrade-catalog、pallastrade-testing |
| 关联 REQ | REQ-20260917-catalog-bulk-media.md |
| 关联 PRD | **PRD-20260915-admin-bulk-operations-2**（Bulk 2.0 的「预览→确认」框架与既有 5 个动作；本 PRD 只补该表最后一行 Media） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **背景**：方案 §5.1「Bulk Operations 2.0」列了 6 个动作，其中 Set Price / Adjust Price % / Adjust Inventory / Add to Channels / Remove from Channels **均已交付**（`PRD-20260915-admin-bulk-operations-2`），只剩 **Media** 一行未做（方案当时标「暂缓」）。现状是商家想处理一批导入错误/低质量图片时，**只能逐商品进入编辑页删除** —— 128 个商品就是 128 次往返。
- **目标**：在 Admin 商品列表新增 **批量移除媒体**，沿用它既有的「Select → Configure → **Preview** → Confirm → Result」范式，使清空一批商品的媒体变成一次可预览、可解释、可审计的操作。
- **成功指标**：
  1. 选中 128 个商品 → 预览显示「将清空 N 个商品 / 将删除 M 个媒体文件 / 跳过 K 个（无媒体）」，且**预览零写入**；
  2. 执行结果是**预览所报数字的同源实现**（预览与执行走同一次遍历，不给两套口径）；
  3. 执行后**不残留任何悬空指针**（`primary_media_id` 必须一并置空）。
- **明确不做**（与方案 §5.1 一致，且符合方案 §2 技术策略「模型层尽量保持稳定」）：
  1. **不做批量替换 / 批量生成 / AI 生图** —— 只做「移除」；
  2. **不新增/修改任何模型与表**（纯 Admin 编排层）；
  3. 不碰变体与商品的**业务数据**（价格/库存/状态/渠道/订单一律不动）。

## 2. 用户故事 / 场景

- 作为**商品运营**，我要把一批从供应商导入、图片全错的商品**先清空媒体**，再统一重新上架正确图片，而不是逐个商品点进去删。
- 作为**店主**，我要在执行前**看到到底会删掉多少个文件**，因为这是不可逆操作。
- 场景：
  - **正常流**：选中若干商品 → 选「批量移除媒体」→ 预览显示将清空 X / 将删除 Y / 跳过 Z → 确认 → 列表 flash 报出更新与跳过数。
  - **边界（无媒体）**：选中的商品里有些本来就没媒体 → 计入 **skipped**，不算失败、不报错。
  - **边界（混合）**：一部分有、一部分没有 → 两者计数相加 **等于** 选中数（不重不漏）。
  - **异常（权限不足）**：当前管理员只能读不能改 → **零更新**、全部 skipped、给出 warning，且**不修改任何数据**。
  - **异常（预览未确认就直达执行 URL）**：执行本身仍然按同一套服务运行（不依赖「必须先预览」这一前端约定来保证安全）。
  - **跨店**：只能作用于 `current_store` 的商品；其他店铺商品即使被塞进 `ids` 也不受影响。

## 3. 功能需求（FR）

- **FR-001 新 bulk action**：商品列表注册 `remove_media`，label/body 走 i18n，`confirm` 走框架既有机制；不新建第二套 bulk 体系（沿用 `PallasTrade.admin.tables.products.add_bulk_action`）。
- **FR-002 服务对象**：新增 `PallasTrade::Products::BulkMediaRemoval < PallasTrade::Products::BulkOperation`，与既有 5 个动作同构（`preview` / `call` 共用同一次 `run(dry_run:)` 遍历）。
- **FR-003 移除范围（必须写进 UI 文案，不留歧义）**：
  1. **商品级媒体** `product.media`（`PallasTrade::Asset` where `viewable = product`）；
  2. **变体级图片** 该商品**所有变体**（含 master）的 `variant.images`。
  即「这个商品的媒体全部清空」，与「批量替换」无关。
- **FR-004 级联不手动重建**：`Asset` 自身已声明 `has_many :variant_media, dependent: :destroy` → 变体↔媒体的关联行随 Asset 删除而清理并触发缩略图刷新。**不得**在服务里手写第二套级联。
- **FR-005 悬空指针必须一并清理**：`Product#primary_media_id` 与 `Variant#primary_media_id` 都**没有** `dependent:` ⇒ 服务在删除后必须把**受影响记录**的该列置 `nil`（只清被删媒体的持有者，不做全表写）。
- **FR-006 预览零写入**：`dry_run: true` 路径**只读**（不改 asset、不改列、不写审计）。
- **FR-007 口径同源**：`updated_count` / `skipped_count` 在预览与执行中来自**同一段遍历逻辑**，预览数字必须等于执行结果。
- **FR-008 分类计数**：有媒体的商品计入 `updated_count`（预览文案「将清空」）；无媒体的计入 `skipped_count`（「跳过」）。
- **FR-009 权限**：需要 `update` 商品 **且** `manage` Asset；不满足时 `updated_count = 0`、`skipped_count = 选中数`、`warnings[:permission_denied] += 1`，**并且不执行任何写操作**。
- **FR-010 跨店隔离**：服务只接受来自 `bulk_collection`（= `model_class.accessible_by(current_ability, :update).where(id: params[:ids])`）的对象，不自行按 id 查全表。
- **FR-011 审计**：执行成功后写 `ProductHistory` bulk 记录（action `product.bulk_media_removed`，metadata 含 updated/skipped 计数），与既有 5 个动作一致。
- **FR-012 结果反馈**：flash 报出更新数与跳过数（i18n key `admin.bulk_ops.products.result.media_removed`）。
- **FR-013 路由**：`put :bulk_media_preview` + `put :bulk_media_remove`，与既有动作同命名法。
- **FR-014 无媒体不报错**：整批都没有媒体时也返回成功语义（0 更新 / N 跳过），**不得**抛错或显示「失败」。

## 4. 非功能需求（NFR）

- **性能**：预览不得逐商品 N+1 —— 媒体计数用**一次聚合查询**（按 `viewable_type/viewable_id` 分组），执行时按集合批量删除；128 个商品的操作与单个商品同阶。
- **安全**：沿用一个不可逆操作应有的防护 —— ①预览先于执行；②权限按 `update` + `manage` 双重判定；③跨店隔离由 `bulk_collection` 保证；④服务不接收任意 id 列表（不提供「按 id 直删 asset」的入口）。
- **可维护**：与既有 5 个 bulk 动作严格同构（同一基类、同一 controller 私有工厂、同一 preview/run 辅助方法），新增动作**不得**引入第三种模式。
- **兼容**：不改模型、不改表、不改 API 契约；既有 bulk 动作与商品编辑页的媒体行为**零回归**。
- **可解释**：预览必须同时给出「将清空 / 将删除文件数 / 跳过」，而不是只给一个总数。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-006**：调用预览后，Asset 行数与 `primary_media_id` **全部不变**（零写入）。
- **AC-002 ← FR-007**：同一批商品，预览报出的 updated/skipped 与随后执行的结果**逐项相等**。
- **AC-003 ← FR-003**：执行后，选中商品的 `product.media` 与各 `variant.images` **均为空**。
- **AC-004 ← FR-005**：执行后，受影响 Product 与 Variant 的 `primary_media_id` **均为 nil**（无悬空外键）。
- **AC-005 ← FR-004**：执行后，不残留任何 `VariantMedia` 行指向已删除的 asset。
- **AC-006 ← FR-008**：有/无媒体混合时，`updated + skipped == 选中数`。
- **AC-007 ← FR-009**：无权限时 `updated_count == 0`、数据零变化、`warnings` 含 `permission_denied`。
- **AC-008 ← FR-010**：把其他店铺的商品 id 塞进 `ids`，该店商品媒体**不受影响**。
- **AC-009 ← FR-011**：执行后产生 `product.bulk_media_removed` 的 ProductHistory bulk 记录且计数与结果一致。
- **AC-010 ← 非目标**：执行后商品的价格/库存/状态/渠道/订单**零变化**。
- **AC-011**：未选中的商品（含同店其他商品）媒体**不受影响**。
- **AC-012 ← FR-014**：整批都无媒体时返回 0 更新 / N 跳过，无异常。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | bulk / media | 无 | ❌ ABSENT |
| Core | `pallastrade_gems/pallastrade_core/app/` | bulk / asset / variant_media | `services/pallastrade/products/{bulk_operation,bulk_price_update,bulk_inventory_adjust,bulk_channel_assignment}.rb`、`models/pallastrade/{asset,variant_media}.rb`、`Product#media` / `Variant#images` | ⚠️ 有批量基类与媒体模型，**无批量媒体服务** |
| API | `pallastrade_gems/pallastrade_api/app/` | bulk / media | 无 bulk 端点（本需求不动 API） | ➖ 不涉及 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | bulk action / preview | `controllers/concerns/.../bulk_operations_concern.rb`、`controllers/.../products_controller.rb`（`bulk_*_preview` / `bulk_*`）、`models/.../admin/table/{bulk_action.rb,table.rb}`、`views/.../bulk_operations/preview` | ⚠️ 框架齐备，**缺 Media 动作** |
| Storefront | `storefront/src/` | media | 仅消费 API，无写能力 | ➖ 不涉及 |
| Platform | `platform/packages/` | media | 无 | ➖ 不涉及 |

**结论**：能力分布 = 批量框架 ✅ / 媒体模型与级联 ✅ / **批量媒体动作 ❌（本 PRD 唯一新增）**。
**防重复判定**：不新建 bulk 体系、不在模型层加任何东西、不写第二套级联 —— 只补「一个服务 + 一个 action 注册 + 两个 controller 动作 + 路由 + i18n + 测试」。

## 7. 技术影响

- **Core**：`app/services/pallastrade/products/bulk_media_removal.rb`（新增）
- **Admin**：`products_controller.rb`（+2 动作 +1 私有工厂）、`config/routes.rb`（+2 路由）、`config/initializers/pallastrade_admin_tables.rb`（+1 bulk action）
- **i18n**：gem `pallastrade_admin/config/locales/en.yml` + host `backend/config/locales/admin_*.zh-CN.yml`
- **数据库 / API / Storefront / Platform**：**零改动**（符合方案 §2 技术策略）
- **影响面**：`harness affected --base origin/dev`

**风险**：

| # | 级别 | 风险 | 缓解 |
|---|---|---|---|
| R-1 | **高** | 不可逆数据删除（媒体文件） | 强制 Preview + confirm；预览给出**将删除文件数**；范围限定「选中商品」；审计留痕 |
| R-2 | 中 | 悬空 `primary_media_id` | AC-004 专门覆盖，Product 与 Variant 两侧都要清 |
| R-3 | 低 | 与既有 bulk 动作模式漂移 | 严格继承 `BulkOperation` + 复用 preview/run 辅助方法 |
| R-4 | 低 | 误删变体媒体超出预期 | FR-003 把范围**写进 i18n 文案**，预览列出「商品级 + 变体级」两行 |
| R-5 | 中 | **共享的 `bulk_collection` 不做店铺作用域**（只按 ability 过滤，而 superuser ability 跳店）⇒ 理论上可借当前店铺的 UI 操作到别的店铺的商品 | 本动作额外 `merge(current_store.products)` 收窄（合法路径 no-op）；**其余 bulk 动作存在同样的口子，未在本 PRD 修正**（需单独评估各自既有 spec）—— 已记录，建议后续单独立项 |

**回滚难度**：低 —— 纯 Admin 层新增动作，**无 schema 变更**。回滚 = 移除 action 注册（动作从列表消失）或 revert 提交；已被删除的媒体文件本身**不可恢复**（这正是强制预览的原因）。

## 8. 测试计划

- **新增**：`backend/spec/services/pallastrade/products/bulk_media_removal_spec.rb`（AC-001…AC-007、AC-010…AC-012）
- **新增**：`backend/spec/requests/pallastrade/admin/bulk_media_removal_spec.rb`（AC-002、AC-009：预览→执行端到端 + 审计）
- **更新**：无（既有 bulk spec 不应受影响，作为回归证据）
- **AC 映射**：AC-001/003/004/005/006/007/010/011/012 → service spec；AC-002/009 → request spec；AC-008 → request spec（跨店）
- **证据**：新增 `harness verify bulk-media-rspec` + `harness check --profile quick`

## 9. 文档同步清单（知识同步门）

- [x] Skill：`pallastrade-admin`（Bulk 节新增 Media 子节 + 范围/级联/指针/`bulk_collection` 不收窄的说明）
- [x] `AGENTS.md` §6（新增 `bulk-media-rspec` verifier 行）
- [x] 场景库 `harness/scenarios/scenarios.json`（GS-176）
- [x] `harness.config.mjs`（`evidence.verifiers['bulk-media-rspec']`）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [x] API 文档：**不涉及**（无端点变更，已验证 `doc-impact` 零缺失）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-17 | 0.1 | 初稿：范围（商品级 + 变体级全清）、级联与指针清理口径、12 条 AC | AI |
| 2026-09-17 | 1.0 | 实施完成：服务 + 动作注册 + 2 路由 + 4 i18n 键（en/zh-CN）+ 17 个新 spec 全绿；既有 `admin-products-bulk-rspec` 与 `admin-i18n-rspec` 回归均通过。**超出原计划的加固**：目标集合额外按 `current_store` 收窄（见 §7 R-5）。 | AI |
