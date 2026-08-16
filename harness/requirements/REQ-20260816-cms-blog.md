# REQ-20260816-cms-blog

> 关联 PRD：PRD-20260816-other-新增cms博客（approved）
> 关联 Task：TASK-20260816005003-30fa01e2
> 关联 Gate：GATE-2026-08-16T00-50-16

## 需求概述

新增 CMS 博客功能：`Post` 模型（store 作用域、多语言、草稿/发布/定时）+ Store/Admin API + 后台管理页 + Storefront `/blog` 列表/详情 + SEO/sitemap + SDK `posts` 资源。

## 范围

MVP（见 PRD §3）：Post 模型 + Store API 只读 + Admin API CRUD + Admin UI + Storefront 博客路由 + SEO/sitemap + SDK。

Out of scope：自定义页面、商品↔文章关联、分类/Tag、评论、Markdown 编辑器。

## 跨层搜索结论

6 层均无现成 Blog/Post 实现（`pallastrade_posts` 为测试 fixture，非真实 CMS）。可复用：`TranslatableResource`、`ActionText`、`FriendlyId`、`Policy` 内容页模式、Store/Admin API 模式、storefront 内容页 + sitemap 模式、SDK 资源模式。详见 PRD §6。

## Skill 咨询记录

| Skill | 结论 |
|---|---|
| pallastrade-resource | 用 `pallastrade:api_resource` 生成 Post（model+migration+controllers+serializers+factory+specs+routes），owned-once 契约 |
| pallastrade-data-model | Post 复用 TranslatableResource + ActionText + FriendlyId（同 Policy） |
| pallastrade-api-v3 | Store API 只读 + prefixed id + `{data, meta}` 封装；Admin API CRUD |
| pallastrade-admin | ResourceController + TableConcern + 导航项 |
| pallastrade-storefront | `/blog` + `/blog/[slug]` + generateMetadata + sitemap；Tailwind（无 inline style） |
| pallastrade-i18n | Mobility translates + store 语言机制；5 语言 locale messages |

## 实施要点

1. `Post` 模型：`store_id`、`title`、`slug`(FriendlyId uniq)、`excerpt`、`body`(ActionText)、`cover_image`(ActiveStorage)、`author`、`published_at`、`seo_title`、`seo_description`；`translates :title, :excerpt, :seo_title, :seo_description` + `translates :body, backend: :action_text`；scope `published`（published_at <= now）。
2. Store 关联 `has_many :posts`。
3. Store API：`store/posts_controller.rb`（只读，仅 published）+ `admin/posts_controller.rb`（CRUD）+ 2 serializers + `dependencies.rb` 注册 + routes。
4. Admin UI：`posts_controller.rb`（ResourceController + TableConcern）+ 视图 + 导航。
5. Storefront：`blog/page.tsx` + `blog/[slug]/page.tsx` + `lib/data/posts.ts` + PostCard 组件 + 5 语言 messages + sitemap。
6. SDK：`store-client.ts` posts 资源 + 类型 + dist。
7. 权限：permission_sets 加 Post 规则。
8. 测试：post_spec、store/admin API specs、admin posts request spec、storefront 测试。

## 验收映射

AC-001→post_spec；AC-002→store posts controller spec；AC-003→admin posts controller spec；AC-004→admin posts request spec；AC-005→storefront blog 测试；AC-006→sitemap/SEO 测试；AC-007→SDK 类型检查。

## 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-08-16 | 0.1 | 创建 REQ |
