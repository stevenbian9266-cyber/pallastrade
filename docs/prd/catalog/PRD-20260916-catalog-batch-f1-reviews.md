# PRD-20260916-catalog-batch-f1-reviews

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 《商品升级方案 V1.0》§十「评论系统升级」——最优先三项：**评分分布 + 分页 + 图片评论**（用户授权原话「继续」，2026-09-16） |
| 分类 | catalog（商品域 / 评论） |
| 关联 Skill | pallastrade-storefront / pallastrade-api-v3 / pallastrade-catalog / pallastrade-i18n / pallastrade-testing |
| 关联 REQ | REQ-20260916-batch-f1-reviews.md（实施时回填） |
| 关联 PRD | 上游：P0-4 评论基础设施（Review 模型 + 审核 + Store API + PDP 评论区 + SEO 聚合）；无同类 PRD（新功能） |
| 需求类型 | 新功能（Storefront 组件 + Store API 契约变更；**无新表**（复用 `active_storage_*`）、不改审核状态机） |

> 🔁 **查重**：`harness prd new` 通过。**范围依据**：§十 明确「不应该重做 Review」——基础（评分 / 文本 / 审核 / Verified Purchase / 评分聚合）已具备，本批只加 ① 评分分布 ② 分页 ③ 图片评论；§十 其余项（排序 / Helpful Vote / 后台批量审核）留后续批次。
> **用户已确认的三项选择（2026-09-16）**：① 范围 = **全量（分布 + 分页 + 图片评论）**；② 前台分页交互 = **Load more**；③ 图片上限 = **每条 ≤3 张**。

## 1. 背景与目标

- **背景**：评论基础设施已在（P0-4）：`PallasTrade::Review`（store/product/user、rating 1–5、title/body、`status ∈ pending|approved|rejected`、`verified_purchase`、前缀 id `rev_`）、后台审核页（`/admin/reviews` approve/reject/delete）、Store API（`GET/POST /api/v3/store/products/:product_id/reviews`）、PDP 评论区（`ProductReviews.tsx`）、商品聚合（`average_rating` / `review_count`）与 SEO 聚合评分。
- **缺口**：① **无分页** —— 索引端点硬编码 `limit(100)`，评论多的商品首屏拿不到完整列表也看不到历史评论；② **无评分分布** —— 只有平均值，买家无法判断「是普遍 4 星还是两极分化」；③ **无图片评论** —— 服装/家居类目的购买决策高度依赖买家实拍图，当前只能纯文字。
- **目标**：把 PDP 评论区升级为**可继续浏览、可判断口碑结构、可看图**的决策面：主评分旁给出 1–5 星分布（计数 + 占比）；评论列表按页加载（Load more 追加）；买家提交评论时最多附 **3 张**实拍图，后台审核时能看到图，PDP 上以缩略图 + 点击放大呈现。
- **成功指标**：① 评论 ≥ 10 条的商品不再被 `limit(100)` 截断、可继续加载到末页；② 分布条总和 == `meta.count` == 商品的 `review_count`（同源，不漂移）；③ 带图评论在 **approved 之前不对外暴露任何图片 URL**（隐私/审核一致性）；④ 上传受限（≤3 张、jpg/png/webp、≤5MB），非法输入被明确拒绝；⑤ API 契约（OpenAPI + SDK 类型）同步，`generated:check` 无漂移。

## 2. 用户故事 / 场景

- 作为**买家**，我在 PDP 看到 4.6 分旁边有分布条（5★ 82%、4★ 11%…），点「Load more」继续看更早的评论，并且能看到买家实拍图（点击放大）。
- 作为**买家**，我写完评论后选 3 张照片（有预览、可移除），提交后提示「待审核」。
- 作为**运营**，我在后台评论列表一眼看到哪些评论带图，据此决定通过/拒绝；图片只在通过后才对外。
- 边界：评论数不足一页 → 不渲染 Load more；加载中 → 按钮禁用并显示 loading；末页 → 按钮消失且不重复请求；无图评论 → 不渲染图片区（不留空位）。
- 异常：第 4 张图片被前端阻止（后端同样拒绝 → 422）；非法类型/超 5MB → 明确报错；非本人上传的 blob signed_id → 拒绝；审核中的评论图片不出现在公共读接口。

