# 后台 i18n 缺口量化（2026-09-17）

> 由「实施」指示产出：量化后台中文覆盖率，为后续分批补齐提供依据。
> 触发原因：2026-09-16 在补 catalog 文案时发现「**只加 en 不会让任何测试变红**」——
> admin UI 语言取自 `current_store.preferred_admin_locale`，而 gem 只带 en。

## 方法

只读对比两侧键集：

- **基准**：gem `pallastrade_admin/config/locales/en.yml` 的 `pallastrade.admin.*` 全量键
- **对照**：宿主 `backend/config/locales/*.zh-CN.yml` 同 scope 的键集

## 结果

| 项 | 数值 |
|---|---|
| en 侧 `admin.*` 键 | **1969** |
| zh-CN 已覆盖 | **1175** |
| **缺失** | **898** |
| 有缺口的域 | **115** |
| 已完全覆盖的域 | 26 |

## 缺口最大的域

| 域 | 缺键数 |
|---|---|
| `orders` | 103 |
| `page_builder` | 35 |
| `tables` | 32 |
| `webhook_endpoints` | 25 |
| `store_setup_tasks` | 24 |
| `products` | 23 |
| `promotions` | 22 |
| `product_history` | 21 |
| `storefront_setup` | 21 |
| `publishing` | 18 |
| `webhook_deliveries` | 15 |
| `table` | 14 |
| `price_lists` | 13 |
| `store_form` / `variants_form` | 11 / 11 |
| `taxon_rules` | 10 |
| `oauth_applications` | 9 |
| …（其余约 100 个域，各 1~8 键） | |

## 为什么没有一次补完

**898 键不是一个批次能可靠做完的量。** 机翻质量会把中文后台变得**比缺文案更糟** ——
商家看到似是而非的中文，比看到英文更难判断自己在点什么。
本批只做了**有确定结论**的部分（catalog 域 + 后台外壳 + products.ai + ai.run）。

## 两个**结构性问题**（比缺键更值得先修）

### 1. scope 错位：已"翻译"的键取不到

`backend/config/locales/admin_ai.zh-CN.yml` 用的是 **`zh-CN.admin.ai.*`**（以及 `zh-CN.ai_tools` 等）
—— 而 `PallasTrade.t` 会 **prepend `:pallastrade`**（`lib/pallastrade/i18n.rb`），
所以这些键**永远不会被取到**，文件里的英文值也说明它们从未生效。

> 意味着：**真实覆盖率比 1175 更低**，因为其中一部分键的位置是错的。
> 2026-09-17 已修正（全部收进 `zh-CN.pallastrade.*`）。

### 1b. 键冲突：一个单词键能把整个功能域挤掉（修正 scope 时才暴露）

同一个文件末尾原有 `ai: AI` 这类**单词翻译**键 —— 它与**功能域** `pallastrade.ai`
（一个 Hash）**同名**。YAML 后键覆盖前键，于是：

```ruby
YAML.load_file('config/locales/admin_ai.zh-CN.yml')['zh-CN']['pallastrade']['ai']
# => "AI"        ← 应该是 Hash（内含 ai.run.* / admin.ai.*）
```

→ 整个 `ai.run.*` 全部失效，**且不报任何错**。修正 scope 后跑 spec 才发现：
`I18n.t('pallastrade.ai.run.id', locale: 'zh-CN')` 返回 nil，而文件的顶层结构看起来完全正常。

**教训**：
- 单词翻译键（`ai: AI` / `view: 查看`）**不能与功能域名同名**；
- 修正 scope 时**必须验证取值**（`I18n.t`），光看文件结构会被"看起来对"骗过；
- 这类错误**不会**报错、**不会**warning，只能靠真实取值或渲染发现。

### 2. Rails 内置键缺失

`zh-CN.datetime.distance_in_words` 缺失 → `time_ago_in_words` 在 AI Runs 页渲染成
`Translation missing: zh-CN.datetime.distance_in_words.less_than_x_minutes ago`。
这属于 **Rails / rails-i18n** 级别的覆盖，不是 gem 文案，需要单独引入。

## 建议

