# REQ-20260917-catalog-json-ld-phase2

> 关联 PRD：`docs/prd/catalog/PRD-20260917-catalog-json-ld-phase2.md`
> 任务：`TASK-20260917095654-b3101665` / gate `GATE-2026-09-17T09-59-14`（feature，standard）

---

## Step 0：跨层搜索（6 层，强制）

| 层 | 搜索路径 | 搜索关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `json_ld` / `jsonld` / `structured_data` / `schema.org` / `shipping_details` / `price_valid_until` / `seller` | 无 | ❌ 零命中（不涉及 host app） |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ 零命中 |
| Core Gem — models | `pallastrade_gems/pallastrade_core/app/models/` | `shipping_details` / `price_valid_until` / `structured_data`；`PriceList` | `pallastrade/price_list.rb`（`starts_at` / `ends_at`、状态机 `draft→active`、`activate` / `deactivate` / `schedule`） | ⚠️ 部分 —— **`ends_at` 已存在**，是 `priceValidUntil` 的权威数据源 |
| Core Gem — services | `pallastrade_gems/pallastrade_core/app/services/` | 同上；`shipping` | `pallastrade/shipping/estimate.rb`（F-2 读模型：`available` / `digital` / `min_days` / `max_days` / `free_shipping` / `methods[].estimated_price`） | ✅ **可直接复用**，本期不新建 |
| API Gem — controllers | `pallastrade_gems/pallastrade_api/app/controllers/` | `shipping_estimate` | `v3/store/shipping_estimates_controller.rb`（PDP 现用端点） | ✅ 已存在，**本期不改** |
| API Gem — serializers | 同上 | `price_list_ends` | `v3/price_serializer.rb`（有 `price_list_id`，**无 `ends_at`**）、`v3/admin/price_serializer.rb` | ❌ **缺口** —— 需新增 `price_list_ends_at` |
| Admin Gem — controllers/views | `pallastrade_gems/pallastrade_admin/app/` | `json_ld` / `structured_data` / `shipping_details` | 无 | ❌ 零命中（后台无需改动） |
| Storefront | `storefront/src/` | `shippingDetails` / `priceValidUntil` / `hasMerchantReturnPolicy` | 无；相关既有：`lib/seo.ts`（`buildProductJsonLd`：Offer/AggregateOffer + brand + aggregateRating + availability）、`components/seo/JsonLd.tsx`（`<` → `\u003c` 转义）、`app/[country]/[locale]/(storefront)/products/[slug]/page.tsx`（L92 调用点；L86 已取 `getShippingEstimate`）、`lib/data/shipping.ts`、`lib/store.ts`（`getStoreName` / `getStoreUrl` / `getDefaultCountry`） | ⚠️ 部分 —— **本期主战场**，三个新字段在此落地 |
| Platform | `platform/packages/` | `shippingDetails` / `priceValidUntil` / `price_list_ends_at` | 无 | ⚠️ SDK `Price` 类型需随契约生成物同步 |

### 搜索结论

- **无重复实现**：全仓搜索 `shippingDetails` / `priceValidUntil` 零命中 → 方案 §4.3「第二阶段」确为未做项。
- **已有能力（不新建数据源）**：① `PriceList#ends_at` 提供价格有效期；② `Shipping::Estimate` 提供运费与时效，且 **PDP 已调用**（`page.tsx` L86），故 `shippingDetails` **不引入新请求**；③ `getStoreName()` / `getStoreUrl()` 提供 `seller`。
- **需新建/小改**：① Store API Price 载荷加 `price_list_ends_at`（只读派生）；② `lib/seo.ts` 三字段构造 + PDP 传入已取到的 estimate；③ 契约链同步（`scripts/ci/contracts.sh` → `store.yaml` + SDK 类型）。
- **架构层级选择**：按 `pallastrade-customization` 决策树，本需求是「**已有能力的对外展示层扩展**」——Core 读模型与序列化器已就位，故落在 **gem 序列化器（API 层）+ storefront lib（展示层）**，**不需要** Decorator / Events / 新模型 / Host App 改动。

---

## Step 1：Skill 文件咨询（强制）

