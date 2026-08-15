# REQ-20260815-redirects-url-change-list

> 关联 PRD：PRD-20260815-catalog-redirect-页面展示商品-url-变更清单并引导创建重定向（approved）
> 任务：TASK-20260815043457-cf988500

## Step 0：跨层搜索（结论见 PRD §6）

- **数据源已存在**：`friendly_id_slugs` 表（friendly_id `:history`，`Product::Slugs` 自动维护旧 slug）
- Admin 层 `redirects` 页面/controller 已存在 → 在此加清单展示
- 无重复实现

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读 | 决策树：Admin 视图/controller 改动走直接修改（第 8 优先级），查询辅助放 Core service |
| `pallastrade-admin` | ✅ 已读 | `load_resource` 自动建 @object；`page_alerts`/`alert-info` 提供页面说明；表格用 `render_table`/自绘 |
| `pallastrade-catalog` | ✅ 已读 | 商品 slug 走 friendly_id `:history`（`Product::Slugs`），旧 slug 在 `friendly_id_slugs` |
| `pallastrade-api-v3` | ✅ 已读 | 新增 Admin API 端点遵循 v3 + prefixed id 约定（本次可选） |

## 实施方案

1. **Core service** `pallastrade_core/app/services/pallastrade/product_url_change.rb`：
   - 输入 current_store；输出 `[{product, locale, old_slug, current_slug, from_path, to_path, handled}]`
   - 查询 `FriendlyId::Slug`（sluggable_type=Product、id ∈ store.products、deleted_at 空）
   - 排除：slug==当前、`deleted-` 前缀、重复 (locale,slug)
   - `handled` = store.redirects.active.from_path 已含 `/products/{old_slug}`
2. **Admin controller** `redirects_controller.rb`：
   - `index`：super 后 `@url_changes = ProductUrlChange.call(current_store)`
   - `new`：super 后从 `params[:from_path]/[:to_path]` 预填 @object
3. **View** `redirects/index.html.erb`：intro 下方展示变更清单表格（商品名/旧URL/新URL/状态/操作）
4. **en.yml**：+ `admin.redirects.url_changes_*` 文案
5. **Spec**：core service + admin UI（清单渲染 + 预填链接）
