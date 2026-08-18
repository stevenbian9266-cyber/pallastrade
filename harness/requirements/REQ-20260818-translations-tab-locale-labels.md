# REQ-20260818-translations-tab-locale-labels — 修复商品翻译抽屉 tab 无法区分语言

> 关联任务：TASK-20260818045517-1020b9ba
> 类型：Bug 修复

---

## Step 0：跨层搜索

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | translation / locale | 无 | 不涉及 |
| Core | `pallastrade_core/app/` | this_file_language | `models/pallastrade/locale.rb`（`Locale#name` 规范化名称解析）、`config/locales/en.yml:1016`（`this_file_language: English (US)`，**唯一定义处**） | 复用 `Locale#name/#label` |
| API | `pallastrade_api/app/` | translation | 无 | 不涉及 |
| Admin | `pallastrade_admin/app/` | translation | `views/.../translations/edit.html.erb:9`（**tab 直接用 `PallasTrade.t('i18n.this_file_language', locale: locale)`，缺 exists? 守卫**）、`controllers/.../translations_controller.rb`（`@locales`）、`helpers/.../translations_helper.rb` | **本次修复对象** |
| Storefront | `storefront/src/` | 无 | 不涉及 | 不涉及 |
| Platform | `platform/packages/` | 无 | 不涉及 | 不涉及 |

**结论**：唯一 bug 点在 `translations/edit.html.erb:9`。`Locale#name` 已有规范解析（this_file_language → 回退 code），`Locale#label` 是 admin 全站 locale 选择器展示模式（`locale_presentation`）。

## 根因（复现步骤）

1. 商品编辑页 → 点 translation → 抽屉 tab 标签用 `PallasTrade.t('i18n.this_file_language', locale: locale)`。
2. `pallastrade.i18n.this_file_language` 仅 `en.yml` 定义（"English (US)"）。
3. dev/prod 服务器 `config.i18n.fallbacks = true`（production.rb:108）→ 非 en 语言缺失翻译回退到默认 en → **所有 tab 显示 "English (US)"**（本地无 fallback 则显示 translation_missing 占位符，同样不可用）。

## 修复方案

- **FR-001**：`edit.html.erb` tab 标签改用 `PallasTrade::Locale.new(code: locale).label`（复用规范名称解析；带语言代码，任何语言都可区分；与 markets/stores 表单 locale 选择器 `locale_presentation` 一致）。
- **FR-002**：为店铺实际支持语言（ar/de/es/fr/it/pt）+ zh-CN 在应用层补 `pallastrade.i18n.this_file_language` 本地化名称（"Deutsch"、"Français"、"简体中文"…），使 tab 显示友好名称。

## AC

- AC-001 ← FR-001：多语言店铺翻译抽屉各 tab 标签互不相同（含语言代码，如 "EN — English"、"DE — Deutsch"），不再全部 "English (US)"。
- AC-002 ← FR-001：单语言无回归（tab 正常显示该语言）。
- AC-003 ← FR-002：`Locale#name`/`#label` 对 de/fr/zh-CN 等返回本地化名。

## 验证

- 新增 `backend/spec/requests/pallastrade/admin/translations_tabs_spec.rb`：多语言店铺抽屉 tab 断言。
- `Locale` 单测补充（如需）。
- quick check + 浏览器 dev 验证。
