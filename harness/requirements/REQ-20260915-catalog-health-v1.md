# REQ-20260915 — 管理后台 Catalog Health V1（商品健康待办中心 + 一键过滤列表）

> 关联 PRD：`docs/prd/admin/PRD-20260915-admin-catalog-health-v1.md`
> 任务：TASK-20260915102309-5c510cc3 ｜ Gate：GATE-2026-09-15T10-25-52

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | catalog_health / 健康 | 无 | 不适用（零宿主改动） |
| App — views/decorators | `backend/app/` | catalog_health | 无 | 不适用 |
| Core — models | `pallastrade_core/app/models/` | media / status / preorderable / backorderable / translations | `product.rb`（`STATUSES=%w[draft active archived]`、`scope :not_archived`、`translates(… column_fallback:)`、`has_media?`、`media_count`）、`variant.rb`（`track_inventory`、`preorderable`、`backorderable` 库存点、`in_stock_or_backorderable`）、`asset.rb`（多态 `viewable`，**无 counter_cache**）、`redirect.rb`（`from_path/to_path/active`） | **数据齐备**（无需新表/迁移） |
| Core — services | `pallastrade_core/app/services/` | url change / translation coverage | `product_url_change.rb`（`sluggable_type=PallasTrade::Product` 的 friendly_id 历史 → `handled` 标记）、`locales.rb`（受支持语言解析）、`products/prepare_nested_attributes.rb`（权限范式） | **URL 未处理口径现成**；新增 2 个服务（Issues / Report） |
| API Gem — controllers | `pallastrade_api/app/controllers/` | catalog health | 无 | 不适用（本批不动 v3 API） |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | products index / translations / redirects / ops 页 | `products_controller.rb`（`scope` 由 `ResourceController#scope` 提供，可直接覆写）、`resource_controller.rb`（`collection → search_collection → scope.ransack`）、`product_translations_controller.rb`（覆盖率口径 `where.not(name: [nil,''])`）、`redirects_controller.rb`（`@url_changes = ProductUrlChange.call(store)`）、`base_controller.rb#authorize_admin`（`model_class` 决定授权锚点） | **框架就绪** → 新增 1 页 + 过滤接线 |
| Admin Gem — views/nav | `pallastrade_admin/app/views/`、`config/initializers/` | products_header_partials / navigation | `products/index.html.erb`（`render_admin_partials(:products_header_partials)`）、`engine.rb`（注入点注册）、`pallastrade_admin_navigation.rb`（`products.add` 子项 DSL） | **注入点现成** → 横幅零视图覆盖 |
| Storefront | `storefront/src/` | — | — | 不涉及 |
| Platform | `platform/packages/` | — | — | 不涉及 |

### 搜索结论

- 7 类问题**全部**可由既有数据推导，**零迁移**；缺口集中在「聚合展示 + 过滤下钻」。
- 两类下钻（缺翻译 / URL 未处理）**已存在专页**（Translations 覆盖率页 / Redirects URL 变更区块）→ 本批只做计数与跳转，不重复造页。
- 防重复：Products List 过滤通过覆写既有 `scope` 实现（不新增列表页、不复制表格配置）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：Admin 扩展（表格/注入点/导航注册）优先于「复制 gem 视图改宿主」；本次用 `products_header_partials` 注入点 + 导航注册，**零 gem 视图覆盖** |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 「只读运维页范式」四件套（控制器 / 表格 / 导航 / 权限）；**新增导航子项必须同步 `navigation_consistency_spec.rb` 子项数组断言**（历史踩坑 Orders/Promotions）；admin 页面三要素（标题/面包屑/操作按钮） |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | ① `Product#gallery_media`：产品级媒体优先、回退变体图 → 缺图判定必须**两层都查**；② 多语言内容经 Mobility `translates` + `column_fallback` → 读 effective 值要「翻译行优先、列回退」；③ `media_count` 为counter cache，但 `Asset` 无 `counter_cache` 声明 → 判空以 `pallastrade_assets` 事实表为准 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 不动 v3 API |
| `pallastrade-data-model` | ☑ 涉及 | ✅ 已读 | 商品/变体/库存点/翻译表列与索引（`status+deleted_at`、`media_count`、翻译 `locale` 唯一索引）→ 计数查询走索引 |
| `pallastrade-decorators` | ⬜ 不涉及 | — | 无宿主装饰器 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | — | 纯只读页，无事件 |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 前台零改动 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | 后端 = RSpec + Factory Bot；admin request spec 需登录 + `stub_authorization!`；**i18n 断言用 `PallasTrade.t`**（引擎翻译裸 `I18n` 查不到） |
| `pallastrade-i18n` | ☑ 涉及 | ✅ 已读 | admin 文案在 `pallastrade_admin/config/locales/en.yml`；新增键须与既有 `admin.*` 结构一致 |

