# REQ-20260915 — PDP 交易状态正确性（Variant 深链 + 预售语义 + 多 SKU 结构化数据）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-pdp-state-correctness.md`
> 任务：TASK-20260915093417-ae7e8ea3 ｜ Gate：GATE-2026-09-15T09-35-25

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | product / variant | 仅 `javascript/types/serializers/PallasTradeApiV3*Product*.ts`（生成类型） | 不适用（宿主层无业务代码） |
| App — views/decorators | `backend/app/` | seller / availability | 无 | 不适用 |
| Core Gem — models | `pallastrade_core/app/models/` | `purchasable?` / `in_stock?` / `preorder?` / `oversellable_now?` | `pallastrade/variant.rb`（L239 preorder 判定、L646 in_stock、L652 backorderable、L664 purchasable、L676 oversellable）、`pallastrade/product.rb`（状态机/委托） | **满足**：所需数据与语义已存在，零改动 |
| Core Gem — services | `pallastrade_core/app/services/` | variant / availability | 无与会话展示相关服务 | 不适用 |
| API Gem — controllers | `pallastrade_api/app/controllers/` | products/variants | `v3/store/products_controller.rb`（slug/prefixed id、available scope） | 已具备（无需改动） |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | — | — | 不涉及（零 admin 改动） |
| Admin Gem — views | `pallastrade_admin/app/views/` | — | — | 不涉及 |
| Storefront | `storefront/src/` | `variant` / `selectedVariant` / `view_item` / `Offer` | `products/[slug]/ProductDetails.tsx`（useState 无 URL 同步）、`products/[slug]/page.tsx`（仅 category_id 参数）、`lib/seo.ts#buildProductJsonLd`（单 Offer）、`lib/analytics/gtm.ts`（`trackViewItem(product, currency, variant?)` L168-178 已支持变体） | **部分满足** → 本需求在此层新建 |
| Platform | `platform/packages/` | CustomField / Variant / Product 类型 | `sdk/src/types/generated/{CustomField,Variant,Product}.ts`（`CustomField.key` 可供 brand 判定） | 满足（无 SDK 改动） |

### 搜索结论

- **后端（core/api/admin）零改动**：`preorder / preorder_ships_at / backorderable / purchasable` 已在 Store 序列化器输出（Product 与 Variant 双序列化器），本需求只消费。
- **Storefront 是本需求唯一改动层**：Variant 深链（URL ↔ 选中态）、展示态语义（预售/缺货可超卖）、结构化数据（AggregateOffer + brand）三处均为新建逻辑。
- **防重复判定**：grep `related|wishlist|recently_viewed` 等为 PHASE-C 范围，与本 PRD 无关；本 PRD 与既有 PRD 无重叠（`prd new` 查重通过）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级「Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions」——本需求是 storefront 展示层（TSX），走最上层路径，**零 gem 修改、零装饰器** |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读（审计轮） | 本次不触碰 admin；已知约定（导航自动推导面包屑、`product_form_partials` 注入点）本需求均不涉及 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | ①「商品不显示在店面」排查清单第 5 条：`product.in_stock?` 只看库存；② OptionType `kind`（swatch/buttons）由 VariantPicker 消费；③ metafields `display_on: front_end/both` 决定 Store API 是否输出（brand 取值依赖此） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 无接口改动 |
| `pallastrade-decorators` | ⬜ 不涉及 | — | 零后端改动 |
| `pallastrade-dependencies` | ⬜ 不涉及 | — | 无服务替换 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 到货订阅（事件层）属 PHASE-C |
| `pallastrade-storefront` | ☑ 涉及 | ✅ 已读 | ① PDP 数据经 `PRODUCT_PAGE_EXPAND`（variants/media/option_types/custom_fields/categories.ancestors）；② 客户端组件禁止 import `@/lib/pallastrade` barrel，SDK 调用必须走 server actions；③ 新组件遵循 srcSet/无障碍/五语言约定 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | storefront 测试栈 = Vitest + Testing Library，文件放 `storefront/src/**/__tests__/*.test.*`；后端 RSpec 不涉及 |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已读（键位守护范式） | 五语言文件 `messages/{de,en,es,fr,pl}.json`；缺键会渲染 key 本身（用户可见缺陷）→ 扩展 `checkout-i18n-keys.test.ts` 的 REQUIRED 模式守护 |

