# PRD-20260917-catalog-json-ld-phase2

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 一句话需求「实施 B1 JSON-LD 第二阶段（3/4 字段）」← `豆包梳理业务需求/商品升级方案.md` §4.3（line 188） |
| 分类 | catalog |
| 关联 Skill | pallastrade-storefront、pallastrade-api-v3、pallastrade-pricing |
| 关联 REQ | REQ-20260917-catalog-json-ld-phase2.md（实施时回填） |
| 关联 PRD | PRD-20260814-catalog-seo-深度增强-商品-分类级元数据-json-ld-301-重定向（JSON-LD 一期，done）；PRD-20260915-catalog-pdp-state-correctness（Offer/AggregateOffer 口径来源） |
| 需求类型 | 优化迭代 |

> ⚠️ **为何 `--force` 新建而非回写**：`prd new` 命中「关联 PRD」中的 SEO PRD（相似度 33%）。但该 PRD 的交付范围是 **301 重定向**，其「范围修正」已记录「JSON-LD 早已实现」并已 `done` 关闭；本期是方案原文点名的**第二阶段**（新增 4 个 schema 字段，其中 3 个在本期做），属独立交付批次。项目惯例：同主题不同批次分开建档（参考 `PRD-20260916-catalog-ai-acceptance-audit.md` 与 `PRD-20260917-catalog-ai-edited-before-save.md` 两份相邻 PRD）。上游关系已在「关联 PRD」登记。

## 1. 背景与目标

- **一句话需求原文**：「实施 B1 JSON-LD 第二阶段（3/4 字段）」
- **背景**：JSON-LD 一期已交付并在线 —— Product / BreadcrumbList / ItemList / Organization 四种 schema；`brand` 取商家自定义字段（`catalog.brand` / `brand` / `*.brand`，缺失即省略）；`aggregateRating` 仅统计已审核评论；`Offer`（单 SKU）/ `AggregateOffer`（多 SKU，取最有利可用性）由 `PRD-20260915-catalog-pdp-state-correctness` AC-009/AC-010 定义。方案 §4.3 把 `shippingDetails` / `hasMerchantReturnPolicy` / `seller` / `priceValidUntil` 列为**第二阶段**。本期做其中 3 个。
- **目标**：让 PDP 的结构化数据具备「**谁在卖** / **价格何时有效** / **运费与时效**」三件事，提升富媒体摘要（rich result）的命中率与准确性。
- **成功指标**：
  1. PDP 输出的 JSON-LD 在上述三个字段上有值（数据具备时），且**不新增任何网络请求**（复用 PDP 已获取的运费估算）；
  2. 数据缺失时字段**不存在**（非 `null`、非空对象）—— 沿用 `findBrandName` 既有约定；
  3. 一期字段（brand / aggregateRating / availability / Offer / AggregateOffer）**零行为变化**，现有 spec 全绿。

## 2. 用户故事 / 场景

- 作为**搜索引擎**，我希望从商品结构化数据里读到「谁在卖、价格有效期、运费与时效」，以便展示准确的商家与配送信息，而不是留空或猜。
- 作为**商家**，我希望这些信息由我在后台已配置的数据（门店名 / 门店 URL / 价目表时间窗 / 配送方式）自动派生，我不需要为 SEO 额外维护一份数据。
- 作为**商家**，我希望没有配置的数据**不要出现**在结构化数据里 —— 宁可字段缺失，也不要被搜索引擎判为「结构化数据错误」。

场景：
- **正常流（单 SKU）**：实体商品，命中带 `ends_at` 的价目表，门店有可用配送方式 → JSON-LD 同时带 `seller` / `priceValidUntil` / `shippingDetails`。
- **正常流（多 SKU）**：`AggregateOffer` 分支同样带三项。
- **边界（数字商品）**：`Shipping::Estimate` 返回 `digital: true` / `available: false` → **省略** `shippingDetails`（数字商品承诺运费是错的）。
- **边界（无价目表 / 价目表无时间窗 / 已过期）**：**省略** `priceValidUntil`。
- **边界（门店名为空）**：**省略** `seller`。
- **异常（运费估算失败）**：`getShippingEstimate` 返回 `null`（既有行为）→ PDP 照常 200，JSON-LD 省略 `shippingDetails`，页面其余部分不变。

## 3. 功能需求（FR）

