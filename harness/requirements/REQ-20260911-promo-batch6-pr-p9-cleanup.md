# REQ-20260911-promo-batch6-pr-p9-cleanup

| 项 | 值 |
|---|---|
| 需求 | Promotion 批次 6 —— PR-P9 清理与下线（盘点 + 决策 + 实施） |
| 类型 | 重构（清理/下线；含不可逆 DB 变更 → 需产品决策） |
| 关联 PRD | `docs/prd/promotions/PRD-20260911-promotions-promo-batch6-pr-p9-cleanup.md`（done，2026-09-11） |
| 关联任务 | TASK-20260911030259-4a126a1b |
| Gate | GATE-2026-09-11T03-03-10 |
| 分支 | dev（基线 efb2bccb） |

---

## Step 0 — 跨层搜索（6 层，2026-09-11 实测）

| 层 | 搜索路径 | 关键词 | 结果 | 是否已满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app/`、`backend/config/` | advertise / path / promotion_category / promotions_stores | 无宿主实现；仅 schema 副本与生成类型 | 不涉及 |
| Core | `pallastrade_core/app/` + `lib/` | 同上 | `promotion.rb`（`advertised` scope / `belongs_to :promotion_category` / `LegacyMultiStoreSupport`）、`promotion_handler/page.rb`（**无调用方**）、`promotion_handler/promotion_duplicator.rb`（写 `path`）、`product.rb#possible_promotions`、`products_helper.rb#promotion_cache_keys`（**无调用方**）、`promotion_category.rb`、`store_promotion.rb`、`legacy_multi_store_support.rb`、`single_store_associations.rake`、`permitted_attributes.rb:202` | ⚠️ 需按决策清理（含不可逆项） |
| API | `pallastrade_api/app/` | promotion_category_id / discount_codes | admin `promotions_controller` permit `:promotion_category_id`、`PromotionSerializer` 输出该字段；store `carts/discount_codes_controller`（**现行** v3 端点） | ⚠️ P9-2 涉及契约；P9-3 端点保留 |
| Admin | `pallastrade_admin/app/` | promotion form / categories | 促销表单含 `advertise`；**无 categories 控制器/视图/路由**；遗留 locale `new_promotion_category` | ⚠️ P9-2 需补 UI（若选 A） |
| Storefront | `storefront/src/` | advertise / promoted / possible_promotions | 无消费 | P9-1 下线不影响店面 |
| Platform | `platform/packages/`、`platform/docs/` | 同上 | admin-sdk 生成类型含 `promotion_category_id`；`core-concepts/promotions.mdx`、`webhooks-events.mdx` 文档化 `advertise`/`promotion_category_id`；`plans/5.6-6.0-*.md` 明确 join 表 **6.0 才 drop**、垫片保留到 6.0 | ⚠️ 约束 D1/D2/D4 |

**关键结论**：`PromotionHandler::Page` 与 `ProductsHelper#promotion_cache_keys` 均为**零调用方**的死代码；`path` 仅被死代码与 Duplicator 使用；`advertise` 保留在上游文档/列中；`promotion_category_id` 已固化进契约与 SDK 类型（删除属破坏性变更）；join 表与兼容垫片按上游口径应在 6.0 清理（当前框架 5.6.0.rc1）。

---

## Step 1 — Skill 咨询证据

| Skill | 读取 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ | 决策树：能改已有 gem 文件就别新建；清理类改动优先"删死代码 + 保留上游列"，避免与框架升级分叉 |
| `pallastrade-promotions` | ✅ | 促销字段/能力表（含 `advertise`、`path`）与 Definition Registry/权限单源的最新约定（batch5a/5b 已收敛） |
| `pallastrade-data-model` | ✅ | 删列/删表必须新增迁移（不改历史迁移、不手改 schema.rb）；`pallastrade_promotions_stores` 属兼容 join 表 |
| `pallastrade-admin` | ✅ | 新增后台资源四件套（控制器/视图/路由/导航 + 权限注册 + 表格注册 + 双语 nav label），补 `promotion_categories` UI 可复用该范式 |
| `pallastrade-api-v3` | ✅ | 动 API 字段需同步 `{admin,store}.yaml`（backend + platform）与 SDK 生成类型，`generated:check` 门禁 |
| `pallastrade-prd` | ✅ | R8：一句话需求 → PRD（含决策清单）→ 用户确认 → gate → 实施 → `prd verify` |

---

## Step 2 — 决策与实施范围（待用户拍板）

见 PRD §3 决策清单（D1..D4）。AI 建议：**D1=B（保守下线 path + 死代码，保留 advertise）**、**D2=A（补 promotion_category 最小 UI）**、**D3=B（legacy cart 收敛暂缓，依赖 P5）**、**D4=B（join 表/垫片暂缓到 6.0 口径）**。

## 用户确认记录

