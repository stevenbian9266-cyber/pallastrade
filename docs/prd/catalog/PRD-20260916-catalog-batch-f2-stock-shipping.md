# PRD-20260916-catalog-batch-f2-stock-shipping

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-16 |
| 来源 | 《商品升级方案 V1.0》§十一「库存与配送信息」——消费者三问：现在有没有货 / 还有多少 / 什么时候送到（用户授权原话「继续」，2026-09-16） |
| 分类 | catalog（商品域 / 库存与配送，沿用 Batch A~F 系列目录） |
| 关联 Skill | pallastrade-catalog / pallastrade-storefront / pallastrade-api-v3 / pallastrade-data-model / pallastrade-i18n |
| 关联 REQ | REQ-20260916-batch-f2-stock-shipping.md（实施时回填） |
| 关联 PRD | 上游：P0-4 评论基础（无关）；同域前置：`PRD-20260915-catalog-pdp-state-correctness`（4.2 预售/缺货四态，本批在其上扩展）；无同类 PRD（全新） |
| 需求类型 | 新功能（Store API 只增字段 + PDP 展示；**无新表**、不改库存计算与结算） |

> 🔁 **查重**：`harness prd new` 通过。**范围依据**：§十一 只要求「库存 UI 阈值化 + 配送时效展示」，不要求改动库存预留/结算链路；§十四 Roadmap 将其列在评论升级之后、商品治理之前。

## 1. 背景与目标

- **一句话需求原文**：「继续」（承接 §十一 库存与配送信息）。
- **背景**（审计结论 + 本次 6 层复核）：
  - PDP 目前只有二元/四态可售状态（`in_stock` / `preorder` / `backorder` / `sold_out`，4.2 已完成），**没有任何「快没了」的稀缺表达**，也没有精确库存的**分桶**口径——要么含蓄（无信息），要么暴露（`count_on_hand`）。
  - PDP **完全没有配送信息**：6 层搜索确认 `storefront/src/**` 对 `shipping|estimate|arrival|freeShipping` 零命中；后台 `ShippingMethod` **已经有** `estimated_transit_business_days_min/max`（`pallastrade_core/app/models/pallastrade/shipping_method.rb`）与 `display_estimated_price`，但 `/api/v3/store/shipping_methods` 只下发 `id/name/code/display_estimated_price`——**时效数据已有来源、只差下发与展示**。
  - 免运费：`Promotion::Action::FreeShipping`（`promotion/actions/free_shipping.rb`）已存在，但 PDP 无「满 X 免运费」提示；店铺偏好（`PallasTrade::Store` preferences，`store.rb` §Preferences）是阈值配置的既有落点。
- **目标**：
  1. 消费者在 PDP 上能判断「现在有没有货 / 还有多少 / 什么时候送到」——用**分桶**而不是精确库存表达稀缺；
  2. 配送时效与免运费阈值在 PDP 可见，减少「结算才知道运费/时效」的流失；
  3. 口径**服务端唯一**：分桶与时效由后端计算，前台只渲染，避免前后端口径漂移。
- **成功指标**：
  - `stock_status` 桶与 `Variant#in_stock?/#preorder?/#backorderable?` 判定**同源**（同一服务对象计算，规格断言一致性）；
  - **任何 Store API 响应都不含精确库存数字**（规格断言：响应 JSON 里不存在 `count_on_hand`/`total_on_hand` 数值字段）；
  - PDP 配送区块在「有配送方式」时展示时效（工作日区间 + 到达日期区间），数字商品与无配送方式各自有替代文案；
  - PD 首屏新增文案全部 5 语言齐备（i18n 键测试守护）。

## 2. 用户故事 / 场景

- 作为**消费者**，看到「Only a few left」时知道要快下决定，但看不到「还剩 3 件」（不给爬虫与竞对留后门）。
- 作为**消费者**，在 PDP 上就想知道「大概几天到 / 什么时候到」，而不是加购到结算才发现要等两周。
- 作为**消费者**，看到「Free shipping over $50」时知道凑单门槛。
- 作为**商家长**，希望「快没了」的阈值可配（不同品类可售深度不同），而不是写死在代码里。
- 作为**数字商品**买家，不需要看到配送时效，应看到「即时下载」。

