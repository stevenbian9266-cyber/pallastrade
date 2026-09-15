# PRD-20260915-catalog-pdp-state-correctness

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 用户指令：「以《商品升级方案 V1.0》为 PRD 理想输入，实施」（2026-09-15）；系列第一期 = Batch A（PDP 交易状态正确性） |
| 分类 | catalog（关键词命中 3；语义：商品域升级系列，落地位置在 storefront 展示层） |
| 关联 Skill | pallastrade-catalog / pallastrade-storefront |
| 关联 REQ | REQ-20260915-pdp-state-correctness.md |
| 关联 PRD | N/A（全新；上游为 git-ignored 业务方案 `豆包梳理业务需求/商品升级方案.md` + 审计报告 `harness/reviews/REVIEW-20260915-storefront-pdp-admin-products-audit.md`） |
| 需求类型 | 优化迭代 |

> 🔁 **查重**：`harness prd new` 查重通过（未命中相似 PRD）。
> 🔁 **系列切分**：本 PRD 只承载 Batch A；Batch B（后台批量 + Catalog Health）= `PHASE-B-*`、Batch C（推荐/收藏/变体订阅）= `PHASE-C-*`、Batch D（AI/治理）= `PHASE-D-*`，各自独立 PRD 立项。

## 1. 背景与目标

- **一句话需求原文**：以《商品升级方案 V1.0》为输入实施（首切片：PDP 状态正确性）。
- **背景**（全部为 dev HEAD 静态审计事实）：
  1. 变体选择仅存在于客户端 state（`ProductDetails.tsx` 中 `selectedVariant` 为 `useState`）——刷新、分享、广告落地丢失 SKU；GA4 `view_item` 上报默认变体 SKU，与落地 URL 不一致。
  2. 预售语义错误：`Variant#purchasable? = in_stock? || oversellable_now?`（`variant.rb` L664），且 `preorder?` 不改变 `in_stock?`（L646 `total_on_hand.positive?`）→ 预售商品 `purchasable=true` 而 `in_stock=false`，PDP 当前同时渲染「Out of Stock 红字 + 到货订阅表单 + 可点击加购」，业务语义错误。
  3. 结构化数据只输出单个 `Offer`（`lib/seo.ts#buildProductJsonLd` L30）——多 SKU 商品无法表达价格区间；无 brand。
- **目标**：PDP 的「可售状态」永远与后端事实一致（含 SKU 深链可复现、预售/缺货超卖表达正确、多 SKU 结构化数据完整），且不引入任何后端改动。
- **成功指标**：本期建立可测基线（无线上流量基线）：① 带 `?variant=` 链接打开/刷新均锁定同一 SKU；② 预售商品页面不再出现「缺货 + 到货订阅」混合语义（有组件测试守护）；③ 多 SKU 商品 JSON-LD 输出 `AggregateOffer` 且价格区间正确。
- **非目标（本期明确不做）**：SKU 独立 SEO 页面/canonical 改写（PHASE-B 评估）；Low Stock 阈值展示（需新序列化字段，PHASE-B）；配送/时效（PHASE-C）；变体级到货订阅（PHASE-C，事件层改造）；`select_variant` 埋点（PHASE-C）。

## 2. 用户故事 / 场景

- 作为**消费者**，我希望分享/收藏的商品链接精确打开我选的规格，以便复购同款。
- 作为**消费者**，我希望预售商品明确显示「预售 + 预计发货日」并可正常下单，而不是看到「缺货 + 留邮箱」。
- 作为**消费者**，我希望缺货但可超卖的商品明确标为「可订购（延迟发货）」，以便自行决策。
- 作为**投放/运营**，我希望落地页 URL 与 GA4 `view_item` 的 SKU 一致，以便归因与选品分析。
- 边界：无效 `?variant=`（回退默认，不报错）；无变体商品（商品级字段回退）；多币种（价格来自价格表解析后的 `variant.price`）；过期 `preorder_ships_at`（后端已输出 null，前端不展示日期）。
- 异常：旧链接携带已下架变体 ID → 视为无效参数回退。

## 3. 功能需求（FR）

