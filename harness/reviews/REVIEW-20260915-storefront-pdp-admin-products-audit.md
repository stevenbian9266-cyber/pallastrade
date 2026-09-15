# REVIEW-20260915 — 商城前台商品详情页（PDP）+ 管理后台商品板块 现状审计与升级方向

> 类型：审计（audit，只读分析 + 报告，零代码改动）
> Task：TASK-20260915085145-93a36ddb（Gate GATE-2026-09-15T08-52-19）
> 日期：2026-09-15 ｜ 基线：dev @ 03e0184f
> 范围：① 商城前台商品详情页（`storefront/src/app/[country]/[locale]/(storefront)/products/[slug]/` + `storefront/src/components/products/`）；② 管理后台商品板块（Rails Admin `pallastrade_admin` 的 Products 命名空间及其供应能力：分类 / 选项 / 库存 / 价目表 / 翻译 / 导入导出 / 评论审核 / 到货订阅）
> 方法：6 层跨层搜索（backend/app → core → api → admin → storefront → platform）+ 领域 Skill（pallastrade-catalog / pallastrade-storefront / pallastrade-admin）+ 关键文件精读；全部为 dev HEAD 静态审计（未做运行时验证）。

---

## 〇、核心结论（速览）

1. **前台 PDP 功能骨架完整、转化增强薄**：媒体画廊（缩略图 / 滑动 / 懒加载灯箱）、变体选择（色板 / 按钮 / 无货划线）、价格（划线价 + 促销标）、库存态、到货通知、Add to Cart + Buy Now、描述 / 自定义字段 / SKU / 选项明细、评论（含提交）、JSON-LD（Product + Breadcrumb）、canonical / hreflang / OG 均已具备。短板集中在：**变体深链缺失、无关联推荐 / 最近浏览 / 收藏、预售不可见、评论无媒体与分页、结构化数据仅单 Offer、无配送预估**。
2. **后台商品板块「框架级完备 + 运营级欠缺」**：Products 顶级菜单下已有 Products List / Price Lists / Stock（Items/Movements/Transfers）/ Translations（覆盖率矩阵 + 抽屉编辑 + 导入导出）/ Categories（三级）/ Options（kind + color_code）；跨模块有 Reviews 审核、Back-in-stock 订阅、Redirects（含 URL 变更看板）。但**批量能力仅限状态 / 分类 / 标签**（`pallastrade_admin_tables.rb` 7 个 bulk action），**无批量价格 / 库存**；**无商品健康度巡检**；**AI（`pallastrade_ai`）零后台 UI 接入**；**到货订阅为商品级**（模型无 `variant_id`）。
3. **模型层远强于界面层**：status 状态机（draft/active/archived + 激活事件）、friendly_id slug 历史（`Product::Slugs`）、ProductPublication 渠道时间窗、preorderable / backorder_limit / preorder_ships_at、价格表（PriceList）、库存预留（P3 StockReservation）、metafields、评论、导入导出 schema、duplicator —— **升级应聚焦「把已有能力暴露到前台 / 运营界面」，而非造新模型**。
4. **与 `docs/research/RESEARCH-20260814-…-shopify-capability-gap…` 路线图对照**：P0-4 评论、P1-11 补货通知、P0-1 SEO（部分：meta 字段 + JSON-LD + 301）、P0-5 图片 CDN（部分：预生成 webp + srcset）已落地；**订阅制（P1-7）、捆绑 / 组合装、商品级 AI、批量编辑矩阵、商品健康度仍缺**，本报告第五节给出落地切片。
5. **测试覆盖薄**：backend 商品相关 spec 仅 3 个文件（`spec/models/pallastrade/product_spec.rb`、`spec/services/pallastrade/product_url_change_spec.rb`、`spec/services/pallastrade/imports/row_processors/product_variant_spec.rb`），**admin / API 商品控制器无 spec**；storefront 有 ProductCard / ProductReviews / BuyNowButton / product-image / seo 单测，**PDP 主组件（ProductDetails / VariantPicker / MediaGallery）无单测**。

---

## 一、盘点方法：6 层跨层搜索命中清单

