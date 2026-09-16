# REQ-20260916-batch-f5-helpful-vote

| 项 | 值 |
|---|---|
| 关联 PRD | `docs/prd/catalog/PRD-20260916-catalog-batch-f5-helpful-vote.md`（approved） |
| 任务类型 | 新功能（feature gate） |
| Harness Task | `TASK-20260916064248-dd107470`（risk: standard） |
| Gate | `GATE-2026-09-16T06-42-57` |
| 分支 | `dev` |

## Step 0：跨层搜索（强制执行）

| 层 | 搜索路径 | 搜索关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `helpful`, `vote`, `voting` | 无 | ❌ 无 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/` | `helpful`, `vote`, `upvote`, `downvote` | 仅 `credit_card.rb:118` 注释 "helpfully"（无关） | ❌ 无 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/` | `helpful`, `vote` | 无 | ❌ 无 |
| Admin Gem — controllers/views | `backend/pallastrade_gems/pallastrade_admin/app/` | `helpful`, `vote` | 无 | ❌ 无 |
| Storefront | `storefront/src/` | `helpful`, `vote` | 无 | ❌ 无 |
| Platform | `platform/packages/**/src/` | `helpful`, `vote` | 无 | ❌ 无 |
| DB 快照 | `backend/db/schema.rb` | `review_vote`, `helpful` | 仅 `pallastrade_reviews`（无计数列） | ❌ 需新表 + 新列 |

**搜索结论**：Helpful Vote 在 6 层 + DB **完全不存在**（已排除 NAME_MISMATCH：`vote`/`helpful`/`upvote`/`downvote`
全部零命中；已排除 LAYER_ASSUME：逐层独立搜索）。本批需**新建**：1 表 + 1 列 + 1 模型 + 2 端点 +
1 序列化字段组 + 1 排序白名单项 + 1 前台按钮 + 1 后台列。
**防重复判定**：与 `Wishlist`（localStorage、无服务端身份）、`BackInStockSubscription`（到货通知）语义正交，不复用。

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → **Generators (resource or model)** → Decorators → Extensions」；本批是**新模型 + 新 API 面**，落在第 5 级（generator 级），且 AGENTS §1 明确 `pallastrade_gems/` 是团队产品、可直接改 gem 文件（升级=merge）→ 采用「gem 内直接新增文件」而非宿主 decorator |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 「**表格**：`config/initializers/pallastrade_admin_tables.rb` 里 `PallasTrade.admin.tables.register(:<key>, …)` + 逐列 `.add`；视图只写 `<%= render_table @collection, :<key> %>`」→ F-5 后台列只需在既有 `:reviews` 表追加一列，不新建视图 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | ①「IDs are computed from the integer PK via Sqids — no database column… `has_prefix_id :<prefix>`… When adding a model, pick a **globally unique** prefix — `backend/spec/models/pallastrade/prefixed_id_spec.rb` requires zero duplicate declarations」→ 已确认 `rv` 未被占用（`grep has_prefix_id :rv` 零命中）；②Review 既有 `has_prefix_id :rev` + `SingleStoreResource`（line 42）→ 投票模型沿用同样的 store 作用域策略 |

