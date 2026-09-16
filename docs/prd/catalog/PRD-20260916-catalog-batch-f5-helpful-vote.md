# PRD-20260916-catalog-batch-f5-helpful-vote

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 「继续」→ 用户选定《商品升级方案 V1.0》§十 剩余项 **Helpful Vote**（2026-09-16 会话确认） |
| 分类 | catalog（商品域 / 评论 / 社交证明） |
| 关联 Skill | pallastrade-catalog、pallastrade-storefront、pallastrade-api-v3、pallastrade-data-model |
| 关联 REQ | （实施时回填 `harness/requirements/REQ-20260916-batch-f5-helpful-vote.md`） |
| 关联 PRD | N/A（§十 剩余项，F-1 / F-3 / F-4 的兄弟批次；F-4 已预留 `most_helpful` 给本批） |
| 需求类型 | 新功能 |

> 🔁 **查重**：`harness prd new` 通过（分类关键词命中 0，已手工归入 catalog）。
> **范围依据**：§十 列出 Rating Distribution / Pagination / Sorting / Media Reviews / Helpful Vote / Admin Bulk。
> F-1（分布+分页+图片）、F-3（批量审核）、F-4（排序）已完成，**本批是 §十 最后一项**。
> F-4 变更记录已写明「`most_helpful` 随 Helpful Vote 后置」—— 本批闭环该承诺。

## 1. 背景与目标

- **一句话需求原文**：「继续」（上下文：继续《商品升级方案》下一批 → 用户选定 Helpful Vote）。
- **背景**：
  - 评论基础设施已完整（评分、文本、审核、Verified Purchase、评分聚合、图片、分页、排序），
    但**读者无法对一条评论表达「有用」**——缺少社交证明信号，优质长评无法浮到列表顶部。
  - 前台目前唯一的排序手段是 `newest` / `highest_rating` / `lowest_rating`（F-4），
    `most_helpful` 因缺少数据源被显式后置。
  - 平台**完全没有投票概念**（6 层搜索零命中，`pallastrade_reviews` 无相关列/表）。
- **目标**：
  1. 让**登录客户**对**已审核**评论投「有用」票，一人一票、可撤销；
  2. 把票数变成公开读模型（评论序列化字段），并驱动 `most_helpful` 排序；
  3. 商家在后台可见票数（内容质量信号）。
- **成功指标**：
  - PDP 每条评论显示 `Helpful (n)`，按钮状态与本人投票一致；
  - `sort=most_helpful` 按票数降序返回，翻页不重不漏（沿用 F-4 稳定 tie-break）；
  - 重复投票不增加计数（幂等），撤销后计数回落；
  - 自己不能投自己、未登录不能投（稳定错误码，不泄漏内部细节）；
  - 任何响应体**不含投票者身份**（user_id / 邮箱 / 名单）。

## 2. 用户故事 / 场景

- 作为**买家**，我希望标记「这条评论有用」，以便帮助其他买家快速找到有价值的信息。
- 作为**买家**，我希望看到某条评论被多少人认为有用，以便判断其可信度。
- 作为**买家**，我希望按「最有帮助」排序评论，以便先看高价值评价。
- 作为**买家**，我希望**撤销**误点的投票。
- 作为**商家**，我希望在后台看到每条评论的票数，以便识别优质内容。

**场景（正常 / 边界 / 异常）**：

| # | 场景 | 期望 |
|---|---|---|
| S1 | 登录客户对他人已审核评论投票 | 201/200，`helpful_votes_count+1`，`helpful_voted=true` |
| S2 | 同一客户重复投票 | 幂等，计数不变，返回当前状态 |
| S3 | 同一客户撤销投票 | 计数 -1，`helpful_voted=false` |
| S4 | 客户对自己的评论投票 | 422（稳定码 `own_review_vote_forbidden`），不落库 |
| S5 | 对 pending / rejected 评论投票 | 404（对外不可见） |
| S6 | 未登录投票 | 401（沿用既有鉴权错误码） |
| S7 | 跨店：A 店评论在 B 店域名下投票 | 404（`current_store` 作用域） |
| S8 | `sort=most_helpful` 翻页 | 按票数降序 + `id DESC` tie-break，不重不漏 |
| S9 | 投票请求失败（网络） | 前台保留原状态（不乐观清空，AP-009b） |
| S10 | 评论票数为 0 | 前台显示 `Helpful`（不显示 `(0)` 或显示 `0`？→ 统一显示计数，0 时省略数字） |

## 3. 功能需求（FR）

- **FR-001 数据模型**：新表 `pallastrade_review_votes`（`review_id` / `user_id` / `store_id` / 时间戳），
  唯一索引 `(review_id, user_id)`；`PallasTrade::Review#helpful_votes`；评论表新增计数列
  `helpful_votes_count`（integer, default 0, null false，counter cache）。
