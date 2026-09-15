# REQ-20260915 — 商城前台 Batch C-1（Related / Recently Viewed / Wishlist，本地优先）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-batch-c1-discovery.md`
> 任务：TASK-20260915104245-f860577b ｜ Gate：GATE-2026-09-15T10-44-19

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | wishlist / related | 无 | 不适用（零宿主改动） |
| App — views/decorators | `backend/app/` | wishlist / recently | 无 | 不适用 |
| Core Gem | `pallastrade_core/app/` | `in_stock` / `in_categories` / `BackInStockSubscription` | `concerns/pallastrade/product_scopes.rb`（`in_stock`/`in_categories`/`not_discontinued` ransack scopes）、`models/pallastrade/back_in_stock_subscription.rb`（仅商品级 → Batch C-2） | **过滤能力齐备**（Related 零后端改动） |
| API Gem | `pallastrade_api/app/` | product list filters | `store/products_controller.rb`（`q[...]` → search provider）、`concerns/.../search_provider_support.rb`、`search_provider/database.rb` | 支持 `in_categories`/`in_stock`，**无需新端点** |
| Admin Gem | `pallastrade_admin/app/` | wishlist | 无 | 不涉及 |
| Storefront | `storefront/src/` | wishlist / recently / related | `lib/data/products.ts`（`cachedListProducts`+`PRODUCT_CARD_FIELDS`）、`components/products/{ProductCard,ProductCarousel,FeaturedProducts}.tsx`、`components/layout/{Header,CartButton}.tsx`、`lib/__tests__/checkout-i18n-keys.test.ts` | **复用底座齐全** → 新增纯函数 + 组件 + 页面 |
| Platform | `platform/packages/` | wishlist | `sdk/src/types/index.ts#ProductListParams`（已含 `in_categories`/`in_stock`） | 不涉及（SDK 无需变更） |

### 搜索结论

- Related 可直接用既有列表 API 的 ransack 过滤（`in_categories` + `in_stock`），**不新增端点、不改 SDK**。
- 最近浏览 / Wishlist 走 **localStorage**（升级方案 §8.2/§8.3 明确 V1 本地、不建服务端模型），无后端改动。
- 防重复：复用 `ProductCard`/`ProductCarousel`（卡片与埋点零重写）、复用 `CartButton` 头部按钮范式、复用 i18n 守护测试文件。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 前台改动 = 直接改 `storefront/src/`（本仓自有源码），无「扩展点优先」约束；跨层能力（列表过滤）优先复用既有 API 而非新增端点 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | ① 组件必须 Tailwind class（AP-001 禁止内联样式）+ 设计 token（AP-006 禁止硬编码色）；② 客户端组件读浏览器状态须在 `useEffect` 后（hydration 安全）；③ 新增用户可见文案必须 5 语言齐备 + 守护测试 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | ① 商品可用性以 `in_stock`/`available` 语义为准（Related 需在售）；② `gallery_media` 两层媒体；③ 列表查询走 `PRODUCT_CARD_FIELDS` 精简字段 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 仅消费既有列表端点，不改接口 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | 前台 = vitest（jsdom + RTL）；测试文件与源码同目录 `__tests__/`；verifier 复用 `storefront-test` 全量套件 |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已读 | 5 语言（de/en/es/fr/pl）文件 + `checkout-i18n-keys.test.ts` 守护范式；键缺 = 用户可见缺陷 |
| `pallastrade-data-model` | ⬜ 不涉及 | — | 零迁移（本地存储） |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 纯前台（Batch C-2 才动事件层） |
| `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 零后端改动 |

---

## 需求标题

商城前台 Batch C-1：Related Products（同分类规则推荐）/ Recently Viewed（本地 12 条）/ Wishlist（本地 + 页面 + 头部入口）。

## 任务类型

新功能（前台转化与留存）

## 需求描述

PDP 底部新增「相关商品」与「最近浏览」区块；PDP 加爱心入 Wishlist；头部新增 Wishlist 入口；`/wishlist` 页面可查看/移除。Related 走服务端规则（同分类 + 在售 + 排除自己），最近浏览与 Wishlist 走 localStorage V1。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 61,
  "affectedComponents": ["ai", "backend", "harness", "platform", "storefront"],
  "estimatedTests": 168
}
```

