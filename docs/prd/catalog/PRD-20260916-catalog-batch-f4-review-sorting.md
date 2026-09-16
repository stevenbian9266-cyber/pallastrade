# PRD-20260916-catalog-batch-f4-review-sorting

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 《商品升级方案 V1.0》§十「评论系统升级」剩余项 **Sorting**（用户授权原话「继续」，2026-09-16） |
| 分类 | catalog（商品域 / 评论，沿用 Batch A~F 系列目录） |
| 关联 Skill | pallastrade-api-v3 / pallastrade-storefront / pallastrade-catalog / pallastrade-testing |
| 关联 REQ | REQ-20260916-batch-f4-review-sorting.md（实施时回填） |
| 关联 PRD | 上游：`PRD-20260916-catalog-batch-f1-reviews`（分页 + 评分分布 + 图片）、`PRD-20260916-catalog-batch-f3-review-bulk-moderation`（批量审核）；无同类 PRD（查重命中的 `PRD-20260908-checkout-…订单列表排序…` 属订单域，不相关） |
| 需求类型 | 优化迭代（Store API **只增 `?sort=` 参数**；零新表、不改审核口径） |

> 🔁 **查重**：`harness prd new` 因相似度命中一条**不相关**的 checkout 排序 PRD 而拒绝新建 → 已人工核对（订单域 ≠ 评论域）后按模板落本文档。
> **为什么选它**：§十 剩余三项中，Helpful Vote 需新表 + 投票者身份 + 反滥用（更大）；排序只在**既有分页契约上增加一个白名单参数**，前台立即可见，风险最小。

## 1. 背景与目标

- **一句话需求原文**：「继续」。
- **背景**（复核结论）：F-1 已把评论列表变成**分页信封**（`?page&limit` + `meta.rating_distribution`），但顺序**写死**为 `created_at DESC, id DESC`（`reviews_controller.rb` 的 `approved_reviews`）。前台 `ProductReviews` 没有任何排序入口（只有评分选择 `selectRating`）。于是：好评多的商品里，最有价值的高分评价被最新的短评顶下去，顾客只能一路 Load more。
- **目标**：
  1. 列表支持 **按最新 / 评分从高到低 / 评分从低到高** 排序（默认＝现状「最新」，**不传参数行为完全不变**）；
  2. 排序**必须与分页组合稳定**（同分同时间有确定次序，翻页不重不漏）；
  3. 前台 PDP 提供排序下拉，切换即回到首屏；
  4. **口径不变**：只有 approved 参与、评分分布仍是全体 approved（与页无关）。
- **成功指标**：三选项 + 非法值回退默认；同分排序稳定（翻页无重复/漏项）；`meta` 只增 `sort` 字段；五语言文案齐备。

## 2. 用户故事 / 场景

- 作为**顾客**，我想先看最差评，判断商品有什么通病（而不是只看最新几条）。
- 作为**顾客**，我想按评分从高到低看，快速找到推荐理由。
- 作为**老用户**，我不传排序参数时，页面行为与升级前**完全一致**。
- 作为**商家**，切换排序不应改变评分分布与平均分（否则顾客会怀疑数据造假）。

## 3. 功能需求（FR）

- **FR-001 排序白名单**：`GET /api/v3/store/products/:id/reviews` 接受 `?sort=`，取值 `newest`（默认）/ `highest_rating` / `lowest_rating`；**未知值或空值一律回退 `newest`**，不报错。
- **FR-002 排序口径**：
  - `newest`：`created_at DESC, id DESC`（＝现状）；
  - `highest_rating`：`rating DESC, created_at DESC, id DESC`；
  - `lowest_rating`：`rating ASC, created_at DESC, id DESC`。
  - **末位一律 `id DESC`**，保证同分/同时间下分页稳定（不重复、不漏项）。
- **FR-003 `meta` 回显**：列表 `meta` **新增** `sort`（当前生效值，含回退后的值）；其余键（`page/limit/count/pages/from/to/in/previous/next/rating_distribution`）保持不变。
- **FR-004 口径不变**：只统计 `approved`；`rating_distribution` 仍是**全体 approved** 的分布（与当前页/排序无关）；未审核评论与图片依旧不外泄。
- **FR-005 前台入口**：PDP 评论区顶部提供排序下拉（三选项），默认选中 `newest`。
- **FR-006 切换行为**：切换排序 → 列表**回到第 1 页**、丢弃已加载分页（避免新旧顺序混排）；请求失败时保留当前列表并提示（不整块清空）。
- **FR-007 i18n**：下拉标签与三个选项名在 5 个 locale 齐备（`products.*`）。
- **FR-008 契约同步**：`backend/public/api-docs/store.yaml` 增参数与 `meta.sort`，同步 `platform/docs/api-reference/store.yaml`，`generated:check` 保持 no drift。

## 4. 非功能需求（NFR）

