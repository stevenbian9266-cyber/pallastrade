# REQ-20260916 — Batch F-1（评论系统升级一期：评分分布 + 分页 Load more + 图片评论）

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-batch-f1-reviews.md`
> 任务：TASK-20260916020126-2998b23f ｜ Gate：GATE-2026-09-16T02-04-31（feature）
> 用户确认：2026-09-16「确认实施」（范围＝全量三项；分页交互＝Load more；图片＝每条 ≤3 张）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | review | 无评论相关宿主代码 | 缺口：按本仓惯例落 gem |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | Review / Asset | `models/pallastrade/review.rb`（rating 1–5 / `status ∈ pending,approved,rejected` / `approved` scope / (product,user) 唯一 / 前缀 id `rev_`）、`models/pallastrade/asset.rb`（多态 + `has_one_attached`，但回调假定 viewable ∈ {Product, Variant}） | 需加 `has_many_attached :images`（**复用 ActiveStorage 表，无新表**）；**不**复用 Asset |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | review | `controllers/.../store/reviews_controller.rb`（`approved.includes(:user).order(created_at: desc).limit(100)`；创建只 permit `:rating,:title,:body`）、`serializers/.../review_serializer.rb`、`product_serializer.rb`（`review_count`/`average_rating`） | **需改**：分页 + 分布 + images |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | reviews | `controllers/.../reviews_controller.rb`（approve/reject/delete）、`views/.../reviews/index.html.erb` + `_row_actions.html.erb`、导航 Catalog > Reviews | 注入点齐备（列表加图片列） |
| Storefront | `storefront/src/` | review/rating/i18n | `components/products/ProductReviews.tsx`、`lib/data/reviews.ts`、`app/.../ProductDetails.tsx`、`lib/seo.ts`（评分聚合 JSON-LD）、5 个 `messages/*.json` | **需改**：分布条 + Load more + 图片 |
| Platform | `platform/packages/` | review | SDK 生成类型（OpenAPI 派生） | **需重生** |

### 搜索结论

- 评论基础（模型/审核/API/PDP/聚合）全部已存在 → 本批是**加维度**，不重做。
- 关键既有约定（来自 api-v3 Skill）：`{data, meta}` 信封、`meta` 仅列表、**分页 = `?page=N&limit=N`（Pagy，limit 默认 25 / 上限 100，`meta.next/previous`）** → F-1 沿用（reviews 端点 limit 默认 10）。
- storefront 现状：`ProductReviews` 为服务端组件 + 客户端表单；5 个 locale 文案（`messages/{de,en,es,fr,pl}.json`）；组件测试用 vitest + RTL。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：能在既有组件/端点上加维度就不要新造 —— 本批在既有 `ProductReviews`、reviews 控制器、Review 模型上扩展；**不改状态机、不建新模型** |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 后台列表加列走既有视图（gem 源直改 + `# PALLAS-CUSTOM:`），不动导航与审核动作 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | `{data, meta}` 信封；**`meta` 只在列表**；分页 offset-based（`?page&limit`，`meta.next/previous`）；列表元素不得暴露内部 id（review 用前缀 id `rev_`）；契约变更必须同步 OpenAPI + SDK 生成类型（`generated:check`） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ☑ 涉及 | ✅ 已读 | `ProductReviews` 已是 PDP 组件（评分摘要 + 列表 + 表单）；文案放 5 个 `messages/*.json`；组件/测试必须过 Biome（80 列） |
| `pallastrade-catalog` | ☑ 涉及 | ✅ 已读 | 商品域口径同源铁律（`review_count`/`average_rating` 只算 approved）→ 分布必须同源 |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已读 | UI 文案走 Rails i18n/下一步：storefront 用 `messages/*.json` 5 语言；数据翻译与 UI 文案分离 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec（容器）+ vitest（组件）；CI 环境差异两条教训（加密密钥 / `PALLASTRADE_AI_ENABLED`）——本批不涉 AI |
| `pallastrade-security` | ☑ 涉及（轻） | ✅ 已读 | 上传面必须校验类型/大小/归属；**审核未通过的内容不得对外**（隐私） |
| `harness-prd` | ☑ 涉及 | ✅ 已读 | PRD → 用户确认 → gate → 实施 → `prd verify` → 知识同步 |
| `pallastrade-data-model` | ☑ 涉及（判断为零迁移） | ✅ 已读 | **无新表/新列**（复用 `active_storage_*`）；不改 `schema.rb` |

---

## 需求标题

PDP 评论区升级：评分分布 + 分页（Load more）+ 图片评论（≤3 张/条，审核通过后可见）。

## 任务类型

新功能（Core 模型附件 + Store API 契约变更 + Admin 列表 + Storefront 组件；零新表）

## 需求描述

买家在商品页不仅看到平均分，还能看到 1–5 星分布；评论列表可分页加载（Load more）；买家可随评论提交最多 3 张实拍图，后台审核时能看图，只有审核通过的评论图片才会对外展示。

## 影响范围（预估）

```text
backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/review.rb                    （has_many_attached :images + 校验）
backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/reviews_controller.rb （分页 + images 参数 + 归属校验 + 隐私过滤）
backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/review_serializer.rb        （images）
backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/product_serializer.rb       （如需：分布不入商品体，保持 reviews meta）
backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/reviews/index.html.erb           （图片列）
backend/pallastrade_gems/pallastrade_admin/config/locales/en.yml                                        （图片列文案）
storefront/src/components/products/ProductReviews.tsx                                                   （分布条 + Load more + 图片）
storefront/src/lib/data/reviews.ts                                                                      （分页参数 + 上传 signed_id）
storefront/src/messages/{de,en,es,fr,pl}.json                                                           （文案）
storefront/src/components/products/__tests__/ProductReviews.test.tsx                                    （组件测试）
backend/public/api-docs/store.yaml + platform/docs/api-reference/store.yaml                              （契约）
platform/packages/sdk/src/types/generated/**                                                            （SDK 类型）
backend/spec/**（3 个新规格）+ harness.config.mjs + AGENTS.md + ai/skills/** + harness/scenarios/**
```

## 技术方案（初步）

- **Core**：`Review#has_many_attached :images`（ActiveStorage）+ 校验（≤3、`image/jpeg|png|webp`、≤5MB）+ `images_ordered` 便捷方法。
- **API**：索引分页（`page`/`limit`，默认 10 / 上限 100，`created_at desc, id desc`）+ `meta.rating_distribution`（单次 SQL 聚合，只算 approved）；序列化 `images: [{id, url, thumb_url}]`（仅 approved 集合）；创建接受 `images: [signed_id]`（≤3、归属当前用户）。
- **Storefront**：`ProductReviews` 增加分布条（aria）、图片网格（点击放大）、Load more 追加（`useState` 累积 + 末页隐藏）；`lib/data/reviews.ts` 返回 `{reviews, meta}`，上传走 ActiveStorage 直传。
- **Admin**：审核列表行内缩略图。

## 风险点

| 风险 | 缓解 |
|---|---|
| 审核中评论的图片泄露 | 公共读只从 `approved` 集合取附件（AC-008 断言） |
| N+1（附件/用户/变体） | `includes(:user, images_attachments: :blob)` + 单次聚合查询 |
| 分页重复/漏项 | 排序含 `id` 兜底 |
| 上传滥用 | 数量/类型/大小 + signed_id 归属校验（非本人拒绝） |
| 契约漂移 | OpenAPI + SDK 类型同步，`generated:check` 纳入验证（AC-010） |

## 验证方案（AC ↔ 命令映射）

| AC | 验证方式 |
|---|---|
| AC-001/003/004/008 | `spec/models/pallastrade/review_images_spec.rb` + `spec/requests/pallastrade/api/v3/store/reviews_images_spec.rb` |
| AC-002/003/008 | `spec/requests/pallastrade/api/v3/store/reviews_pagination_spec.rb` |
| AC-005/006/009 | storefront `pnpm vitest run`（`ProductReviews.test.tsx` + i18n 键测试） |
| AC-007 | `spec/requests/pallastrade/admin/reviews_images_spec.rb` |
| AC-010 | `harness generated:check` |
| 回归 | `harness verify reviews-f1-rspec --task TASK-20260916020126-2998b23f` + `pnpm typecheck` + storefront 全量 vitest |
| 知识同步 | `harness sync-check --id PRD-20260916-catalog-batch-f1-reviews` → 处理 → `--ack` |

## 用户确认

- 2026-09-16 经问答确认三项：范围＝全量（分布 + 分页 + 图片评论）；分页交互＝Load more；图片上限＝每条 ≤3 张；
- 2026-09-16 回复「确认实施」。
