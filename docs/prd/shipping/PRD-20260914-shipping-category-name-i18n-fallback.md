# PRD-20260914-shipping-category-name-i18n-fallback

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | bug：shipping categories 翻译异常：`Translation missing: en.PallasTrade.seed.shipping.categories.default`（dev 后台分类列表） |
| 分类 | shipping |
| 关联 Skill | pallastrade-data-model / pallastrade-admin |
| 关联 REQ | REQ-20260914-shipping-category-name-i18n-fallback.md |
| 关联 PRD | N/A（查重未命中） |
| 需求类型 | Bug 修复（数据修复 + 源头防复发） |

> 用户原文：`bug：shipping categories 翻译异常：[Translation missing: en.PallasTrade.seed.shipping.categories.default](…/shipping_categories/scat_UkLWZg9DAJ/edit)[…digital](…/scat_gbHJdmfrXB/edit)`

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **现象**：dev 后台配送分类列表显示 `Translation missing: en.PallasTrade.seed.shipping.categories.default` / `…digital`（用户报告，附分类编辑页链接）。
- **根因（数据层，已逐项验证）**：这两个分类的 `pallastrade_shipping_categories.name` **落库的就是 missing 文案本身**（非显示层问题）。它来自历史 seed：`ShippingCategory` 名称由 `I18n.t('pallastrade.seed.shipping.categories.*')` 输出驱动，当时词条未解析成功，Rails 把 `translation missing: …` 字符串当返回值写进了 `name`。
- **连带影响**：后续 seed 又创建了字面名称的 `Digital`(id3)/`Default`(id4) → **重名分类并存**；商品（37 个）全部指向 id4，而配送方式 `Free` 当时只绑定了遗留 id1 → 结算时报 `cart_cannot_complete`（配送区域/分类不匹配）。
- **目标**：① 修复 dev 遗留脏数据（合并/删除）；② 从源头消除该类 bug —— 分类名是**数据**，不再由 I18n 输出驱动，并提供幂等数据修复入口（重跑 seed / rake 即可自愈）。
- **成功指标**：`SELECT count(*) FROM pallastrade_shipping_categories WHERE LOWER(name) LIKE 'translation missing:%'` = **0**；后台分类列表仅剩 `Default` / `Digital`；商品与配送方式关联完整且结算下单仍通过。

## 2. 用户故事 / 场景

- 作为**运营/开发者**，我希望后台分类名称直接可读，而不是翻译缺失文案。
- 作为**后续环境维护者**，我希望重跑 seed 或执行一个 rake 任务就能修复历史脏数据且幂等，而不用手改数据库。
- 场景：① 已污染环境（dev）执行修复 → 关联迁移、遗留行删除；② 新环境 seed 不再产生脏名称；③ 对干净环境重复执行 → 空操作；④ 新商品在无翻译环境下建 → 分类名为字面 `Default`。

## 3. 功能需求（FR）

- **FR-001**（Core · 模型）：`PallasTrade::ShippingCategory` 新增 `DEFAULT_NAME = 'Default'`、`default_category`、`legacy_translation_name?` 与 **幂等** `repair_legacy_names!`（按 `.digital` / 其他后缀判定规范名；迁移 `products.shipping_category_id` 与 `shipping_method_categories` 关联；删除遗留行；返回 `[legacy_id, canonical_id]` 列表）。
- **FR-002**（Core · seed）：`Seeds::ShippingCategories#call` 改用模型常量命名，并在创建前调用 `repair_legacy_names!`（重跑 seed 自愈）。
- **FR-003**（Core · 商品钩子）：`Product#ensure_default_shipping_category` 改用 `default_category || create!(DEFAULT_NAME)`，不再依赖 `I18n.t`。
- **FR-004**（运维入口）：新增 rake `pallastrade:shipping_categories:repair_legacy_names`（幂等，输出修复统计）供各环境执行数据修复。
- **FR-005**（dev 数据修复）：对 dev 执行修复（解除 `Free` 对遗留分类的关联，合并引用并删除 id 1/2 遗留行）。
- **FR-006**（范围外声明）：不改后台展示层（数据干净后即正常）；不删 `en.yml` 中 `pallastrade.seed.shipping.categories.*` 词条（仍可作展示文案）。

## 4. 非功能需求（NFR）