**按需 Skill（本次涉及）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | line 179「Pagination is offset-based via Pagy — pass `?page=N&limit=N`」；line 357-367「`?sort=` 白名单 + 每个排序以**唯一 tie-break** 收尾（否则翻页会重复/漏行）+ `meta.sort` 回显**实际生效值**，其余 meta 键不变」→ F-5 的 `most_helpful` 必须沿用同一契约；line 399-410「评论**公开读**（api_key）/ **写需 customer JWT**，只有 approved 评论暴露」→ 投票写端点必须 `require_authentication!` |
| `pallastrade-storefront` | ✅ | ✅ 已读 | line 169「**Client-component SDK calls go through server actions**… A client component that needs the Store API must call a `"use server"` action in `src/lib/data/`」→ 投票动作必须新增 server action，不得在客户端直连 SDK |
| `pallastrade-testing` | ✅ | ✅ 已读 | 栈为 **RSpec + Factory Bot + Capybara**（非 Minitest/fixtures），宿主测试位于 `spec/`；新增用例必须进注册验证器（`harness.config.mjs` verifiers）→ 注册 `f5-helpful-vote-rspec` |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 前台文案在 `storefront/messages/*.json`，F-1/F-4 的评论键集中在顶层 `reviews` 命名空间 → F-5 文案沿用同一 namespace（5 语言） |
| `pallastrade-security` | ✅ | ✅ 见 PRD §4 | 跨店隔离是硬边界（`current_store` 作用域）；不暴露投票者身份；错误语义不混用（401 未认证 / 404 不可见 / 422 业务冲突） |

## 需求标题

**Batch F-5 —— 评论 Helpful Vote**：让登录客户对已审核评论投「有用」票（一人一票、可撤销），
票数成为公开读模型并驱动 `most_helpful` 排序，商家在后台可见。

## 范围

**做**：新表 `pallastrade_review_votes` + `pallastrade_reviews.helpful_votes_count`；
`PallasTrade::ReviewVote` 模型；`POST`/`DELETE /api/v3/store/reviews/:review_id/helpful_vote`；
`ReviewSerializer` 增 `helpful_votes_count`（公开）/ `helpful_voted`（仅登录）；
`SORT_ORDERS` 增 `most_helpful`；前台 `Helpful (n)` 按钮 + server action；后台 Helpful 列；5 语言文案。

**不做**：up/down 双向投票、匿名投票、投票通知、按票自动置顶、改评论状态机 / 评分聚合 / Verified Purchase 口径、投票者名单导出。

## 验收（与 PRD AC-001~012 一致）

| AC | 判定 | 归属测试 |
|---|---|---|
| AC-001/002 | 唯一索引 `(review_id,user_id)` 生效；计数与记录数一致 | `spec/models/pallastrade/review_vote_spec.rb` |
| AC-003/004 | POST 幂等；DELETE 幂等可撤销 | `spec/requests/api/v3/store/review_votes_spec.rb` |
| AC-005/006/007 | 自投 422；pending/rejected 404；未登录 401；跨店 404 | 同上 |
| AC-008 | 字段只增；匿名 `helpful_voted` 为 `null`（非 false）；无投票者身份 | 同上 + `reviews_spec.rb` |
| AC-009/010 | `most_helpful` 排序 + tie-break + `meta.sort`；非法值仍回退 | `spec/requests/api/v3/store/reviews_helpful_sorting_spec.rb` |
| AC-011 | 前台按钮（计数/已投/未登录/失败保留） | `storefront/src/components/products/__tests__/ProductReviewsHelpfulVote.test.tsx` |
| AC-012 | 后台 Helpful 列 | admin 表注册断言 |

## 实施计划（文件级）

1. `backend/db/migrate/20260916210000_create_pallastrade_review_votes.rb`
2. `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/review_vote.rb`
3. `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/review.rb`（关联 + 计数）
4. `backend/pallastrade_gems/pallastrade_api/config/routes.rb`（嵌套 `resource :helpful_vote`）
5. `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/review_helpful_votes_controller.rb`
6. `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/reviews_controller.rb`（`most_helpful` + 预取已投集合）
7. `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/review_serializer.rb`（两个字段）
8. `backend/pallastrade_gems/pallastrade_admin/config/initializers/pallastrade_admin_tables.rb`（Helpful 列）
9. `storefront/src/lib/data/reviews.ts`（server action）+ `ProductReviews.tsx`（按钮）+ `messages/*.json`（5 语言）
10. 测试 4 个 + 契约（store.yaml ×2）+ 知识同步（api-v3 / storefront / data-model Skill + GS-152 + AGENTS §6 + verifier）
