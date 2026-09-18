# dev 环境 · 商品经营系统功能验证记录

| 项 | 值 |
|---|---|
| 日期 | 2026-09-18 |
| 环境 | dev（`dev.pallastrade.cn` / 阿里云 ECS `115.29.185.128`） |
| 代码版本 | `3c3bcfe9`（dev 分支） |
| 任务 | `TASK-20260917235829-d9580f8a` · gate `GATE-2026-09-17T23-58-41`（test / quick） |
| 性质 | 只读验证 + 已授权的演示数据写入（**无代码改动**，`git status` 为空） |
| 覆盖 | 商品升级方案 §4–§12 的服务层 + HTTP/页面层 |

---

## 一、磁盘清理（前置任务）

### 起因
服务器持续出现 `磁盘可用 < 5GB，执行 builder prune`，可用空间仅 5.8G（85% 已用）。

### 诊断到的真实问题（非预期）
一条 **2026-08-24 创建的僵尸看门狗进程**（PID 2379832）仍在运行：

```bash
bash -c while pgrep -f 'pull-deploy.sh dev' >/dev/null 2>&1; do sleep 10; done; echo PULL_DONE; ...
```

它的**自身命令行里就含 `pull-deploy.sh dev`**，于是 `pgrep -f 'pull-deploy.sh dev'` **匹配到自己** → 死循环至今（25 天）。
后果：任何 `pgrep -f pull-deploy` 都恒判「部署进行中」——本次磁盘清理脚本与部署预检都被它误导（表现为「等部署结束」永不返回）。

**处置**：kill 掉该僵尸进程；并把部署检测改为精确路径（`deploy/pull-deploy.sh`、`deploy/deploy.sh`）+ 构建进程匹配，避免自匹配。

### 结果

| | 清理前 | 清理后 |
|---|---|---|
| 磁盘可用 | **5.8G（85% 已用）** | **15G（61% 已用）** |
| 镜像 | 129 个 / 12.78GB（8.79GB 可回收） | **8 个 / 3.0GB（0% 可回收）** |
| 构建缓存 | 2.139GB | 1.151GB |

**净释放约 9.2GB。**

### 采用策略（保守，宁少勿错）
- ✅ `docker image prune -f` —— **仅删 dangling（`<none>`）**，即历史构建残留下来的无标签层
- ✅ `docker builder prune -f` —— 仅删**未被使用**的构建缓存
- 🚫 **不做** `docker system prune -a --volumes`
- 🚫 **绝不触碰 docker volume**（14 个，含 postgres / redis / meilisearch / storage 真实数据）
- 🚫 **绝不在部署进行中清理**（脚本内先确认无真实部署）

### 四条事后断言（全部通过）
| 断言 | 结果 |
|---|---|
| A 所有容器引用的镜像仍在 | `ALL_IN_USE_IMAGES_PRESENT`（7/7） |
| B 数据卷数量未变 | `before=14 after=14` → `VOLUMES_UNCHANGED` |
| C 容器全部在跑 | 7/7（web/worker/storefront/postgres/redis/mailpit/meilisearch） |
| D 服务健康 | `backend_up=200` · `storefront=200` |

---

## 二、演示数据（已按要求保留，不清理）

标记前缀 `DEMO-260918`，脚本可重复执行（幂等）。**最终零失败**。

