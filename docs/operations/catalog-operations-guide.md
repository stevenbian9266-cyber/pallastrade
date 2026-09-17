# 商品经营系统 · 使用手册（Catalog Operating System）

| 项 | 值 |
|---|---|
| 适用版本 | `b1b055e7`（dev）及以后 |
| 覆盖范围 | 商品域升级方案 §4–§12 交付的全部前台/后台能力 |
| 交付审计 | `harness/reviews/REVIEW-20260918-catalog-upgrade-completion-audit.md` |
| 读者 | 商家运营人员（§2–§3）、开发/运维（§4） |

---

## 1. 这套系统改变了什么

升级前：**商品列表 → 逐个编辑商品**。
升级后：**商品 → Catalog Health（发现问题）→ 批量操作（处理）→ 商品编辑（细节）**，AI 作为辅助嵌入每个环节。

三条主线：

| 主线 | 解决的问题 |
|---|---|
| 前台正确性与转化 | 变体深链、预售/缺货语义、配送时效、相关推荐、最近浏览、收藏 |
| 后台运营效率 | 批量改价/库存/渠道/媒体、健康待办、重复商品治理、运营报表 |
| 商品质量与效率 | Catalog Health（含可解释健康分）、AI Copilot（描述/SEO/翻译/修复建议） |

---

## 2. 商家侧使用说明（后台）

### 2.1 菜单地图

| 菜单 | 位置 | 路径 |
|---|---|---|
| Products（商品列表） | Products | `/admin/products` |
| **Catalog Health** | Products 子菜单（第 8 位） | `/admin/catalog_health` |
| **Duplicate Products** | Products 子菜单（第 9 位） | `/admin/duplicate_products` |
| **Catalog Operations**（运营报表） | Products 子菜单（第 9.5 位） | `/admin/catalog_operations` |
| Price Lists | Products 子菜单 | `/admin/price_lists` |
| Stock | Products 子菜单 | `/admin/stock_items` |
| Translations | Products 子菜单（第 25 位） | `/admin/product_translations` |
| Categories | Products 子菜单 | `/admin/taxonomies` |
| Reviews | 侧栏（第 172 位） | `/admin/reviews` |
| Back-in-stock subscriptions | 侧栏（第 170 位） | `/admin/back_in_stock_subscriptions` |
| AI Tools | 侧栏 | `/admin/ai` |

---

### 2.2 批量操作（Bulk Operations）

**入口**：`/admin/products` → 勾选商品 → 顶部 **Bulk actions** 下拉。

**统一交互**（高风险操作强制）：**选择 → 配置 → 预览 → 确认 → 结果**。

| 批量动作 | 作用 | 需要预览 |
|---|---|---|
| Set active / Set draft / Set archived | 批量改状态 | 否 |
| Add to / Remove from categories | 批量归类 | 否 |
| Add tags / Remove tags | 批量打标签 | 否 |
| **Set price** | 设定固定价 | **是** |
| **Adjust price %** | 按百分比调价 | **是** |
| **Adjust inventory** | 增减库存 | **是** |
| **Add to / Remove from channels** | 批量渠道上下架 | **是** |
| **Remove media** | **清空所选商品的全部图片** | **是** |

#### 预览页会给你的数字

预览与执行走**同一套代码**，所以预览的计数必然等于执行结果：

| 字段 | 含义 |
|---|---|
| Selected | 选中的商品数 |
| Will update | 实际会被改动的数量 |
| Skipped | 不会被改动的数量（原因见 Warnings） |

#### 常见 Warning 与处理

| Warning | 含义 | 处理 |
|---|---|---|
| `permission_denied` | 你没有该商品的权限 | 找管理员补权限 |
| `no_price` / `negative_result` | 没有价格 / 调整后为负 | 先补价格 |
| `inventory_not_tracked` | 未开启库存跟踪 | 在商品编辑页开启 |
| `clamped_at_zero` | 扣减后会被夹到 0 | 属正常，确认即可 |
| `media_permission_denied` | 能改商品但**不能管理媒体** | 需要 `manage Asset` 权限 |