## 3. 功能需求（FR）

- **FR-001 图片存储（Review 侧）**：`PallasTrade::Review` 增加 `has_many_attached :images`（ActiveStorage；**复用既有 `active_storage_*` 表，无新表**），并加校验：数量 ≤ **3**、内容类型 ∈ `image/jpeg|png|webp`、单张 ≤ **5MB**；顺序按 attachment id。
- **FR-002 索引分页**：`GET /api/v3/store/products/:product_id/reviews` 改为分页（**沿用 v3 约定**：`?page=N&limit=N`，`limit` 默认 **10** / 上限 **100**；按 `created_at desc, id desc` 稳定排序），响应保持 `{ data: [...], meta: { count, current_page, total_pages, next, previous } }`（与 API v3 列表契约一致，见 `pallastrade-api-v3` Skill §分页）。
- **FR-003 评分分布**：同一响应 `meta.rating_distribution = { "1" => n1, …, "5" => n5 }`，**只统计 approved**，且 `Σn == meta.count`（与商品 `review_count`/`average_rating` 同源口径）。
- **FR-004 提交带图**：`POST /api/v3/store/products/:product_id/reviews` 接受 `images: [signed_id, ...]`（ActiveStorage 直传产物）；服务端校验 ≤3 张 / 类型 / 大小 / **signed_id 归属当前用户**（非本人 → 拒绝）；评论仍以 `status: 'pending'` 创建。
- **FR-005 PDP 评论区（storefront）**：`ProductReviews.tsx` 增加 ① 评分分布条（每星一行：星数 + 条 + 计数 + 占比，`aria` 可读）；② 评论卡内图片缩略图网格（点击放大，键盘可达）；③ **Load more** 追加式分页（首屏第 1 页；加载中禁用 + loading 文案；末页隐藏；追加不重复）。
- **FR-006 评论表单上传（storefront）**：评价表单支持选择 ≤3 张图片（前端预览 + 移除；超出立即阻止并提示），经 ActiveStorage 直传后提交 signed_id；提交失败保留已选图片与文本。
- **FR-007 Admin 审核体验**：`/admin/reviews` 列表行内展示图片缩略图（点击新窗口打开原图）；approve/reject/delete 行为不变（§十 的「批量审核」不在本批）。
- **FR-008 i18n**：storefront 现有 5 个 locale（`de/en/es/fr/pl`）新增键（分布标题、Load more/loading、图片上限提示、错误文案等）；admin `en` 新增图片列文案。
- **FR-009 契约同步**：Store API 变更（review `images` + `meta.rating_distribution` + 分页参数）→ 同步 `backend/public/api-docs/store.yaml`、`platform/docs/api-reference/store.yaml` 与 SDK 生成类型（`harness generated:check`）。
- **FR-010 不做（本批边界）**：不做评论排序/筛选、Helpful Vote、后台批量审核（§十 其余项）；不做图片裁剪/水印/EXIF 清洗（仅按类型与大小校验）；不做已审核评论的图片二次编辑；不改审核状态机与 Verified Purchase 口径；不引入新评论模型。

## 4. 非功能需求（NFR）

