# PRD-20260911-promotions-promo-batch6-pr-p9-cleanup

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-11 实施完成；用户拍板 D1=A、D2=A、D3/D4 暂缓） |
| 创建日期 | 2026-09-11 |
| 来源 | `promotion模块架构-任务拆解.md` 批次 6 → Phase 9（PR-P9-1..5）；`harness/reviews/REVIEW-20260908-promotions-module-audit.md` 发现 P3 |
| 分类 | promotions |
| 关联 Skill | pallastrade-promotions、pallastrade-data-model、pallastrade-admin、pallastrade-api-v3、pallastrade-prd |
| 关联 REQ | REQ-20260911-promo-batch6-pr-p9-cleanup.md |
| 需求类型 | 重构（清理与下线，**含不可逆 DB 变更 → 需产品决策**） |

> **本 PRD 的第一交付物是盘点 + 决策清单**（PR-P9-1 / P9-2 / P9-4 涉及产品口径），决策后再进入实施。

---

## 1. 背景

批次 6 是 promotions 收敛计划的最后一批（清理与下线）。与前五批不同，本批**含不可逆变更**（删列/删表/删模型/删 API 字段）与**上游框架版本口径**冲突点，因此必须先盘点事实、列决策项、由用户拍板后再动代码。

---

## 2. 盘点（2026-09-11 实测）

### PR-P9-1 `advertise` / `path` / `PromotionHandler::Page`

| 事实 | 证据 |
|---|---|
| `advertise`（boolean，默认 false）+ 索引存在于 schema | `backend/db/schema.rb:1831,1852`；上游迁移 `pallastrade_four_three`（core + 宿主各一份） |
| `Promotion.advertised` scope | `pallastrade_core/app/models/pallastrade/promotion.rb:89` |
| `advertise` 唯一消费链 | `Product#possible_promotions`（`-> { advertised.active }`，`product.rb:82`）→ `PallasTrade::ProductsHelper#promotion_cache_keys`（`products_helper.rb:65`）——该 helper **全仓无调用方** |
| Store API / Storefront | 检索 `advertise`/`promoted` 无 v3 store 路由、无 storefront 消费（与 REVIEW-20260908 P3 一致） |
| 后台表单 | 仍展示 `advertise`（`PallasTrade::Admin::PromotionsController` 走 `permitted_attributes`，含 `:advertise, :path, :promotion_category_id, ...`，`permitted_attributes.rb:202`） |
| `path`（string） | 仅两处使用：`PromotionHandler::Page`（`page.rb:21` `store.promotions.active.find_by(path: path)`，**全仓无调用方**）与 `PromotionDuplicator`（复制促销时给新记录生成 `path`） |
| Admin API（v3）暴露 | `promotion_category_id` 在 admin serializer 与 permit 列表；**未暴露** `advertise`/`path` |
| i18n / docs | `en.yml`/`en_pallastrade_translations.yml` 有 `advertise`/`path` 标签；`platform/docs/developer/core-concepts/promotions.mdx`、`webhooks-events.mdx` 仍文档化 `advertise`/`promotion_category_id` |

### PR-P9-2 `promotion_category`

| 事实 | 证据 |
|---|---|
| 模型/表 | `PallasTrade::PromotionCategory`（`promotion_category.rb`）；表 `pallastrade_promotion_categories`（`schema.rb:1761`） |
| 关联 | `Promotion belongs_to :promotion_category, optional: true`（`promotion.rb:37`） |
| API | Admin v3 `promotions_controller` permit `:promotion_category_id`（`:41`）；`PromotionSerializer` 输出 `promotion_category_id`（`:20`）→ 契约（`admin.yaml` ×2、admin-sdk 生成类型）已固化 |
| 后台 UI | **无**：无 `promotion_categories` 控制器/视图/路由（检索 0 命中）；仅遗留 locale `new_promotion_category`（`admin/config/locales/en.yml:1097`） |
| 种子/工厂 | `promotion_category_factory` 存在（仅测试） |
| 消费方 | 无业务代码读取分类（除关联与 API 字段本身） |

