# 需求文档：商城前台 SEO 优化

> 日期：2026-07-27 | 任务类型：新功能 / 功能优化 | Gate: GATE-2026-07-27T15-02-21

---

## Step 0：跨层搜索（6 层已完成）

| 层 | 搜索路径 | 关键词 | 发现 | 满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | seo, meta_title, sitemap | 仅有 admin CSS（seo-form 样式） | 否 — 无后端 SEO 逻辑 |
| Core | `pallastrade_core/app/` | meta_title, sitemap, robots | Store 模型有 `meta_description`/`meta_keywords`/`seo_title` 的 translatable 字段；Product 有 `meta_title`/`meta_description`/`meta_keywords` | 部分 — 数据字段已有，但未暴露 SEO 端点 |
| API | `pallastrade_api/app/` | seo, meta | 无 SEO 相关端点 | 否 |
| Admin | `pallastrade_admin/app/` | seo, meta | Admin 有 SEO form partial（`shared/seo`）用于产品编辑 | 部分 — 已有 SEO 录入 UI |
| **Storefront** | `storefront/src/` | metadata, seo, jsonLd, sitemap | **核心 SEO 层** — 详见下方 | ⚠️ 基础设施强但有 gap |
| Platform | `platform/packages/` | seo, metadata | SDK 类型包含 `meta_title`/`meta_description`；Dashboard 有 SEOCard 组件 | 部分 |

### Storefront 现有 SEO 能力分析

| 能力 | 文件 | 状态 |
|---|---|---|
| Next.js `generateMetadata()` | 每个 page.tsx | ✅ 完整 |
| OpenGraph 标签 | `lib/metadata/*.ts` | ✅ 有 og:title/image/description/type/locale |
| Twitter Card | `lib/metadata/product.ts` | ✅ |
| Canonical URL | `lib/seo.ts` → `buildCanonicalUrl()` | ✅ |
| Product JSON-LD | `lib/seo.ts` → `buildProductJsonLd()` | ✅ |
| Breadcrumb JSON-LD | `lib/seo.ts` → `buildBreadcrumbJsonLd()` | ✅ |
| JsonLd 组件 | `components/seo/JsonLd.tsx` | ✅ |
| robots.txt | `app/robots.ts` | ✅ |
| 动态 Sitemap | `app/sitemap.ts` | ✅ |
| Store SEO 配置（env vars） | `lib/store.ts` | ✅ |
| **hreflang alternate 标签** | — | ❌ **缺失** |
| **Category JSON-LD (ItemList)** | — | ❌ **缺失** |
| **Website/Organization JSON-LD** | — | ❌ **缺失** |
| **Sitemap `<lastmod>`** for categories | `app/sitemap.ts` | ❌ 未传 `updated_at` |
| **og:locale:alternate** | `lib/metadata/store.ts` | ❌ **缺失** |
| **图片 SEO（alt 兜底）** | 组件层 | ⚠️ 部分缺失 |

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ 已读 | 优先级：Settings → Events → Dependencies → Admin → Decorators。SEO 属于 storefront 层改动，不需要后端 Decorator |
| `pallastrade-storefront/SKILL.md` | ✅ 已读 | Storefront 用 `@pallastrade/sdk` 调 API，禁止裸 `fetch()`。metadata 在 page 层通过 `generateMetadata()` 导出 |
| `pallastrade-api-v3/SKILL.md` | ✅ 已读 | Store API 通过 publishable key + locale header 认证 |

---

## 需求标题

商城前台 SEO 优化 — 提升 Google 检索、收录、推荐能力

## 任务类型

功能优化

## 需求描述

对商城前台进行 SEO 增强，确保 Google 能正确检索、收录、推荐商城页面。当前 storefront 已有良好的基础 SEO 设施（metadata、sitemap、robots、JSON-LD），但缺少多语言和多层级结构化数据支持。

## 具体实施项

### P0（必须 — 直接影响 Google 收录）

1. **hreflang alternate 标签** — 每个页面输出所有可用 locale 的 alternate links
2. **og:locale:alternate** — OpenGraph 多语言声明
3. **Sitemap `<lastmod>`** — 分类页加上 `updated_at`

### P1（推荐 — 提升 Google 展示质量）

4. **Category JSON-LD** — `schema.org/ItemList` 结构化数据
5. **Website/Organization JSON-LD** — 在首页或 layout 层注入
6. **图片 alt 兜底** — 产品图片无 alt 时用 product.name

---

> ⚠️ **用户确认门禁**：请审阅以上内容，确认后我将进入实现。是否有遗漏或需要调整的优先顺序？