---

## 需求标题

PDP 交易状态正确性：Variant 深链 + 预售/缺货可购语义 + 多 SKU 结构化数据

## 任务类型

功能优化（前台展示层）

## 需求描述

商品详情页当前存在三类状态错误：① 变体选择不进入 URL（分享/刷新/投放丢失 SKU）；② 预售商品（可下单）被渲染成「缺货 + 到货订阅」；③ 多 SKU 商品的 JSON-LD 只输出单 Offer。本期以前台改造修正三者，全部复用既有后端字段。

## 影响范围（harness affected 输出）

```json
{"filesChanged":0,"affectedComponents":[],"errors":[],"estimatedTests":0}
```

（实施前输出——HEAD 干净；实施后以 `git diff` + `harness doc-impact` 复核。）

## 技术方案（初步）

- 决策树层级：**最上层（展示层）**——不新增模型/接口/事件；改动集中在 `ProductDetails.tsx`、`page.tsx`、`lib/seo.ts`、新纯函数模块。
- 纯函数抽取（`lib/utils/variant-selection.ts`）：`resolveInitialVariant`（选择优先级）、`deriveAvailabilityState`（状态推导）、`withVariantParam`（URL 参数构造）→ 表驱动单测。
- UX：预售徽标 + Ships by（locale 本地化）；缺货可超卖提示；两者隐藏订阅表单；不可购维持缺货 + 订阅。
- 结构化数据：单 → `Offer`；多 → `AggregateOffer`；availability 聚合映射；brand 取自定义字段。
- i18n：4 新键 × 5 语言 + 守护测试。

## 风险点

- 最高风险：组件测试对 `next/navigation` / `CartContext` 的 mock 成本 → 缓解：核心逻辑走纯函数测试，组件测试只断言渲染与 `router.replace` 调用。
- 回滚难度：低（纯前台文件，revert 一个提交即可）。

## 决策节点

> ⏸️ 用户已确认（2026-09-15 原话：「那就以此为作为 PRD 理想输入，实施」）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| storefront TSX/TS（PDP/JSON-LD/纯函数） | 见 PRD §7 清单 | `pnpm test`（storefront 全量） | 60 文件 / 367 用例全绿（~60s） | ✅ |
| 同上 | 同上 | `pnpm exec tsc --noEmit` | exit 0 | ✅ |
| 文案/i18n | `messages/{de,en,es,fr,pl}.json` | `pnpm check:locales` + i18n 守护测试 | 四语言与 en 全等；products 4 键守护通过 | ✅ |
| 注册 verifier（正式证据） | — | `harness verify storefront-test --task TASK-20260915093417-ae7e8ea3` | 收尾步骤执行（证据绑定 staged tree） | ⬜ |
| 文档影响 | PRD / REQ / Skill / scenarios.json | `harness doc-impact --base origin/dev` + `sync-check --ack` | 收尾执行 | ⬜ |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题 | — | N/A | 本任务零 admin 改动 |
| ② 面包屑 | — | N/A | 同上 |
| ③ 页面操作按钮 | — | N/A | 同上 |
| ④ Turbo method 约定 | — | N/A | 同上 |

### 验证结论

预检全绿：单测 367/367（variant-selection 18 例 / ProductDetails 7 例 / seo 扩展 5 例 / i18n 守护扩展）、`tsc --noEmit` exit 0、locale parity 五个文件全同步。正式 test 证据（注册 verifier `storefront-test`）与 `doc-impact` 在文档冻结后采集；无 TypeScript / Biome / 运行时回归。
