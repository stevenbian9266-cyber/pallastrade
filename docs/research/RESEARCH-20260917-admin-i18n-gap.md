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
| `products` 域 | ✅ 23 键全部补齐（含保留 HTML 与 `%{link}` 插值的 `option_types_link`） |
| 断言 | ✅ i18n 键集断言新增 `products` 域；孤儿键断言排除 4 个既有导航键（不阻塞，但仍抓新孤儿） |
| 真实渲染 | ✅ AI Runs 页在中文后台 `translation missing` 计数 **0** |

> 剩余：约 875 键 / 113 个域（`orders` 103 最大），按上述建议分批。