> ⚠️ **批量移除媒体不可撤销。** 它会清空所选商品的**商品级图片 + 该商品所有变体（含 master）的图片**，并清空 `primary_media_id` 指针。
> 清空后这些商品会**自然出现在 Catalog Health 的「缺图」待办里** —— 这是设计好的闭环：先清掉错的，再从待办里重传。

---

### 2.3 Catalog Health（商品健康待办中心）

**入口**：Products → **Catalog Health**

它不是报表，而是**待办中心**：点击任意问题数量 → 直接进入**过滤后的商品列表**，可以立即接批量操作。

#### 七类可执行问题

| 问题 | 判定口径（要点） |
|---|---|
| Missing image | 商品级与变体级**都没有**资产 |
| Missing description | 翻译行优先，回退到模型列 |
| Missing SEO | 同上口径 |
| Missing translations | 按语言槽位比对 |
| Active + zero stock | 在售但没有可售变体（考虑 `track_inventory` / `preorderable` / `backorderable`） |
| Old drafts | 长期停留在 draft |
| Redirect unresolved | 存在未处理的历史 URL 变更 |

#### 覆盖率（五套分母，各自独立）

| 维度 | 分母 |
|---|---|
| 内容（图/描述/SEO） | 未归档商品 |
| 库存 | active 商品 |
| 草稿 | draft 商品 |
| 翻译 | 商品 × 语言槽位 |
| URL | 变更总数 |

#### 可解释健康分（0–100）

- **等权**：只对**可计算**的维度加权。
- **不编造**：某维度分母为 0 或计数报错时，该维度**被排除**，既不记 0 也不记满分。全部维度都不可计算时，总分显示为 `—`（`nil`），而不是 0。
- 工作台会列出每一维的**分子 / 分母 / 权重 / 未计入原因**，你可以手工复算。

> 设计原则：**能被复算的分数才可信。**

---

### 2.4 Catalog Operations（商品运营报表）

**入口**：Products → Catalog Operations

只读报表，两个时间窗（7 天 / 30 天）。回答两个问题：

| 区块 | 回答的问题 |
|---|---|
| `operations` | 这段时间**批量操作**了多少条、覆盖了多少商品（去重） |
| `maintenance` | 平均每个被维护的商品经历了多少次编辑 |
| `actors` | 谁在改（无操作人的写入归入 `system`，不冒充「人」） |

> ⚠️ **口径提示**：底层审计表**没有店铺维度**，所以本报表是**全库口径**，页面会如实标注 `all_stores`。多店作用域是独立议题。

---

### 2.5 重复商品检测与合并

**入口**：Products → **Duplicate Products**

#### 三类重复信号

| 信号 | 说明 |
|---|---|
| duplicate_barcode | 变体条码相同 |
| duplicate_sku | SKU 相同（注意：SKU 校验可被关闭或留空） |
| duplicate_name | 名称相同（忽略大小写与首尾空格） |

> 注意：**slug 不算信号** —— 系统会自动补 uuid 保证唯一。

#### 操作流程

1. 工作台按信号分组列出候选；
2. 点进**对比视图**逐字段比对；
3. 「合并」→ 先看**预检**（零写入）→ 确认执行；
4. 合并会写入 `pallastrade_product_merges` 台账；
5. **可以撤销**（`undo_merge`），逐项还原。

#### 合并的硬约束（重要）

- **历史交易零改写** —— 已产生的订单、支付、退款记录不会被改动；
- SKU / 评论冲突时**跳过并保留在原处**，不静默丢弃；
- 归档 / 软删 / `merged_into` 均留痕；
- **撤销时若存在阻塞项则整体拒绝**，不会做一半。

---