| 层 | 搜索路径 | 命中（商品域） | 结论 |
|---|---|---|---|
| App（宿主） | `backend/app/` | 仅生成类型 `javascript/types/serializers/PallasTradeApiV3(Admin)Product*.ts` | 宿主层无商品域业务代码，定制在 gem |
| Core | `pallastrade_core/app/` | `models/pallastrade/product.rb`（1034 行）、`variant.rb`（831 行）、`product_publication.rb`、`option_type.rb`、`imports|exports|import_schemas/products.rb`、`services/pallastrade/products/{prepare_nested_attributes,duplicator,auto_match_taxons}.rb`、`back_in_stock_subscription.rb`、`reviews`、`product_scopes.rb`、`search_provider` | 商品域主战场：模型 / 服务 / 导入导出全在此 |
| API | `pallastrade_api/app/` | `store/products_controller`、`admin/products_controller`（bulk + clone）、`v3/product_serializer`（151 行）、`v3/admin/product_serializer`、11 个 product_filter* 序列化器 | Store/Admin 双面齐备；bulk API 是后台批量编辑的现成范式 |
| Admin | `pallastrade_admin/app/` | `products_controller.rb`（328 行）+ `views/…/products/*`（index/new/edit + form 9 个分区）、`variants_form_controller.js`、`reviews_controller.rb`、`product_translations_controller.rb`、`price_list_products_controller.rb`、`redirects_controller.rb`（URL 变更看板）、`assets_controller.rb`（variant_ids 分配） | 页面矩阵完整；运营级批量 / 巡检缺 |
| Storefront | `storefront/src/` | `app/…/products/[slug]/{page,ProductDetails}.tsx`、`components/products/*`（21 个）、`lib/{seo,metadata/product,data/{products,cached,reviews},utils/product-query}.ts` | PDP 组件齐； merchandising 组件（related / 收藏）为零 |
| Platform | `platform/packages/` | `sdk` 生成类型与 zod（Product / ProductPublication / ProductFilters）、`cli` 插件模板 product-card（`.tt`） | 仓库内无 dashboard/admin-sdk 运行代码；SDK 类型已覆盖商品面 |

> 领域 Skill 已读：`ai/skills/pallastrade-catalog`（商品图谱 / 媒体 / 搜索）、`pallastrade-storefront`（PDP / SEO / 组件约定）、`pallastrade-admin`（后台表格 / 导航 / 注入点；发现一处文档漂移见 §六）。

---

## 二、商城前台商品详情页（PDP）现状

### 2.1 页面组装（文件级）

| 文件 | 职责 |
|---|---|
| `products/[slug]/page.tsx` | 服务端：`getCachedProduct(slug, PRODUCT_PAGE_EXPAND)`、canonical + hreflang、Product / Breadcrumb JSON-LD、面包屑（依赖 `?category_id|首个分类`）、拉取审核通过的评论 + 登录态 |
| `products/[slug]/ProductDetails.tsx` | 客户端主组件：媒体画廊、价格、库存、变体选择、数量、加购、Buy Now、描述（HTML）、自定义字段、SKU/选项明细、评论区 |
| `components/products/VariantPicker.tsx` | 选项渲染：`color_swatch` 色板（支持 `color_code` / `image_url` 背景）与按钮两种形态；不可选 / 不可购（划线）态 |
| `components/products/MediaGallery.tsx` + `MediaLightbox.tsx` | 主图 + 缩略图 + 触摸滑动切换（阈值 50px）+ 懒加载灯箱；srcSet（预生成 webp 多尺寸）；10×10 模糊占位 |
| `components/products/BackInStockNotify.tsx` | 缺货时邮箱订阅（**商品级**，见 §2.5-3） |
| `components/products/BuyNowButton.tsx` | P5 快捷下单：独立 cart → 直达 `/checkout/{cart.id}`，不污染购物车 |
| `components/products/ProductReviews.tsx` | 评分摘要（星 + 数量）+ 评论列表（已购验证徽标/日期）+ 登录用户提交表单 |
| `components/products/ProductCustomFields.tsx` | metafields 展示（boolean / json / rich_text / 文本 / 数字） |

### 2.2 数据面

- **展开参数**（`lib/data/cached.ts` → `PRODUCT_PAGE_EXPAND`）：`variants, media, option_types, custom_fields, categories.ancestors`；列表页用 `PRODUCT_CARD_FIELDS`（10 字段稀疏取数，压缩缓存与流式负载）。
- **缓存**：`"use cache: remote"` + `cacheLife("tenMinutes")` + `cacheTag("products", "product:{slug}")`；**按用户 JWT 分段**（登录用户可看 B2B / 会员价）。
- **价格语义**：`price` 为价格表解析后的计算价，`original_price` 仅当与基础价不同（划线）时返回；处理了 `compare_at` 与促销划线并存的分支。
- **库存 / 可购**：`purchasable / in_stock / backorderable / available / preorder` 由 Store 序列化器输出；PDP 使用 `purchasable` 门控按钮、`in_stock` 门控缺货 UI。
- **评论聚合**：`average_rating / review_count` 由序列化器直接带出（仅 approved 计入），JSON-LD 与 UI 复用。

