# PRD-20260915-catalog-batch-c1-discovery

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 《商品升级方案 V1.0》Batch C 切片一（用户授权原话：「那就以此为作为 PRD 理想输入，实施」+「继续」，2026-09-15） |
| 分类 | catalog（前台商品发现） |
| 关联 Skill | pallastrade-storefront / pallastrade-catalog |
| 关联 REQ | REQ-20260915-batch-c1-discovery.md |
| 关联 PRD | 同计划：Batch A = `PRD-20260915-catalog-pdp-state-correctness`；Batch B-1 = `PRD-20260915-admin-bulk-operations-2`；Batch B-2 = `PRD-20260915-admin-catalog-health-v1`；Batch C-2（SKU 级到货订阅）另行立项 |
| 需求类型 | 新功能（前台转化与留存） |

> 🔁 **查重**：`harness prd new` 通过。切片划分：C-1 = Related / Recently Viewed / Wishlist（本 PRD）；C-2 = SKU 级 Back-in-stock（§九，需改事件层 + `variant_id`）。

## 1. 背景与目标

- **背景**（《商品升级方案》§八）：PDP 目前是「交易终点」——审计确认关联推荐、最近浏览、wishlist、similar、bundle 均未实现（本次 6 层搜索复核：`storefront/src/**` 对 `wishlist|recently|related|similar` 零命中），用户看完一个商品后无处可去。
- **目标**：把 PDP 变成**商品发现节点**——① 规则化 Related（同分类 → 在售 → 排除自己 → ≤8）；② 最近浏览（本地 12 条）；③ Wishlist（本地 V1 + 页面 + 头部入口）。**不做推荐算法、不建服务端域模型**（等真实曝光/点击/加购数据后再进算法阶段）。
- **成功指标**：① PDP 稳定渲染 Related（无结果显示整块隐藏，不出现空标题）；② 最近浏览按访问顺序（去重、上限 12、跨路由保持）；③ Wishlist 可加/可移除且页面可用，5 语言键齐备；④ 零新后端 API、零 DB 迁移、零新依赖。

## 2. 用户故事 / 场景

- 作为**顾客**，我在 PDP 底部看到「相关商品」，可以继续浏览同类在售商品而不必回到列表页。
- 作为**顾客**，我回到商店时能看到「最近浏览」区块（本地记录，不需要账号），快速回到刚才看过的商品。
- 作为**顾客**，我点 PDP 的爱心把商品加入 Wishlist，从头部图标进入 `/wishlist` 查看/移除，无需登录。
- 边界：无同分类在售商品 → Related 整块不渲染；localStorage 不可用（隐私模式/配额满）→ 功能静默降级、不抛错、不阻塞渲染；空 wishlist → 空态文案 + 引导去逛商品；商品被删/下架 → 快照仍可展示（点击后由 PDP 的 404/售罄态兜底）。
- 异常：损坏的 localStorage JSON → `parse*` 返回空数组（绝不让脏数据炸页面）。

## 3. 功能需求（FR）

- **FR-001 Related Products（服务端规则推荐）**：PDP 的服务端组件取「同分类（含子分类）+ `in_stock` 在售 + 排除当前商品」的 ≤8 个商品，用既有 Store API 列表接口（`in_categories` / `in_stock`）实现；**不引入算法、不加权重**；结果为空 → 不渲染区块（含标题）。
- **FR-002 最近浏览（本地 12 条）**：客户端把访问过的商品快照写入 `localStorage['pt.recently_viewed']`；按最近访问倒序、按商品 id 去重（重复访问移到最前）、上限 **12**；PDP 展示时**排除当前商品**；跨标签页通过 `storage` 事件同步，同页面通过自定义事件即时刷新。
- **FR-003 Wishlist V1（本地）**：`localStorage['pt.wishlist']`；PDP 爱心按钮切换（`aria-pressed` 反映状态）；上限 100；`/wishlist` 页面列出已存商品 + 移除按钮 + 空态引导；头部新增图标入口（含数量徽章）。
- **FR-004 i18n**：新增文案在 **5 个语言文件**（de/en/es/fr/pl）齐备，并纳入既有 i18n 守护测试（缺键 = 用户可见缺陷）。
- **FR-005 SSR 安全**：所有本地读取发生在 `useEffect`/`mounted` 之后，服务端渲染阶段不读 `localStorage`（避免 hydration 不匹配）；区块在客户端挂载前不渲染空态（避免闪跳）。
- **FR-006 边界**：不动 v3 API / OpenAPI / SDK；无 DB 迁移；无新 npm 依赖；不改动 `view_item`/`add_to_cart` 等既有埋点语义（Related/最近浏览的点击沿用 `ProductCard` 现有 `select_item` 逻辑，`listId` 区分区块）。
- **FR-007 纯函数下沉**：三块能力的状态计算（解析/去重/截断/切换）下沉为纯函数模块（`src/lib/utils/{related-products,recently-viewed,wishlist}.ts`），组件只做读写与渲染——保证可测性与 SSR 安全。

