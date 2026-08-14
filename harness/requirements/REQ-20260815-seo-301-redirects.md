# REQ-20260815-seo-301-redirects

| 元数据 | 值 |
|---|---|
| PRD | PRD-20260814-catalog-seo-深度增强-商品-分类级元数据-json-ld-301-重定向 |
| 类型 | 优化迭代（阶段一 P0-1，聚焦真实缺口） |

## 需求

301 重定向管理（Redirect 模型 + Store/Admin API + Admin UI + storefront 中间件）。

**背景**：meta/JSON-LD/canonical/hreflang/OG 已实现；真正缺口是商品下架/改 URL 后 SEO 权重丢失（无 301）。

**⚠️ 范围修正**：列表页为无限滚动、分页不在 URL（`listing-search-params.ts`）→ 分页 canonical/prev-next 不适用，已移除。

## 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| App | backend/app/ | redirect | 无 | 不涉及 |
| Core | pallastrade_core/ | meta、Redirect | product.rb/taxon.rb/store.rb（meta 字段） | meta 已有；Redirect 需新建 |
| API | pallastrade_api/ | serializer | product/category/media serializer | meta 已暴露；redirects 端点需新建 |
| Admin | pallastrade_admin/ | 控制器模式 | api_keys/webhook 模式 | 需新建 redirects 管理 |
| Storefront | storefront/src/ | metadata、seo | lib/seo.ts、lib/metadata/* | 已完整；中间件+分页需补 |
| Platform | platform/packages/ | meta | SDK 类型 | 需补 redirects 类型 |

## 改动清单

1. Core：`Redirect` 模型（store、from_path、to_path、status_code、active、唯一约束）+ 迁移 `pallastrade_redirects`
2. API：Store `resolve` 端点 + Admin CRUD（controller + serializer + routes + scoped_resource）
3. Admin：Redirects 管理页（navigation + table + views）
4. Storefront：301 middleware（resolve fetch + 60s 缓存 + 降级 + 循环防护）
5. SDK：redirects 类型 + generated:check
6. 文档：api-docs yaml + 3 skill + scenarios

## 验收（AC）

- AC-001：Redirect 模型唯一约束 + 路径规范化
- AC-002：Store resolve / Admin CRUD API 可用
- AC-003：Admin Redirects 页可用
- AC-004：storefront from_path → 301 to_path；未命中正常渲染
- AC-005：API 不可达降级正常渲染；A→A 不循环

## Skill 咨询证据表

| Skill | 结论 |
|---|---|
| pallastrade-api-v3 | v3 约定：/api/v3/store|admin 前缀、prefixed ID、{data,meta} 信封、current_store 作用域——redirects 端点遵循 |
| pallastrade-admin | 资源控制器 + navigation + table 模式（api_keys/webhook 参照）——redirects 管理页复用 |
| pallastrade-storefront | metadata/seo 管线已有（lib/metadata/*、lib/seo.ts）——301 中间件 + 分页 canonical 补强 |
| pallastrade-customization | 决策树：新模型用 generator/decorator，本需求走新模型 + 新端点（符合第 5/4 层） |
| pallastrade-prd | 一句话需求 → PRD 流程已走（查重、用户确认） |
