# REQ-20260817-stores-currency-unify — 统一新建店铺与市场的 currency 选择器（本地化显示）

> 关联 PRD：PRD-20260817-admin-新建店铺表单-货币语言选择器与邮箱预设（迭代 2）
> 关联任务：TASK-20260817083140-7c836c69
> 类型：功能优化（`优化：`前缀，用户 2026-08-17 明确回复"优化"确认）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | currency_options / CurrencyHelper / Money::Currency / display_names | 无 | 不涉及 |
| App — views/decorators | `backend/app/` | 同上 | 无 | 不涉及 |
| Core Gem — models | `pallastrade_core/app/models/` | `PallasTrade::Currency`（`name`/`label`，包 `Money::Currency.find`）、`concerns/pallastrade/stores/markets.rb`（`supported_currencies_list` → `Array<Money::Currency>`） | **复用数据源** |
| Core Gem — helpers/services | `pallastrade_core/app/helpers/` | `currency_helper.rb`（`currency_options` / `currency_presentation` / `supported_currency_options`，用 `::Money::Currency.table`）、`locales.rb`（`Locales::ALL`） | **复用 helper** |
| API Gem — controllers | `pallastrade_api/app/controllers/` | `concerns/pallastrade/api/v3/locale_and_currency.rb`（API v3 只读参考 Money::Currency） | 不涉及（只读参考） |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | `stores_controller.rb`（`all_currencies` helper_method：`::Money::Currency.all`） | 本次改造对象（可移除） |
| Admin Gem — views | `pallastrade_admin/app/views/` | `stores/new.html.erb`（迭代 1：`all_currencies` + 无 display_names_type）、`markets/_form.html.erb`（**currency 用 `currency_options` + `display_names_type: 'currency'`；locale 用 `display_names_type: 'language'` —— 对齐目标**）、`gift_cards/_form`、`gift_card_batches/_form`、`orders/_form`、`store_credits/_form`、`promotion_rules/forms/_currency`（均用 `supported_currency_options`，只读） | **本次改造对象** |
| Admin Gem — JS | `pallastrade_admin/app/javascript/` | `controllers/autocomplete_select_controller.js` + `helpers/display_names.js`（`Intl.DisplayNames` 本地化 option 标签，由 `data-display-names-type` 触发） | **复用** |
| Storefront | `storefront/src/` | currency_options / display_names / currencyOptions | 无 | 不涉及 |
| Platform | `platform/packages/` | 同上 | 无 | 不涉及 |

### 搜索结论

- **数据源单一**：markets 与 stores 表单的货币均来自 money gem ISO 4217（`::Money::Currency.table` / `.all` 同源）；语言均来自 `PallasTrade::Locales::ALL`。
- **markets 表单已有完整先例**：`currency_options` + `display_names_type: 'currency'`（Intl.DisplayNames 本地化）。`currency_options` 的**唯一调用方是 markets 表单**（其余表单用 `supported_currency_options`，不受影响）→ 重构安全。
- **本次改动范围**：Admin 层 `stores/new.html.erb`（3 个选择器）+ `currency_helper.rb`（暴露 `all_currency_options` 供单选/多选复用）+ `stores_controller.rb`（移除 `all_currencies` 死代码）。无迁移、无 API 变更、storefront/platform 不涉及。

---

## Step 1：Skill 文件咨询（功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树："Add a section / form field to an existing admin page → `PallasTrade.admin.partials.<page>` → deep-dive **pallastrade-admin**"；优先级 Settings → … → Admin / Ransack。本次为表单选择器样式统一，属 Admin 层视图改动。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 多店铺章节（§多店铺管理 2026-08-17）："`default_currency`/`default_locale` 为下拉选择（`::Money::Currency.all` / `PallasTrade::Locales::ALL`）"——迭代 2 需更新为"复用 `currency_options` + `display_names_type` 本地化显示"；`pallastrade_select` 表单组件约定。 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⬜ 不涉及 | 本次无 catalog 模型改动。 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 不涉及 | ⬜ | 无接口变更（不涉及 controller/routes/serializer） |
| `pallastrade-decorators` | ⬜ 不涉及 | ⬜ | 无装饰器 |
| `pallastrade-dependencies` | ⬜ 不涉及 | ⬜ | 无 DI 替换 |
| `pallastrade-events-webhooks` | ⬜ 不涉及 | ⬜ | 无事件/订阅者 |
| `pallastrade-storefront` | ⬜ 不涉及 | ⬜ | storefront 无改动 |
| `pallastrade-testing` | ⬜ 不涉及 | ⬜ | 沿用现有 RSpec request spec 模式（stores_multi_spec.rb） |
| `pallastrade-i18n` | ⬜ 不涉及 | ⬜ | 不新增 i18n key（复用现有 label） |