| 时间 | 用户输入 | 授权范围 |
|---|---|---|
| 2026-09-11 | 「继续」（承接 AI 声明的"先出盘点 + 决策清单 PRD"） | 授权本批次盘点与 PRD；**实施范围待决策问答确认** |
| 2026-09-11 | 决策问答：**D1=A（全下线 advertise/path）、D2=A（补 promotion_category 最小 UI）、D3/D4 暂缓（记录理由）** | 授权按 D1=A / D2=A 实施 P9-1 + P9-2；D3/D4 本批不动 |

---

## Step 3 — 实施记录（2026-09-11）

### 3.1 变更文件（P9-1 字段/死代码下线）

| 文件 | 动作 |
|---|---|
| `backend/db/migrate/20260911000001_remove_advertise_and_path_from_pallastrade_promotions.rb` | 新增（删索引 + 删 `advertise`/`path` 列） |
| `pallastrade_core/.../promotion_handler/page.rb` | 删除（零调用方） |
| `pallastrade_core/.../promotion_handler/promotion_duplicator.rb` | 去 path 赋值 |
| `pallastrade_core/.../promotion_handler/free_shipping.rb` | 去 `path: nil` 条件 |
| `pallastrade_core/.../promotion.rb` | 去 `normalizes :path`、`advertised` scope、ransack `path` |
| `pallastrade_core/.../product.rb` | 去 `possible_promotions` |
| `pallastrade_core/.../products_helper.rb` | `cache_key_for_product` 去促销片段 |
| `pallastrade_core/lib/.../permitted_attributes.rb` | 去 `:path`/`:advertise`（保留 `:promotion_category_id`） |
| `pallastrade_api/.../admin/promotions_controller.rb` | permit 去 `:path` |
| `pallastrade_api/.../admin/promotion_serializer.rb` | 去 `path` 属性/类型 |
| `pallastrade_core/config/locales/{en,en_pallastrade_translations}.yml` | 清理 `advertise`/`path` 词条 |
| `platform/docs/.../promotions.mdx`、`webhooks-events.mdx` | 文档同步 |

### 3.2 变更文件（P9-2 分类最小 UI + 权限）

| 文件 | 动作 |
|---|---|
| `pallastrade_admin/app/controllers/.../promotion_categories_controller.rb` | 新增 CRUD 控制器 |
| `pallastrade_admin/app/views/.../promotion_categories/{index,_form,new,edit}.html.erb` | 新增视图 |
| `pallastrade_admin/config/routes.rb` | `resources :promotion_categories, except: [:show]` |
| `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb` | Promotions → Categories 子项（position 20） |
| `pallastrade_admin/config/initializers/pallastrade_admin_tables.rb` | 表格注册 `:promotion_categories` |
| `pallastrade_admin/config/locales/en.yml` + `backend/config/locales/admin_nav.zh-CN.yml` | 双语文案 |
| `pallastrade_admin/app/views/.../promotions/form/_settings.html.erb` + `promotions_controller.rb` | 分类选择器 + `@promotion_categories` |
| `pallastrade_core/.../promotion_category.rb` | ransack 白名单 `name/code` |
| `backend/config/initializers/pallastrade_permission_registry.rb` | 注册 `:promotion_categories` |
| `backend/spec/...`（3 个文件） | 新增/更新规格（AC-001..006） |

### 3.3 验证证据

| 项 | 结果 |
|---|---|
| 新增规格 | `promotion_legacy_cleanup_spec.rb`（11 例）+ `promotion_categories_spec.rb`（10 例）全绿 |
| 回归集合 | 206 examples / 0 failures / 6 pending（促销 + 权限 + 导航 + API + services + jobs + rake） |
| 全量套件 | `backend-rspec` 验证器 **1426 examples / 0 failures** / 6 pending（首次运行 1 例失败：batch5b 写死 `resources=14` → 已改为按注册表动态取数，提交 `819a0c7c`） |
| 迁移 | 容器 `db:migrate` 成功；`schema.rb` 同步 |
| 注册表 | `permissions:validate` resources=15 models=14 errors=0 warnings=3 |
| 导航 | `nav:validate` OK（0 warning），`check --profile quick` 无反模式/AP-009 |
| 契约 | `generated:check` 无漂移；`doc-impact` 3 synced / 0 missing；`prd verify` 全 AC 覆盖 |
| 规范 | 新增文件 rubocop 0 offense；改动行沿用文件既有模式 |
| 知识同步门 | `sync-check` 全资产 20 项评估（6 updated / 14 reviewed-no-change）→ `--ack`；知识环 20/11 通过 |
| 恢复计划 | `REC-bfbcee01f781c6`（manual-only：备份 → 停损 → 回滚 → 验证） |
| 证据环 | test（EVD-…044619）+ review（EVD-…044806）+ knowledge（EVD-…051345）+ approval（EVD-…051330，用户显式批准，不含推送 dev） |
| Gate / Task | `GATE-2026-09-11T03-03-10` finished；`TASK-20260911030259-4a126a1b` completed with verified evidence |
| 提交 | `93f9f3b6`（主体）+ `819a0c7c`（修复断言/文档） |

