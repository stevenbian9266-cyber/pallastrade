# PRD-20260814-catalog-seo-深度增强-商品-分类级元数据-json-ld-301-重定向

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-08-15 已验证：301 端到端生效） |
| 创建日期 | 2026-08-14 |
| 来源 | 阶段一：SEO 深度增强（对标 Shopify）——301 重定向管理 + 分页 canonical 补强 |
| 分类 | catalog（自动判定） |
| 关联 Skill | pallastrade-api-v3、pallastrade-admin、pallastrade-storefront |
| 关联 REQ | REQ-20260815-seo-301-redirects.md（实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 优化迭代 |

> 📌 **范围修正（2026-08-15 盘点）**：RESEARCH 文档所列 meta/JSON-LD/canonical/hreflang/OG 等**均已实现**（后端 Product/Taxon/Category meta 字段 + API serializer + storefront `lib/metadata/*` + `lib/seo.ts` JSON-LD + sitemap/robots）。本次**聚焦真实缺口**：① **301 重定向管理**（Redirect 模型 + API + Admin + storefront 中间件）。
>
> 📌 **二次修正（2026-08-15 实施期）**：列表页（products / c/...）使用**无限滚动**，分页**不在 URL**（`listing-search-params.ts` 明示）→ **无多页 URL，分页 canonical/prev-next 不适用**，已从本 PRD 移除。

## 1. 背景与目标

- **一句话需求原文**：实施 RESEARCH-20260814 阶段一（P0-1 SEO 增强）
- **背景**：RESEARCH 文档对标 Shopify 识别 SEO 差距；2026-08-15 深度盘点发现 meta/JSON-LD/canonical/hreflang/OG 已全部实现（后端 Product/Taxon/Category meta + storefront `lib/metadata/*` + `lib/seo.ts`）。真正的差距是**301 重定向管理**（商品下架/改 URL 后 SEO 权重丢失）。列表页为无限滚动（无分页 URL），分页 canonical 不适用。
- **目标**：① 新增 `Redirect` 模型（from_path→to_path，301），Admin CRUD + Store API + storefront 中间件落地。
- **成功指标**：商品改 URL 后旧链接 301 到新链接。

## 2. 用户故事 / 场景

- 作为运营，我希望商品下架/改名后旧 URL 301 跳转到新 URL，以便保留 SEO 权重
- 作为运营，我希望在后台配置 301 重定向（来源路径 → 目标路径），以便无需改代码
- 作为搜索爬虫，我希望访问旧路径得到 301 且目标页 canonical 正确
- 边界：from_path 唯一、按 store 作用域、循环重定向防护（防 A→B→A）、来源未命中时正常 404

## 3. 功能需求（FR）

- FR-001：Core 新增 `PallasTrade::Redirect` 模型（`store`、`from_path`、`to_path`、`status_code` 默认 301、`active`、唯一约束 store+from_path、规范化路径）
- FR-002：Store API：`GET /api/v3/store/redirects/resolve?path=...`（或 storefront 通过现有 config 拉取全量）；Admin API：`/api/v3/admin/redirects` 全量 CRUD
- FR-003：Admin UI：Rails Admin Gem 增加 Redirects 管理（index/new/edit/delete + active 开关）
- FR-004：Storefront：中间件或 layout 级路径匹配 —— 命中 from_path → 301 跳转 to_path；未命中正常渲染
- FR-005：降级：API 不可达/超时 → 正常渲染（Turnstile 降级模式）；循环重定向防护（A→A 跳过）

## 4. 非功能需求（NFR）

- 安全：redirect 目标必须站内路径（防开放重定向）；按 store 作用域（`current_store`）
- 性能：redirects 表小，storefront 启动/缓存拉取全量（首屏不阻塞）
- 兼容：未命中旧行为不变（404）

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：Redirect 模型存在；store+from_path 唯一约束；路径规范化（去尾部斜杠）
- AC-002 ← FR-002：Store resolve 端点对命中返回目标；Admin CRUD 可用
- AC-003 ← FR-003：Admin Redirects 页可增删改查 + 启用/停用
- AC-004 ← FR-004：storefront 访问 from_path 返回 301 → to_path；未命中 404
- AC-005 ← FR-005：API 不可达时正常渲染；A→A 不循环

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | redirect、seo、meta | 无 | 不涉及 |
| Core | `pallastrade_core/app/` | meta_title、og_image、Redirect | `product.rb`(TRANSLATABLE meta)、`taxon.rb`(meta 验证)、`store.rb` | meta 已有；**Redirect 需新建** |
| API | `pallastrade_api/app/` | meta_title、serializer | `product_serializer.rb`、`category_serializer.rb`、`media_serializer.rb`(og_image_url) | meta 已暴露；**redirects 端点需新建** |
| Admin | `pallastrade_admin/app/` | 控制器、navigation | api_keys/webhook 等资源控制器模式 | **redirects 管理需新建** |
| Storefront | `storefront/src/` | generateMetadata、JsonLd、seo | `lib/seo.ts`、`lib/metadata/*`、`components/seo/JsonLd.tsx` | 元数据已完整；**301 中间件 + 分页 canonical 需补** |
| Platform | `platform/packages/` | meta、redirect | SDK 已含 meta 字段 | **redirects SDK 类型需补** |

**结论**：meta/JSON-LD/canonical/hreflang/OG 已实现；需新建 Redirect 模型/API/Admin/中间件 + 列表分页 canonical。

## 7. 技术影响

- 涉及：core（模型+迁移）、api（store/admin 控制器+序列化器）、admin（导航+视图）、storefront（中间件+metadata）、SDK（类型）
- 数据库：新增 `pallastrade_redirects` 表
- 影响面：API 文档需同步（`backend/public/api-docs/admin.yaml` + `store.yaml`）、SDK 类型、skill 文档

## 8. 测试计划

- 新增：`spec/models/pallastrade/redirect_spec.rb`、`spec/requests/api/v3/admin/redirects_spec.rb`、`spec/requests/api/v3/store/redirects_spec.rb`
- 新增：storefront 中间件单测 + metadata 分页测试
- 更新：`pallastrade-api-v3/SKILL.md`、`pallastrade-admin/SKILL.md`、`pallastrade-storefront/SKILL.md`
- AC 映射：AC-001→redirect_spec、AC-002→requests spec、AC-003→admin 请求 spec、AC-004→storefront 测试、AC-005→metadata 测试

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`
- [x] Skill 文档：api-v3 / admin / storefront
- [x] README / 规范：按 `sync-check` 矩阵
- [x] 场景库：scenarios.json（如需）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-15 | 0.1 | 初稿（基于 RESEARCH 阶段一 + 真实盘点范围修正） | AI |
| 2026-08-15 | 0.2 | 用户确认聚焦真实缺口（301 重定向 + 分页 canonical） | AI |