## 3. 功能需求（FR）

### A. 库存阈值化（分桶，不暴露精确库存）

- **FR-001**：Store API 在 **variant** 与 **product** 层新增 `stock_status` 字段，取值枚举 `in_stock | low_stock | preorder | backorder | out_of_stock`；**保留**既有布尔字段（`in_stock` / `backorderable` / `preorder` / `purchasable`）不变——只增不改，避免破坏 4.2 的既有消费者。
- **FR-002**：分桶口径（服务端唯一实现，`PallasTrade::Catalog::StockStatus`）：
  - 可售数量 **> 阈值** → `in_stock`；
  - 可售数量 **在 1..阈值** → `low_stock`；
  - 可售数量 = 0 且 `preorderable?` → `preorder`；
  - 可售数量 = 0 且 `backorderable?` → `backorder`；
  - 其余 → `out_of_stock`。
  - **product 层**取「最优变体」：优先任一 `in_stock` → 否则 `low_stock` → 否则 `preorder` → 否则 `backorder` → 否则 `out_of_stock`（与 4.2 `aggregateAvailability` 语义一致）。
- **FR-003**：阈值由**店铺偏好**配置 `low_stock_threshold`（integer，默认 5，最小 1），Admin 店铺表单可改；未配置时回退默认值。阈值 **0/负数**视为非法 → 归一为默认值（保存时校验）。
- **FR-004**：`stock_status` 计算**不产生 N+1**（用户已确认列表/卡片也要展示，见 §11-5）：
  - 面向给定 product ids 的**单次聚合查询**（`stock_items → variants → products` 分组求和）；
  - 列表（`GET /api/v3/store/products`）：**一次**分组 SQL 取回本页全部 product 的可售数量，再在 Ruby 侧套阈值分桶；
  - 规格断言：列表请求 SQL 条数**不随返回条数增长**（1 条 vs 10 条差 ≤ 常数）；禁止逐商品调用 `total_on_hand`。
- **FR-005**：前台 PDP 按 `stock_status` 展示徽章：`In stock` / `Only a few left` / `Pre-order` / `Available on backorder` / `Out of stock`；`preorder` 保留既有 `preorderShipsBy` 说明，`out_of_stock` 保留既有补货订阅入口。

### B. 配送信息（PDP）

- **FR-006**：`/api/v3/store/shipping_methods` 扩展下发 `estimated_transit_business_days_min` / `estimated_transit_business_days_max`（可空）与 `zone_country_codes`（可选，用于前台按访客国家过滤）；**不改变**既有字段语义。
- **FR-007**：新增/扩展 PDP 所需的聚合读模型（`PallasTrade::Shipping::Estimate`）：
  - 输入：store + 访客国家（前台路由 `[country]` 已有）+ 商品/变体（含 `shipping_category` 与 `digital?`）；
  - 输出：`{ available:, min_days:, max_days:, estimated_price:, free_shipping_threshold: }`；
  - 规则：数字商品 → `digital: true`（不显示时效）；无可匹配配送方式 → `available: false`（前台给替代文案，不猜数字）。
- **FR-008**：`free_shipping_threshold` 来源（**待用户确认，见 §11 问题 3**）：
  - 方案 A（推荐）：店铺偏好 `free_shipping_threshold`（金额，可空=关闭）+ 活跃 `FreeShipping` 促销存在时**覆盖**为「免运费」；
  - 方案 B：只读店铺偏好（更简单，不解析促销）。
- **FR-009**：前台 PDP 在价格区下方渲染配送区块（位置待确认，见 §11 问题 2）：
  - `Shipping estimate`：`3–5 business days`（有 min/max 时）或 `Ships in 1–2 days`（只有 min）或省略；
  - `Estimated arrival`：按**工作日**从今天推算的日期区间（例：`Sep 22–25`），不含节假日日历（明示假设）；
  - `Free shipping over $50`（阈值存在时）；
  - 全部 i18n 化（5 语言），日期用 `Intl.DateTimeFormat` 按 locale 渲染。