### 2.3 SEO / 结构化数据（`lib/seo.ts`）

- `buildProductJsonLd`（L30）：`Product`（name / description / sku / image[] / **单个 Offer** / `aggregateRating`），OpenGraph og_image 支持 `og_image_url`（1200×630）。
- `buildBreadcrumbJsonLd`（L90）：Home → 分类祖先 → 分类 → 商品。
- metadata（`lib/metadata/product.ts`）：`meta_title / meta_description / meta_keywords`、description 回退 `stripHtml` 截 160、canonical + hreflang alternates、`product:price:*` OG 扩展。

### 2.4 交互能力清单

| 能力 | 实现 | 评价 |
|---|---|---|
| 变体选择 | 客户端 `useState`；不可购值划线、缺货值禁用 | 可用；**未与 URL 同步** |
| 加购 | `CartContext.addItem`（服务端 action），失败 toast | 可用；数量无上限（后端兜底） |
| Buy Now | 独立 cart → 统一 checkout | 亮点（P5） |
| 到货通知 | 商品级邮箱订阅 | 缺变体粒度（§2.5-3） |
| 评论提交 | 登录 + 服务端 action；商家审核后可见 | 可用；无图片评论 |
| 分析埋点 | `trackViewItem / trackAddToCart / trackSelectItem`（GTM） | 齐备 |
| 无障碍 | `aria-label`（缩放按钮、星级）、`role="status"`（通知成功） | 基线以上 |

### 2.5 缺口清单（PDP）

1. **变体深链缺失（P1）**：`selectedVariant` 仅组件内 state，刷新 / 分享 / 广告落地丢变体；无 `?variant=` 约定，canonical 恒指向主商品 URL（SKU 级 SEO 与投放一致性受损）。
2. **预售能力不可见（P1）**：后台已支持 `preorderable / preorder_ships_at / backorder_limit`，序列化器已输出 `preorder / preorder_ships_at`，但 PDP **无任何预售徽标、预计发货时间或文案**——预售商品会落入「缺货 + 订阅」错误语义。
3. **到货通知为商品级（P1）**：`BackInStockSubscription` 仅 `belongs_to :product`（模型注释写「variant」，schema 无 `variant_id`）；多规格商品无法按变体精准通知，且前台订阅后无「已订阅」态回显。
4. **评论深度不足（P2）**：无图片 / 视频、无评分分布直方图、无分页 / 排序、「有用」投票；后台仅逐条 approve / reject。
5. **无关联推荐 / 最近浏览 / 收藏 / 对比（P1）**：全站 grep（recommend / related / recently_viewed / wishlist / similar / bundle）零命中；PDP 是流量终点而非枢纽。
6. **结构化数据单 Offer（P1）**：多规格商品仅输出默认变体的 price / availability；缺 `priceValidUntil`、`itemCondition`、`seller`、`shippingDetails`、`hasMerchantReturnPolicy`；无 `brand`（无 Brand 模型，catalog skill 建议用 metafield 或生成器补）。
7. **配送 / 时效信息缺失（P2）**：PDP 无运费预估、免邮门槛提示、预计到达时间。
8. **富文本渲染无 sanitize 白名单（P2）**：描述与 `rich_text` 自定义字段走 `dangerouslySetInnerHTML`（注释声明来源可信）；建议加服务端 sanitize（深度防御 + 防商家误贴第三方脚本）。
9. **数量上限 / 库存联动缺失（P2）**：`QuantityPicker` 仅下限 1，无按变体可售数上限与「仅剩 N 件」阈值化提示。
10. **面包屑依赖分类（P3）**：无分类商品（`categories` 空）时无面包屑与 Breadcrumb JSON-LD；`?category_id` 参数是唯一上下文。

### 2.6 亮点（应保持）

- 缓存策略（remote cache + per-user 分段 + 标签失效）、稀疏字段列表取数、预生成 webp srcSet（不回炉 Next 优化器）、懒加载灯箱、`use cache` 与超时降级（8s fetch timeout）约定明确。
- 价格模型统一（价格表解析 + 划线原始价），`average_rating` 字符串陷阱已在 Skill 记录并有防护。
- GTM 三事件 + 评论聚合随序列化下发，前端零额外请求。

