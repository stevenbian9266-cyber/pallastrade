# REQ-20260916 — Batch F-2（§十一 库存阈值化 + 配送信息）

> 关联 PRD：`docs/prd/catalog/PRD-20260916-catalog-batch-f2-stock-shipping.md`
> 任务：TASK-20260916032902-9316360d ｜ Gate：GATE-2026-09-16T03-29-20（feature，risk=critical）
> 用户确认：2026-09-16「确认实施」（决策：阈值默认 5 / 配送区块在 PDP 价格下方一行 / 免运费＝店铺偏好+促销覆盖 / 到达日期＝天数区间+日期区间 / **库存桶含商品列表与卡片**）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | stock_status / low_stock / shipping / estimate | 无库存与配送展示代码 | 缺口：按本仓惯例落 gem（Core 服务 + API 序列化） |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | total_on_hand / can_supply / in_stock / threshold / shipping_method | `models/pallastrade/stock/quantifier.rb`（`total_on_hand`）、`models/pallastrade/variant.rb`（`:646 in_stock?` / `:652 backorderable?` / `:664 purchasable?` / `:251 preorder?`）、`models/pallastrade/product.rb`（`total_on_hand` memoized）、`models/pallastrade/shipping_method.rb`（**已有** `estimated_transit_business_days_min/max`，校验 ≥1）、`models/pallastrade/store.rb` §Preferences（`preference :x, default:` DSL） | **部分满足**：库存/时效数据源齐备；**无** low_stock / stock_status / 配送估算概念 → 新建两个读模型服务；阈值落 Store 偏好 |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | in_stock / backorderable / preorder / delivery_method / estimated / free_shipping | `serializers/.../variant_serializer.rb`（`purchasable/in_stock/backorderable/preorder`）、`serializers/.../product_serializer.rb`、`serializers/.../delivery_method_serializer.rb`（只有 `id/name/code/display_estimated_price`，**缺时效**）、`controllers/.../store/shipping_methods_controller.rb`（返回全部 `display_on: both/front_end`，无国家参数） | **需改**：只增字段（`stock_status` + 时效），不动既有布尔语义 |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | shipping_method / transit / store form / preference | ShippingMethod 编辑页已可填 transit days（既有字段，无需改）；店铺表单是 preferences 既有编辑面 | **小改**：店铺表单增 `low_stock_threshold` / `free_shipping_threshold` 两项 + 校验 |
| Storefront | `storefront/src/` | shipping / estimate / arrival / freeShipping / lowStock / stock_status | **零命中**；`lib/utils/variant-selection.ts`（4.2 四态 `deriveAvailabilityState`）、`components/products/ProductDetails.tsx`、`components/products/ProductCard.tsx`、`lib/data/products.ts`、5 个 `messages/*.json` | **需改**：PDP 配送区块 + 徽章五态 + 列表卡片徽章 + i18n |
| Platform | `platform/packages/` | Variant / Product / DeliveryMethod | SDK 生成类型（typelizer 派生）含 `Variant`/`Product`/`DeliveryMethod` | **需重生**：`generated:check` 无漂移；**dist 必须提交**（F-1 教训） |

### 搜索结论