### PR-P9-3 legacy cart 促销路径（Order-as-cart → 单一 Recalculation 入口）

| 事实 | 证据 |
|---|---|
| `POST /api/v3/store/carts/:cart_id/discount_codes` | **是现行 v3 端点**（非 legacy）：`store/carts/discount_codes_controller.rb`、`store.yaml`、SDK `store-client.ts:514` |
| 「Order-as-cart」内部重算路径 | `PromotionHandler::Cart` / `Coupon`、`Order#discounts`(=`order_promotions`) 别名等，与新 Cart 实体（P5 Commerce Core Consolidation）耦合 |
| 依赖 | 任务拆解标注依赖 **PR-P4-6**、与「新 Cart 实体迁移节奏绑定」→ 本批次**无法独立完成** |

### PR-P9-4 `pallastrade_promotions_stores` + `LegacyMultiStoreSupport`

| 事实 | 证据 |
|---|---|
| 框架版本 | **5.6.0.rc1**（`pallastrade_core/lib/pallastrade/core/version.rb`） |
| 上游口径 | `platform/docs/plans/5.6-6.0-single-store-promotions-payment-methods.md`：join 表 **5.6 保留、6.0 才 drop**；`LegacyMultiStoreSupport` 兼容垫片同样保留到 6.0（`unless defined?(PallasTradeMultiStore)` 自动 include：`product.rb:37`、`payment_method.rb:16`、`promotion.rb:15`） |
| 现状 | `StorePromotion`（`store_promotion.rb`，表 `pallastrade_promotions_stores`）+ `single_store_associations.rake` 的回填/兼容逻辑 |
| 影响面 | 若在 5.6 期间删除，将与上游 6.0 迁移脚本、以及 `pallastrade_multi_store` 扩展（**该 gem 当前不存在**）的兼容层冲突 |

### PR-P9-5 文档/技能同步

- 随各实施项同步：`pallastrade-promotions` Skill（字段/能力表）、`pallastrade-data-model`（模型/表）、`pallastrade-api-v3` + `{admin,store}.yaml`（若动 API 字段）、`scenarios.json`、PRD 索引。
- 若 PR-P9-1/2 涉及 `advertise`/`promotion_category_id` 下线，`platform/docs/developer/core-concepts/promotions.mdx`、`webhooks-events.mdx`、admin-sdk 生成类型也需同步。

---

## 3. 决策清单（需用户拍板）

| # | 决策项 | 选项 A | 选项 B | 选项 C | AI 建议 |
|---|---|---|---|---|---|
| D1 | PR-P9-1（`advertise`/`path`/`PromotionHandler::Page`） | **全下线**：删 `PromotionHandler::Page` + `path` 列 + `advertise` 列/scope/possible_promotions/helper + 表单/i18n/docs 清理（1 个迁移，**不可逆**） | **保守下线**：删无调用方的 `PromotionHandler::Page` + `path`（+ Duplicator 赋值），**保留** `advertise`（上游列/文档仍引用，避免与框架分叉） | 全部保留，仅在 Skill/审计中标注为 v2 残留 | **B（保守下线）**：去掉真正死代码，避免删上游仍在文档化的列；`advertise` 若确认无业务用途可后续单独决策 |
| D2 | PR-P9-2（`promotion_category`） | **补最小 UI**：后台 CRUD（列表/新建/编辑）+ 促销表单选择器 + 权限资源注册（`:promotion_categories`）+ 导航 zh-CN | **下线**：删 API 字段（serializer/permit/契约/admin-sdk 类型）+ 删关联 + 删表/模型（迁移，不可逆）+ docs 清理 | 保留现状，仅标注（当前：API 暴露字段但 UI 无法管理 → 语义悬空） | **A（补最小 UI）**：字段已在契约与 SDK 类型中固化，删它属破坏性变更；补 UI 成本小（复用只读页范式） |
| D3 | PR-P9-3（legacy cart 重算收敛） | **立即做**（需先完成 P5 购物车收敛） | **暂缓**（等 P5，「与新 Cart 实体迁移节奏绑定」） | — | **B（暂缓）**：本批不具备依赖条件 |
| D4 | PR-P9-4（join 表/兼容垫片） | **立即删**（违反上游 5.6→6.0 分阶段，会与 6.0 升级冲突） | **暂缓到 6.0 口径**（与上游计划一致，保留垫片） | — | **B（暂缓）**：当前框架 5.6.0.rc1，上游明确 6.0 才 drop |