> ✅ 必读 Skill 全部已读；按需 Skill 经评估均不涉及。

---

## 需求标题

统一新建店铺表单（`admin/stores/new`）的货币/语言选择器与市场编辑表单（`admin/markets/*/edit`）一致：复用 `currency_options` 列表 + `display_names_type` 本地化显示（中文界面货币显示"美元"而非"US Dollar"）。

## 任务类型

功能优化（迭代 2，续 PRD-20260817-admin-新建店铺表单-货币语言选择器与邮箱预设）

## 需求描述

1. `default_currency` 下拉改为与 markets 同款：选项格式「代码 — 名称」（如 `USD — United States Dollar`），加 `data-display-names-type="currency"` 本地化显示，可搜索，默认 USD。
2. `supported_currencies` 多选改为同一列表 + 本地化显示；提交数组 → 逗号分隔落库逻辑不变。
3. `default_locale` 下拉补 `data-display-names-type="language"`（与 markets 一致）。
4. 数据源保持单一：`currency_helper.rb` 新增 `all_currency_options`（`[label, code]` 对），`currency_options` 与多选共用；移除 `stores_controller#all_currencies` 死代码。

## 影响范围（harness affected 输出）

- 改动文件：`backend/pallastrade_gems/pallastrade_core/app/helpers/pallastrade/currency_helper.rb`、`backend/pallastrade_gems/pallastrade_admin/app/views/pallastrade/admin/stores/new.html.erb`、`backend/pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/stores_controller.rb`、`backend/spec/requests/pallastrade/admin/stores_multi_spec.rb`、PRD 文档 + admin SKILL。
- 仅 Admin 表单展示层；无模型/DB/API/路由改动。

## 技术方案（初步）

1. `CurrencyHelper#currency_options`：基于新增的 `all_currency_options`（`::Money::Currency.table.map { currency_presentation }`，memoized）构建，输出不变（markets 不受影响）。
2. `stores/new.html.erb`：`default_currency` → `currency_options(...)` + `data: { display_names_type: 'currency' }`；`supported_currencies` → `options_from_collection_for_select(all_currency_options, :last, :first, ...)` + `multiple` + `data: { display_names_type: 'currency' }`；`default_locale` → 补 `data: { display_names_type: 'language' }`。
3. `stores_controller.rb`：删除 `all_currencies` helper_method（不再被引用）。
4. Spec：更新「renders currency and locale selectors」用例，断言 `data-display-names-type` 与「代码 — 名称」选项格式；多选提交与默认选中断言保持。

## 风险点

- 低风险：纯视图 + helper 展示层改动；`currency_options` 唯一调用方 markets 表单输出不变（有 gift_cards/orders 等 `supported_currency_options` 调用不受影响）。
- 回滚：单文件 revert，无迁移。

## 决策节点

> 用户已于 2026-08-17 回复"优化"明确确认实施（上一轮 AI 提议："把 markets 的 currency_options helper（含本地化显示）复用到新建店铺表单"）。PRD 迭代 2 已记录（FR-007~009 / AC-007~009）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby helper | `currency_helper.rb` | `harness check --profile quick` + rspec stores_multi_spec | 待执行 | ⬜ |
| Admin 视图 | `stores/new.html.erb` | rspec 选择器断言 + 浏览器 DOM/截图 | 待执行 | ⬜ |
| 控制器清理 | `stores_controller.rb` | rspec 回归 + nav:validate | 待执行 | ⬜ |
| 文档 | PRD + admin SKILL | `doc-impact` | 待执行 | ⬜ |

### 新增 admin 页面三要素检查（凡新增/改动 admin 页面必填）

> 本次仅改动既有新建页的选择器（不改标题/面包屑/操作按钮/提交方式），但仍逐项核对：

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题（page_title / 页面头 h3） | `/admin/stores/new` | ✅ 不变 | 迭代 1 已验证 |
| ② 面包屑（含图标） | `/admin/stores/new` | ✅ 不变 | 迭代 1 已验证（skip_breadcrumb_derivation 手写） |
| ③ 页面操作按钮（page_actions）与返回路径 | `/admin/stores/new` | ✅ 不变 | 迭代 1 已验证 |
| ④ POST/PATCH/DELETE 用 `data: { turbo_method: ... }` | 表单 POST `new_store` | ✅ 不变 | form_for 正常 POST，无链接按钮 |

### 验证结论

待实施后填写（rspec 全绿 + quick check + 浏览器 DOM 验证 data-display-names-type + 选项本地化渲染）。