- **隐私与审核一致性**：只有 `approved` 评论的图片可经公共读接口获取；pending/rejected 不泄露任何 signed 变体 URL。
- **性能**：索引端点避免 N+1（`includes(:user, images_attachments: :blob)`）；分布用**单次 SQL 聚合**（group by rating count）而非 5 次查询；每页默认 10 条（原 `limit(100)` 一并消除）。
- **稳定性**：分页排序含 `id` 兜底（避免同秒创建导致重复/漏项）；`page` 越界 → 空数组 + 正确 meta（不报错）。
- **可测试性**：API（分页/分布/上传校验/隐私）、组件（分布条、Load more、上传上限）、Admin 渲染四层各有规格；storefront 用组件测试（vitest + RTL）。
- **可运维**：上传走 ActiveStorage 直传（不占 Rails 请求线程）；错误一律明确文案 + 稳定状态码。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`Review` 可挂 ≤3 张图；**第 4 张被拒**；非法内容类型与 >5MB 被拒（模型层校验）。
- AC-002 ← FR-002：`?page=2&limit=2` 返回第二页的正确集合与 `meta{count,current_page,total_pages,next,previous}`；默认 `limit=10`；`limit=999` 被夹到 100；越界页返回空数组且 meta 正确。
- AC-003 ← FR-003：`meta.rating_distribution` 只含 approved，且各档之和 == `meta.count` == 商品的 `review_count`（同源断言）。
- AC-004 ← FR-004：POST 带 3 个本人 signed_id → 201 且关联 3 张；带 4 个 → 422；带**他人** blob → 拒绝；未登录 → 401。
- AC-005 ← FR-005：PDP 渲染分布条（计数与占比正确、`aria` 可读）；`Load more` 追加下一页且无重复；末页不渲染按钮（组件测试）。
- AC-006 ← FR-006：表单选满 3 张后第 4 张被阻止并提示；移除后可再选（组件测试）。
- AC-007 ← FR-007：`/admin/reviews` 列表行渲染缩略图（渲染断言），审核动作回归不变。
- AC-008 ← NFR/FR-001：**pending 评论的图片不出现在公共读接口**（隐私断言）。
- AC-009 ← FR-008：storefront 5 个 locale 的评论图片/分页键齐备（沿用现有 i18n 键测试机制）。
- AC-010 ← FR-009：`harness generated:check` → **no drift**（OpenAPI + SDK 类型已同步）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App（宿主） | `backend/app/` | review | 无评论相关宿主代码 | 缺口：按本仓惯例落 gem |
| Core Gem | `pallastrade_core/app/` | Review / Asset | `models/pallastrade/review.rb`（rating 1–5、status 状态机、`approved` scope、唯一性 (product,user)、前缀 id `rev_`；**无媒体**）、`models/pallastrade/asset.rb`（`viewable` 多态 + `has_one_attached`，但其回调假定 viewable ∈ {Product, Variant} → **不适合直接给 Review 用**） | 需新增 `has_many_attached :images`（**零新表**） |
| API Gem | `pallastrade_api/app/` | review | `controllers/.../store/reviews_controller.rb`（索引 `approved.includes(:user).order(created_at: desc).limit(100)`、创建 `params.permit(:rating,:title,:body)`、`verified_purchase?`）、`serializers/.../review_serializer.rb`、`product_serializer.rb`（`review_count` / `average_rating`） | **需改**：分页 + 分布 + images + 参数 |
| Admin Gem | `pallastrade_admin/app/` | reviews | `controllers/.../reviews_controller.rb`（approve/reject/delete）、`views/.../reviews/index.html.erb` + `_row_actions.html.erb`、导航 Catalog > Reviews | 注入点齐备（列表加图片列） |
| Storefront | `storefront/src/` | review / rating | `components/products/ProductReviews.tsx`（平均分 + 列表 + 表单）、`lib/data/reviews.ts`（list/create）、`app/.../products/[slug]/ProductDetails.tsx`（引入）、`lib/seo.ts`（聚合评分）、`lib/__tests__/checkout-i18n-keys.test.ts`（5 locale 键测试机制） | **需改**：分布条、Load more、图片展示与上传 |
| Platform | `platform/packages/` | review | SDK 生成的 Review 类型（由 OpenAPI 派生） | **需重生**：`generated:check` |

**结论**：评论基础设施齐备（模型/审核/API/PDP/聚合），本批是**在其上加维度**：图片（模型附件 + 上传校验）、分页（索引端点 + 前台追加加载）、分布（聚合 + 前台可视化）。**不新建评论模型、不改审核状态机、不新增表**（ActiveStorage 表已存在）。

## 7. 技术影响

- **Core Gem（改动）**：`models/pallastrade/review.rb`（`has_many_attached :images` + 校验 + 上传者归属校验入口）。
- **API Gem（改动）**：`store/reviews_controller.rb`（分页 + `images` 参数 + 归属校验 + 隐私过滤）、`review_serializer.rb`（`images` 数组：`id`/`url`/`thumb_url`）、索引响应 `meta`（`rating_distribution`）。
- **Admin Gem（改动）**：`views/.../reviews/index.html.erb`（图片列）+ `config/locales/en.yml`。
- **Storefront（改动）**：`components/products/ProductReviews.tsx`（分布条 + Load more + 图片网格）、`lib/data/reviews.ts`（分页参数与响应 meta、上传 signed_id）、直接上传辅助、5 个 locale 文案；新增组件测试。
- **契约（改动）**：`backend/public/api-docs/store.yaml`、`platform/docs/api-reference/store.yaml`、SDK 生成类型。
- **数据库**：**无新表**（复用 `active_storage_attachments/blobs/variant_records`）；`Review` 无需新列。
- **风险**：① 隐私泄露（pending 图片）→ 公共读只从 approved 集合取附件，并加 AC-008 断言；② N+1 → `includes`；③ 分页重复/漏项（同秒排序）→ `created_at desc, id desc`；④ 上传滥用 → 数量/类型/大小 + 归属校验；⑤ 契约漂移 → `generated:check` 纳入验证。