## 4. 非功能需求（NFR）

- **性能**：Related 复用既有缓存列表函数（`cachedListProducts`，10 分钟缓存 + `products` tag）；本地两件套零网络请求；localStorage 单键写入 < 50KB/12 条（快照为商品对象，报价缓存由 PDP 兜底）。
- **兼容**：不改 Header/Cart 现有结构语义（仅追加一个客户端图标按钮）；不影响 PDP 既有区块顺序与埋点。
- **可访问性**：爱心按钮有 `aria-label` + `aria-pressed`；区块有语义标题（`h2`）；最近浏览/愿望清单列表为真实链接。
- **可测试性**：纯函数 100% 单测覆盖；组件测试覆盖「未挂载不渲染 / 挂载后从 localStorage 渲染 / 切换写入」；i18n 守护覆盖 5 语言。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001/FR-007：`buildRelatedQuery` 生成 `in_categories` + `in_stock: true` + `limit+1`；`pickRelated` 排除指定 id 并截断到 limit（不足则原样返回；空数组返回空）。
- AC-002 ← FR-001：`RelatedProducts` 服务端组件在结果为空时不渲染区块（无标题、无容器）。
- AC-003 ← FR-002/FR-007：`pushRecentlyViewed` 去重（同 id 移到最前）、保序、上限 12；`parseRecentlyViewed` 对非法 JSON/错误形状返回 `[]`。
- AC-004 ← FR-002：`RecentlyViewed` 区块挂载后从 localStorage 渲染卡片，排除当前商品；无记录时不渲染。
- AC-005 ← FR-002：`RecentlyViewedTracker` 在挂载时写入当前商品快照（同一商品重复访问不产生重复条目）。
- AC-006 ← FR-003/FR-007：`toggleWishlistItem` 加入/移除并返回新数组；`isWishlisted` 反映状态；`parseWishlist` 对脏数据返回 `[]`；上限 100。
- AC-007 ← FR-003：`WishlistButton` 点击切换 `aria-pressed` 并写入 localStorage（组件测试）。
- AC-008 ← FR-003：`/wishlist` 页面渲染已存商品（含名称与链接），移除后从列表消失；空时渲染空态文案。
- AC-009 ← FR-003：头部心愿单入口存在（含数量徽章，挂载后显示）。
- AC-010 ← FR-004：5 语言文件包含全部新增键（守护测试）。
- AC-011 ← FR-005：服务端渲染阶段不访问 localStorage（组件在未挂载时返回 `null`，测试断言首帧为空）。
- AC-012 ← FR-006：不新增后端接口/迁移——本批 `git diff` 只含 storefront 与文档文件（评审项，由监督 diff 覆盖）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | wishlist / related / recently | 无 | 不适用（零宿主改动） |
| Core | `pallastrade_core/` | in_stock / in_categories / BackInStockSubscription | `product_scopes.rb`（`in_stock` / `in_categories` / `not_discontinued` 等 ransack scopes）、`back_in_stock_subscription.rb`（仅商品级，C-2 处理） | **过滤能力齐备** → Related 无需后端改动 |
| API | `pallastrade_api/` | product list filters | `store/products_controller.rb`（`q[...]` → `search_provider.search_and_filter`）、`search_provider_support.rb`（过滤器解码）、`database.rb`（ransack 应用） | 支持 `in_categories` / `in_stock`，**无需新端点** |
| Admin | `pallastrade_admin/` | wishlist | 无 | 不涉及（本批纯前台） |
| Storefront | `storefront/src/` | wishlist / recently / related | `lib/data/products.ts`（`cachedListProducts` + `PRODUCT_CARD_FIELDS`）、`components/products/{ProductCard,ProductCarousel,FeaturedProducts}.tsx`（可复用卡片/轮播）、`components/layout/{Header,CartButton}.tsx`（头部按钮范式）、`lib/__tests__/checkout-i18n-keys.test.ts`（i18n 守护范式） | **复用为主** → 新增 3 个纯函数模块 + 5 个组件 + 1 个页面 |
| Platform | `platform/packages/` | wishlist | 无 | 不涉及（SDK `ProductListParams` 已含 `in_categories`/`in_stock`，无需改 SDK） |

