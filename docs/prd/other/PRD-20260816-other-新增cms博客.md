# PRD-20260816-other-新增cms博客

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-16 |
| 来源 | 需求：新增CMS博客（用户 2026-08-16 明确回复"实施"确认） |
| 关联 REQ | REQ-20260816-cms-blog |
| 分类 | other（自动判定） |
| 关联 Skill | pallastrade-resource / pallastrade-data-model / pallastrade-api-v3 / pallastrade-admin / pallastrade-storefront / pallastrade-i18n |
| 关联 REQ | 实施时回填 |
| 关联 PRD | N/A（全新需求，查重未命中） |
| 需求类型 | 新功能 |

---

## 1. 背景与目标

- **一句话需求原文**：新增CMS博客
- **背景**：对标 Shopify 能力盘点（`docs/research/RESEARCH-20260814-pallastrade-shopify-capability-gap-and-upgrade-roadmap.md` §2.3 / §4.2）确认：PallasTrade **不存在** Blog/Post/CMS 内容管理能力（唯一的内容页是静态 `Policy` 政策页）。独立站获客依赖内容营销 + 长尾 SEO，博客是 **P0-2 内容管理 CMS（博客/页面）** 的核心，被列为"内容营销 + SEO 主引擎"。
- **目标**：为 store 提供**博客文章管理**能力——后台可创作/编辑/发布（草稿/发布/定时）多语言文章，前台 `/blog` 列表 + `/blog/:slug` 详情渲染，文章进 sitemap 并带 SEO meta + JSON-LD `Article`，形成可沉淀的内容营销与 SEO 资产。
- **成功指标**：
  - 可发布至少双语言文章（en + 第二语言）并在前台正确展示
  - `/blog` 列表分页正常、`/blog/:slug` 详情正常（含 SEO meta 生效）
  - 已发布文章出现在 sitemap.xml 中
  - 后台可完成"新建 → 草稿 → 发布"完整闭环

## 2. 用户故事 / 场景

- 作为 **运营/编辑**，我希望在后台创建并发布博客文章（含标题/摘要/正文/封面图），以便沉淀内容营销资产。
- 作为 **运营/编辑**，我希望文章支持**草稿 → 发布 / 定时发布**，以便控制内容上线节奏。
- 作为 **运营/编辑**，我希望文章内容可**多语言翻译**（复用 store 的语言机制），以便覆盖多市场读者。
- 作为 **访客**，我希望在 `/blog` 浏览文章列表并可点击阅读 `/blog/:slug`，以便获取品牌内容与产品信息。
- 作为 **SEO 负责人**，我希望文章具备独立 title/description + JSON-LD `Article` + 进入 sitemap，以便获取自然搜索流量。

**场景列表**：
- 正常流：后台新建文章 → 填标题/摘要/正文 → 保存草稿 → 发布 → 前台可见 → sitemap 收录
- 正常流：访客访问 `/blog` 列表 → 分页 → 点入 `/blog/:slug` → 渲染正文 + SEO meta
- 边界：文章 slug 冲突（同 store 内唯一）；未发布文章前台 404
- 边界：无文章的 store 访问 `/blog` → 空态提示
- 异常：slug 不存在 → 404

## 3. 功能需求（FR）

> 范围界定：本 PRD 聚焦**博客文章（Blog Post）MVP**——Blog/Post 模型 + Store/Admin API + 后台管理 + 前台列表/详情 + sitemap/SEO。**自定义页面（Page）**与**商品/分类关联文章**列入后续迭代（见 §11 Out of Scope）。