- **FR-001 Variant 深链**：以 `?variant={variant_prefixed_id}` 表达 SKU；服务端读取并作为初始选择传入客户端；选择优先级 = URL 指定（命中 variants 或 default_variant）→ `default_variant` → 首个 `purchasable` → 首个变体。切换 SKU 时静默更新 URL（`router.replace`，`scroll:false`，保留其它查询参数，不新增历史）。GA4 `view_item` 以落地时的变体上报。
- **FR-002 预售/缺货可购语义前台化**：由既有序列化字段推导展示态，优先级 `in_stock` > `preorder`(可购) > `backorder`(可购) > `out_of_stock`；预售显示徽标 + 「Ships by {date}」（`preorder_ships_at` 存在时，按 locale 本地化）；缺货可超卖显示「可订购（延迟发货）」；两者均保持加购/Buy Now 可用且**隐藏**到货订阅表单；不可购（含超卖额度用尽）维持缺货样式 + 订阅表单。有变体用变体字段，无变体用商品级字段。
- **FR-003 多 SKU 结构化数据**：`buildProductJsonLd` 单变体保持 `Offer`；多变体且存在价格 → `AggregateOffer`（lowPrice/highPrice/offerCount/priceCurrency）；availability 映射（单：状态→InStock/PreOrder/BackOrder/OutOfStock；聚合：任一 InStock > 任一 PreOrder > 任一 BackOrder > OutOfStock）；`brand` 取自自定义字段（key = `brand` / `catalog.brand` / `*.brand`，或 label 大小写不敏感为 brand），缺失则省略。
- **FR-004 可维护性与 i18n**：状态推导与 variant 解析抽为纯函数模块（便于表驱动单测）；新增文案键 4 个（`preorder` / `preorderShipsBy` / `backorder` / `backorderNote`）× 5 语言（de/en/es/fr/pl）齐备；零后端/接口/DB 改动；不新增网络请求；`use cache` 缓存策略不变。

## 4. 非功能需求（NFR）

- **兼容**：无 `?variant=` 时行为与现状完全一致；canonical/OG 仍指向商品主 URL。
- **性能**：纯客户端计算，无额外请求；不改变 `PRODUCT_PAGE_EXPAND`（复用 `variants` 展开）。
- **安全**：URL 参数仅用于匹配查找（无注入面）；不新增 HTML 注入点。
- **可访问性**：状态徽标输出可读文本（不仅靠颜色/图标区分）。
- **可测试性**：核心逻辑（选择优先级、状态推导、availability 映射）必须为可导出的纯函数。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：URL 携带有效 `?variant=` → 初始选中该变体（服务端参数经 props 传入）。
- AC-002 ← FR-001：无效/未知 variant → 回退链 `default_variant` → 首个可购 → 首个变体，不报错。
- AC-003 ← FR-001：切换 SKU → `router.replace` 静默更新 `variant` 参数并保留其它查询参数、`scroll:false`。
- AC-004 ← FR-001：GA4 `view_item` 以落地时变体上报（`trackViewItem(product, currency, variant)`）。
- AC-005 ← FR-002：预售可购（`preorder=true, in_stock=false, purchasable=true`）→ 预售徽标 + Ships by 日期；加购可用；**无**到货订阅表单。
- AC-006 ← FR-002：缺货可超卖（`backorderable=true, purchasable=true`）→ 「可订购（延迟发货）」+ 加购可用；无订阅表单。
- AC-007 ← FR-002：不可购（`purchasable=false`）→ 缺货样式 + 到货订阅表单（回归保护）。
- AC-008 ← FR-002：状态优先级 `in_stock > preorder > backorder > out_of_stock`（表驱动）。
- AC-009 ← FR-003：单变体 → `Offer`；多变体 → `AggregateOffer`（lowPrice/highPrice/offerCount/priceCurrency）。
- AC-010 ← FR-003：availability 映射（单值 + 聚合）。
- AC-011 ← FR-003：brand 从自定义字段取值；缺失时省略 `brand` 字段。
- AC-012 ← FR-004：4 个新文案键在 5 个语言文件齐备（守护测试）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | product/variant | 仅生成类型 `javascript/types/serializers/*Product*.ts` | 不适用（无宿主业务代码） |
| Core | `pallastrade_core/app/` | `purchasable?/in_stock?/preorder?` | `variant.rb`（L239/253/646/652/664/676）、`product.rb` 状态机 | **数据齐备**（不改动）：`preorder/preorder_ships_at/backorderable/purchasable` 语义已实现 |
| API | `pallastrade_api/app/` | variant serializer | `v3/variant_serializer.rb`、`v3/product_serializer.rb` | **已输出**全部所需字段（preorder/preorder_ships_at/backorderable/purchasable）→ 无需接口改动 |
| Admin | `pallastrade_admin/app/` | product form | products 表单/控制器 | 不适用（零 admin 改动） |
| Storefront | `storefront/src/` | `variant`/`selectedVariant`/`view_item` | `products/[slug]/{page,ProductDetails}.tsx`、`lib/seo.ts`、`lib/analytics/gtm.ts`（`trackViewItem` 已支持 variant 入参 L168-178） | **部分满足**：无 URL 同步、无预售/超卖语义、单 Offer → 本 PRD 需新建（仅此层） |
| Platform | `platform/packages/` | CustomField/Variant types | `sdk/src/types/generated/{CustomField,Variant,Product}.ts` | 类型齐备（`CustomField.key` 可用于 brand 判定）→ 无 SDK 改动 |

**结论**：仅 storefront 展示层改动；后端 / admin / SDK 零改动；不新增接口 → 无需 OpenAPI/SDK 同步。