---

## 三、管理后台商品板块现状

### 3.1 菜单结构（`pallastrade_admin_navigation.rb:145`）

| 层级 | 项 | 说明 |
|---|---|---|
| 一级 | **Products**（icon: package, position 30, 顶级落地 = Products List） | 可管理 `PallasTrade::Product` 时可见 |
| 二级 | Products List / **Price Lists** / **Stock**（tabs：Items / Movements / Transfers）/ **Translations** / **Categories**（taxonomies+taxons）/ **Options**（option types+values） | 均有权限门控 |
| 顶级叶子 | **Reviews**（:626）、**Back in Stock Subscriptions**（:608）、Abandoned Cart Notifications（:617） | 跨模块承载商品域数据 |

### 3.2 商品列表页（`products/index.html.erb` + `pallastrade_admin_tables.rb:15`）

- **列（11）**：name、status、inventory、sku、price、created_at、updated_at、in_stock、taxons、tags、channels。
- **批量动作（7）**：`set_active / set_draft / set_archived / add_to_taxons / remove_from_taxons / add_tags / remove_tags`（`tables.rb:145-200`；表单仅 `_tag_picker` / `_taxon_picker` 两种——**无价格 / 库存 / 渠道批量**）。
- **导入**：`Imports::Products`（38 字段 schema：slug/sku/name/price/SEO/尺寸重量/库存/图 1-3/option1-3/category1-3）经 drawer 导入；**导出**：`Exports::Products`（含 export modal）。
- **检索**：`search_param :search`（模型 `search` scope：按变体名 / SKU 反查）；SPA / turbo autocomplete `search` action（`products_controller#search`，≥3 字符）。
- **URL 变更看板**：实测位于 **Developers → Redirects** 页（`redirects_controller.rb:14`、`redirects/index.html.erb:15`），非 products index（见 §六 文档漂移）。
- 每行有外部预览链接（`external_page_preview_link`，`products/edit.html.erb:11`）。

### 3.3 商品编辑页分区（`products/_form.html.erb`）

| 分区 | 能力 | 关键实现 |
|---|---|---|
| 分类（PALLAS-CUSTOM） | **三级级联下拉**（一级必填，写入 `product[taxon_ids][]` 单个手工分类） | `form/_categorization.html.erb`（category-cascade JS + name/children map JSON） |
| 基础 | 名称（必填）+ Trix 富文本描述（`pallastrade-rte`） | `form/_base.html.erb` |
| 媒体 | 共享媒体表单：排序（sortable）、多文件上传（Uppy 直传 OSS）、批量删除 | `shared/_media_form.html.erb` + `assets_controller`（资产编辑支持 **variant_ids 分配**） |
| 价格 | master / 变体价格（按币种，价格表价格另算） | `variants/form/pricing` |
| 变体矩阵 | 选项创建器（拖拽排序、新建 option/value）+ 变体表格（缩略图 / 价格 / 库存 / 删除） | `form/_variants.html.erb` + `variants_form_controller.js` |
| 库存 | track_inventory、**preorderable / preorder_ships_at / backorder_limit**、按库存点数量 + 缺货继续售卖、SKU / 条码 | `form/_inventory.html.erb` |
| 状态 / 发布 | status（draft/active/archived，`activate` 权限门控）＋ 每渠道发布窗口（published_at / unpublished_at，店铺时区） | `form/_status.html.erb`、`form/_publishing.html.erb` + `product_publishing_controller.js` |
| 运费 / 税 | shipping category、tax category | `_shipping` / `_tax` |
| SEO（侧栏） | meta title / description / slug + 实时预览 + 来源同步（Trix 描述） | `shared/_seo.html.erb` + `seo-form` JS |
| 注入点 | `product_form_partials` / `product_form_sidebar_partials` / `products_actions|header_partials` | 扩展友好 |

### 3.4 变体矩阵与保存防护（服务端）