> 注：`harness affected` 内部对 `origin/main...HEAD` 取 diff；本仓 dev-only 无 main（AGENTS §0.4），该 error 不影响估算；计数含并行会话（D8）未提交文件。本任务自身仅改 `storefront/**` 与文档。

## 技术方案（初步）

- 纯函数下沉：`related-products`（查询构造 + 排除自身/截断）、`recently-viewed` / `wishlist`（解析/去重/切换/上限 + 事件名）。
- 组件：Related（服务端）+ RecentlyViewed/Tracker/WishlistButton（客户端，挂载后读库）+ 头部入口（镜像 CartButton）。
- 页面：`/wishlist`（服务端壳 + 客户端列表）。
- i18n：5 语言 + 守护测试追加；埋点沿用 `ProductCard`（`listId` 区分区块）。

## 风险点

- 快照价格过期（V1 接受，点击进 PDP 为准）；localStorage 不可用 → try/catch 静默降级。
- SSR/hydration：所有本地读取在挂载后；未挂载返回 `null`。
- 回滚难度：低（纯前台代码，revert 提交即可）。

## 决策节点

> ⏸️ 用户已授权（2026-09-15 原话：「那就以此为作为 PRD 理想输入，实施」+「继续」）；本 PRD 为《商品升级方案》Batch C 的忠实切片（C-2 SKU 级到货订阅另行立项）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 纯函数（3 个）+ 存储封装 | `src/lib/utils/{related-products,recently-viewed,wishlist,local-store}.ts` | `harness verify storefront-test --task …` | 定向跑 12 文件 85 例绿（含 new vitest 用例：去重/上限/脏数据/降级） | ✅ |
| 组件 + 页面 + Header | `src/components/**`、`src/app/**/wishlist/**`、PDP 接线 | 同上（RTL 组件测试：首帧空/挂载后渲染/切换写库/空态） | 组件测试 7 例绿；`pnpm -C storefront typecheck` 0 错误；biome 0 warning | ✅ |
| i18n + 守护 | `messages/*.json`（5） + `checkout-i18n-keys.test.ts` | 同上（守护测试逐语言断言） | 12 文件 85 例绿（含 checkout-i18n-keys 守护） | ✅ |
| 文档/知识 | storefront Skill / scenarios / PRD | `harness doc-impact` + `sync-check --ack` | Skill discovery rails 章节 + GS-132（133/133 valid） | ✅ |

### 新增前台页面检查（固定检查项）

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题 / metadata | `/wishlist` | ✅ | 服务端壳导出 `generateMetadata`（title + `robots.index=false`），客户端列表在壳内 |
| ② i18n 键齐备（5 语言） | 全部新增文案 | ✅ | 守护测试 `checkout-i18n-keys.test.ts` REQUIRED 已登记 |
| ③ 空态 | `/wishlist`、Related、最近浏览 | ✅ | wishlist 空态引导回目录；两个 rail 空则整块不渲染 |
| ④ a11y | 爱心按钮、头部入口 | ✅ | `aria-pressed` 反映状态 + `aria-label` + 数量徒章；区块 `aria-labelledby` |
| ⑤ SSR 安全 | 本地存储组件 | ✅ | 首帧返回 `null` / 徽章 0，挂载后同步（测试断言首帧空） |

### 验证结论

<!-- 收尾时回填 -->

- **测试**：定向 vitest 12 文件 / 85 例绿（纯函数 + 组件 + i18n 守护）；`pnpm -C storefront typecheck` 0 错误；biome check 0 warning。
- **实施事实**：`getTranslations` 的 `locale` 参数需全局 `Locale` 类型（页面传参 `locale as Locale`）；`product.price?.currency` 为 `string|null` → 传给 props 需 `?? undefined`。
- **边界**：零后端改动（不改 v3 API / 无迁移 / 无新依赖）；两 rail 本地存储，隐私模式静默降级。
- **知识同步**：storefront Skill（discovery rails 章节 + 六条约定 + changelog）/ GS-132（133/133 valid）/ PRD 状态 done。