### 2.6 Product History（商品时间线）

**入口**：商品编辑页 → 侧栏 **History**

展示价格、状态、渠道、库存关键变化、slug 变化、操作者与时间。

- **只记变化字段**：无变化的保存不产生条目（保持时间线可读）；
- 批量操作给**每个受影响商品各记一条**，并带批次计数；
- 与价格历史合并后**倒序**呈现。

---

### 2.7 评论审核

**入口**：侧栏 → **Reviews**（`/admin/reviews`）

| 能力 | 说明 |
|---|---|
| 图片列 | 列表直接看到评论附图 |
| **批量通过 / 拒绝** | 勾选后一次最多 **50 条** |
| 逐条鉴权 | 无权限的条目**跳过并计入报告**，不整批失败 |
| 四计数报告 | 成功 / 跳过 / 失败 / 总数 |
| Helpful 列 | 展示「有用」票数 |

> 公开口径是**只增不改**：审核只改变可见性，不修改评论内容。

---

### 2.8 AI Copilot

#### 先配置（一次性）

**入口**：侧栏 → **AI Tools**（`/admin/ai`）

1. **Providers** —— 配置供应商与 API Key（支持 OpenAI / DeepSeek），可点「Test connection」验证；
2. **Models** —— 启用要用的模型；
3. **Capabilities** —— 为每个 AI 能力指定使用哪个模型。

> API Key 只保存在服务端，页面不会回显明文。

#### 四个可用能力

| 能力 | 入口 | 产出 |
|---|---|---|
| 商品描述 | 商品编辑页 → Description → `[Generate with AI]` | 描述文案 |
| SEO | 商品编辑页 → SEO → `[Generate SEO]` | Meta title + Meta description |
| 翻译 | 翻译抽屉 → `[AI Translate Missing]` | **仅缺失**的语言字段 |
| 健康修复建议 | Catalog Health 工作台行内面板 / 商品侧栏卡片 | 针对该健康问题的修复建议 |

#### 安全边界（这是设计约束，不是缺陷）

- AI **不会**自动改价格、自动调库存、自动上下架、自动改渠道；
- 所有产出都是 **Generate → Preview → Accept → Save**，**Accept 之前不落库**；
- AI 的翻译只**填充缺失**字段，不会覆盖已有译文；
- 每一次 Run（输入/输出/用量/成本）都留痕，可在 **AI Tools → Runs** 查看；
- 你点了 Accept 之后又改了内容，系统会记录「**采纳后已修改**」——这是衡量 AI 实际有用程度的指标。

---

### 2.9 Back-in-stock 订阅（SKU 级）

**入口**：侧栏 → **Back-in-stock subscriptions**

- 前台用户可选**具体 SKU** 订阅（如某个尺码/颜色）；
- 库存恢复时**只通知订阅该 SKU 的用户**，不会给全商品订阅者发错货信息；
- 后台按 **Product / Variant（SKU）** 查看；
- 历史遗留的**商品级订阅仍然有效**，不影响老数据。

---

### 2.10 商品翻译覆盖

**入口**：Products → **Translations**

展示每种语言的**已翻译数 / 总数 / 进度条**；没有配置多语言时会显示空态引导。

---

## 3. 消费者侧功能说明（前台 PDP）

### 3.1 变体深链（可分享的规格链接）

链接格式：

```
/{country}/{locale}/products/{slug}?variant={variant_id}
```

| 行为 | 结果 |
|---|---|
| 直接打开带 `variant` 的链接 | 自动选中该 SKU |
| 页面内切换规格 | URL **静默更新**（不刷新页面、不新增历史记录负担） |
| 刷新 | 保持原 SKU |
| 分享 / 广告落地 | 接收方打开同一 SKU |
| `variant` 无效或不存在 | 回退到默认 SKU（不报错） |