- `products_controller#load_variants_data`：装配 `@product_options / @product_available_options / @product_stock / @product_prices / @product_variant_ids|prefix_ids|images`（一次性 JSON 注入 JS，避免 N 次请求）。
- `PallasTrade::Products::PrepareNestedAttributes`：变体删除 **opt-in**（只销毁 `removed_variant_ids` 明列的），价格 / 库存 / 发布权限逐项裁剪，空表单不能静默删变体；有已完成订单的变体转 **discontinue**（`update` 前置 `variants_to_discontinue`）。
- `slug` 唯一化兜底（`ensure_slug_is_unique`）、空白 slug 回滚（`slug_was`）、时区时间解析（`available_on / discontinue_on / make_active_at / preorder_ships_at`）。
- 克隆：`products_controller#clone` → `PallasTrade::Products::Duplicator`（`product.rb:526`）。

### 3.5 API 面

- Store：`store/products_controller`（slug 或 `prod_` 前缀 ID、locale 回退、`available(currency, include_preorderable)`、search provider 过滤排序分页）；序列化器含 review 聚合、`prior_price`（EU Omnibus）等 expand。
- Admin：`admin/products_controller` scoped_resource + **bulk API**（`bulk_status_update / bulk_add|remove_to_categories / bulk_add|remove_from_channels / bulk_destroy`，`require_ids!` + 权限隔离）+ `clone`；admin 序列化器增加 status / metadata / tax_category_id / price / deleted_at / 时间戳与全量 expand（含 channels、product_publications）。

### 3.6 缺口清单（后台）

1. **批量编辑矩阵缺失（P1）**：批量仅状态 / 分类 / 标签；**价格、库存、渠道、媒体**均无批量入口（Admin API 已有 channels/categories bulk，Rails Admin 层未消费）。
2. **无商品健康度 / 质量巡检（P1）**：无缺图 / 缺描述 / 缺 SEO / 缺翻译 / URL 变更未处理 / 有销量零库存等聚合视图（数据源已全部存在，见 §五 U4）。
3. **AI 零接入（P1）**：`pallastrade_ai` gem 已具备 provider 网关（OpenAI / DeepSeek）、capability registry、runs / artifacts、Admin AI API 控制器；**Admin UI（Rails）零引用**——商品文案 / 翻译用不上。
4. **到货订阅商品级（P1）**：同 §2.5-3，后台列表视图也无法按变体筛选 / 通知。
5. **库存预留不可见（P2）**：`StockReservation` 仅在交易详情页展示（`transactions/show.html.erb`）；商品 / 变体库存页看不到「已预留 / 可售」拆分（与 P3 库存语义升级衔接的短板）。
6. **无商品级变更时间线（P2）**：全局 Audits 页存在（:543），但商品详情页无字段级 diff / 操作时间线。
7. **无 focal_point 编辑（P2）**：模型支持 `focal_point`（catalog skill），admin 层 grep 零命中——营销裁切需回媒体模型层操作。
8. **媒体类型受限感知（P3）**：产品媒体模型含 `video / external_video`（URL 型），后台媒体表单为图片上传形态为主（未提供视频 URL 录入 UI 的迹象），catalog skill 宣称的视频能力在后台无落地入口（**待实施时二次验证**）。
9. **草稿审核 / 协作流缺失（P3）**：有 `:activate` 权限（草稿→上架门控），但无评论 / 指派 / 审批记录（大团队场景）。

### 3.7 亮点（应保持）

- 三级分类级联为团队自研（PALLAS-CUSTOM），直接服务中文电商运营习惯。
- 渠道发布窗口（含店铺时区提示、徽标状态）在同级开源框架里属于高配。
- SEO 面板带实时预览与会话内字段同步；slug 历史 + Redirects 看板闭环 301。
- 变体矩阵全量数据一次性注入 + opt-in 删除 + 权限裁剪，破坏性操作防护到位。
- 翻译矩阵（覆盖率 + 抽屉编辑 + 双向导入导出）已闭环。
- Admin/Store 双序列化器 + bulk API 为后续批量功能提供了现成协议范式。

---

## 四、对标分析（产品管理知识视角）

