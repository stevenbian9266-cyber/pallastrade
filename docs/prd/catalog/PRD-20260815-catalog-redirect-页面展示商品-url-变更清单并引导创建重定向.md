# PRD-20260815-catalog-redirect-页面展示商品-url-变更清单并引导创建重定向

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-08-15 已实施并部署验证） |
| 创建日期 | 2026-08-15 |
| 来源 | 优化：redirect 页面展示商品 URL 变更清单并引导创建重定向（用户大白话描述） |
| 分类 | catalog（自动判定） |
| 关联 Skill | pallastrade-admin、pallastrade-catalog、pallastrade-api-v3 |
| 关联 REQ | REQ-20260815-redirects-url-change-list.md（实施时回填） |
| 关联 PRD | 能力关联：PRD-20260814-catalog-seo-深度增强-...（301 重定向本体） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文（用户大白话）**：redirect 功能不错，但客户可能不知道有商品的 URL 发生了变更需要做重定向。能否在 redirect 页面显示"商品 URL 有变更的商品清单"，商品 URL 变更后在 redirect 页面显示，用户针对该商品做重定向。
- **背景**：301 重定向需要用户**主动**创建（from_path → to_path）。但商品改名/改 slug 后，用户往往**不知道哪些商品 URL 变了**，旧链接继续 404、SEO 权重流失。需要一个"URL 变更雷达"：自动识别 slug 变更过的商品，在 redirects 管理页展示，引导用户一键创建重定向。
- **关键有利条件**：商品已启用 friendly_id `:history`（`Product::Slugs`：`friendly_id :slug_candidates, use: [:history, :slugged, :scoped, :mobility]`），**旧 slug 已自动记录在 `friendly_id_slugs` 表**（含 sluggable_type/sluggable_id/slug/locale/deleted_at）——**无需新增表/迁移**，直接查询即可得到"历史 URL"。
- **目标**：redirects 页面展示"URL 已变更且未创建重定向"的商品清单，每行可一键预填创建重定向。
- **成功指标**：商品改名后，redirects 页面自动出现该商品（旧 URL→新 URL）；点击一键预填即可完成重定向创建；已创建重定向的商品标记为"已处理"并可从清单消失。

## 2. 用户故事 / 场景

- 作为店主/运营，我希望在 Redirects 页面看到"哪些商品 URL 变过、旧地址是什么、新地址是什么"，以便决定是否补重定向。
- 作为店主/运营，我希望点一下"创建重定向"就自动填好 旧→新，不用手抄 URL。
- 场景：
  - 正常流：商品 A 改名 slug 从 `old-a` → `new-a` → Redirects 页出现「A /products/old-a → /products/new-a [待处理]」→ 一键创建 301 → 变为「已处理」并从待处理清单消失。
  - 已处理：已创建过 from_path=`/products/old-a` 的 redirect → 该行标记已处理（不重复提示）。
  - 边界：商品被删除（slug 变 `deleted-xxx-uuid`）→ 不提示（目标已不存在）；多语言 slug（每 locale 一个 slug）→ 按 locale 展示历史。
  - 空态：无 URL 变更 → 清单区域不显示或显示"暂无 URL 变更的商品"。

## 3. 功能需求（FR）

- FR-001：Admin 侧提供"URL 变更商品清单"查询——基于 `friendly_id_slugs`（sluggable_type=`PallasTrade::Product`、deleted_at 为空、sluggable_id ∈ current_store.products），**排除**：与当前 slug 相同的记录（最新 slug）、`deleted-` 前缀（软删 punch）、已存在 redirect（from_path=`/products/{旧slug}`）的商品；输出商品名/旧 slug/当前 slug/locale。
- FR-002：`/admin/redirects` 页面（intro 文案下方）展示该清单表格：商品名、旧 URL、新 URL、状态（待处理/已处理）、操作。
- FR-003：每行"创建重定向"操作 → 跳转 `/admin/redirects/new` 并**预填** `from_path=/products/{旧slug}`、`to_path=/products/{新slug}`（bare 路径，任何 country/locale 均命中）。
- FR-004：无变更时显示空态文案；已处理的商品标"已处理"（不重复提示）。
- FR-005：文案复用 `PallasTrade.t` locale（`admin.redirects.url_changes_*`），沿用现有 `alert-info`/表格样式。