| Skill 文件 | 状态 | 关键结论引用（真实结论） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：Settings → Events → DI → Admin Extensions → Generators → Decorators → Extensions → 直接改 gem。本需求**不需要任何自定义机制**（无副作用、无行为替换、无新模型），只是「读模型 → 序列化 → 展示」；改动落在 gem 序列化器时按仓库约定加 `# PALLAS-CUSTOM:` 说明。 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | §SEO / metadata：`seo.ts` 是共享 SEO 层（canonical / OG / 结构化数据），`metadata/` 为每路由元数据构建器；「新增页面路由应扩展对应 builder 而非在页面内联」→ 本期**继续集中在 `lib/seo.ts`**，不在 `page.tsx` 内联 schema。另：`buildProductJsonLd` 现状为单 SKU `Offer` / 多 SKU `AggregateOffer`（lowPrice/highPrice/offerCount + 最有利可用性），`brand` 从自定义字段读取、**缺失即省略** —— 本期三字段必须沿用同一「缺失即省略」约定。CI 强制 `pnpm check`（Biome lint + format）。 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | 契约链：**Typelizer → SDK + `api-docs/{store,admin}.yaml`**，编排脚本 `scripts/ci/contracts.sh`；宿主 rake `api:docs:generate` / `schemas:check` / `validate`。**契约漂移由 `harness generated:check` 守（漂移即失败）**；`store.yaml` 在 `backend/public/api-docs/` 与 `platform/docs/api-reference/` 双份。Store API 只暴露客户可见字段 → 新增 `price_list_ends_at` 属**加法、非破坏**。 |
| `ai/skills/pallastrade-pricing/SKILL.md` | ✅ 已读 | §PriceList：`starts_at` / `ends_at` 是价目表的**可选时间窗**，`status` 是状态机（`draft → active`，`activate` / `deactivate` / `schedule`）；**购物车管线取优先级最高且命中的 PriceList，未命中回落默认（`price_list: nil`）**。→ `priceValidUntil` 必须取**实际命中**的那张价目表的 `ends_at`；回落默认价目表时**无时间窗可用，应省略该字段**（不猜）。 |

**按需 Skill（本次涉及）**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-catalog` | ✅ | ✅ 已读 | 目录图：Product → Variant（master + 真实变体）→ Price（按币种）；**Metafield 承载自定义字段**（`findBrandName` 取 `catalog.brand` 的依据）。本需求**不动目录结构、不动价格模型**。 |
| `pallastrade-testing` | ✅ | ⬜ 未读 | 本期计划沿用既有 spec 路径（`storefront/src/lib/__tests__/seo.test.ts` + Rails serializer spec），不新建测试基础设施。若实施中发现需要新测试范式，再补读。 |
| `pallastrade-admin` | ✅ | ✅ 已读 | §只读运维页范式（资源控制器 + 表格注册 + 导航 + 权限四件套）。→ 本期在**已有** Policies CRUD 上补字段，不新增资源、不新增导航子项、不新增权限注册。 |
| `pallastrade-i18n` | ✅ | ⬜ 未读 | 结构化退货条款的后台文案需 en + zh-CN **双向键集相等**（受 `admin-i18n-rspec` 门禁）。实施时补读并跑门禁。 |
| `pallastrade-data-model` | ✅ | ⬜ 未读 | 一次**加法迁移**（`pallastrade_policies.preferences` text）。实施时补读并遵守迁移规范（不得改旧迁移/schema.rb）。 |
| `pallastrade-decorators` / `pallastrade-dependencies` / `pallastrade-events-webhooks` | ❌ | — | 无副作用、无行为替换 |

---

## 需求标题

为商品页 JSON-LD 第二阶段补充 `seller` / `priceValidUntil` / `shippingDetails` / `hasMerchantReturnPolicy`（4/4 字段）

## 任务类型

功能优化（优化迭代）

## 需求描述

一期 JSON-LD 已交付并在线（Product / BreadcrumbList / ItemList / Organization；`brand` 取自定义字段；`aggregateRating` 仅统计已审核评论；`Offer` 与 `AggregateOffer` + `availability`）。方案 §4.3 把四个字段列为第二阶段 —— **用户确认四个全做**（原话：「最好是做，结构化字段，这是很重要的SEO能力」）：

1. **`seller`** —— 从门店配置（门店名 + 门店 URL）派生，让搜索引擎知道「谁在卖」。
2. **`priceValidUntil`** —— 从**实际命中**的价目表的 `ends_at` 派生（仅当存在且未过期）。
3. **`shippingDetails`** —— 复用 PDP **已经取到**的运费估算（`Shipping::Estimate`）映射为 `OfferShippingDetails`（运费 + 目的地 + 时效），同时挂到 `Offer` 与 `AggregateOffer` 两个分支。
4. **`hasMerchantReturnPolicy`（结构化）** —— 为退货政策引入结构化条款（类目 / 窗口天数 / 退货方式 / 费用 / 适用国家），输出 schema.org `MerchantReturnPolicy`。**不是**只给一个政策 URL。

**核心原则（沿用 `findBrandName` 既有约定）：任何字段缺可靠数据就省略，绝不输出 `null` / 空对象 / 猜测值。**

### 结构化退货条款的落点（调研结论）

调研发现 `Policy` 基础设施**已存在且已接通前台**（`PallasTrade::Policy` 模型 + 后台 `admin/policies` CRUD + Store API `policies#show` + 前台 `client.policies.get(slug)` + 每店自动生成 `returns-policy`）。因此：