- **FR-001 `seller`**：在 Product schema 输出 `seller`（`{ "@type": "Organization", name, url }`），取值来自门店配置（门店名 + 门店 URL）；门店名为空或门店 URL 缺失时不输出。
- **FR-002 `priceValidUntil`**：Store API 的 Price 载荷新增 `price_list_ends_at`（ISO8601，nullable，**只读派生字段**）；`buildProductJsonLd` 仅当该值存在且**未过期**时输出 `priceValidUntil`（日期部分），并同时适用于 `Offer` 与 `AggregateOffer`。
- **FR-003 `shippingDetails`**：复用 PDP **已获取**的 `Shipping::Estimate`（不新增请求），映射为 `OfferShippingDetails`：`shippingRate`（MonetaryAmount，取估算价；`free_shipping` 时为 0）、`shippingDestination`（DefinedRegion + 访问者国家）、`deliveryTime`（transitTime：min/max 天 + `unitCode: DAY`）。挂到 `Offer` 与 `AggregateOffer` 两个分支。
- **FR-004 诚实省略**：任一字段无可靠数据时必须**省略**，不得输出 `null` / 空对象 / 占位值 / 猜测值。
- **FR-005 `hasMerchantReturnPolicy`（结构化退货条款）**：为退货政策引入**结构化**条款存储，使 PDP 能输出符合 schema.org 的 `MerchantReturnPolicy`。
  - **落点**：`PallasTrade::Policy`（退货政策记录本身）。依据：① 后台**已有** Policies CRUD（`admin/policies`），商家本就在那里编辑退货政策，结构化条款与它描述的正文同处一页；② 前台**已按 slug 取 Policy**（`client.policies.get('returns-policy')`，Store API `policies#show` 已存在）→ **无需新增端点、无需新增菜单**。
  - **存储**：给 `pallastrade_policies` 增一个**通用** `preferences` 文本列并 `include PallasTrade::Preferable`（与 `pallastrade_stores.preferences` 同机制），条款以**类型化 preference** 存放 —— **不在通用 Policy 模型上开退货专用列**（避免隐私/配送/条款三类政策都多出空列）。
  - **条款字段**（全部可选；**未设置即整个 `hasMerchantReturnPolicy` 省略**）：`merchant_return_policy_category`（`not_permitted` / `finite_window` / `unlimited_window`）、`merchant_return_policy_days`（整数）、`merchant_return_policy_method`（`by_mail` / `in_store`）、`merchant_return_policy_fees`（`free` / `customer_pays`）、`merchant_return_policy_countries`（ISO-2 逗号分隔；空 → 用门店默认国家）。
  - **有效性门槛**：`finite_window` **必须**有 `days` 才输出；否则省略整个字段，**不产出残缺政策**。
- **FR-006 API 兼容**：`price_list_ends_at` 与 Policy 的 `merchant_return_policy` 均为**新增字段**，不得改动既有字段的语义与取值；不改变价格计算与政策正文逻辑。
- **FR-007 后台可编辑**：结构化条款在 `admin/policies` 表单上可编辑（**仅退货政策显示**），文案需 en + zh-CN 双语。

## 4. 非功能需求（NFR）