> **SEO 说明**：canonical 仍指向商品主 URL（不带 variant），这是刻意设计——本阶段**不制造 SKU 级独立 SEO 页面**。

### 3.2 库存 / 预售 / 缺货状态

PDP 统一为五种语义，**不再只有「有货 / 缺货」二元**：

| 状态 | 页面表达 |
|---|---|
| In Stock | 正常购买 |
| Low Stock | 少量库存提醒 |
| Pre-order | 预售 + 预计发货日期 |
| Backorder | 可购买 + 延迟发货说明 |
| Out of Stock | 到货通知（可选具体 SKU） |

> **重要**：只会展示**分桶**（如「仅剩少量」），**不会把精确库存数字下发给浏览器**。这既产生稀缺感，也避免库存被爬虫抓走。

### 3.3 配送估算

PDP 展示：**配送时效**、**预计到货**、**免运费门槛**（未达门槛时提示「满 X 免运费」，已达则显示「免运费」）。

估算按访客所在国家计算；拿不到数据时整块不渲染，不显示占位假数据。

### 3.4 商品发现

| 能力 | 说明 |
|---|---|
| **Related Products** | 同分类 + 有货的规则推荐（**不是**推荐算法，limit 8，自动排除自己）；无结果时整块不渲染 |
| **Recently Viewed** | 本地存储，最多保留 10–20 条；无需登录 |
| **Wishlist（收藏）** | V1 本地存储；按钮为次要样式，不抢主 CTA |

> Wishlist 后续如需跨设备同步，属于用户账户体系（V2），本阶段不做服务端模型。

### 3.5 评论

| 能力 | 说明 |
|---|---|
| 评分分布 | 各星级数量与列表**同源**（不可能出现对不上的情况） |
| 分页 | Load more，默认每页 10 条，最多 100 |
| 排序 | 最新 / 最高分 / 最低分 / **最有帮助**（未知值自动回退默认） |
| 图片评论 | 每条最多 3 张；未审核的图片**不会外泄** |
| Helpful Vote | 一人一票（可撤销）；未登录可以看到票数，投票时引导登录；**不能给自己投票** |

---

## 4. 技术说明

### 4.1 关键配置

| 配置 | 位置 | 说明 |
|---|---|---|
| AI 供应商与密钥 | `/admin/ai/providers` | 只存服务端，不回显 |
| AI 能力→模型绑定 | `/admin/ai/capabilities` | 逐能力配置 |
| 退货条款（JSON-LD 用） | 后台 **Policies** 页 | 存于 `pallastrade_policies.preferences`，随现有 `policies#show` 下发，**零新端点** |
| 免运费门槛 / 时效 | 配送方式与运费规则 | 由 `Shipping::Estimate` 读模型汇总 |
| Catalog Health 阈值 | `PallasTrade::CatalogHealth::*` | 口径唯一来源在 `issues.rb` / `coverage.rb` |

### 4.2 结构化数据（JSON-LD）

商品页输出 `Product` 结构化数据：

- **单 SKU** → `Offer`
- **多 SKU** → `AggregateOffer`（`lowPrice` / `highPrice` / `offerCount` / `availability`）
- 第二阶段字段：`seller`、`priceValidUntil`（取自命中的价目表结束时间）、`shippingDetails`（复用 PDP 已取到的运费估算）、**结构化** `hasMerchantReturnPolicy`

> **铁律：缺数据一律不输出**。宁可少一个字段，也不输出编造或空值——否则会被搜索引擎判为欺骗。

### 4.3 商品事件回流（自有数据）

前台按页面浏览聚合并批量上报（一次最多 100 条）：

| 事件 | 用途 |
|---|---|
| `impression` | 推荐位/列表曝光（CTR 分母） |
| `click` | 点击（CTR 分子） |
| `product_added` | 加购 |
| `product_searched` | 搜索 |