### 3.1 用户决策结果（2026-09-11，拍板后实施）

| # | 用户选择 | 实施口径 |
|---|---|---|
| D1 | **A（全下线）** | 删 `PromotionHandler::Page` + `path` 列 + `advertise` 列/scope/`possible_promotions`/`promotion_cache_keys`；表单/i18n/docs 全链清理；新增迁移（不可逆） |
| D2 | **A（补最小 UI）** | 后台 `promotion_categories` CRUD（列表/新建/编辑/删除）+ 促销表单分类选择器 + 导航（en/zh-CN）+ PermissionRegistry `:promotion_categories` + 回归 |
| D3 | **暂缓**（待 P5 购物车收敛） | 本批不动 legacy cart 重算路径 |
| D4 | **暂缓**（等上游 6.0 口径） | `pallastrade_promotions_stores` join 表与 `LegacyMultiStoreSupport` 垫片保留 |

---

## 4. 实施范围（已按 D1=A / D2=A 实施）

1. **P9-1 字段与死代码下线**：
   - 迁移 `backend/db/migrate/20260911000001_remove_advertise_and_path_from_pallastrade_promotions.rb`（删 `advertise` 索引+列、`path` 列）。
   - 删除 `PromotionHandler::Page`；`PromotionDuplicator` 去掉 path 赋值；`Promotion` 去 `advertised` scope + `normalizes :path` + ransack `path`；`Product` 去 `possible_promotions`；`ProductsHelper#cache_key_for_product` 去促销片段；`PromotionHandler::FreeShipping` 去 `path: nil` 条件。
   - `PermittedAttributes` 去 `:path`/`:advertise`；Admin API permit 去 `:path`；Admin `PromotionSerializer` 去 `path` 属性与类型。
   - i18n（`en.yml` ×2 + `en_pallastrade_translations.yml`）与 platform docs（`promotions.mdx`、`webhooks-events.mdx`）同步清理。
2. **P9-2 促销分类最小 UI**：
   - 新增后台 `PromotionCategoriesController` + 视图（index/new/edit/_form）+ 路由 `resources :promotion_categories, except: [:show]` + 表格注册（`name`/`code`，搜索 `name_or_code_cont`）。
   - 导航 Promotions 组新增 `promotion_categories`（position 20，`can?(:manage, PromotionCategory)`），en + zh-CN 双语。
   - 促销表单 `form/_settings.html.erb` 增加分类选择器（`@promotion_categories` 于 `PromotionsController#load_form_data` 注入）；`PromotionCategory` 补 ransack 白名单。
   - PermissionRegistry 注册 `:promotion_categories`（`PromotionCategory`，read/create/update/destroy，`data_fields: []`——表无 store_id）。
3. **P9-5 文档/技能同步**：Skill 更新 + GS-090 + PRD 索引 + 本 PRD 状态。

---

## 5. 业务规则与边界