- **性能**：PDP 不新增外部调用；JSON-LD HTML 体积增量 < 1.5 KB。
- **安全**：输出沿用 `components/seo/JsonLd.tsx` 的 `JSON.stringify` + `<` → `\u003c` 转义；`seller.url` 取自站内配置（不接受请求参数）。
- **兼容**：既有 JSON-LD 字段与取值不变；`country` / `locale` 参数不影响已有字段；Store API 为**向后兼容的加法变更**。
- **可维护**：全部字段构造集中在 `storefront/src/lib/seo.ts`，页面内不内联 schema。
- **可观测**：省略是**静默且正确**的行为，不产生日志噪声（与 `findBrandName` 一致）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001**：门店名 / 门店 URL 具备时，`seller.name` / `seller.url` 分别等于门店配置值；门店名为空时 schema **不含** `seller` 键。
- **AC-002 ← FR-002**：命中带 `ends_at`（未来）的价目表时输出 `priceValidUntil`（ISO 日期）；无价目表 / 无 `ends_at` / `ends_at` 已过期三种情况均**不含**该键。
- **AC-003 ← FR-003**：有可用配送方式时 `shippingDetails` 的 `shippingRate.value` 与 `deliveryTime.transitTime.minValue` / `maxValue` 与同一次 `Shipping::Estimate` 的数值**一致**；`free_shipping: true` 时 `shippingRate.value == "0"`。
- **AC-004 ← FR-003**：`digital: true` 或 `available: false` 时**不含** `shippingDetails`。
- **AC-005 ← FR-003**：`AggregateOffer` 分支与 `Offer` 分支**都有** `shippingDetails`。
- **AC-006 ← FR-004**：三种缺数据场景下对应键**不存在**（不是 `null`、不是 `{}`）。
- **AC-007 ← FR-006**：新增 `price_list_ends_at` 不改变既有 Price 字段取值与价格计算；现有 price serializer spec 全绿。
- **AC-008 ← NFR**：渲染后的 JSON-LD 可被 `JSON.parse`；序列化输出不含裸 `<`。
- **AC-009 ← FR-005**：结构化条款**全部未设置**时，JSON-LD **不含** `hasMerchantReturnPolicy`（不是空对象）。
- **AC-010 ← FR-005**：`category = finite_window` 但 `days` 缺失/非正数时**仍不输出** `hasMerchantReturnPolicy`（不产出残缺政策）。
- **AC-011 ← FR-005**：`category = finite_window` + `days` 已设时，输出的 `merchantReturnDays` 等于配置值，且 `returnPolicyCategory` 为 schema.org 的 `MerchantReturnFiniteReturnWindow`。
- **AC-012 ← FR-005**：`countries` 为空时 `applicableCountry` 回退到门店默认国家；已填时等于所填 ISO-2 列表。
- **AC-013 ← FR-005**：Policy 序列化器仅对**退货政策**输出 `merchant_return_policy`，隐私/配送/条款政策**不含**该键。
- **AC-014 ← FR-007**：结构化条款在后台表单上可保存并回显；且仅退货政策显示该分组；en/zh-CN 两端文案齐全（过 `admin-i18n-rspec`）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `json_ld` / `jsonld` / `structured_data` / `schema.org` / `shipping_details` / `price_valid_until` / `seller` | **无（ABSENT）** | 不适用 —— 不涉及 host app |
| Core | `pallastrade_gems/pallastrade_core/app/` | `shipping_details` / `price_valid_until` / `structured_data`；`shipping` / `PriceList` | `services/pallastrade/shipping/estimate.rb`（可复用读模型）、`models/pallastrade/price_list.rb`（`starts_at` / `ends_at`） | **部分** —— 数据源齐备，但无 schema 字段 |
| API | `pallastrade_gems/pallastrade_api/app/` | `shipping_details` / `price_list_ends` / `structured_data` | `serializers/pallastrade/api/v3/price_serializer.rb`（有 `price_list_id`，**无 `ends_at`**）、`serializers/.../admin/price_serializer.rb`、`store/shipping_estimates_controller.rb` | **缺口** —— 需新增 `price_list_ends_at` |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `json_ld` / `structured_data` / `shipping_details` | **无（ABSENT）** | 不适用 —— 后台无需改动 |
| Storefront | `storefront/src/` | `shippingDetails` / `priceValidUntil` / `hasMerchantReturnPolicy` | **无（ABSENT）**；相关既有：`lib/seo.ts`、`components/seo/JsonLd.tsx`、`app/[country]/[locale]/(storefront)/products/[slug]/page.tsx`、`lib/data/shipping.ts`、`lib/store.ts` | **本期主战场** —— 三个新字段在此落地 |
| Platform | `platform/packages/` | `shippingDetails` / `priceValidUntil` / `price_list_ends_at` | **无（ABSENT）** | SDK `Price` 类型需随契约同步（生成物） |

**结论**：
- **已有能力（防重复判定）**：运费估算读模型（`Shipping::Estimate`，F-2 批次）与价目表时间窗（`PriceList#ends_at`）**都已存在** —— 本期不新建任何数据来源，只做派生与序列化；PDP 页面**已经**调用 `getShippingEstimate`，因此 `shippingDetails` **不引入新请求**。
- **需新建**：① Store API Price 载荷的 `price_list_ends_at`；② storefront 三字段构造；③ 契约与 SDK 类型同步。
- **轮子检查**：全仓（6 层）搜索 `shippingDetails` / `priceValidUntil` 均为 0 命中 → 确认无重复实现。

## 7. 技术影响