- **幂等安全**：`repair_legacy_names!` 可在任何环境反复执行（先进关联引用、后删遗留行；干净环境空操作）。
- **数据一致**：修复过程先迁移引用再删除，避免出现悬空 `shipping_category_id`。
- **兼容**：不改表结构（无迁移）；不改 API/序列化输出（分类名从脏变干净属预期改善）。
- **可观测**：rake 任务输出修复行数与映射，便于审计。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-003：无翻译环境下 `Product#ensure_default_shipping_category` 写入字面 `Default`（spec：`shipping_category_spec.rb`）。
- **AC-002** ← FR-001：遗留行合并到规范分类，商品与配送方式引用随之迁移，遗留行删除（spec）。
- **AC-003** ← FR-001：数据已规范时 `repair_legacy_names!` 返回 `[]`（幂等，spec）。
- **AC-004** ← FR-001：`legacy_translation_name?` 能识别 missing 文案、不误判正常名称（spec）。
- **AC-005** ← FR-004/005：dev 执行修复后 `pallastrade_shipping_categories` 中 missing 名称行数 = 0（DB 前后对比）。
- **AC-006** ← FR-002：dev 重跑 `PallasTrade::Seeds::ShippingCategories` 不产生新重复分类（DB 验证）。
- **AC-007** ← FR-005：dev 后台分类列表仅剩 `Default`/`Digital`；`Free` 分类关联 = `[Default]`（后台/DB 证据）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | shipping_category / translation missing | 无宿主层实现 | — |
| Core | `pallastrade_gems/pallastrade_core/app/` | shipping_categories / seeds | `models/pallastrade/shipping_category.rb`（仅有 `DIGITAL_NAME`/`self.digital`，无 Default 常量与修复入口）；`services/pallastrade/seeds/shipping_categories.rb` L7-8（**`I18n.t` 驱动名称**）；`models/pallastrade/product.rb` L959（同 pattern）；`config/locales/en.yml` L1433-1435（词条存在） | **本次改动点** |
| API | `pallastrade_gems/pallastrade_api/app/` | shipping_category | 无分类写入端点（仅序列化引用） | 否 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | shipping_categories | 控制器与 `_form.html.erb` 直接渲染 `name` 原值 → 数据脏则显示脏（无需改代码） | 否 |
| Storefront | `storefront/src/` | shipping category | 无消费点 | — |
| Platform | `platform/packages/` | — | 无 | — |

**结论**：缺陷单点在 Core（模型命名 + seed + 商品钩子），加上 dev 数据修复；Admin/API/Storefront 无需改动；**无 DB 迁移**（仅数据行修复）。

## 7. 技术影响

- **修改**：`pallastrade_core/app/models/pallastrade/shipping_category.rb`（常量 + `default_category` + `legacy_translation_name?` + `repair_legacy_names!`）、`.../services/pallastrade/seeds/shipping_categories.rb`（常量命名 + 先修复）、`.../models/pallastrade/product.rb`（默认分类钩子去 i18n）
- **新增**：`pallastrade_core/lib/tasks/shipping_categories.rake`、`backend/spec/models/pallastrade/shipping_category_spec.rb`
- **数据**：dev 执行 `pallastrade:shipping_categories:repair_legacy_names`（幂等）；商品/配送方式关联迁移后删除遗留分类行
- **数据库结构 / 接口 / SDK**：无变更

## 8. 测试计划

- **新增**：`backend/spec/models/pallastrade/shipping_category_spec.rb`（4 例：AC-001..004）
- **dev 验证（AC-005..007）**：
  1. 修复前快照：`SELECT id, left(name, 60) FROM pallastrade_shipping_categories ORDER BY id`（存在 2 行 missing）
  2. 执行：`bin/rails pallastrade:shipping_categories:repair_legacy_names`
  3. 修复后：missing 行 = 0；`Free` 关联 = `[Default]`；商品仍全部指向规范分类
  4. 重跑 `PallasTrade::Seeds::ShippingCategories` → 不新增行
  5. 回归：dev 真实下单（cart → PATCH billing_mode → submit）仍通过
- **AC 映射**：AC-001..004 → 新增 spec；AC-005..007 → dev DB 前后对比 + 后台列表 + 下单回归

## 9. 文档同步清单（知识同步门）

| 知识资产 | 结论 |
|---|---|
| `doc-impact --base origin/dev` | ✅ no knowledge doc updates required（8 文件未命中同步规则） |
| 场景库 / 反模式库（`sync-check`） | ✅ 已评估无需更新（未新增机制/范式；修复后行为与既有约定一致） |
| `pallastrade-prd` Skill / `AGENTS.md` / `copilot-instructions.md` | ✅ 已评估无需更新（流程与规范无变化） |
| 本 PRD 状态 + `docs/prd/README.md` 索引 | ✅ 已更新（`done` + 索引行） |
| `harness sync-check --ack` | ✅ 已确认（知识环 4/4） |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 初稿→实施：模型修复方法 + seed/商品钩子去 i18n + rake 任务 + spec（4 例通过）；dev 数据修复待 rake 部署后执行 | AI |
| 2026-09-14 | 1.1 | dev 数据修复执行完成：遗留分类 1→`Default`、2→`Digital` 合并，`Free` 关联归一；修复后 missing 行 = 0、商品 37/37 指向 `Default`、下单回归通过（`or_86uR0I7fEb`，账单地址 = 配送地址）；备份 `/tmp/scat-backup-20260914.json` | AI |