## 7. 技术影响

- **改动文件**：
  - `storefront/src/lib/utils/variant-selection.ts`（新增：`resolveInitialVariant` / `deriveAvailabilityState` / `buildVariantHref` / `aggregateAvailability`）
  - `storefront/src/components/products/AvailabilityStatus.tsx`（新增：四态展示组件，收敛 ProductDetails 分支；STD-CQ-001 决策点预算）
  - `storefront/src/app/[country]/(storefront)/products/[slug]/ProductDetails.tsx`（URL 同步 + view_item 传变体 + 组装状态）
  - `storefront/src/app/[country]/(storefront)/products/[slug]/page.tsx`（读取 `searchParams.variant` → `initialVariantId`）
  - `storefront/src/lib/seo.ts`（`buildProductJsonLd` 升级）
  - `storefront/messages/{de,en,es,fr,pl}.json`（+4 键）
- **测试文件**：`lib/utils/__tests__/variant-selection.test.ts`（新）、`products/[slug]/__tests__/ProductDetails.test.tsx`（新）、`lib/__tests__/seo.test.ts`（扩展）、`lib/__tests__/checkout-i18n-keys.test.ts`（扩展 products 命名空间）
- **影响面**：`harness affected --base origin/dev` 实施前输出为 0（HEAD 干净）；实施后以 `git diff` + `doc-impact` 复核。
- **依赖/风险**：无新依赖；组件测试需 mock `next/navigation` 与 `CartContext`（若 mock 不可行则降级为纯函数断言 + 渲染断言并记录）。

## 8. 测试计划

| AC | 测试文件 | 用例要点 |
|---|---|---|
| AC-001/002/008 | `storefront/src/lib/utils/__tests__/variant-selection.test.ts`（新） | 有效/无效/缺省参数的选择链；状态优先级表驱动 |
| AC-003/004/005/006/007 | `storefront/src/app/[country]/(storefront)/products/[slug]/__tests__/ProductDetails.test.tsx`（新） | replace 调用参数；view_item 变体；预售/超卖/缺货三种渲染 |
| AC-009/010/011 | `storefront/src/lib/__tests__/seo.test.ts`（扩展） | Offer vs AggregateOffer；availability 映射；brand 取值/省缺 |
| AC-012 | `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（扩展） | products 命名空间 4 键 × 5 语言齐备 |

- 注册 verifier：`storefront-test`（全量 storefront 套件，自动覆盖新增测试）。
- 手动验证：`pnpm -C storefront typecheck` + biome check（仅本批文件）。

## 9. 文档同步清单（知识同步门）

- [x] Storefront Skill：`ai/skills/pallastrade-storefront/SKILL.md` §Components（PDP 状态语义 / 深链约定 / JSON-LD）——已更新
- [x] 场景库：`harness/scenarios/scenarios.json`（GS-128：PDP availability states + SKU deep link）——已新增
- [ ] 本 PRD 状态流转 + `docs/prd/README.md` 索引（`prd-status-sync`）
- [x] 接口文档：**已评估，无需更新**（零接口改动）
- [x] 反模式库 / 任务规则：**已评估，无需更新**（无新反模式；未改 policies）
- [x] SDK 类型：**已评估，无需更新**（无接口变更）

### 9.1 知识同步门评估（sync-check，2026-09-15）

| 触发资产 | 结论 |
|---|---|
| pallastrade-storefront Skill | 已更新（PDP 状态语义/深链/JSON-LD 条目；BackInStockNotify 触发条件修订） |
| 组件测试 | 已更新（新增 `variant-selection.test.ts` / `ProductDetails.test.tsx`，扩展 `seo.test.ts` / i18n 守护；全量 367 例绿） |
| 场景库（scenarios.json） | 已更新（GS-128；`harness eval-ai --scenarios` 129/129 valid） |
| pallastrade-prd Skill | 已评估，无需更新（流程无变化，本次即按该 Skill 执行） |
| AGENTS.md | 已评估，无需更新（无目录/架构/命令级变更） |
| copilot-instructions.md | 已评估，无需更新（R0–R9 规则无变化） |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿（Batch A 切片：FR-001~004 / AC-001~012） | AI |
| 2026-09-15 | 0.2 | 用户确认（原话：「那就以此为作为 PRD 理想输入，实施」）→ 状态 approved | AI |
| 2026-09-15 | 1.0 | 实施完成：storefront 8 文件（新增 variant-selection 及测试 / ProductDetails / page / seo / 守护测试）+ 5 语言键；全量 363 用例绿 / tsc 0 / locale parity OK；知识同步（Storefront Skill + GS-128）→ 状态 done | AI |
| 2026-09-15 | 1.1 | 监督整改：提取 `AvailabilityStatus` 组件 + 下沉 flags/深链纯函数（STD-CQ-001 决策点预算）并复跑全量测试（367/367 绿） | AI |