| 维度 | PallasTrade 现状 | 业界基线（Shopify 等） | 差距 |
|---|---|---|---|
| 商品信息结构 | metafields + 自定义字段展示；无 Brand / 规格表结构 | metafields 全链 + 规格 / 尺码表组件 | 中 |
| 媒体 | 图（webp 多尺寸）+ 排序 + variant 分配；无 focal_point 编辑 / 视频 UI | 焦点裁切、视频、3D、批量 alt | 中 |
| 变体 | 矩阵编辑器 + 选项 kind（色板 / 按钮）+ 每变体价 / 库存 / 图 | 同左 + 变体级条形码 / 成本 / 重量 | 小 |
| 定价 | 多币种 + 价格表（B2B）+ compare_at + prior_price | 同左 + 营销价日历 / A/B | 小 |
| 库存 | 库存点 / 移动 / 转储 + 预留（预留不可视） | 可售 = 现存 − 预留 的运营视图 | 中 |
| 渠道 | 时间窗发布 + 批量 channels API | 多渠道 + 渠道级内容差异 | 小 / 中 |
| 内容 / SEO | meta 字段 + JSON-LD + 301 + hreflang | 单 Offer → 多 Offer / 政策字段 | 中 |
| UGC | 评论（审核 + 已购验证） | 图片评论、评分分布、Q&A | 中 |
| 转化增强 | Buy Now / 到货通知（商品级） | 关联推荐、收藏、对比、套装、变体级通知 | 大 |
| 运营效率 | 导入导出 38 字段 + 批量（状态 / 分类 / 标签） | 批量矩阵（价 / 存 / 内容）、保存视图、巡检 | 大 |
| AI | 网关与能力注册中心就绪，UI 零接入 | 文案 / 翻译 / 图像 / 客服全链 | 大（低成本可追） |
| 国际化 | 翻译矩阵 + 导入导出 | AI 初翻 + 术语表 + 店级覆盖 | 小 / 中 |
| 数据治理 | 无重复检测 / 合并 / 健康度 | 产品合并、健康度评分 | 大 |

**与 `RESEARCH-20260814` 路线图的衔接**：该路线图的 P0-4 / P1-11 / 部分 P0-1 / P0-5 已落地；本报告第五节在其未完成项（订阅制、AI、批量运营）之外，补充「PDP 转化增强 + 商品运营效率」两组更贴近商品域自身的切片，且全部给出代码级切入点。

---

## 五、升级方向（按优先级，含代码级切入点）

> 约定：每项给出「现状证据 → 目标 → 切入点 → 依赖」；估算为开发量级（人日），不含评审 / 回归。

### P0 — 直接拉动转化或运营效率（建议先行）

**U1. 变体深链（PDP URL 与状态同步）** — 1–2 人日
- 现状：`ProductDetails.tsx` 中 `selectedVariant` 为本地 `useState`；刷新 / 分享 / 广告落地丢失变体。
- 目标：`/products/{slug}?variant={variant_id}` 双向同步（初始从 searchParams 预选、切换时 `router.replace` 静默更新）；文案 / 结构化数据跟随所选变体；canonical 维持主 URL（或按策略给变体页）。
- 切入点：`storefront/src/app/…/products/[slug]/ProductDetails.tsx`、`page.tsx`（读取 searchParams 传入）；SKU 埋点沿用 `trackViewItem`。

**U2. JSON-LD / 结构化数据升级** — 1–2 人日
- 现状：`buildProductJsonLd` 仅输出单 Offer（默认变体），缺政策与销售期字段；无 brand。
- 目标：多规格用 `AggregateOffer`（lowPrice/highPrice/offerCount）或每变体 Offer；补 `priceValidUntil`、`itemCondition`、`seller`、`shippingDetails`、`hasMerchantReturnPolicy`；brand 用 metafield（`catalog.brand`）先落地（后续再评估 Brand 模型）。
- 切入点：`storefront/src/lib/seo.ts#buildProductJsonLd`；Store 序列化器如缺字段（如 `available_on` 已输出）追加 expand（`prior_price` 类似范式）。

**U3. 后台批量编辑扩展（价格 / 库存 / 渠道 / 媒体）** — 3–5 人日
- 现状：`tables.rb:145-200` 仅 7 个 bulk action；表单仅 tag / taxon picker；但 Admin API 已有 `bulk_add|remove_to_channels`、`bulk_add|remove_to_categories`、`bulk_status_update` 现成范式。
- 目标：① 新增 `set_price` / `adjust_inventory` / `add_to_channels` / `remove_from_channels` bulk action + 对应 form partial；② 大集合走 Api 批量端点（可选：Rails Admin 直接复用 `BulkOperationsConcern`）。
- 切入点：`pallastrade_admin_tables.rb`、`bulk_operations/forms/*`、`accepted` 参数由 `products_controller` 扩展（模式同 `bulk_status_update`）；权限：价格 / 库存需对齐 `PermissionSets::ProductManagement`。