**结论**：三件套的**数据与组件底座全部现成**（列表过滤 + ProductCard/ProductCarousel + 头部按钮 + i18n 守护），缺口只有「纯函数状态模块 + 区块组件 + wishlist 页面 + 头部入口」。

## 7. 技术影响

- **Storefront（新增）**：
  - `src/lib/utils/related-products.ts`（`buildRelatedQuery` / `pickRelated`）
  - `src/lib/utils/recently-viewed.ts`（常量 + `parse` / `push` / `serialize` + 事件名）
  - `src/lib/utils/wishlist.ts`（常量 + `parse` / `toggle` / `isWishlisted` / `remove` / `serialize` + 事件名）
  - `src/components/products/{RelatedProducts,RecentlyViewed,RecentlyViewedTracker,WishlistButton}.tsx`
  - `src/components/layout/WishlistHeaderButton.tsx`
  - `src/app/[country]/[locale]/(storefront)/wishlist/page.tsx` + `WishlistList.tsx`
- **Storefront（改动）**：
  - `src/lib/data/products.ts`（+`getRelatedProducts`）
  - `src/app/[country]/[locale]/(storefront)/products/[slug]/page.tsx`（渲染 Related / RecentlyViewed / Tracker）
  - `src/app/[country]/[locale]/(storefront)/products/[slug]/ProductDetails.tsx`（+爱心按钮）
  - `src/components/layout/Header.tsx`（+头部入口）
  - `messages/{de,en,es,fr,pl}.json`（新增 `products.relatedTitle` / `products.recentlyViewedTitle` / `wishlist.*`）
  - `src/lib/__tests__/checkout-i18n-keys.test.ts`（REQUIRED 追加新键）
- **测试（新增）**：`src/lib/utils/__tests__/{related-products,recently-viewed,wishlist}.test.ts` + `src/components/products/__tests__/{WishlistButton,RecentlyViewed}.test.tsx`。
- **无 DB 迁移、无 v3 API 变更、无新依赖**。
- **风险**：快照价格可能过期（V1 接受：点击进 PDP 以服务端为准）；隐私模式下 localStorage 抛错 → 全部读写包 try/catch 静默降级；回滚 = revert 提交。

## 8. 测试计划

- 纯函数：`related-products`（query 生成 + 排除自身 + 截断）、`recently-viewed`（去重/保序/上限/脏数据）、`wishlist`（切换/上限/脏数据）。
- 组件：`WishlistButton`（首帧不渲染 → 挂载后可切换并写库）、`RecentlyViewed`（挂载后渲染、排除当前商品、空态不渲染）。
- 守护：`checkout-i18n-keys.test.ts` 追加 `products.relatedTitle` / `products.recentlyViewedTitle` / `wishlist.{title,empty,add,remove,removeAria,viewAll}`。
- 验证器：复用既有 **`storefront-test`**（vitest 全量，自动覆盖新测试）——不新增 verifier，避免额外知识同步负担。
- 手动（可选）：本地浏览器查看 PDP 三块与 `/wishlist` 页面，不作为门禁证据。

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-storefront/SKILL.md`（PDP discovery rails 章节 + 六条约定 + changelog）
- [x] `harness/scenarios/scenarios.json`（GS-132：discovery rails；`harness eval-ai --scenarios` → 133/133 valid）
- [x] `harness.config.mjs`：**复用既有 `storefront-test`**（已评估，无需新 verifier）
- [x] API 文档 / SDK：**已评估，无需更新**（零接口变更）
- [x] 本 PRD 状态 + `docs/prd/README.md` 索引（`prd-status-sync --fix/--check`）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch C-1：FR-001~007 / AC-001~012） | AI |
| 2026-09-15 | 1.0 | 实施完成：纯函数 3 个 + 浏览器存储封装 + 组件 5 个 + `/wishlist` 页 + PDP/Header 接线 + 5 语言 8 键；新增测试 12 文件 85 例全绿（verifier `storefront-test`）；知识同步（storefront Skill + GS-132）→ 状态 done | AI |
