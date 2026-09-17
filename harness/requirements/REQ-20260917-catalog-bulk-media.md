# REQ-20260917-catalog-bulk-media

| 元数据 | 值 |
|---|---|
| 关联 PRD | `docs/prd/catalog/PRD-20260917-catalog-bulk-media.md`（approved → done） |
| 关联 Task | `TASK-20260917145700-f359fb1b` |
| 任务类型 | 新功能 |
| 分支 | dev |

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | bulk / media | 无 | ❌ ABSENT |
| App — views/decorators | `backend/app/` | bulk / media | 无 | ❌ ABSENT |
| Core Gem — models | `pallastrade_gems/pallastrade_core/app/models/` | asset / media / product | `pallastrade/asset.rb`（`has_many :variant_media, dependent: :destroy`）、`pallastrade/variant_media.rb`、`Product#media`、`Variant#images` / `Variant#variant_media` | ⚠️ 模型与级联齐备，**无批量服务** |
| Core Gem — services | `pallastrade_gems/pallastrade_core/app/services/` | bulk | `pallastrade/products/{bulk_operation,bulk_price_update,bulk_inventory_adjust,bulk_channel_assignment}.rb` | ⚠️ 有基类与 3 个同类服务，**缺 media** |
| API Gem — controllers | `pallastrade_gems/pallastrade_api/app/controllers/` | bulk | 无 | ➖ 不涉及 |
| Admin Gem — controllers | `pallastrade_gems/pallastrade_admin/app/controllers/` | bulk | `concerns/.../bulk_operations_concern.rb`（`bulk_collection`）、`products_controller.rb`（5 组 `*_preview` / `*` 动作） | ⚠️ 框架与模式齐备 |
| Admin Gem — views | `pallastrade_gems/pallastrade_admin/app/views/` | bulk / preview | `bulk_operations/{new,_preview}.html.erb`、`bulk_operations/forms/{_price,_inventory,_channels,_confirmation,...}.html.erb` | ✅ **通用预览 + 空确认 partial 已有**，无需新视图 |
| Storefront | `storefront/src/` | media | 仅消费 API | ➖ 不涉及 |
| Platform | `platform/packages/` | media | 无 | ➖ 不涉及 |

### 搜索结论

**已有**：批量框架（注册表 / 通用 modal / 通用 preview / 空确认 partial）、`BulkOperation` 基类、
媒体模型与其级联、Catalog Health 的 `missing_media` 口径。

**需新建**：仅 4 项 —— 一个服务 + 一个动作注册 + 两个控制器动作 + 两个路由（i18n 4 键 + 测试）。

**防重复判定**：不新建 bulk 体系、不新建视图、**不改模型/表**（符合方案 §2 技术策略）、不写第二套级联。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（真实结论） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：「Add a section / form field to an existing admin page」→ `PallasTrade.admin.partials...` 与「Customize an admin table」→ `PallasTrade.admin.tables.<key>.add`；本需求正是后者（**第 4 级 Admin 扩展**），**不需要** decorator 或改模型 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | ①Bulk 2.0 的**五个部件缺一不可**（服务对象 / 预览路由 / 表单 partial / 预览 partial / 执行路由）；②**不变量**：预览零写入、逐条跳过而非整体失败、i18n 必须补 `admin.bulk_ops.products.*` 且规格断言要用 `PallasTrade.t(key, default: nil)`（裸 `I18n.exists?` 查不到引擎翻译）；③`_preview.html.erb` 是**通用**的；④`missing_media` 口径 =「产品层与变体层都无资产」 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 媒体挂在 `PallasTrade::Asset` 上（`viewable` 多态），商品与变体各自持有；Catalog Health 直接读 `pallastrade_assets` 事实表 |

**按需 Skill（本次涉及）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-testing` | ✅ 是 | ✅ 已读 | RSpec + Factory Bot；`create(:asset, viewable: product)` 会自动挂 fixture 图；**绝不用 `Model.create`** |
| `harness-prd` | ✅ 是 | ✅ 已读 | AC 必须有测试覆盖；接口变更才需同步 OpenAPI（本需求无端点变更） |
| `pallastrade-events-webhooks` | ⬜ 否 | — | 不涉及事件总线 |
| `pallastrade-storefront` | ⬜ 否 | — | 不涉及前台 |

---

## 需求标题

商品批量移除媒体（Bulk Media）—— Admin 商品列表新增破坏性批量动作，走「预览 → 确认 → 执行」。

## 任务类型

新功能（Admin 编排层；**零模型/表/API 变更**）。

## 需求描述

方案 §5.1「Bulk Operations 2.0」列了 6 个动作，只剩 **Media** 未做。现状是商家想清理一批导入错误
的图片时只能逐个商品进编辑页删除。本需求补上这一行：选中商品 → 预览「将清空 N / 将跳过 K」→ 确认 →
清空**商品级与变体级**全部媒体，并清理 `primary_media_id` 指针与变体关联。

## 影响范围

- **Core**：`app/services/pallastrade/products/bulk_media_removal.rb`（新增）
- **Admin**：`products_controller.rb`（+2 动作 +1 私有工厂）、`config/routes.rb`（+2 路由）、
  `config/initializers/pallastrade_admin_tables.rb`（+1 动作注册）
- **i18n**：gem `en.yml` + host `admin_bulk_ops.zh-CN.yml`（各 4 键）
- **DB / API / Storefront / Platform**：**零改动**
- **影响面**：`harness affected --base origin/dev`

## 技术方案（初步）

严格复制既有 5 个 bulk 动作的模式：`BulkMediaRemoval < BulkOperation`，`preview = run(dry_run: true)`、
`call = run(dry_run: false)`，返回 `Result(selected/updated/skipped/warnings)`；
控制器复用 `render_bulk_preview` / `run_bulk_operation` 辅助方法；`form_partial` 用现成的空确认 partial。

两处必须写对的地方：①资源指针 `primary_media_id`（Product + Variant）**没有** `dependent:`，删完要手动置 nil；
②`bulk_collection` 不做店铺作用域，而媒体删除不可逆 ⇒ 本动作额外按 `current_store` 收窄。

## 风险点

| # | 级别 | 风险 | 缓解 | 回滚 |
|---|---|---|---|---|
| R-1 | 高 | 不可逆删除媒体 | 强制预览 + confirm；预览给出将删除的商品数与跳过数；范围限定选中商品；审计留痕 | 移除注册即动作消失；已删文件不可恢复（故强制预览） |
| R-2 | 中 | 悬空 `primary_media_id` | 两侧都置 nil，并由 AC-004 覆盖 | — |
| R-3 | 中 | `bulk_collection` 跨店 | 本动作 `merge(current_store.products)`；**其余动作的同类口子已记录但未改** | — |
| R-4 | 低 | 与既有批量模式漂移 | 严格继承同一基类、复用同一辅助方法与通用视图；既有 `admin-products-bulk-rspec` 回归通过 | — |

## 决策节点

- 用户 2026-09-17 在结构化提问中**明确选定**「批量移除媒体（Bulk Media）」，选项描述已含
  「只做移除 / 不改模型层 / 走 Preview→Confirm / 逐条跳过原因 + 审计」⇒ 范围已确认（PRD approved）。