| # | 规则 | 说明 |
|---|---|---|
| R1 | 删除即不可逆 | 迁移只删列、不建回填；回滚需手工加列（PRD 已在 §3 记录用户拍板） |
| R2 | 不改业务语义 | 删的字段均无业务消费点（盘点证据见 §2）；`match_policy`/`kind`/券码体系不动 |
| R3 | 契约保守 | Admin API 仅删 `path` 输出（从未被后端允许写入）；`promotion_category_id` 保留 |
| R4 | 分类为安装级数据 | `pallastrade_promotion_categories` 无 `store_id` → scope 不走 `current_store`，数据范围声明为空 |
| R5 | 权限单源 | 新后台入口必须注册 capability；`nav:validate` / `permissions:validate` 必须通过 |
| R6 | 表单不可静默清空 | 分类下拉用完整集合（不按 ability 过滤），避免无 category 权限的角色编辑促销时清空已选分类 |
| R7 | 分类删除不阻断 | `Promotion belongs_to :promotion_category, optional: true`，删除分类不删促销（关联置空） |

---

## 6. 验收标准（AC，与测试一一映射）

| AC | 对应 | 判定条件 | 映射测试 |
|---|---|---|---|
| AC-001 | FR-001/D1 | `pallastrade_promotions` 无 `advertise`/`path` 列；`Promotion` 无 `advertised` scope、无 `path=`/`advertise=`；`PermittedAttributes.promotion_attributes` 不含 `:path`/`:advertise` 且保留 `:promotion_category_id` | `backend/spec/models/pallastrade/promotion_legacy_cleanup_spec.rb` |
| AC-002 | FR-001/D1 | `PromotionHandler::Page` 常量不存在；`Product#possible_promotions` 不存在；无 path 也能创建/克隆促销；FreeShipping handler 查询链路可执行 | 同上 + `spec/models/pallastrade/promotion_spec.rb` 回归 |
| AC-003 | FR-002/D2 | 后台分类 CRUD：列表渲染、新建（空名拒绝 422）、更新、删除均生效；`prefixed_id` 路由可用 | `backend/spec/requests/pallastrade/admin/promotion_categories_spec.rb` |
| AC-004 | FR-002/D2 | 促销编辑页渲染分类下拉（含分类名）且保存 `promotion_category_id` 持久化 | 同上 |
| AC-005 | FR-003 | capability 闸门：未授予 `promotion_categories` 的角色被拒；授予后 200；导航项双语齐备（en/zh-CN）且出现在 Promotions 组 | 同上 + `spec/requests/pallastrade/admin/navigation_consistency_spec.rb` |
| AC-006 | FR-004 | 知识同步与校验：`permissions:validate` 0 error、`nav:validate` OK、`generated:check` 无漂移、Skill/GS-090/PRD 索引更新 | 回归命令 + `harness prd verify` / `doc-impact` |

---

## 7. 跨层搜索记录（6 层，2026-09-11 实测）

| 层 | 路径 | 关键词 | 找到 | 结论 |
|---|---|---|---|---|
| App（宿主） | `backend/` | advertise / path / promotion_category / promotions_stores | 宿主无实现（仅 schema/迁移副本、生成类型） | 不涉及 |
| Core | `pallastrade_core/app/` + `lib/` | 同上 | `promotion.rb`（scope/关联/permitted）、`promotion_handler/page.rb`、`promotion_duplicator.rb`、`product.rb#possible_promotions`、`products_helper.rb#promotion_cache_keys`、`store_promotion.rb`、`legacy_multi_store_support.rb`、`single_store_associations.rake`、`promotion_category.rb` | 见 §2 逐项 |
| API | `pallastrade_api/app/` | promotion_category_id / discount_codes | admin `promotions_controller` permit + `PromotionSerializer`；store `carts/discount_codes_controller`（现行端点） | P9-2 涉及契约；P9-3 端点保留 |
| Admin | `pallastrade_admin/app/` | promotion form / categories | 促销表单含 advertise/kind；**无 categories 控制器/视图/路由**；locale `new_promotion_category` | P9-2 需补 UI |
| Storefront | `storefront/src/` | advertise / promoted / possible_promotions | 无消费 | P9-1 下线不影响店面 |
| Platform | `platform/packages` + `platform/docs` | 同上 | admin-sdk 生成类型含 `promotion_category_id`；`docs/developer/core-concepts/promotions.mdx`、`webhooks-events.mdx` 文档化 advertise/promotion_category_id；`plans/5.6-6.0-*.md` 给出 join 表 6.0 清理口径 | 决策 D1/D2/D4 受此约束 |

