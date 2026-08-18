# PRD-20260818-catalog-p0-4-产品评论

| 元数据 | 值 |
|---|---|
| 状态 | approved（用户 2026-08-18 需求「实施 B3[P0-4 产品评论]」确认） |
| 创建日期 | 2026-08-18 |
| 来源 | 需求：P0-4 产品评论（来自 RESEARCH-20260814 升级路线） |
| 分类 | catalog（自动判定） |
| 关联 Skill | pallastrade-api-v3 / pallastrade-storefront / pallastrade-admin / pallastrade-data-model |
| 关联 REQ | （实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 新功能 |

---

## 1. 背景与目标

- **一句话需求原文**：实施调研路线 P0-4 产品评论/评分。
- **背景**：评论是转化率与信任的关键（Shopify Product Reviews 标配），且评论可进 SEO JSON-LD（AggregateRating）。PallasTrade 已确认**无任何 Review/评分模型**（全新资源）。已有完整客户/订单/序列化/Admin 模板可复用。
- **目标**：评论提交（登录客户）+ 审核（Admin）+ 商品页展示（评分摘要/列表/表单）+ JSON-LD AggregateRating。
- **成功指标**：可提交/审核/展示评论；聚合评分进商品页与 JSON-LD；已购客户带 verified 标记。

## 2. 用户故事 / 场景

- 作为**登录客户**，我购买后可为商品评分并写评论，以便给其他买家参考。
- 作为**运营**，我审核评论（通过/拒绝），以便保证内容质量。
- 作为**访客**，我查看商品评分与评论，以便决策。
- 场景：
  - 正常流：登录→商品页写评论（1-5 星+标题+正文）→ pending→Admin 通过→商品页显示 + 评分聚合 + JSON-LD。
  - 边界：每商品每客户仅一条（唯一约束）；未登录不可提交（401）；已购自动标 verified。
  - 异常：拒绝的评论不展示、不进聚合。

## 3. 功能需求（FR）

- FR-001：`Review` 模型（product、user、rating 1-5、title、body、status[pending/approved/rejected]、verified_purchase、store）；`(product_id, user_id)` 唯一；`SingleStoreResource`。
- FR-002：Store API 只读——`GET /api/v3/store/products/:id/reviews`（approved 列表）；ProductSerializer 暴露 `average_rating`/`review_count`（controller 预载防 N+1）。
- FR-003：Store API 写——`POST /api/v3/store/products/:id/reviews`（`require_authentication!` + current_user；Wishlist 模式）；创建后 status=pending。
- FR-004：Admin 审核页（列表/查看/通过/拒绝/删除；BackInStockSubscriptions 13 处模板）。
- FR-005：Storefront 商品详情页——评分摘要（星星+数量）+ 评论列表 + 评论表单（登录客户；已购标 verified）；`ProductDetails` 挂载。
- FR-006：JSON-LD `AggregateRating`（`buildProductJsonLd` 加 aggregateRating/reviewCount/bestRating:5，仅 approved 聚合）。
- FR-007：SDK `reviews` 方法 + `generated:check` 重新生成类型（AP-007，禁止手改 generated）。
- FR-008：权限注册（`permission_registry.rb` + `permission_sets` 加 reviews）。

## 4. 非功能需求（NFR）