- 表：`pallastrade_catalog_events`（**只追加**，保留 90 天，有清理作业）
- **幂等**：靠 `event_id` 唯一约束去重，重复上报不重复计数
- **跨店隔离**：按 store 分区
- **零 PII**：不存 IP / UA / 邮箱 / 客户 ID；访客标识是**服务端 HMAC 摘要**（按店铺派生，跨店不可关联、不可逆）
- **旁路表**：任何业务路径（库存 / 价格 / 订单 / 结账）**不得读它做判定**，整表可随时清空而不影响业务
- **CTR 分母为 0 时返回 `nil`**，不返回 0 也不返回 1

### 4.4 权限

| 能力 | 需要的权限 |
|---|---|
| 批量改价 / 库存 / 渠道 / 状态 | 对商品的 `update` |
| **批量移除媒体** | 对 `PallasTrade::Asset` 的 `manage`（与商品权限独立） |
| Catalog Health / Duplicate / Operations | 对商品的 `read` |
| 评论审核 | 对 `PallasTrade::Review` 的 `manage` |
| Back-in-stock 订阅 | 对 `PallasTrade::BackInStockSubscription` 的 `manage` |

> 批量操作**逐条鉴权**：无权限的条目会被跳过并计入 Warnings，**不会整批失败**。

### 4.5 已知口径与边界

| 事项 | 说明 |
|---|---|
| 运营报表是全库口径 | 底层审计表无店铺维度，页面标注 `all_stores` |
| 批量动作的店铺范围 | `bulk_collection` 只按 ability 过滤，超管权限为跨店。**Bulk Media（不可撤销）已单独收窄到当前店铺**；其余动作沿用框架既有行为，建议独立立项处理 |
| 「变体选择 → 加购」指标 | 无独立埋点（`view_item` 有意只在页面打开时触发一次，以保证 GA4 的 SKU 与分享 URL 一致）。需要时另立小需求新增 `select_variant` 事件 |
| Back-in-stock 转化归因 | 表内无 source 字段，订阅→购买的归因依赖 GA4 会话拼接 |

### 4.6 变更后的验证方式

| 改动类型 | 验证命令 / 验证器 |
|---|---|
| 批量价格/库存/渠道 | `harness verify admin-products-bulk-rspec` |
| 批量移除媒体 | `harness verify bulk-media-rspec` |
| Catalog Health | `harness verify admin-catalog-health-rspec` |
| 重复商品 / 合并 | `harness verify duplicate-products-rspec` / `d3-product-merge-rspec` |
| Product History | `harness verify product-history-rspec` |
| 评论（F1–F5） | `harness verify reviews-f1-rspec` / `f3-review-bulk-rspec` / `f4-review-sorting-rspec` / `f5-helpful-vote-rspec` |
| 库存/配送 | `harness verify f2-stock-shipping-rspec` |
| 到货订阅 | `harness verify back-in-stock-rspec` |
| AI Copilot / 翻译 / 建议 | `harness verify ai-copilot-rspec` / `ai-translate-rspec` / `ai-health-suggestion-rspec` |
| 商品事件回流 | `harness verify catalog-events-rspec` |
| 前台整体 | `harness verify storefront-test` |
| 导航结构 | `node scripts/nav-validate-static.mjs` |

---

## 5. 快速上手（运营人员 10 分钟）

1. 打开 **Products → Catalog Health**，看清七类问题各有多少；
2. 点「Missing image」的数量 → 进入过滤后的商品列表；
3. 勾选要处理的一批商品 → **Bulk actions → Remove media** → 看预览 → 确认（清掉错图）；
4. 再从待办进入、逐个补传正确图片；
5. 打开 **Products → Duplicate Products**，处理重复商品（对比 → 合并 / 撤销）；
6. 打开 **Products → Catalog Operations**，看本周批量操作规模与维护比率；
7. 在商品编辑页用 **Generate with AI / Generate SEO / AI Translate Missing** 提升内容质量，**Accept 前一律先预览**。