- **FR-002 投票语义**：单值「有用」（不做 up/down）；`POST` = 投票（幂等），`DELETE` = 撤销；
  两者都返回**当前权威状态**（计数 + 本人是否已投）。
- **FR-003 权限与隔离**：需客户 JWT（`require_authentication!`）；**不能投自己的评论**；
  仅 `approved` 评论可投（其余一律 404）；一切查询经 `current_store` 作用域（跨店 404）。
- **FR-004 读模型**：评论序列化新增 `helpful_votes_count`（公开整数）；
  `helpful_voted`（布尔，可空）仅对**已登录**请求返回本人状态（true/false），
  匿名请求返回 `null` —— `null` 表示「未询问」，绝不用 `false` 冒充「他看过并决定不投」。
- **FR-005 排序**：F-4 白名单新增 `most_helpful`（`helpful_votes_count DESC, id DESC`）；
  未知/空值仍回退 `newest`；`meta.sort` 回显；`meta.rating_distribution` 与排序保持正交。
- **FR-006 前台**：评论行新增 `Helpful (n)` 按钮（`data-testid="review-helpful-<id>"`）；
  已投 = 高亮 + 可撤销；未登录 = 引导登录（跳登录页并回跳 PDP）；
  失败**保留原状态**（不乐观重置）；计数 0 时显示不带数字的文案。
- **FR-007 后台**：`/admin/reviews` 列表新增 **Helpful** 列（可排序）；详情页显示票数；
  列名/CSS 走既有 admin table 机制（`pallastrade_admin_tables.rb`）。
- **FR-008 i18n**：5 语言（en/de/es/fr/pl）新增 `reviews.helpful*` 文案（按钮、已投、登录引导、错误）。

**本批边界（不做）**：
- 不做 up/down 双向投票、不做评分之外的权重；
- 不做匿名投票（不引入 IP / 指纹，避免不可靠身份与隐私风险）；
- 不做「投票后通知作者」「按票数自动置顶（pin）」；
- 不改评论状态机、不改 Verified Purchase 口径、不改评分聚合；
- 不做投票者名单导出（隐私）。

## 4. 非功能需求（NFR）

- **性能**：评论列表查询数不随条数增长（计数走 counter cache → 无 N+1）；投票为单条
  INSERT/DELETE + 计数更新，无长事务、无外部调用。
- **安全**：跨店隔离（`current_store`）；不暴露投票者身份；未授权 401、不可见资源 404、
  业务冲突 422 —— 三类错误语义不混用；投票动作幂等，重放无害。
- **兼容**：序列化**只增字段**（老客户端忽略即可）；`sort` 契约只扩白名单，未知值行为不变。
- **可维护性**：唯一索引兜底（并发双击不会双票）+ 应用层幂等；`store_id` 冗余写入以支撑多店统计。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：`pallastrade_review_votes` 存在且 `(review_id, user_id)` 唯一；同一用户对同一评论二次插入触发唯一约束（模型校验 + DB 索引双保险）。
- **AC-002 ← FR-001**：`Review#helpful_votes_count` 随投票/撤销精确增减，且等于该评论投票记录数（counter 不漂移）。
- **AC-003 ← FR-002**：`POST` 两次 → 计数只 +1（幂等），响应 `helpful_voted=true`。
- **AC-004 ← FR-002**：`DELETE` 后计数 -1 且 `helpful_voted=false`；对未投过的评论 `DELETE` → 幂等无副作用。
- **AC-005 ← FR-003**：评论作者投票 → 422 `own_review_vote_forbidden`，且库中无记录。
- **AC-006 ← FR-003**：对 `pending`/`rejected` 评论投票 → 404；未登录 → 401。
- **AC-007 ← FR-003**：跨店（另一 store 的评论）→ 404，且不产生记录。
- **AC-008 ← FR-004**：列表/单条响应含 `helpful_votes_count`；登录请求含 `helpful_voted`（true/false）；匿名请求 `helpful_voted` 为 `null`（不是 `false`）；任何响应不含 `user_id`/投票者信息。
- **AC-009 ← FR-005**：`sort=most_helpful` 按票数降序 + `id DESC`；同票数翻页不重不漏；`meta.sort='most_helpful'`；`meta.rating_distribution` 与排序无关（同一数据下三/四种排序一致）。
- **AC-010 ← FR-005**：`sort=banana` 仍回退 `newest`（F-4 契约不回归）。
- **AC-011 ← FR-006**：前台按钮渲染计数、已投态可撤销、未登录引导登录、失败保留原状态（组件测试）。
- **AC-012 ← FR-007**：后台评论列表含 Helpful 列且可排序；列表数值与模型计数一致。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `helpful` / `vote` | 无 | ❌ 需新建（模型在 gem 内） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `helpful` / `vote` / `upvote` / `downvote` | 仅 `credit_card.rb:118` 注释中的 "helpfully"（无关） | ❌ 无投票能力 |
| API | `pallastrade_gems/pallastrade_api/app/` | `helpful` / `vote` | 无 | ❌ 无端点 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `helpful` / `vote` | 无 | ❌ 无后台展示 |
| Storefront | `storefront/src/` | `helpful` / `vote` | 无 | ❌ 无 UI |
| Platform | `platform/packages/**/src/` | `helpful` / `vote` | 无 | ❌ 无 SDK 类型 |
| DB | `backend/db/schema.rb` | `review_vote` / `helpful` | 仅 `pallastrade_reviews`（无计数列） | ❌ 需新表 + 新列 |