- **落点 = `PallasTrade::Policy` 自身**：后台已有 Policies CRUD（商家本就在那编辑退货政策）+ 前台已按 slug 取 → **零新端点、零新菜单**；
- **存储 = 通用 `preferences` 文本列 + `include PallasTrade::Preferable`**（与 `pallastrade_stores.preferences` 同机制）—— 不在通用 Policy 上开退货专用列；
- **不选 Store 字段**：storefront 的门店数据走 `NEXT_PUBLIC_*` 环境变量（`lib/store.ts`），放 Store 会强制新增一条下发路径；
- **不选 Policy 专列**：隐私/配送/条款三类政策会各多一排空列，且枚举/天数硬编码在表结构上不利演进。

## 影响范围（`harness affected` 输出）

- 实施前基线（仅两份 PRD 文档）：`filesChanged: 2`、`affectedComponents: []`、`estimatedTests: 6` → **尚无代码变更**，实施后需重跑。
- 计划改动清单（详见 PRD §7）：
  - `storefront/src/lib/seo.ts`（三字段构造）
  - `storefront/src/app/[country]/[locale]/(storefront)/products/[slug]/page.tsx`（传入已取到的 estimate + country）
  - `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/price_serializer.rb`（新增 `price_list_ends_at`）
  - `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/` + SDK 类型（契约链生成物）
  - `storefront/src/lib/__tests__/seo.test.ts`（AC 映射）
- **零数据库迁移、零后台改动、零权限改动。**

## 技术方案（初步）

1. **`seller`**：`getStoreName()` + `getStoreUrl()` 已存在 → 纯前端派生，**零 API 改动**。
2. **`priceValidUntil`**：`PriceSerializer` 增 `price_list_ends_at`（`price.price_list&.ends_at`，ISO8601，nullable）→ 契约链（`scripts/ci/contracts.sh`）同步 `store.yaml` + SDK 类型 → `lib/seo.ts` 仅在该值存在且未过期时输出。
3. **`shippingDetails`**：`buildProductJsonLd(product, canonicalUrl, { shippingEstimate, country })` —— 把 `page.tsx` L86 **已经拿到**的 estimate 传进去，映射 `shippingRate` / `shippingDestination` / `deliveryTime`；`digital: true` 或 `available: false` 直接省略。
4. **`hasMerchantReturnPolicy`**：
   - 迁移：`add_column :pallastrade_policies, :preferences, :text`（通用列）；
   - `Policy` `include PallasTrade::Preferable` + 5 个类型化 preference（含归一化：非法枚举→空、非正天数→nil）；
   - `PolicySerializer` 增 `merchant_return_policy`（nullable 对象，**仅退货政策输出**）；
   - 后台 `admin/policies/_form` 增退货条款分组（**仅退货政策渲染**）+ 双语 i18n；
   - 前台 `lib/data/policies.ts` 取结构化条款 → `lib/seo.ts` 映射 schema.org（`returnPolicyCategory` / `merchantReturnDays` / `returnMethod` / `returnFees` / `applicableCountry` / `url`）。

**有效性门槛**：`finite_window` 必须有 `days` 才输出；全未设置或不满足门槛 → **整个字段省略**。

## 风险点