- 安全：未登录不可提交；每商品每客户唯一；审核前不公开。
- 性能：聚合值 controller 预载（joins/aggregate SQL，仿 `UserMethods#with_min_total_spent`）；列表分页。
- 可维护：模型走 `SingleStoreResource`（防跨店泄漏）；API 走 v3 前缀 ID + expand/fields。
- 合规：评论可删除（Admin）；防滥用。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：可创建 Review，唯一约束生效；status 默认 pending。
- AC-002 ← FR-002：approved 评论可通过 Store API 读取；商品 serializer 暴露 average_rating/review_count。
- AC-003 ← FR-003：登录客户可提交；未登录 401；同一客户重复提交被拒。
- AC-004 ← FR-004：Admin 可审批/拒绝/删除；被拒评论不进列表/聚合。
- AC-005 ← FR-005：商品页显示评分摘要 + 列表 + 表单；已购客户带 verified 徽标。
- AC-006 ← FR-006：商品页 JSON-LD 含 aggregateRating（有 approved 评论时）。
- AC-007 ← FR-007：SDK 可调用 reviews 方法；generated 类型一致（generated:check 通过）。
- AC-008 ← FR-008：权限注册后 nav:validate 通过。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | user | `models/pallastrade/user.rb`（host User + UserMethods：completed_orders_for_store） | 复用（verified 判定） |
| Core | `pallastrade_core/app/` | product / single_store | `product.rb`（completed_orders 关联）、`single_store_resource.rb`、`wishlist.rb`（登录客户资源先例）、`back_in_stock_subscription.rb`（13 处注册模板） | **新增 Review 照此** |
| API | `pallastrade_api/app/` | product serializer / back_in_stock | `product_serializer.rb`（expand/attributes）、`store/back_in_stock_subscriptions_controller.rb`（嵌套 create）、`jwt_authentication.rb`（require_authentication!）、routes（嵌套资源先例） | **新增 reviews 端点照此** |
| Admin | `pallastrade_admin/app/` | back_in_stock / products | `back_in_stock_subscriptions`（13 处模板：route/nav/table/permission/locale/factory）、`products_controller.rb` | **新增 reviews 审核页照此** |
| Storefront | `storefront/src/` | products/[slug] / BackInStockNotify / seo | `products/[slug]/page.tsx`、`ProductDetails.tsx`、`BackInStockNotify.tsx`（client 表单先例）、`seo.ts`（buildProductJsonLd 无 aggregateRating）、`cookies.ts`（JWT） | **评论 UI + JSON-LD 挂载** |
| Platform | `platform/packages/` | sdk products / generated | `sdk store-client.ts`（products.get + backInStockSubscriptions.create 先例）、`types/generated/Product.ts`（Typelizer 生成） | **新增 reviews 方法 + 重新生成** |

**结论**：全新 Review 资源，无重复；全链路模板齐备（模型/API/Admin/前台/SDK 均有成熟先例可照抄）。

## 7. 技术影响

- **Core**：迁移 `create_pallastrade_reviews`（product_id/user_id/rating/title/body/status/verified_purchase/store_id，唯一索引）；`Review` 模型 + `Product has_many :reviews`；聚合 scope（average_rating/review_count）。
- **API**：Store routes 嵌套 `resources :reviews, only: [:index, :create]`（products 下）；ReviewSerializer；ProductSerializer 加 average_rating/review_count；`store/reviews_controller.rb`（require_authentication! 写 + 只读 approved 列表）。
- **Admin**：`reviews` 页（index/edit approve/reject/destroy + table + nav + permission + locale + factory）。
- **Storefront**：ProductDetails 下加评分摘要/列表/表单组件（client，仿 BackInStockNotify）；seo.ts 加 aggregateRating。
- **SDK**：store-client 加 `products.reviews.list/create`；`generated:check` 重新生成（Product 类型 + reviews）。
- **API 文档**：`store.yaml` 需同步（新增 /products/:id/reviews 端点）→ `generated:check` + api docs。

## 8. 测试计划

- 新增：`spec/models/pallastrade/review_spec.rb`、`spec/requests/api/v3/store/reviews_spec.rb`、`spec/requests/pallastrade/admin/reviews_spec.rb`、`spec/serializers/.../review_serializer_spec.rb`。
- 更新：Product 聚合测试。
- AC 映射：AC-001~AC-008 → 上述 spec。
- 回归：admin 全量 + API spec + quick check + generated:check。

## 9. 文档同步清单（知识同步门）

- [ ] Skill：`pallastrade-api-v3/SKILL.md`（新增 reviews 端点）、`pallastrade-storefront/SKILL.md`（评论组件 + JSON-LD）、`pallastrade-admin/SKILL.md`（审核页）、`pallastrade-data-model/SKILL.md`（Review 模型）
- [ ] API 文档：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml`（+ SDK 类型 `generated:check`）
- [ ] 场景库：`harness/scenarios/scenarios.json` 新增 GS 场景（评论）
- [ ] 本 PRD 状态 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-18 | 0.1 | 初稿（FR-001~008 / AC-001~008）；基于代码探索 | AI |