- FR-001：Core 新增 `Post` 模型（store 作用域），字段含 `title`、`slug`（FriendlyId 唯一）、`excerpt`、`body`（ActionText 富文本）、`cover_image`（ActiveStorage）、`author`（可选字符串）、`published_at`（空=草稿）、`seo_title` / `seo_description`（可选 SEO 元数据）。多语言复用 `PallasTrade::TranslatableResource`（title/excerpt/body/seo 字段）。
- FR-002：Store API 只读端点 `GET /api/v3/store/posts`（列表，仅已发布，分页 + meta）与 `GET /api/v3/store/posts/:slug`（详情，按 slug 或 prefixed id 查找，未发布 404）。
- FR-003：Admin API 全量 CRUD `GET/POST/PATCH/DELETE /api/v3/admin/posts`（草稿/发布/定时发布均可见，`published_at` 未来时间 = 定时）。
- FR-004：Rails Admin Gem 增加 Post 管理页（列表 + 新建/编辑表单 + 删除），含 ActionText 富文本编辑器 + 封面图上传 + 发布状态切换。接入 `PallasTrade::Admin` 导航。
- FR-005：Storefront 新增 `/blog`（列表，分页）与 `/blog/[slug]`（详情）路由；列表卡片显示标题/摘要/封面/日期；详情渲染正文 + 封面 + 作者 + 发布日期。
- FR-006：SEO：文章页 `generateMetadata` 输出独立 `<title>`/`<meta description>`（seo_title/seo_description 优先，回退 title/excerpt）+ JSON-LD `Article` 结构化数据；已发布文章加入 `sitemap.ts`。
- FR-007：SDK 增加 `posts` 资源（`posts.list` / `posts.get`），类型与 serializer 同步。

## 4. 非功能需求（NFR）

- 性能：文章列表分页（复用现有 pagy/kaminari 模式）；详情页可缓存。
- 安全：Store API 仅暴露已发布文章；Admin CRUD 走 CanCanCan 权限（`can :manage, PallasTrade::Post`，需在 permission_sets 配置）。
- 兼容：多语言 slug 复用 FriendlyId scoped + Mobility `translates`；ID 使用 prefixed id（`post_xxx`），不暴露整数主键。
- 可维护性：模型/API/序列化器/工厂/测试用 `pallastrade:api_resource` 生成后按 owned-once 契约扩展；正文渲染沿用 Policy 的 ActionText trusted HTML 模式。
- 反模式：不引入 `style={{}}`；Storefront 用 Tailwind；不绕过 SDK 用 raw fetch；不做跨 store 查询（一律 `current_store.posts`）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`Post` 模型存在，`store_id` 作用域、`published_at` 空=草稿、slug 同 store 唯一、title/excerpt/body 可多语言翻译（Mobility `translates` + ActionText body）。
- AC-002 ← FR-002：`GET /api/v3/store/posts` 只返回已发布文章且分页 meta 正确；`GET /api/v3/store/posts/:slug` 返回详情，草稿返回 404。
- AC-003 ← FR-003：Admin API 可创建/更新/删除文章；未来 `published_at` 保存为定时发布；草稿在 Admin API 可见。
- AC-004 ← FR-004：后台菜单出现 Posts/博客入口；新建/编辑表单含富文本编辑器、封面图上传、发布状态；保存后列表可见。
- AC-005 ← FR-005：`/blog` 列表展示已发布文章（标题/摘要/封面/日期）并分页；`/blog/[slug]` 详情正常渲染；无文章时空态；未发布 slug 404。
- AC-006 ← FR-006：文章详情页 HTML 含独立 `<title>` + `<meta name="description">` + JSON-LD `Article`；已发布文章出现在 `sitemap.xml`。
- AC-007 ← FR-007：SDK `posts.list` / `posts.get` 可用且类型正确（`@pallastrade/sdk` 类型 + dist 重建）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | blog/post/article/cms/content | 无 Blog/Post 模型；仅 admin ai 控制器/视图 | ❌ 需新建 |
| Core | `pallastrade_gems/pallastrade_core/app/` | blog/article/cms/post | `policy.rb`（TranslatableResource + ActionText + FriendlyId 模板）、`translatable_resource.rb` concern、`store.rb`（has_many :policies 模式） | ❌ 无 Post；✅ 有可复用模板 |
| API | `pallastrade_gems/pallastrade_api/app/` | blog/article/posts | `store/policies_controller.rb`（只读 slug 查找模式） | ❌ 无 posts 端点；✅ 有 controller 模板 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | blog/article/posts/cms | 无 Post 管理页；`products_controller.rb`（ResourceController 模式）、`emails` 系列（一级菜单 + 二级导航模式） | ❌ 需新建；✅ 有 CRUD/导航模板 |
| Storefront | `storefront/src/` | blog/article/posts/cms | `policies/[slug]/page.tsx`（内容页 + generateMetadata 模式）、`lib/data/policies.ts`（server action + SDK 模式）、`sitemap.ts` | ❌ 无 /blog；✅ 有内容页/SEO/sitemap 模板 |
| Platform | `platform/packages/` | blog/article/posts | `sdk/src/store-client.ts`（policies 资源模式）；docs 提及旧 `pallastrade_posts`（已提取，非本仓库实现）；`backend/pallastrade_gems/pallastrade_posts/` 仅为**测试 fixture gem**（无模型/控制器） | ❌ SDK 无 posts；✅ 有资源模板 |