## 4. 非功能需求（NFR）

- **零迁移**：复用 friendly_id_slugs，不新增表/列（唯一新增可能：无）。
- 查询性能：按 store 的 product_id 集合批量 IN 查询 friendly_id_slugs；商品量 < 数千时无需索引优化（friendly_id_slugs 已有 sluggable_type+id 索引）。
- 不破坏现有 redirects CRUD/API；不引入新依赖。
- 多语言：slugs 按 locale 记录，清单按商品合并展示（每 locale 一行或取默认 locale）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：改造商品 slug 后，`friendly_id_slugs` 含旧 slug；Admin 查询返回该商品的"旧 slug + 当前 slug"。
- AC-002 ← FR-002：GET `/admin/redirects` 页面包含"URL 变更商品"表格（含商品名/旧URL/新URL）。
- AC-003 ← FR-003：点击"创建重定向"跳转 new 页且 from_path/to_path 已预填 `/products/{旧slug}` / `/products/{新slug}`。
- AC-004 ← FR-004：创建对应 redirect 后清单中该商品显示"已处理"（或不再提示）；无变更时显示空态。
- AC-005 ← FR-005：文案走 locale，无 translation missing。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | friendly_id/slug/url变更 | 无 | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/models/pallastrade/product/` | slug/history | `slugs.rb`（friendly_id `:history`）；`friendly_id_slugs` 迁移；`history_decorator.rb` | ✅ 数据源已存在（复用） |
| API | `pallastrade_gems/pallastrade_api/app/` | redirect | `redirects_controller.rb`（admin CRUD + store resolve） | 部分（可加"url_changes"端点） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | redirects/table | `redirects/index.html.erb`、`redirects_controller.rb`（ResourceController+SettingsConcern） | ✅ 在此层实现清单展示 |
| Storefront | `storefront/src/` | products/url | `lib/metadata/product.ts`、`lib/utils/path.ts`（`/products/{slug}` 约定） | 否（仅确认 URL 格式） |
| Platform | `platform/packages/` | redirect | 仅文档 | 否 |

**结论**：无重复实现；数据源（friendly_id_slugs）与展示层（redirects admin）均已存在，本次仅补"查询 + 展示 + 预填引导"，无新模型/迁移。

## 7. 技术影响

- 涉及文件（预估）：
  - `pallastrade_gems/pallastrade_core/app/models/pallastrade/product.rb`（可选：加 `url_changes` 查询辅助；或放 service）
  - `pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/redirects_controller.rb`（+ `url_changes` action 或复用 index）
  - `.../redirects/index.html.erb`（+ 清单表格 partial）
  - `pallastrade_gems/pallastrade_api/app/...`（可选：Admin API `GET /api/v3/admin/redirects/url_changes`）
  - `en.yml`（+ `admin.redirects.url_changes_*` 文案）
  - `new.html.erb`/`_form.html.erb`（支持 query 预填 from/to）
  - spec：admin UI + core 查询
- 无 DB 迁移、无 storefront/前端改动（预填用 query string 即可）。

## 8. 测试计划

- Core：`friendly_id_slugs` 查询——改名后旧 slug 可查、当前 slug 被排除、deleted- 被排除、已有 redirect 被排除。
- Admin UI request spec：GET `/admin/redirects` 含清单表头/商品名/旧URL/新URL；预填链接带 from/to query。
- 本地 `docker compose exec web env DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec ...` 全绿。

## 9. 文档同步清单

- `ai/skills/pallastrade-admin/SKILL.md`：记录 redirects 页 URL 变更清单约定（基于 friendly_id_slugs）
- `ai/skills/pallastrade-catalog/SKILL.md`：商品 slug/friendly_id history 说明（如新增查询辅助）
- `backend/public/api-docs/admin.yaml`（若新增 url_changes 端点）
- `harness/scenarios/scenarios.json`：GS-028 补充"URL 变更清单引导创建重定向"场景

## 10. 变更记录

- 2026-08-15：创建 PRD（reviewing），待用户确认