---

## 需求标题

管理后台 Catalog Health V1：商品健康待办中心（缺图/缺描述/缺 SEO/缺翻译/零库存/URL 未处理/旧草稿）+ 一键进过滤列表。

## 任务类型

新功能（管理后台）

## 需求描述

运营进入 `/admin/catalog_health` 看到 7 类问题的实时计数；5 类商品级问题点击后进入**已过滤**的商品列表（计数 == 列表条数），勾选后可直接用 Batch B-1 批量动作处理；缺翻译 / URL 未处理直达既有专页。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 45,
  "affectedComponents": ["ai", "backend", "harness", "platform"],
  "estimatedTests": 135
}
```

> 注：`harness affected` 内部对 `origin/main...HEAD` 取 diff；本仓 dev-only 无 main（见 AGENTS §0.4），该条 error 不影响组件/测试估算。计数含并行会话（D8 支付适用范围）尚未提交的文件。

## 技术方案（初步）

- 决策树层级：**Admin 扩展（导航 + 注入点 + scope 覆写）+ Core 查询服务**——零迁移、零 API 变更、零 gem 视图覆盖。
- Core：`PallasTrade::CatalogHealth::Issues`（口径唯一权威：`product_relation(base, key, store:)` / `counts`）+ `Report`（编排 + 单项降级）。
- Admin：`CatalogHealthController`（`BaseController`，`model_class = PallasTrade::Product` 锚定授权）、`ProductsController#scope` 覆写（合法 `health_issue` 追加过滤）、横幅 partial 注册到 `products_header_partials`、导航子项。
- 一致性保证：计数与过滤共用同一 scope 构造器（规格断言「计数 == 列表条数」）。

## 风险点

- 最高风险：`ProductUrlChange` 为 Ruby 侧遍历（大目录有 N 次查询）；缓解：一期只做页面级统计，V2 下推 SQL（PRD §7 已记）。
- 口径漂移风险：缺翻译沿用既有翻译页口径（`name` 非空）并在 PRD §3.1 固化。
- 回滚难度：低（纯代码，无迁移；revert 即可）。

## 决策节点

> ⏸️ 用户已授权（2026-09-15 原话：「那就以此为作为 PRD 理想输入，实施」+「继续」）；本 PRD 为《商品升级方案》Batch B-2 的忠实切片。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core 服务（2 个） | `pallastrade_core/app/services/pallastrade/catalog_health/{issues,report}.rb` | `harness verify admin-catalog-health-rspec --task …` | 17 examples, 0 failures（2026-09-15，容器 `pallastrade-web-1`；含 7 类口径逐项 + 降级 200） | ✅ |
| Admin 控制器/路由/导航/视图/i18n | `pallastrade_admin/**` | 同上（请求规格覆盖计数、过滤、横幅、权限） | 17 例含：7 行渲染与下钻目标、`?health_issue=` 过滤（计数==列表条数）、非法 key 忽略、筛选横幅、导航项、无权限 302、i18n 逐键 | ✅ |
| 文档/知识 | Skill / scenarios / harness.config / AGENTS / PRD | `harness doc-impact` + `sync-check --ack` | admin Skill（Catalog Health 章节）/ GS-131（132/132 valid）/ verifier 注册 / AGENTS §6 行 / PRD 状态 done；nav:validate exit 0 | ✅ |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题 | `/admin/catalog_health` | ✅ | `content_for :page_title` + 导航 label（`admin.catalog_health.title`） |
| ② 面包屑 | `/admin/catalog_health` | ✅ | 导航推导（Products > Catalog Health）；navigation_consistency_spec 27 例绿 |
| ③ 页面操作按钮 | 无（只读页，操作在列表页） | N/A | 只读范式：无 new/edit 按钮；下钻均为 GET 链接 |
| ④ POST/PATCH/DELETE 链接用 `data: { turbo_method: }` | 页面内无写链接（仅 GET 下钻） | N/A | 过滤为 GET 链接 + 清除筛选链接 |

### 验证结论

<!-- 收尾时回填 -->

- **测试**：`admin-catalog-health-rspec` → 17 examples / 0 failures（新增页 + 过滤链路 + 导航一致性 27 例一并绿）。
- **口径要点**（实施中发现的事实）：工厂传播的库存点默认 `backorderable: true` → 「active + 零库存」夹具必须显式关闭 backorderable，否则商品实际可缺货售卖（口径正确、夹具需精确）。
- **知识同步**：admin Skill / GS-131（132/132 valid）/ verifier 注册 / AGENTS §6 全部落盘；nav:validate exit 0。
- **未越界声明**：不动 v3 API / OpenAPI / SDK；无 DB 迁移；无宿主 `backend/app/` 改动；零 gem 视图覆盖（仅 `products_header` 注入点）。