**U4. 商品健康度巡检面板** — 2–4 人日
- 现状：数据全有、视图全无——`ProductUrlChange`（Redirects 页）、翻译覆盖率（Translations 页）、产品校验（name / price / shipping_category）、库存与状态。
- 目标：Admin 新品页「Catalog Health」：缺图 / 缺描述 / 缺 SEO 字段 / 缺翻译 / URL 变更未处理 / active 且零库存 / draft 超期 等分组清单 + 一键跳转编辑（可逐步加「AI 一键补全」联动 U5）。
- 切入点：新控制器 + 复用 `rendered tables`（`PallasTrade.admin.tables.register`）；查询放 core（避免 N+1，使用 `not_archived` 等既有 scope）。

**U5. AI 商品内容助手（接入 `pallastrade_ai`）** — 3–5 人日
- 现状：`pallastrade_ai` 提供 provider 网关（OpenAI / DeepSeek）、capability registry、runs / artifacts、限流与 usage 统计、Admin AI API 控制器；Rails Admin **零引用**。
- 目标：① 商品表单描述 / SEO 字段旁加「AI 生成 / 润色」按钮（调用 AI Admin API，结果落 artifact 后回填，人工确认后保存）；② 翻译矩阵页「批量初翻」；③ 运营侧成本可见（usage）。
- 切入点：`pallastrade_ai/app/controllers/pallastrade/api/v3/admin/ai/**`（后端已就绪）；Admin 层新增 Stimulus controller 调用；权限集 `pallastrade/ai/permission_sets.rb` 复用。

### P1 — 体验与留存

**U6. 变体级到货订阅** — 2–3 人日
- 现状：`BackInStockSubscription` 无 `variant_id`（模型注释与 schema 不一致）。
- 目标：模型加 `variant` 关联（可选，兼容商品级）；前台按所选变体订阅 + 「已订阅」态；补货事件带变体粒度通知；后台列表按变体筛选。
- 切入点：新迁移 + `back_in_stock_subscription.rb`、`Store API` 订阅端点、`BackInStockNotify.tsx`；事件负载与邮件模板（`pallastrade_emails` 已有 back_in_stock 场景）。

**U7. PDP 关联推荐 / 最近浏览 / 收藏** — 3–5 人日
- 现状：grep 零命中；PDP 无任何商品间跳转模块。
- 目标：① 服务端「同类推荐」（同分类 / 同标签，`products.list` 过滤 + 排除自身）；② 客户端「最近浏览」（cookie / localStorage）；③ 收藏（登录用户走 customer API 或先用本地）。
- 切入点：`components/products/` 新组件 + `lib/data/products.ts`；列表页已有筛选 / 排序基建可复用。

**U8. 评论体系增强** — 3–5 人日
- 现状：评论仅文本 + 星级（`verified_purchase` 已有）；后台逐条审核。
- 目标：图片评论（ActiveStorage 直传）、评分分布直方图、分页 / 排序、「有用」投票；后台批量 approve / reject。
- 切入点：`Review` 模型 + `reviews_controller.rb` + `ProductReviews.tsx`；序列化器聚合字段扩展（`rating_histogram`）。

**U9. 预售 / 缺货销售前台化** — 1–2 人日
- 现状：后台 `preorderable / preorder_ships_at / backorder_limit` 齐备，序列化器已输出 `preorder / preorder_ships_at`；PDP 无展示。
- 目标：预售徽标 + 预计发货文案（所选变体粒度）；backorder 商品在缺货时不显示「订阅」而显示「可继续购买」语义。
- 切入点：`ProductDetails.tsx`（使用已有字段，零后端改动）。

**U10. 库存透明度与配送预估** — 2–4 人日
- 现状：仅二值 in_stock；无稀缺提示、无运费 / 时效预估。
- 目标：阈值化「仅剩 N 件」（示例：≤5，注意与防爬平衡）；PDP 免邮门槛 / 运费预估（按 Market + shipping methods 估算）。
- 切入点：Store 序列化器按需暴露可售数（需与后端商定阈值策略）；`components/products/` 新组件。

**U11. 媒体增强（focal_point / 视频 / 批量 alt）** — 2–4 人日
- 现状：媒体模型支持 focal_point 与 video / external_video（catalog skill），后台无 focal_point 编辑（grep 零命中）。
- 目标：资产编辑页加 focal point 选择器；视频 URL 录入（如模型已就绪则纯 UI）；alt / 文件名批量编辑。
- 切入点：`pallastrade_admin/app/views/pallastrade/admin/assets/edit.html.erb` + `assets_controller`（variant_ids 分配已是同页范式）。

### P2 — 平台化与治理