**结论**：Helpful Vote 在 6 层**完全不存在**（AP-SEARCH-2 已排除命名差异：`vote` / `helpful` / `upvote` 全部零命中）。
本批需**新建**：1 张表 + 1 列 + 2 个 store 端点 + 1 个前台上传面（投票按钮）+ 1 个后台列 + 1 个排序白名单项。
**防重复判定**：与既有 `Wishlist`（localStorage，无服务端身份）和 `BackInStockSubscription`（订阅通知，非社交证明）语义正交，不复用。

## 7. 技术影响

- **数据库**：新表 `pallastrade_review_votes`；`pallastrade_reviews` 增 `helpful_votes_count`（新 migration，禁止改历史 migration）。
- **模型**：`PallasTrade::Review`（关联 + counter）、新模型 `PallasTrade::ReviewVote`（唯一性校验 + store 作用域）。
- **API**：`reviews_controller` 增 `vote` / `unvote` 动作；`ReviewSerializer` 增字段；`SORT_ORDERS` 增 `most_helpful`；`routes` 增两条 store 路由。
- **Admin**：`pallastrade_admin_tables.rb` 增列；`reviews_controller#index` 排序白名单若有限制需同步。
- **Storefront**：`components/products/ProductReviews.tsx`（按钮 + 状态）、`lib/data/reviews.ts`（新增 server action）、`messages/{en,de,es,fr,pl}.json`。
- **Platform**：SDK 生成类型随契约更新（typelizer 链）。
- **影响面**：`harness affected --base origin/dev` 于实施前执行并记录。

## 8. 测试计划

**新增（后端）**：
- `spec/models/pallastrade/review_vote_spec.rb`（唯一性、store 作用域、counter 一致性）
- `spec/requests/api/v3/store/review_votes_spec.rb`（投票/撤销/幂等/自投 422/pending 404/未登录 401/跨店 404）
- `spec/requests/api/v3/store/reviews_helpful_sorting_spec.rb`（most_helpful 排序 + 翻页不重不漏 + meta 正交 + 回退）

**新增（前台）**：
- `storefront/src/components/products/__tests__/ProductReviewsHelpfulVote.test.tsx`

**更新**：`reviews_sorting_spec.rb`（白名单新增项不破坏既有回退）、`reviews_spec.rb`（序列化新字段）、前台 `ProductReviews.test.tsx`（新字段可选兼容）。

**AC → 测试映射**：AC-001..002 → model spec；AC-003..007 → request spec（votes）；AC-008 → reviews_spec + votes spec；AC-009..010 → sorting spec；AC-011 → 组件测试；AC-012 → admin 列测试。

**注册验证器**：`f5-helpful-vote-rspec`（harness.config.mjs）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（评论投票读模型 + 计数语义）
- [ ] `ai/skills/pallastrade-api-v3/SKILL.md`（两个新端点 + 序列化字段 + sort 白名单扩展）
- [ ] `ai/skills/pallastrade-storefront/SKILL.md`（评论按钮交互与降级）
- [ ] `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`（新端点 + 字段 + sort enum）
- [ ] `harness/scenarios/scenarios.json`（新增 GS-152：社交证明只能来自真实且可撤销的一人一票）
- [ ] `AGENTS.md` §6 验证表新增一行（验证器 `f5-helpful-vote-rspec`）
- [ ] `harness.config.mjs`（注册验证器）
- [ ] `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（Batch F-5：FR-001~008 / AC-001~012；范围 = §十 剩余项 Helpful Vote：一人一票 + 可撤销 + most_helpful 排序 + 后台可见；边界 = 不做 up/down、不做匿名投票、不改状态机） | AI |
| 2026-09-16 | 1.0 | 用户确认「确认实施」，并**全部采纳**三个设计点（most_helpful 排序 / 后台 Helpful 列 / 支持撤销投票）→ 状态 approved，进入 gate + REQ | AI |
| 2026-09-16 | 1.1 | 实施完成：新表 `pallastrade_review_votes` + 计数器列；2 个投票端点；读模型两字段（`helpful_voted` 匿名返 `null`）；`most_helpful` 排序；前台投票按钮 + 登录引导；后台 Helpful 列。后端 29 例 / 前台 6 例绿，`generated:check` 无漂移，`f5-helpful-vote-rspec` 已注册 → 状态 **done** | AI |