| 对象 | 内容 | 目的 |
|---|---|---|
| `demo-260918-tshirt`（id 39） | 2 个 SKU：`-S`（价 29.99 / 库存 10）、`-L`（价 34.99 / **库存 0 + 可预售 + 预计发货 +14 天**） | Bulk 批量 / PDP 变体深链 / 预售语义 |
| 同上 · 商品级媒体 2 张 | 复用已有 blob（不向 OSS 重复上传） | 批量移除媒体 |
| 同上 · **变体级媒体 4 张** | dev 原本为 **0**，本次补齐 | 验证 Bulk Media 的「商品级 + 变体级」范围 |
| `demo-260918-tshirt-copy`（id 40） | **同名 + 同 SKU** | 重复商品检测（name / sku 两个信号） |
| `demo-260918-old-draft` | 草稿，`updated_at` 回拨 200 天 | Catalog Health「长期草稿」 |
| `demo-260918-no-media` | 在售 / 无媒体 / 零库存 | Catalog Health「缺图」「在售零库存」 |
| `demo-260918-neighbour` | 同分类（Kitchen）邻居 | 相关推荐数据面 |
| 3 个演示用户 + 3 条已审核评论 | 5 星 / 4 星 / 3 星 | 评分分布、排序、有用票 |
| 1 张有用票 | 作用于第 1 条评论 | Helpful Vote |
| 1 条 **SKU 级**到货订阅 | 绑定 `-L` 变体（dev 原本为 0） | §9 SKU 化 |
| 7 条商品事件 | 5 曝光 / 2 点击（推荐位 `demo-260918-list`） | CTR |

---

## 三、服务层验证结果（29/29 通过）

### §6 / §6.1 Catalog Health
```
七类问题计数（落点）
  missing_media        2   → products 过滤列表
  missing_description  0   → products
  missing_seo          4   → products
  missing_translations 179 → product_translations 专页
  active_zero_stock    2   → products
  redirect_unresolved  1   → redirects 专页
  old_drafts           1   → products

覆盖率 —— 五套各自独立的分母（一处分母定义）
  missing_media         2 / 42   = 4.76%    (未归档商品)
  missing_description   0 / 42   = 0.00%
  missing_seo           4 / 42   = 9.52%
  missing_translations  179 / 252 = 71.03%  (商品 × 语言槽位)
  active_zero_stock     2 / 41   = 4.88%    (active 商品)
  redirect_unresolved   1 / 2    = 50.00%   (变更总数)
  old_drafts            1 / 1    = 100.00%  (draft 商品)

可解释健康分 0.6569（7/7 维全部可计算，各维权重 1.0）
```

### §5.1 Bulk Operations 2.0（四类 preview 均**零写入**）
| 服务 | preview 结果 |
|---|---|
| BulkPriceUpdate | selected 1 / updated 1 / skipped 0 |
| BulkInventoryAdjust | selected 1 / updated 1 / skipped 0 |
| BulkChannelAssignment | selected 1 / updated 0 / **skipped 1**（空渠道集合正确跳过） |
| BulkMediaRemoval | selected 1 / updated 1 / skipped 0 |

零写入断言：商品级媒体 `[2,2]` · 变体级媒体 `[4,4]` · 库存 `[10,10]` → `zero_write: true`

### §12 商品治理
- `DuplicateCandidates.call` → 2 组，`{duplicate_name: 1, duplicate_sku: 1}`，**演示重复对被检出**
- `MergePreview.call(store:, survivor:, absorbed:)` → **零写入**（变体 4→4）；六个段落 `variants / master_stock / reviews / media / classifications / promotions` 各 2 条；`historical = {line_items: 0, orders: 0}`（历史交易零改写）
- `ProductHistory::Timeline` → 3 条，kind = `price`

### §11 库存分桶 / 配送
- 阈值 5；商品桶 `in_stock`
  - `DEMO-260918-TSHIRT-S`（在手 10）→ `in_stock`
  - `DEMO-260918-TSHIRT-L`（在手 **0 + 可预售**）→ **`preorder`** ✅ 预售语义正确
- `Shipping::Estimate` → `available=true, digital=false, 1–7 天, free_shipping=true`

### §16 指标数据面
- `Catalog::Operations::Report` → `scope_note: "all_stores"`（如实标注全库口径）；totals / bulk / maintenance 结构正常
- `CatalogEvent.list_metrics` → 演示推荐位 `impressions=5, clicks=2, ctr=0.4` ✅

