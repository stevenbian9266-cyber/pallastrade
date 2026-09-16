# REQ-20260916 — Batch F-4（评论列表排序 Sorting）

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-batch-f4-review-sorting.md`
> 任务：TASK-20260916054208-1875b2dc ｜ Gate：GATE-2026-09-16T05-42-13（feature，risk=critical）
> 用户确认：2026-09-16「确认实施」（三选项 = newest / highest_rating / lowest_rating；`most_helpful` 随 Helpful Vote 后置）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | review / sort | 无 | 缺口：按惯例落 gem + storefront |
| Core Gem | `pallastrade_core/app/` | review / approved / audit | `models/pallastrade/review.rb`（`approved` scope，F-1 图片） | **复用**：排序在 API 层，模型不动 |
| API Gem | `pallastrade_api/app/` | order / pagy / params / meta | `controllers/.../store/reviews_controller.rb`：`DEFAULT_LIMIT=10` / `MAX_LIMIT=100` / `pagy(approved_reviews(product), …)` / `approved_reviews` 里**写死** `.order(created_at: :desc, id: :desc)` / `collection_meta` 组装 `rating_distribution`（单次 `group(:rating).count`） | **主战场**：加白名单 `sort` + 稳定 tie-break + `meta.sort` |
| Admin Gem | `pallastrade_admin/app/` | review | 审核列表 + F-3 批量（与排序正交） | **不涉及** |
| Storefront | `storefront/src/` | sort / select | `components/products/ProductReviews.tsx`（有评分下拉 `selectRating`，**无排序入口**）、`lib/data/reviews.ts`（`getProductReviews` / `getMoreProductReviews` 返回 `{reviews, meta}`） | **需改**：排序下拉 + 透传 `sort` + 切换重置首屏 |
| Platform | `platform/packages/` | Review | SDK 生成类型 + `store-client.ts` 的 `products.reviews.list(productId, params)` | **需小改**：透传 `sort`；`ReviewListMeta` 增 `sort` |

### 搜索结论

- F-1 已建立「分页信封 + 分布」，本批只把**写死的 order** 变成白名单参数并加前台入口，不引入新概念。
- **tie-break 是本批正确性核心**：末位一律 `id DESC`，否则同分评论在翻页时可能重复或消失。
- **分布与排序正交**：`rating_distribution` 始终基于全体 approved（与当前页/排序无关），必须用规格锁死（AC-005）。
- **不传 `sort` ＝ 现状**（NFR-002），升级对既有消费者零影响。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-api-v3` | ✅ 已读 | `{data, meta}` 信封；分页 = `?page&limit`（Pagy）；**契约只增不改**；列表禁裸主键；契约变更必须同步 OpenAPI + SDK 类型（`generated:check`） |
| `pallastrade-customization` | ✅ 已读 | 决策树：能在既有端点/组件上加维度就不要新造 → 本批只加一个白名单参数与一个前台下拉 |
| `pallastrade-catalog` | ✅ 已读 | **只有 approved 公开**、平均分/评论数只算 approved → 排序不得改变该口径（AC-005/009） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ☑ 涉及 | ✅ 已读 | PDP 由 `ProductDetails` 组装、`ProductReviews` 为客户端组件；文案入 5 个 `messages/*.json`；**改 storefront 必须本地 `pnpm build`**（F-1 教训）+ Biome 80 列 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec（容器）+ vitest 组件；注册 verifier 供 `harness verify` |
| `pallastrade-data-model` | ☑ 涉及（判断为零迁移） | ✅ 已读 | 无新表/新列；排序只用既有列 |
| `pallastrade-security` | ☑ 涉及（轻） | ✅ 已读 | 输入必须白名单（`sort` 不接受任意 SQL 顺序）；越界值回退而非报错泄漏内部结构 |
| `harness-prd` | ☑ 涉及 | ✅ 已读 | PRD → 确认 → gate → REQ → 实施 → 证据 → 知识同步 |

---

## 需求标题

评论列表排序：`?sort=` 白名单（最新 / 评分高→低 / 评分低→高）+ `meta.sort` 回显 + PDP 排序下拉（切换重置首屏）。

## 任务类型

优化迭代（Store API 只增参数；零新表、不改审核口径）

## 需求描述

顾客在 PDP 评论区可切换「最新 / 评分从高到低 / 评分从低到高」；API 用白名单参数实现排序并要求稳定 tie-break，保证分页翻页不重不漏；评分分布与审核口径完全不随排序变化。

## 影响范围（预估）

```text
backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/reviews_controller.rb  （SORT_ORDERS 白名单 + order_for + meta.sort）
backend/public/api-docs/store.yaml + platform/docs/api-reference/store.yaml                               （sort 参数 + meta.sort）
backend/spec/requests/api/v3/store/reviews_sorting_spec.rb                                               （新增，AC-001~005/009）
storefront/src/lib/data/reviews.ts                                                                        （透传 sort）
storefront/src/components/products/ProductReviews.tsx                                                     （排序下拉 + 切换重置）
storefront/messages/*.json ×5                                                                             （products.sort* 文案）
storefront/src/components/products/__tests__/ProductReviews.test.tsx + src/lib/__tests__/checkout-i18n-keys.test.ts （AC-006/007/010）
platform/packages/sdk/src/{store-client.ts,types/index.ts} + dist                                         （透传 sort + 类型）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / docs/prd/README.md                    （治理）
```

## 决策记录

1. 三选项：`newest`（默认，＝现状）/ `highest_rating` / `lowest_rating`；`most_helpful` **后置**（随 Helpful Vote）。
2. 未知值/空值 → **回退 `newest`**，不返回 4xx（避免把内部取值面暴露成错误码）。
3. tie-break：所有排序末位 `id DESC`（稳定分页）。
4. `meta` 只增 `sort`；其余键语义不变。
5. 前台切换排序 → **丢弃已加载分页、回到第 1 页**；请求失败保留现有列表。
6. 分布/审核口径不动（AC-005/009 回归守护）。