**结论**：
- 6 层均**无现成 Blog/Post 实现**——全新需求，无重复建设风险。
- `backend/pallastrade_gems/pallastrade_posts/` 是测试 fixture（gemspec 注明 "test fixture extension"，install generator 是 no-op），**不承载真实 CMS**，本 PRD 不依赖它。
- 可复用基础设施：`TranslatableResource`（多语言）、`ActionText`（富文本）、`FriendlyId`（slug）、`Policy` 内容页模式、Store/Admin API controller 模式、storefront 内容页 + sitemap 模式、SDK 资源模式。

## 7. 技术影响

- **新增模型**：`PallasTrade::Post`（`backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/post.rb`）+ 迁移 `create_pallastrade_posts`（含 `store_id`、`title`、`slug`、`excerpt`、`body` ActionText、`cover_image` ActiveStorage、`author`、`published_at`、`seo_title`、`seo_description`、`pallastrade_*_translations` 表）。
- **Store 关联**：`store.rb` 增加 `has_many :posts`。
- **API**：`store/posts_controller.rb`（只读）+ `admin/posts_controller.rb`（CRUD）+ 两个 serializer + `dependencies.rb` 注册 + routes（store + admin）。
- **Admin**：`posts_controller.rb`（ResourceController + TableConcern）+ 视图（index/show/new/edit/_form，含 ActionText editor + cover 上传）+ 导航项。
- **Storefront**：`app/[country]/[locale]/(storefront)/blog/page.tsx` + `blog/[slug]/page.tsx` + `lib/data/posts.ts` + 组件（PostCard 等）+ 5 语言 locale messages + `sitemap.ts` 加 posts。
- **SDK**：`store-client.ts` 加 `posts` 资源 + 类型 + dist 重建。
- **权限**：`permission_sets` 增加 `can :read, PallasTrade::Post`（store）/ `can :manage`（admin）。
- **测试**：模型 spec（多语言/slug 唯一/草稿发布）、store API spec、admin API spec、emails/导航相关 spec、storefront 组件/页面测试。
- **影响面**：`harness affected --base origin/main` 于实施时确认。

## 8. 测试计划

- 新增：
  - `backend/spec/models/pallastrade/post_spec.rb`（AC-001）
  - `backend/spec/controllers/pallastrade/api/v3/store/posts_controller_spec.rb`（AC-002）
  - `backend/spec/controllers/pallastrade/api/v3/admin/posts_controller_spec.rb`（AC-003）
  - `backend/spec/requests/pallastrade/admin/posts_spec.rb`（AC-004）
  - `backend/spec/factories/pallastrade/post_factory.rb`
  - storefront：`blog` 页面组件测试 + sitemap 含 posts 断言（AC-005/AC-006）
- 更新：
  - `storefront/src/app/sitemap.ts` 相关测试
- AC 映射：AC-001→post_spec；AC-002→store posts controller spec；AC-003→admin posts controller spec；AC-004→admin posts request spec；AC-005→storefront blog 页面测试；AC-006→sitemap/SEO 测试；AC-007→SDK 类型检查。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`（新增 posts 端点）
- [ ] Skill 文档：`pallastrade-data-model`（Post 模型）、`pallastrade-api-v3`（posts 端点）、`pallastrade-storefront`（§Components blog）、`pallastrade-resource`（如涉及生成器使用）
- [ ] `docs/prd/README.md` 索引更新
- [ ] SDK 类型：`@pallastrade/sdk` dist 重建 + `platform/packages/README.md`（如涉及）
- [ ] 反模式库 / 任务规则 / 场景库：如涉及按 sync-check 矩阵判定

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-16 | 0.1 | 初稿（PRD 骨架 + 完整扩充，跨层搜索完成） | AI |

## 11. Out of Scope（后续迭代）

- 自定义页面（Page）管理（P0-2 下半部分，可复用 Post 模式）
- 商品/分类 ↔ 文章关联（内容引流到商品）
- 文章分类/Tag、作者模型、评论、阅读统计
- Markdown 编辑器（本 PRD 用 ActionText 富文本；如后续需要 Markdown 再评估）
