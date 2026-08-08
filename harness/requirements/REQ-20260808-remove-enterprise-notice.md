# REQ-20260808-remove-enterprise-notice — 去掉管理后台升级提示

> 关联 PRD：`docs/prd/admin/PRD-20260808-admin-去掉管理后台左侧菜单的升级逻辑-community-edition-升级提示.md`

## 需求

去掉管理后台左侧菜单的升级逻辑（Community Edition → Enterprise 提示），交付源码不含向客户的升级推销。

## 跨层搜索结论

升级逻辑**全部**在 `pallastrade_admin` gem，7 处引用，无 spec 测试引用：

| # | 位置 | 内容 |
|---|---|---|
| 1 | `app/views/.../shared/sidebar/_store_nav.html.erb` (L5-7) | 渲染 `enterprise_edition_notice` 的 div 块 |
| 2 | `app/views/.../shared/sidebar/_enterprise_edition_notice.html.erb` | 通知视图（整文件删除） |
| 3 | `app/controllers/.../dashboard_controller.rb` (L61-64) | `dismiss_enterprise_edition_notice` action |
| 4 | `config/routes.rb` (L305) | dismiss 路由 |
| 5 | `config/locales/en.yml` (L190-192) | `enterprise_edition_notice.body/upgrade` 文案 |
| 6 | `app/helpers/.../base_helper.rb` (L10-12) | `enterprise_edition?` helper（仅 notice 使用） |
| 7 | `app/assets/tailwind/.../components/_layout.css` (L393-394, L564-578) | enterprise notice 样式两处 |

## 实施计划

1. `_store_nav.html.erb`：删除渲染 notice 的 `<div class="mt-auto flex flex-col">` 块
2. 删除 `_enterprise_edition_notice.html.erb` 文件
3. `dashboard_controller.rb`：删除 `dismiss_enterprise_edition_notice` action
4. `routes.rb`：删除 dismiss 路由行
5. `en.yml`：删除 `enterprise_edition_notice` 段
6. `base_helper.rb`：删除 `enterprise_edition?` helper
7. `_layout.css`：删除 enterprise notice 样式（393-394、564-578 两处）

## 验证

- `git grep enterprise_edition_notice` 无命中（AC-002）
- 浏览器验证后台侧边栏无升级提示（AC-001）
- 后台其他页面 200（AC-003）
- 注意：`enterprise_edition?` 移除后，adyen 的 `application_info_presenter.rb` 仍用 `defined?(PallasTradeEnterprise)`（不依赖 helper，不受影响）

## 知识同步

- `pallastrade-admin` skill：评估是否需要更新（侧边栏部分）
- API 文档：不涉及