1. **先修结构性缺口**（scope 错位 + 键冲突 + Rails 内置键）—— 它们让"已经翻译"的键也白费；
2. 再按**商家实际使用频率**分批补域。本批已补 `products`（23 键，商品是后台最常用的域之一）；
   `orders`（103）最大但风险也最高，建议单独一批并配**真实渲染验证**；
3. **不要把 i18n 键集断言扩成"全量必须在 CI 绿"** —— 那会红一大片，最终结果是人们绕过它。
   建议：**守住增量**（新增键必须 en + zh-CN 同时存在，已有机制）
   + 存量按批次清，每批配一条"整页零 missing"断言。

## 本批已做（2026-09-17）

| 项 | 结果 |
|---|---|
| scope 错位 | ✅ `admin_ai.zh-CN.yml` 全部收进 `zh-CN.pallastrade.*` |
| 键冲突 | ✅ 移除与功能域同名的单词键（`ai: AI` 等），`pallastrade.ai` 恢复为 Hash |
| `ai.run.*` 表头 | ✅ 顺带补齐 8 个**原本就缺**的键（id/capability/model/status/tokens/latency/cost/time） |
| `products` 域（第一批） | ✅ 23 键全部补齐（含保留 HTML 与 `%{link}` 插值的 `option_types_link`） |
| `tables`（第二批） | ✅ 32 键（共享表格组件：筛选器/排序/列选择 —— 补一次全部列表页受益） |
| `variants_form`（第二批） | ✅ 11 键（含保留 `<a href="%{link}">` 与 `%{stock_location}` 插值） |
| `price_lists`（第二批） | ✅ 13 键 |
| 断言 | ✅ i18n 键集断言新增 `products` / `tables` / `variants_form` / `price_lists`；孤儿键断言排除 4 个既有导航键 |
| 真实渲染 | ✅ AI Runs 页零 missing；`/admin/products` 里**本批三域零 missing** |

## ⚠️ 真渲染新暴露的两件事（本批发现，尚未处理）

### A. 顶级键也缺（量化脚本未覆盖）

`/admin/products` 页面上还有一批 **`pallastrade.<key>` 顶级键**没有中文：

```
translation missing: zh-CN.pallastrade.products
translation missing: zh-CN.pallastrade.import / .export
translation missing: zh-CN.pallastrade.filtered_records
translation missing: zh-CN.pallastrade.admin.export_only_filtered_records
translation missing: zh-cn.pallastrade.in_stock / .variants
```

→ 本文开头的量化**只统计了 `pallastrade.admin.*`**，这份清单说明**顶级 `pallastrade.*` 也有一批缺口**。
真实缺口规模**大于 898**，需要下一次量化把顶级键一起算。

### B. locale 大小写不一致

同一页上同时出现 `zh-CN.…` 与 **`zh-cn.…`**（小写）两种前缀。
Rails 的 locale 区分大小写，因此**同一条键可能大小写不同而结果不同**；
需排查是否某处 `I18n.locale` 被设成了 `:zh-cn` / `'zh-cn'`（而非 `zh-CN`）。

> 两件都计在**下一批**处理（或单独一批）。

---

## 补充：第二轮量化与 B 的排查结果（2026-09-17）

### A 已量化 —— 真实缺口是 **1234**，不是 898

统计**全部** `pallastrade.*`（而非只看 `admin.*`）：

| 项 | 键数 |
|---|---|
| en 顶级 `pallastrade.*` 全量 | **2393** |
| zh-CN 已覆盖 | 1287 |
| **缺失** | **1234** |
| 其中 `admin.*` 前缀 | 819 |
| 其中**非** `admin.*`（顶级/其它） | **415** |
| 顶级**叶子**键（无子层） | **271** |

→ 本文开头报的「898」是**低估**（只统计了 `admin.*`）。
第三批已补顶级叶子键里的 38 个高频项（通用动作 / 列表页标题 / 调整项说明），
并给顶级键加了**单独断言**（原有的 `admin.<domain>` 结构检查覆盖不到它们）。

### B ✅ 已定位并修复 —— **不是 locale 被写坏，是键真的缺**