---

## 8. 风险与约束

- **不可逆变更**：D1-A 删列（`advertise`/`path`）不可逆——回滚需新增迁移重新加列并回填历史值；实施前需备份生产库。D2-A 仅新增后台入口与 capability，未删表。
- **上游一致性**：`advertise`/`path`/`promotion_category_id` 均为上游列/字段；删除会与未来 gem 升级分叉（本项目直接改 gem，需在 §0.1 记录）。
- **契约链**：动 `promotion_category_id` 需同步 `backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/admin.yaml` + `admin-sdk` 生成类型 + `generated:check`。
- **权限**：P9-2 已按 batch5b 的 capability 规范注册 `:promotion_categories`（单模型 + `data_fields: []`），`nav:validate`/`permissions:validate` 均通过。
- **工作树并行会话**：实施前必须 `git status --porcelain` 核对（此前发生过外部回退事故）。

---

## 9. 测试计划

| 场景 | 测试 |
|---|---|
| P9-1（AC-001/002） | `promotion_legacy_cleanup_spec.rb`：删列/删 scope/常量消失/仍可创建克隆/FreeShipping 可执行；`promotion_spec.rb` 回归 |
| P9-2（AC-003/004/005） | `promotion_categories_spec.rb`：CRUD + 表单选择器 + capability 闸门；`navigation_consistency_spec.rb`：Promotions 组子项 + 双语键 |
| P9-5（AC-006） | `prd verify` / `doc-impact` / `check --profile quick` / `nav:validate` / `permissions:validate` / `generated:check` |

---

## 10. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-promotions/SKILL.md`（字段与后台入口表同步）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（促销表列变更）
- [x] `ai/skills/pallastrade-admin/SKILL.md`（Promotions → Categories 入口 + capability）
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`（admin promotion 可写字段去除 `path`）
- [x] `harness/scenarios/scenarios.json`（GS-090）
- [x] `platform/docs/developer/core-concepts/promotions.mdx` + `platform/docs/api-reference/webhooks-events.mdx`
- [x] `docs/prd/README.md` 索引

**知识同步门结论（sync-check，2026-09-11）**：全资产 20 项已逐项评估 —— **updated 6 项**（领域 Skill `pallastrade-promotions`、`pallastrade-data-model`、`pallastrade-api-v3`、`pallastrade-admin`、测试、场景库）+ **reviewed-no-change 14 项**（`{store,admin}.yaml`：未增删端点且 `generated:check` 无漂移；SDK 类型；storefront Skill/组件测试、events Skill、typescript-sdk Skill、platform/根 README、security Skill、AGENTS.md §8、prd Skill、AGENTS.md、copilot-instructions.md）。已 `sync-check --ack`，知识环 20/11 通过。

---

## 11. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-11 | 0.1 | 初稿：PR-P9-1..5 盘点（含证据行号）+ 决策清单（D1..D4）+ 建议范围；等用户拍板后置 approved 并实施 | AI |
| 2026-09-11 | 1.0 | 用户拍板 D1=A / D2=A / D3+D4 暂缓；按此实施 P9-1 字段与死代码下线 + P9-2 分类最小 UI；补 §4/§5/§6/§9/§10 定稿 | AI |
| 2026-09-11 | 1.1 | 收尾：全量套件 1426 examples 通过（修复 batch5b 写死计数断言）、知识同步门 20 项评估 + ack、恢复计划 REC-bfbcee01f781c6、gate finished + task completed；用户显式批准关键风险收尾（不含推送 dev） | AI |