- **NFR-001 索引友好**：排序只用 `rating` / `created_at` / `id` 列，不引入 N+1 或额外查询（分布仍是原有单次 `group(:rating).count`）。
- **NFR-002 兼容**：不传 `sort` 的响应与改动前**逐字节等价**（键集合与顺序语义不变，`meta` 仅多一个键）。
- **NFR-003 a11y**：下拉有可读 label（`aria-label` / 关联 `<label>`），键盘可操作。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：三个合法值各自生效；`sort=banana` / `sort=` / 不传 → 一律等价于 `newest`（请求规格）。
- AC-002 ← FR-002：`highest_rating` 返回序列严格 `rating` 非升（同分按 createdAt desc）；`?limit=1` 逐页翻完得集合无重复、无遗漏（请求规格）。
- AC-003 ← FR-002：`lowest_rating` 同理（请求规格）。
- AC-004 ← FR-003：`meta.sort` 回显生效值（含回退值），且既有 `meta` 键全部仍在（超集断言）。
- AC-005 ← FR-004：三选项下都只有 approved；`rating_distribution` 与排序无关（同夹具三选项下完全一致）。
- AC-006 ← FR-007：5 个 locale 的 `products.sort*` 键齐备（i18n 键测试）。
- AC-007 ← FR-005/006：组件渲染下拉且默认 `newest`；切换 → 重新拉第一页（组件测试，断言以 `sort` + `page=1` 调用）；失败保留列表。
- AC-008 ← FR-008：`generated:check` → no drift。
- AC-009 ← NFR-002：不传 `sort` 时列表序列与「改动前口径」（`created_at desc, id desc`）一致（回归断言）。
- AC-010 ← NFR-003：下拉可被 `getByLabelText` 定位（组件测试）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| **App** | sort / review | 无 | 缺口：按惯例落 gem + storefront |
| **Core** | review / scope | `models/pallastrade/review.rb`（`approved` scope；F-1 图片） | 复用：排序在 API 层做，模型不动 |
| **API** | order / pagy / params | `controllers/.../store/reviews_controller.rb`（`DEFAULT_LIMIT=10`、`MAX_LIMIT=100`、`approved_reviews` 里写死 `order(created_at: :desc, id: :desc)`、`collection_meta` 组装 `rating_distribution`） | **主战场**：白名单 `sort` + 稳定 tie-break + `meta.sort` |
| **Admin** | review | 审核列表与 F-3 批量（与排序无关） | 不涉及 |
| **Storefront** | sort / select | `components/products/ProductReviews.tsx`（有评分下拉 `selectRating`，**无排序**）、`lib/data/reviews.ts`（`getProductReviews` / `getMoreProductReviews`） | **需改**：新增排序下拉 + 取数透传 `sort` + 切换重置 |
| **Platform** | Review | SDK 生成类型（`Review`/`ReviewListMeta`）；`store-client.ts` 的 `products.reviews.list(productId, params)` | **需小改**：透传 `sort`、`ReviewListMeta` 增 `sort` |

### 搜索结论

- 排序**不是新能力**，而是把既写死的 order 变成白名单参数 + 前台入口；分页/分布/审核口径全部沿用 F-1。
- 稳定 tie-break（`id DESC` 收尾）是本批的正确性核心：否则同分评论在翻页时可能重复或消失。
- 分布与排序正交：分布始终基于全体 approved，**不能**随排序变化（AC-005 守护）。

## 7. 技术影响

```text
backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/reviews_controller.rb （SORT_ORDERS 白名单 + order_for + meta.sort）
backend/public/api-docs/store.yaml + platform/docs/api-reference/store.yaml                                  （参数 + meta.sort）
backend/spec/requests/api/v3/store/reviews_sorting_spec.rb                                                   （新增，AC-001~005/009）
storefront/src/lib/data/reviews.ts                                                                           （list/getMore 透传 sort）
storefront/src/components/products/ProductReviews.tsx                                                        （排序下拉 + 切换重置）
storefront/messages/*.json ×5                                                                                （products.sort* 文案）
storefront/src/components/products/__tests__/ProductReviews.test.tsx + checkout-i18n-keys.test.ts            （AC-006/007/010）
platform/packages/sdk/src/{store-client.ts,types/index.ts} + dist                                            （透传 sort + 类型）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / docs/prd/README.md                       （治理）
```

## 8. 测试计划

- **后端**：`spec/requests/api/v3/store/reviews_sorting_spec.rb`（AC-001~005、AC-009）；回归 `reviews_spec.rb` / `reviews_pagination_spec.rb`。
- **verifier**：`f4-review-sorting-rspec`。
- **前台**：`ProductReviews.test.tsx` 扩展（AC-007/010）+ `checkout-i18n-keys.test.ts`（AC-006）；本地 `pnpm build`（F-1 教训）。
- **契约**：`harness generated:check`（AC-008）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-api-v3/SKILL.md`（新增「Review list ordering」段：白名单与回退、**每种排序末位都必须有唯一 tie-break**、`meta.sort` 回显、分布与排序正交）
- [x] `ai/skills/pallastrade-storefront/SKILL.md`（新增 ProductReviews 排序条：label 关联、默认取 `meta.sort`、**切换重拉第 1 页且不混排**、失败保留列表）
- [x] `harness/scenarios/scenarios.json`（新增 **GS-150**：分页排序不重不漏、聚合不随排序变化；GS-148/149 已被本会话与并行批次占用）
- [x] `harness.config.mjs`（verifier `f4-review-sorting-rspec`）+ `AGENTS.md` §6 行
- [x] `pallastrade-catalog`（**已评估，无需更新**：approved-only 与聚合口径未变）/ `pallastrade-data-model`（**已评估，无需更新**：零迁移）
- [x] `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`（`sort` enum 参数与说明）+ `harness generated:check`（no drift）
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态（done）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（Batch F-4：FR-001~008 / AC-001~010；范围 = §十 剩余项「Sorting」，三选项；`most_helpful` 随 Helpful Vote 后置） | AI |
| 2026-09-16 | 1.0 | 用户确认「确认实施」→ 实施并推送 `bf1c4e74`（后端白名单 + 稳定 tie-break + `meta.sort` + 契约）与 `3e9b9e3a`（前台下拉 + 5 语言 + SDK 透传）；后端 10 例 / 前台 30 例绿，`typecheck`/`pnpm build`/biome 均通 | AI |
| 2026-09-16 | 1.1 | 收尾：GS-150、api-v3/storefront Skill、AGENTS §6、verifier 注册、§9 勾选、状态 → done | AI |