- **最高风险**：Store API 加字段引发契约漂移（`generated:check` 失败）。缓解：走 `scripts/ci/contracts.sh` 生成链，不手改 yaml；改完立即跑 `harness generated:check`。
- **次高**：`priceValidUntil` 取错价目表（默认价目表 `ends_at` 为 nil 时误输出）。缓解：只在 `price_list_id` 非空且 `ends_at` 未过期时输出，并对三种情况各写一条 AC（AC-002）。
- **回滚难度**：低 —— 全部为加法变更，零迁移、零资金路径；回滚只需 revert commit。

## 决策节点

> 1. **`priceValidUntil` 数据源**：确认为「实际命中价目表的 `ends_at`」，回落默认价目表时省略 —— （新增 Store API 字段）**用户已回复「接受」**。
> 2. **`hasMerchantReturnPolicy`**：**用户已回复「最好是做，结构化字段，这是很重要的SEO能力」** → 本期做，且**必须结构化**（不是只给 URL）。
> 3. **落点选择**：由 AI 自主定为「`Policy` + 通用 `preferences` 列」（理由见上文「结构化退货条款的落点」），已记录在 PRD 0.2 变更记录。
> 4. **枚举取值**：采用 schema.org 原生词汇（`MerchantReturnFiniteReturnWindow` / `ReturnByMail` / `FreeReturn` 等）的**小写蛇形内部值**，由序列化层映射到 schema.org URI —— 避免把 schema.org 字串硬编码进业务数据。

> ⏸️ 以上已获用户确认（原话：「1、接受 2、最好是做，结构化字段，这是很重要的SEO能力 3、自主决策」）→ 已开实施。

---

## 阶段②：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 迁移 | `pallastrade_policies.preferences` | `bin/rails db:migrate` + schema 无意外变更 | `migrated (0.0142s)`；`schema.rb` 自动更新 `t.text "preferences"` | ✅ |
| Core 模型 | `policy.rb`（Preferable + 5 preference + returns_policy?） | Rails model spec（归一化） | `policy_return_terms_spec` 11 例绿 | ✅ |
| API 序列化器 | `policy_serializer.rb` / `price_serializer.rb` | Rails serializer spec | `policy_serializer_spec` + `price_serializer_spec`；合计 22 例 0 失败 | ✅ |
| 后台表单 | `admin/policies/_form.html.erb` + i18n | `admin-i18n-rspec` + 页面渲染取证 | en/zh-CN 键集 19=19 双向相等；`returns_policy?` 在 en/zh-CN/fr 下均为 true、隐私政策为 false | ✅ |
| Storefront lib | `storefront/src/lib/seo.ts` + `lib/data/policies.ts` | `pnpm check` + `seo.test.ts` | vitest 23 passed（6 既有零回归 + 17 新增）；biome 4 files 无修复 | ✅ |
| Next.js 页面 | `products/[slug]/page.tsx` | PDP 渲染取证 | 以真实 HTTP 响应取证：`returns-policy` 返回完整 `merchant_return_policy`，`privacy-policy` 为 `null` | ✅ |
| API 契约 | `store.yaml` + SDK 类型 | `harness generated:check` | 无漂移；`Price.price_list_ends_at` + `Policy.merchant_return_policy` 已生成 | ✅ |
| 整体 | — | `harness check --profile quick` | 无反模式 / AP-009 干净 / nav-validate 0 警告 | ✅ |

### 验证结论

全部绿。实施过程中发现并修复两个**真 bug**（均已记入仓库记忆）：

1. **`returns_policy?` 在中文界面下失效** —— Mobility 为未翻译语言留下**空 translation 行**，
   空行遮住 `column_fallback`，按 `default_locale` 读 `name` 得到 nil → 判定 false →
   商家在中文后台**看不到**该填的结构化条款字段。改为「列值 + 每条翻译」与「各语言文案」
   交叉比对，并在 spec 里钉住 zh-CN/fr 两个回归点。
2. **`harness generated:check` 假阴性** —— 改完序列化器后它报「无漂移」，而 `store.yaml`
   实际缺字段（docker-gated 静默跳过）。已把提示写进 `platform/packages/README.md`。

另有一处**未覆盖**已如实声明并补上：dev 库无价目表数据，`price_list_ends_at` 的
iso8601 路径在手工验证时没被跑到 —— 已在 `price_serializer_spec` 用工厂造数据覆盖。