## 8. 测试计划

- **API 规格**：`spec/requests/pallastrade/api/v3/store/reviews_pagination_spec.rb`（AC-002/003/008）+ `reviews_images_spec.rb`（AC-004）；模型规格 `spec/models/pallastrade/review_images_spec.rb`（AC-001）。
- **Storefront 组件测试**：`ProductReviews.test.tsx` 扩展（AC-005/006：分布条、Load more、上传上限、aria）。
- **Admin 渲染规格**：`spec/requests/pallastrade/admin/reviews_images_spec.rb`（AC-007）。
- **i18n**：沿用 `checkout-i18n-keys.test.ts` 模式新增键测试（AC-009）。
- **契约**：`harness generated:check`（AC-010）。
- **注册 verifier**：`reviews-f1-rspec`（后端 3 个规格文件）+ storefront `pnpm vitest`（组件）。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-storefront/SKILL.md`（评论区分页/分布/图片组件约定 + Load more 模式 + `"use server"` 只能导出 async 函数）
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`（reviews 索引分页 + `meta.rating_distribution` + images 上传契约 + `direct_uploads`）
- [x] `ai/skills/pallastrade-data-model/SKILL.md`（`has_many_attached :images` + `MAX_IMAGES`/`ALLOWED_IMAGE_TYPES`/`MAX_IMAGE_BYTES`）
- [x] `ai/skills/pallastrade-typescript-sdk/SKILL.md`（`ReviewListResponse` 信封 + `directUploads` + 新导出类型）
- [x] `harness/scenarios/scenarios.json`（GS-144：评论图片只在审核通过后可见 + 分页稳定不重复 + 分布同源）
- [x] `harness.config.mjs`（verifier `reviews-f1-rspec`）+ `AGENTS.md` §6 行
- [x] `docs/prd/README.md` 索引 + 本 PRD 状态（done）
- [x] `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml` + `generated:check`（no drift）
- [x] `pallastrade-catalog` / `pallastrade-i18n`（已评估，无需更新：评论域不在 catalog 能力清单；i18n 为文案新增，键齐备由 `checkout-i18n-keys.test.ts` 守护）
- [x] `pallastrade-testing` / `pallastrade-security`（已评估，无需更新：沿用既有 rspec/vitest 约定；上传走既有 `direct_uploads` 授权模型，未引入新凭证面）
- [x] 补充说明：`sync-check` 列出的 `backend/db/migrate/20260916180000_create_pallastrade_payouts.rb` 属并行批次（D13b payout）变更，与本 PRD 无关；本批**无迁移**（图片用 ActiveStorage 内置表）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（Batch F-1：FR-001~010 / AC-001~010；范围=评分分布 + 分页 Load more + 图片评论 ≤3 张；用户已确认三项选择） | AI |
| 2026-09-16 | 1.0 | 用户确认「确认实施」→ 状态 approved（范围：全量三项；分页交互 Load more；图片 ≤3 张） | AI |
| 2026-09-16 | 1.1 | 实施完成 `354b302a`：后端 31 例 + 前台 14 例 + i18n 键 5 语言 + `generated:check` 无漂移；状态 → done | AI |
| 2026-09-16 | 1.2 | CI 修复 `9904f5ad`/`e01d9114`/`fe217fe3`（`"use server"` 常量导出 → 构建失败、Biome 80 列、SDK `dist` 未提交导致镜像类型检查失败）；`d1820ba9` 治理收尾（AGENTS §6 + GS-144 + 4 份 Skill + PRD/README + AC 标记） | AI |