**U12. 陈列 / 精选后台化** — 2–3 人日
- 现状：首页精选 = `products.list({ limit: 8 })`（无精选标记 / 排序参数，运营不可控）。
- 目标：精选集合（手动排序 / 定时上下架）或最小方案「featured 标记 + 排序字段」；前台 `FeaturedProducts` 改为精选取数。
- 切入点：metafield 方案零迁移；`FeaturedProducts.tsx` + 新查询参数。

**U13. 捆绑 / 组合装与订阅制** — 5–10 人日（新模型）
- 现状：路线图 P1-7 仍未落地；无 Bundle / Subscription 模型。
- 目标：Bundle（父子行项目展开与库存联动）、订阅（周期订单 + 支付方式 token 化）——建议各自独立 PRD 立项。
- 切入点：`pallastrade_core` 新模型 + 订单链路集成（与 P0–P7 交易编排衔接）。

**U14. 商品级变更时间线** — 2–3 人日
- 现状：全局 Audits 页存在；商品页无时间线。
- 目标：商品详情页「历史」抽屉（字段级 diff：价格 / 状态 / 库存关键变更）。
- 切入点：`Audited` 数据 + 新 partial 挂 `product_form_sidebar_partials` 注入点。

**U15. 渠道批量发布（Rails Admin 层）** — 1–2 人日
- 现状：Admin API 有 channels bulk；Rails Admin bulk 无 channels。
- 目标：列表页「Add to channels / Remove from channels」bulk action。
- 切入点：`tables.rb` + 新 form partial（channel picker，模式同 `_taxon_picker`）。

**U16. 商品数据治理（重复检测 / 合并）** — 5+ 人日
- 现状：无重复检测 / 合并工具；导入 upsert 依赖 slug / sku 约束。
- 目标：相似商品报告（名称 / SKU 模糊）、合并向导（变体重挂 + 301 + 评论迁移）。
- 切入点：core 服务 + Admin 任务页；属于数据治理专项，建议后排。

---

## 六、验证与局限

- 本报告为**静态审计**：未运行测试、未启动应用；所有行为结论基于 dev HEAD（`03e0184f`）的源码阅读，运行时表现（如加购超库存的错误文案）未实测。
- 已发现一处**文档漂移**：`ai/skills/pallastrade-admin/SKILL.md` L95 记载「URL 变更表在 Products index 页」，实测位于 **Developers → Redirects**（`redirects_controller.rb:14`、`redirects/index.html.erb:15`）；建议后续文档同步修订（本任务不动该文件）。
- 两项结论标注「待二次验证」：① 媒体表单对 `video / external_video` 的后台录入 UI；② `Review` 模型是否已有图片附件位（实施 U8 前需复核迁移）。
- 工作区存在并行会话的未提交文件（支付 D1 批次），本审计未触碰、未提交；报告文件为本次任务唯一产物。

## 七、附：关键文件索引

| 域 | 文件 |
|---|---|
| PDP | `storefront/src/app/[country]/[locale]/(storefront)/products/[slug]/{page,ProductDetails}.tsx`、`components/products/{VariantPicker,MediaGallery,MediaLightbox,ProductReviews,BackInStockNotify,BuyNowButton,ProductCustomFields}.tsx`、`lib/{seo.ts,metadata/product.ts,data/{products,cached,reviews}.ts}` |
| Admin | `pallastrade_admin/app/controllers/pallastrade/admin/{products,reviews,product_translations,price_list_products,redirects,assets}_controller.rb`、`app/views/pallastrade/admin/products/**`、`config/initializers/pallastrade_admin_{navigation,tables}.rb`、`app/javascript/pallastrade/admin/controllers/{variants_form,product_form,product_publishing}_controller.js` |
| Core | `pallastrade_core/app/models/pallastrade/{product,variant,product_publication,option_type,back_in_stock_subscription}.rb`、`services/pallastrade/products/{prepare_nested_attributes,duplicator}.rb`、`import_schemas/products.rb` |
| API | `pallastrade_api/app/controllers/pallastrade/api/v3/{store,admin}/products_controller.rb`、`app/serializers/pallastrade/api/v3/{product_serializer.rb,admin/product_serializer.rb}` |
| AI | `pallastrade_ai/app/controllers/pallastrade/api/v3/admin/ai/**`、`app/models/pallastrade/ai/**` |

---

*本文档为审计 / 路线建议，不构成代码变更。各升级项需单独 PRD 立项并经 gate 流程实施。*