- **FR-010**：配送区块只在 PDP（价格下方一行，§11-2）；购物车/结算保持现状，避免与结算期运费口径打架。
- **FR-011**（用户确认的扩展范围，§11-5）：`stock_status` 同时用于**商品卡片/列表**：
  - 卡片在 `low_stock` 显示紧凑徽章（`Only a few left`）；`in_stock` **不**显示库存徽章（避免噪音）；`preorder`/`backorder`/`out_of_stock` 沿用既有可售性表达（不重复）；
  - 列表分页响应每个 product 带 `stock_status`（同一次聚合查询，与详情同源）；
  - 列表缓存口径必须包含 `stock_status`，不得出现「已售罄仍显示有货」——实现时确认 `"use cache"` 现状并给出不陈旧方案（§7）。

## 4. 非功能需求（NFR）

- **NFR-001 隐私**：Store API 任何响应都不出现精确库存数字（含 `count_on_hand`、`total_on_hand`、`stock_items` 数量）。
- **NFR-002 性能**：product 详情 `stock_status` 计算不增加单次查询数（规格断言 SQL 计数不退化）；列表不计算。
- **NFR-003 兼容**：只增字段/只增端点字段，既有 SDK 消费者不破（`generated:check` 无漂移）。
- **NFR-004 a11y**：状态徽章与配送区块有可读文本（`aria-label`/语义元素），不靠颜色单独传达稀缺。
- **NFR-005 时区/工作日**：到达日期按店铺时区（`Store#timezone`）计算，工作日 = 周一~周五，不含法定节假日（文档明示）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-002/003：分桶口径逐项（>阈值 / 1..阈值 / 0+preorder / 0+backorder / 0）服务层断言，且与 `Variant#in_stock?` 判定一致（模型/服务规格）。
- AC-002 ← FR-003：`low_stock_threshold` 默认 5；非法值（0/负数/空）归一为默认；店铺偏好可改后分桶随之变化（模型 + 服务规格）。
- AC-003 ← FR-001/010：Store API variant/product 详情响应含 `stock_status` 枚举，且**响应体不含任何精确库存数字**（请求规格，断言 JSON 键集合）。
- AC-004 ← FR-004：product 详情计算 `stock_status` 的查询数不高于改动前基线（请求规格 SQL 计数）。
- AC-005 ← FR-006：`GET /api/v3/store/shipping_methods` 返回时效字段（含 null 分支）（请求规格）。
- AC-006 ← FR-007/008：`Shipping::Estimate` 输出矩阵——普通商品（有配送方式）/ 数字商品 / 无匹配方式 / 有免运费阈值 / 无阈值（服务规格）。
- AC-007 ← FR-009：PDP 组件按 estimate 渲染三种形态（有 min/max → 区间；仅 min → 单值；不可用 → 替代文案）并渲染免运费阈值（组件测试）。
- AC-008 ← FR-009：`Estimated arrival` 工作日推算正确（含跨周末、跨月的边界）（纯函数测试）。
- AC-009 ← FR-009/NFR-005：到达日期按店铺时区渲染、日期格式随 locale（组件测试断言 de/en 两种输出不一致且均非空）。
- AC-010 ← FR-001/009：PDP 徽章五态渲染 + `preorder` 保留 `preorderShipsBy`、`out_of_stock` 保留补货订阅入口（组件测试，回归 4.2）。
- AC-011 ← NFR-001/003：`generated:check` → **no drift**（OpenAPI + SDK 类型已同步）；Store API 快照键集合是**超集**而非替换（规格断言既有键仍在）。
- AC-012 ← NFR-004：配送区块/徽章的可访问性（状态文本可读、非纯色表达）（组件测试 `getByRole`/`getByText`）。
- AC-013 ← FR-011：列表 `GET /api/v3/store/products` 每个 product 含 `stock_status`，且与详情接口**同源一致**（同夹具下两接口结果相同）（请求规格）。
- AC-014 ← FR-004：列表查询数不随条数增长（1 条 vs 10 条 SQL 计数差 ≤ 常数）（请求规格）。
- AC-015 ← FR-011：商品卡片按状态渲染徽章（`low_stock` 显示、`in_stock` 不显示），列表页缺 `stock_status` 时不崩（件测试）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 搜索关键词 | 结论 |
|---|---|---|
| **App** `backend/app/` | `stock_status` / `low_stock` / `shipping` / `estimate` / `pdp` | 宿主 App 无库存/配送展示代码；`ai/` 无相关能力 → **无现成实现，需新建服务** |
| **Core** `backend/pallastrade_gems/pallastrade_core/app/` | `total_on_hand` / `can_supply` / `in_stock` / `threshold` / `shipping_method` | `Stock::Quantifier#total_on_hand`、`Variant#in_stock?/#preorder?/#backorderable?/#purchasable?`（`variant.rb:646/652/664`）、`Product#total_on_hand`（memoized）**已存在**；`ShippingMethod#estimated_transit_business_days_min/max` **已存在**（`shipping_method.rb` 校验 >=1）；`Store` 有 preferences DSL（`preference :xxx, default:`）→ 阈值**落点已有**；**无** low_stock/stock_status/estimate 概念 → 需新建（服务层，非模型） |
| **API** `backend/pallastrade_gems/pallastrade_api/app/` | `in_stock` / `backorderable` / `preorder` / `delivery_method` / `estimated` / `free_shipping` | `variant_serializer.rb`（`purchasable/in_stock/backorderable/preorder`）、`product_serializer.rb`（`purchasable/in_stock/backorderable/available`）已有布尔；`delivery_method_serializer.rb` **只有** `id/name/code/display_estimated_price`（**缺时效**）；`store/shipping_methods_controller.rb` 返回全部 `display_on: both/front_end`（**无国家过滤、无时效**）→ 需扩展 |
| **Admin** `backend/pallastrade_gems/pallastrade_admin/app/` | `shipping_method` / `transit` / `store form` / `preference` | `ShippingMethod` 编辑页已可填 transit days（既有字段）；店铺表单是 preferences 的既有编辑面（D 系列 / 多店审计）→ 只需加 `low_stock_threshold` 表单项 |
| **Storefront** `storefront/src/` | `shipping` / `estimate` / `arrival` / `freeShipping` / `lowStock` / `stock_status` | **零命中**：PDP 无配送区块；`lib/utils/variant-selection.ts` 的 `deriveAvailabilityState` 只有四态（4.2）；`ProductDetails.tsx` 展示 `preorder/backorder/sold out` 文案——本批在**其上扩展** low_stock + 配送区块 |
| **Platform** `platform/packages/` | `Variant` / `Product` / `DeliveryMethod` / `ShippingRate` | SDK 有 `Variant`/`Product` 类型（typelizer 生成）与 `DeliveryMethod` 类型 → 加字段后需 typelizer 重生成 + `generated:check`；无「estimates」资源 → 本批不新增 SDK 资源，只扩展既有类型 |