**先给结论：`I18n.locale` 自始至终是 `:"zh-CN"`（大写，正确）。
`translation missing: zh-cn.…` 里的**小写是 i18n 在 fallback 解析时另一次查表的产物**，
不是我们的 bug。**真正的问题是 `in_stock` / `variants` 这两个键在 zh-CN 下确实缺失。

**定位过程（临时日志，定位后已全部删除）**

在三个可疑位置插桩，记录**实际生效**的 locale：

| 插桩点 | 输出 |
|---|---|
| `Admin::BaseController#set_locale`（`super` 之后） | `I18n.locale=:"zh-CN" current_locale="zh-CN" default_locale="zh-CN" selected=nil cookie=nil store_pref="zh-CN"` |
| `ProductsHelper#display_inventory`（渲染库存列的 helper 内） | `I18n.locale=:"zh-CN" caller=…/tables/columns/_product_inventory.html.erb:3` |
| `PallasTrade.translate`（进入查表前） | `key=:in_stock I18n.locale=:"zh-CN" opts_locale=nil`（`:variants` 同） |

→ **发出 missing 的那次调用，locale 就是大写。** 结合浏览器侧：

| 事实 | 值 |
|---|---|
| `<html lang>` | `zh-CN` |
| `window.PallasTrade.locale` | `"zh-CN"` |
| `body` 上 `zh-cn.pallastrade.*` 出现次数 | **25**（全在服务端渲染的 `TD#inventory_product_N` 内） |
| `I18n.fallbacks[:"zh-CN"]` | `[:"zh-CN", :zh]` |
| `I18n.default_locale` / `enforce_available_locales` | `:en` / `true` |

#### 根因（两层，都要理解）

1. **表层**：这两个键在 zh-CN 下不存在 → 查表落空 → i18n 沿 fallback 链
   （`zh-CN` → `zh` → 默认 `en`）逐个尝试，最终在**某个层级**给出 missing 文本，
   该文本里的 locale 片段被渲染成 `zh-cn`。**小写只是表象**，
   把它当 bug 去"修 locale"会白费力气 —— 这一点是本次排查最重要的收获。
2. **深层**：这两个键是**顶级叶子键**（`pallastrade.in_stock`），
   而当时手上的量化脚本与断言都只看 `admin.<domain>` 结构，
   **覆盖不到顶级键**。所以它们不在 898 也不在后续几批的视野里，
   却出现在**每个商家每天都会看的**商品列表库存列上。

#### 为什么值得单独记一笔

- 该缺陷**不是**"少翻几个词"，而是**主列表页每行都报错**（用户看到的是
  英文夹 `translation missing`），属于**用户可见的破窗**。
- 它同时暴露了一个**量化盲区**：只按 `admin.*` 前缀统计会漏掉顶级键。
  顶级叶子键共 **271** 个，第三批已补 38 个高频项，其余仍需分批。
- **教训（已写入 skill）**：看到 `xxx.locale…` 形式的 missing，
  **先确认该 locale 下的键是否真的存在**，再怀疑 locale 变量本身。
  确认手段就是在上表那三处插桩（成本很低，一次请求即可返回结论）。

#### 修复

| 改动 | 内容 |
|---|---|
| `backend/config/locales/admin_top_level.zh-CN.yml` | 新增 `in_stock: 有货`、`variants: 变体`（带注释说明缺陷背景） |
| `backend/spec/i18n/admin_catalog_locale_coverage_spec.rb` | 两键加入 `TOP_LEVEL_BATCH`；新增回归块断言库存列拼接结果**恰为** `15000 有货 - 3 变体`，且不含 `translation missing` / `zh-cn.` |

#### 修复后实测

| 指标 | 修复前 | 修复后 |
|---|---|---|
| `body` 内 `zh-cn.pallastrade` 出现次数 | 25 | **0** |
| 库存单元格文本 | `translation missing: zh-cn.pallastrade.in_stock` | **`15000 有货 - 3 变体`** |
| 断言 | 58 examples | **63 examples, 0 failures** |

> 注：视图对两个标签调用了 `.downcase`（`PallasTrade.t(:in_stock).downcase` 之类），
> 中文不受 `downcase` 影响 —— 这是能安全补中文而非必须用英文的原因。