- **数据源已存在，缺的是「服务端口径 + 下发 + 展示」**：`total_on_hand` / `estimated_transit_business_days_*` 都在，本批不新增库表、不改库存计算与结算。
- **口径同源铁律**（catalog Skill `:221`）：`Product#in_stock?` 只在 `track_inventory` 变体有正库存时为 true → **`track_inventory_levels` 关闭时全部视为 `in_stock`**（不展示稀缺），分桶必须复用该语义而不是自己数库存。
- **隐私**：精确库存属商家敏感数据（同 Security Skill 的「最小暴露」原则）→ 任何 Store API 响应只出**枚举桶**，不出数字。
- 列表（用户新增范围）需要**一次聚合查询**：`pallastrade_stock_items → variants → products` 分组求和后套阈值，禁止逐商品 `total_on_hand`。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：「改变商家可见设置（currencies, …, shipping methods）」→ 走 **Admin Settings UI**；「商品变体/库存等结构性改动」才用 decorator。本批只**新增读模型服务 + 序列化字段 + 偏好**，不 decorate 既有类、不改状态机 → 走最高优先级的既有扩展面 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | `:221` 「**Is it in stock?** `product.in_stock?` — false if no `track_inventory` variant has positive stock」+ `:53` `Config[:track_inventory_levels]` 决定 `default_variant` 口径 → 分桶必须与 `in_stock?` 同源，tracking 关闭时不制造稀缺 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | `{data, meta}` 信封；**分页 = `?page&limit`（Pagy）**；前缀 id（`variant_…`）；列表禁裸主键；**契约变更必须同步 OpenAPI + SDK 类型（`generated:check`）** | 
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD → **用户确认才开 gate** → REQ（含本表）→ AC↔测试映射（`prd verify`）→ 知识同步门（`sync-check --ack`） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ☑ 涉及 | ✅ 已读 | PDP 由 `ProductDetails` 组装，可售性由纯函数 `lib/utils/variant-selection.ts` 派生（4.2）→ 本批在同层扩展 `low_stock` 与配送区块；文案入 5 个 `messages/*.json`；**改 storefront 必须本地跑 `pnpm build`**（F-1 `"use server"` 教训）+ Biome 80 列 |
| `pallastrade-data-model` | ☑ 涉及（判断为零迁移） | ✅ 已读 | 新偏好落 `PallasTrade::Store` preferences（无新表/无 `schema.rb` 手工改动）；`ShippingMethod` 时效列**已存在** |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已读 | UI 文案与数据翻译分离；storefront 走 `messages/*.json` 五语言，键齐备由 `checkout-i18n-keys.test.ts` 守护 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec（容器 `docker exec pallastrade-web-1 … bundle exec rspec`）+ vitest 组件测试；注册 verifier 供 `harness verify` |
| `pallastrade-security` | ☑ 涉及（轻） | ✅ 已读 | 敏感数据最小暴露原则（凭证 reveal 分级/审计同源思路）→ **精确库存数字不下发**，只出枚举桶；不改授权面 |
| `harness-prd` | ☑ 涉及 | ✅ 已读 | gate 阶段 `preparation → implementation → verification`；`verify-test` 只能由 typed evidence 关闭 |
| `pallastrade-admin` | ☑ 涉及（轻） | ✅ 已读 | 后台表单加字段走 gem 源直改 + `# PALLAS-CUSTOM:`；不动导航 |

---

## 需求标题

PDP 与商品列表的库存稀缺表达（分桶，不暴露精确库存）+ 配送时效/免运费提示。

## 任务类型

新功能（Core 读模型服务 + Store 偏好 + Store API 只增字段 + PDP/列表展示；零新表）

## 需求描述

消费者在 PDP 与商品卡片上能看到「快没了 / 预售 / 可缺货预定 / 售罄」的**分桶**状态（不是精确数字），并在 PDP 价格下方看到配送时效（工作日区间 + 到达日期区间）与免运费门槛。

## 影响范围（预估）

```text
backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/catalog/stock_status.rb      （新增：分桶 + 批量聚合）
backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/shipping/estimate.rb         （新增：配送估算读模型）
backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/store.rb                        （+2 preferences）
backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/{variant,product}_serializer.rb   （+stock_status）
backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/delivery_method_serializer.rb     （+时效）
backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/{products,shipping_methods}_controller.rb （列表聚合 + country 参数）
backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/…              （PDP 相关：估算下发方式见实施）
backend/pallastrade_gems/pallastrade_admin/app/views/…/stores/_form.html.erb                     （+2 字段）
backend/spec/**                                                                                   （新规格）
backend/public/api-docs/store.yaml + platform/docs/api-reference/store.yaml                       （契约）
storefront/src/{components,lib,app}/**, storefront/messages/*.json                                 （徽章 + 配送区块 + i18n）
platform/packages/sdk/**                                                                          （typelizer 类型 + dist）
harness.config.mjs / AGENTS.md / harness/scenarios/scenarios.json / docs/prd/README.md            （治理）
```

## 决策记录

1. 阈值默认 **5**，存 `Store#low_stock_threshold`（admin 可改，非法值归一为默认）。
2. 配送区块在 **PDP 价格下方一行**。
3. 免运费 = **店铺偏好 `free_shipping_threshold` + 活跃 `FreeShipping` 促销覆盖**。
4. 到达日期 = **天数区间 + 日期区间**（工作日 = 周一~五，不含节假日；按店铺时区 + locale 渲染）。
5. 库存桶展示范围 = **PDP + 商品列表/卡片**（列表走单次聚合查询，禁 N+1；缓存不得陈旧）。
6. `track_inventory_levels` 关闭 → 一律 `in_stock`（不制造稀缺、也不误报售罄）。