## 7. 技术影响

- **新增服务（Core）**：
  - `PallasTrade::Catalog::StockStatus`（纯函数：`for(variant:, threshold:)` / `for_product(product:, threshold:)`）；
  - `PallasTrade::Shipping::Estimate`（读模型：`call(store:, country:, product: nil, variant: nil)`）。
- **偏好**：`Store` 新增 `preference :low_stock_threshold, :integer, default: 5`、`preference :free_shipping_threshold, :decimal, default: nil`（方案 A）→ Admin 店铺表单新增两项 + 校验（AC-002）。
- **序列化**：`variant_serializer` / `product_serializer` 增 `stock_status`（typelizer 同步）；`delivery_method_serializer` 增时效字段。
- **路由**：`GET /api/v3/store/shipping_methods` 可接受 `?country=`（可选参数，缺省不过滤）→ 向后兼容。
- **契约**：`backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml` + typelizer 类型 + SDK `dist`（**注意 F-1 教训：dist 必须提交**）。
- **前台**：`ProductDetails.tsx` 价格区下方新增配送区块组件；`variant-selection.ts` 扩展 `low_stock` 态（纯函数 + 测试）；`messages/*.json` 5 语言。
- **不做**：不改库存预留/结算/发货链路；不新增库表；不在列表接口计算分桶；不解析节假日日历。