### §9 SKU 级到货订阅
`BackInStockSubscription.where.not(variant_id: nil).count = 1`（variant_id 132 / demo-sku@example.com / active）

### §10 评论
- 评分分布 `{3=>1, 4=>1, 5=>1}`
- `most_helpful` 排序 `[[4,1],[6,0],[5,0]]`（票数降序 + id 降序稳定 tie-break）

### §7 AI Copilot
- 已注册能力 4 个：`catalog.product_description / product_seo / product_translation / health_fix_suggestion`
- 能力→模型绑定：**0 条**（dev 未配置）
- **未配置时的降级路径正确**：`generate_description` 返回 `status=:skipped, error_code="ai_disabled"`，**无异常、无 500** ✅

### §4 PDP 数据面
- 变体深链：`variant_pQHklVeMgb`（id 132）可解析，价 34.99，`preorderable=true`
- 预售：在手 0 + `preorderable=true` + `preorder_ships_at=2026-10-02` + 桶 `preorder`
- 相关推荐：分类 `Kitchen` 下同分类商品 2 个（除自己 1 个）
- 媒体：商品级 2 + **变体级 4**

---

## 四、HTTP / 页面层验证

### 前台 PDP
| 请求 | 结果 |
|---|---|
| `/us/en/products/demo-260918-tshirt` | 200 |
| `?variant=variant_pQHklVeMgb`（前缀 id） | 200 |
| `?variant=132`（数字 id） | 200 |
| 无效 variant | 200（回退默认 SKU，不报错） |

**落地 HTML 中的升级项标记（全部命中）**：
```
data-testid="availability-row"      ← §4.2 库存/预售行
data-testid="rating-distribution"   ← §10 评分分布
data-testid="review-sort"           ← §10 排序
data-testid="review-helpful-count-rev_..."   ← §10 有用票（计数）
data-testid="review-helpful-signin-rev_..."  ← §10 有用票（未登录引导）
data-testid="shipping-estimate"     ← §11 配送估算
'preorder' 出现 9 次                 ← §4.2 预售
SKU: DEMO-260918-TSHIRT-S           ← §4.1 变体
```

### 后台页面（应 302 登录跳转，不得 404）
`catalog_health` · `catalog_operations` · `duplicate_products` · `back_in_stock_subscriptions` · `reviews` · `product_translations` · `ai` · `ai/runs` · `ai/capabilities` · `products` → **全部 302** ✅

### Store API
- `/api/v3/store/products` → 200；`?expand=variants,media` → 200
- `POST /api/v3/store/catalog_events`（空批）→ **422**（整批拒收正确）

### 健康
`backend /up` 200 · `storefront /us/en` 200

---

## 五、结论与观察

**结论：商品升级方案 §4–§12 的已交付能力在 dev 上全部可用，未发现功能缺陷。**

### 附带发现（均非本次任务的缺陷）
1. **僵尸看门狗进程**（2026-08-24 起，已清理）——会让所有基于 `pgrep pull-deploy` 的部署检测永久误判。建议检查是否还有同类残留。
2. **dev 的 AI 能力未绑定模型**（`CapabilitySetting = 0`）——AI 功能会走 `ai_disabled` 降级路径。若要实际演示 AI 生成，需先在 `/admin/ai/capabilities` 绑定；**降级行为本身已验证正确**。
3. **不存在的商品 slug 返回 HTTP 200**（页面内渲染 404 文案）——软 404，对 SEO 不友好。属**既有**行为，与本次升级无关，建议单独立项评估。
4. **`Variant#options=` 的入参形状陷阱**（建演示数据时踩到）：它期望 `[{ name: <option_type>, value: <值名> }]`，传 `OptionValue` 对象会被 `next if option[:value].blank?` **静默跳过**，最终报出很具误导性的 `Option value variants can't be blank`。已记入仓库记忆。