涉及文件：
- **数据库**：`pallastrade_policies` 新增 `preferences`（text）—— **一个通用列，无业务字段**（迁移可逆、无数据回填）。
- `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/policy.rb` —— `include PallasTrade::Preferable` + 五个类型化 `preference`（含归一化：非法枚举值归空、负数归 nil）。
- `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/policy_serializer.rb` —— 新增 `merchant_return_policy`（nullable 对象），**仅退货政策**输出。
- `backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/policies/_form.html.erb` + `policies_controller.rb`（permitted params）—— 新增退货条款分组（仅退货政策渲染）。
- `backend/config/locales/admin_*.{en,zh-CN}.yml` —— 新增文案键（双语气）。
- `storefront/src/lib/seo.ts` —— `buildProductJsonLd` 增加可选上下文入参（运费估算 + 访问者国家），新增 `seller` / `priceValidUntil` / `shippingDetails` 的构造与映射；沿用「缺失即省略」约定。
- `storefront/src/lib/data/policies.ts` —— 新增取退货政策的结构化条款的 server action（复用现有 `client.policies.get`）。
- `storefront/src/app/[country]/[locale]/(storefront)/products/[slug]/page.tsx` —— 把**已经获取**的 `estimate`（当前仅传给 `ShippingEstimate` 组件）一并传入 `buildProductJsonLd`；新增取退货条款。
- `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/price_serializer.rb` —— 新增 `price_list_ends_at`（`typelize` + `attribute`），由 `price.price_list&.ends_at` 派生；**只读，不参与计算**。
- `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/` —— Price 与 Policy schema 增字段。
- SDK 类型（`@pallastrade/sdk` 的 `Price` / `Policy`）—— 随契约生成物同步。

不涉及：后台 UI、事件、权限。数据库仅一次**加法迁移**（无回填、无索引变更）。

影响面：JSON-LD 为一期能力的**加法**变更；`price_list_ends_at` 为 Store API 加法字段（既有消费者不受影响）。

## 8. 测试计划

- **更新**：`storefront/src/lib/__tests__/seo.test.ts`
  - AC-001（seller 存在 / 门店名为空时省略）
  - AC-002（价目表三种情况 → 只在前者输出 `priceValidUntil`）
  - AC-003 / AC-004 / AC-005（shippingDetails 数值一致 / digital 省略 / AggregateOffer 分支）
  - AC-006（缺数据时键不存在 —— 断言 `!("seller" in schema)` 而非 `toBeNull()`）
  - AC-008（`JSON.parse` 可解析 + 无裸 `<`）
- **更新**：Price serializer 的 Rails spec
  - AC-002（`price_list_ends_at` 取值与 null 分支）
  - AC-007（既有字段取值不变 —— 回归）
- **门禁**：`pnpm check`（Biome lint + format，CI 强制）、`harness generated:check`（OpenAPI + SDK 类型一致）。
- **渲染取证**：PDP 实际 HTML 中 `<script type="application/ld+json">` 的三字段片段。

AC 映射：AC-001~AC-006 / AC-008 → `seo.test.ts`；AC-002 / AC-007 → Rails price serializer spec。

## 9. 文档同步清单（知识同步门）

- [ ] **API 文档**：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/`（新增 `price_list_ends_at`）
- [ ] **Skill 文档**：`ai/skills/pallastrade-storefront/SKILL.md`（§SEO / metadata 补三字段与「缺失即省略」）；`ai/skills/pallastrade-api-v3/SKILL.md`（Price 字段增量）—— 按 `sync-check` 判定后处理
- [ ] **场景库**：若改动 Skill 文件，则同步 `harness/scenarios/scenarios.json`（doc-impact 硬要求）
- [ ] **反模式库 / 任务规则**：预计不涉及（无新反模式）
- [ ] **本 PRD 状态** + `docs/prd/README.md` 索引
- [ ] `AGENTS.md` §6 —— 若新增 / 变更 verifier 则同步

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-17 | 0.1 | 初稿（B1：seller / priceValidUntil / shippingDetails；`hasMerchantReturnPolicy` 明确排除） | AI |
| 2026-09-17 | 0.2 | **用户确认后扩范围**：`hasMerchantReturnPolicy` 纳入本期且要求**结构化**（用户原话「最好是做，结构化字段，这是很重要的SEO能力」）；落点定为 `PallasTrade::Policy` + 通用 `preferences` 列；新增 AC-009~AC-014 | AI |
| 2026-09-17 | 1.0 | **已交付**：4/4 字段全部上线。后端 rspec 22 例、前台 vitest 23 例、`harness check --profile quick`、`generated:check` 全绿；运行时取证两条政策端点。实施中发现并修复两个真 bug：① Mobility 空翻译行遮住 `column_fallback` 导致 `returns_policy?` 在中文界面下失效；② `generated:check` 的 docker-gated 假阴性（已记入 `platform/packages/README.md`）。已知取舍：PDP 新增一次 `policies#show` 调用（未加缓存） | AI |