## 8. 测试计划

- **后端规格**：`spec/services/pallastrade/catalog/stock_status_spec.rb`（AC-001/002）、`spec/services/pallastrade/shipping/estimate_spec.rb`（AC-006）、`spec/requests/api/v3/store/products_reviews...` 不相关 → 改 `spec/requests/api/v3/store/products_spec.rb` 增 `stock_status` + 无精确库存断言（AC-003/004/011）、`spec/requests/api/v3/store/shipping_methods_spec.rb`（AC-005）、`spec/models/pallastrade/store_spec.rb` 或偏好规格（AC-002）、`spec/requests/pallastrade/admin/stores_spec.rb`（表单新增字段）。
- **注册 verifier**：`f2-stock-shipping-rspec`（上述规格合集）。
- **前台**：`src/components/products/__tests__/ShippingEstimate.test.tsx`（AC-007/009/012）、`ProductDetails` 徽章测试（AC-010）、`variant-selection.test.ts` 扩展（low_stock）、`checkout-i18n-keys.test.ts` 新增键组（AC-009 五语言）。
- **契约**：`harness generated:check`（AC-011）。
- **门禁**：`pnpm build`（F-1 教训：`typecheck`/`vitest` 查不出 `"use server"` 与 dist 类型问题）。

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-api-v3/SKILL.md`（`stock_status` 分桶口径 + 时效字段 + 不暴露精确库存原则）
- [ ] `ai/skills/pallastrade-storefront/SKILL.md`（PDP 库存徽章五态 + 配送区块 + 工作日/时区换算约定）
- [ ] `ai/skills/pallastrade-catalog/SKILL.md`（若含库存展示口径则同步；否则记「已评估，无需更新」）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`（Store 新增两个 preference 的语义与默认值）
- [ ] `ai/skills/pallastrade-i18n/SKILL.md`（已评估：为文案新增，键齐备由测试守护 → 记「已评估，无需更新」）
- [ ] `harness/scenarios/scenarios.json`（新增 GS：稀缺感用分桶表达、任何响应不含精确库存）
- [ ] `harness.config.mjs`（verifier `f2-stock-shipping-rspec`）+ `AGENTS.md` §6 行
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-16 | 0.1 | 初稿（Batch F-2：FR-001~010 / AC-001~012；范围 = §十一 库存阈值化 + 配送信息；待用户确认 §11 五个决策点） | AI |
| 2026-09-16 | 1.0 | 用户确认「确认实施」→ 状态 approved；决策：阈值默认 5 / 配送区块在 PDP 价格下方一行 / 免运费 = 店铺偏好+促销覆盖 / 到达日期 = 天数区间+日期区间 / **库存桶扩展到商品列表与卡片**（原推荐仅 PDP，用户选更大范围→新增 FR-011 与 AC-013~015，FR-004 改为「列表单次聚合、禁 N+1」） | AI |

## 11. 已确认决策（2026-09-16，用户回答）

1. **低库存阈值默认值**：**5**（`Store#low_stock_threshold`，admin 店铺表单可改）。
2. **配送区块位置**：**PDP 价格下方一行**。
3. **免运费阈值来源**：**店铺偏好 + 免运费促销覆盖**（偏好 `free_shipping_threshold`；存在活跃 `FreeShipping` 促销时显示「免运费」）。
4. **到达日期表达**：**天数区间 + 日期区间**（`3–5 business days · Sep 22–25`）。
5. **库存桶展示范围**：**PDP + 商品列表/卡片**（超出 AI 推荐的最小范围 → 已追加 FR-011 / AC-013~015 与列表性能约束）。
6. **确认实施**：用户已明确确认（“确认实施”）。
