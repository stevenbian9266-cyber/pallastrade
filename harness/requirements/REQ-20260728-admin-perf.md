# REQ-20260728-admin-perf

## Step 0：跨层搜索

| 层 | 搜索关键词 | 发现 |
|---|---|---|
| Admin Controllers | ResourceController, OrdersController | `collection` 方法使用 `preload_associations_lazily`，基础分页用 countish paginator |
| Admin Views | ERB partials, render_table | 大量 partial 嵌套渲染 |
| Core Models | default_scope, Asset.default_scope | `Asset.default_scope { includes(attachment_attachment: :blob) }` — 全局预加载造成不必要的 JOIN |
| API V3 | preload_associations_lazily | 多处使用但定义在 gem 中 |

## 根因分析

管理后台慢的三大原因：

1. **开发模式开销** — 每次请求重载所有 Ruby 文件 + 详细 SQL 日志 + 查询标签
2. **Asset::default_scope 导致全局 N+1** — 每个 Asset 查询自动 JOIN attachment 和 blob
3. **开发缓存关闭** — 无片段缓存、无资产缓存

## 优化方案（仅影响开发环境）

| # | 修改 | 预期收益 |
|---|---|---|
| 1 | `development.rb`: 启用缓存 | 资产/片段缓存命中，2x+ |
| 2 | `development.rb`: 关闭 verbose_query_logs | 减少 SQL 注释开销 |
| 3 | `development.rb`: 关闭 query_log_tags | 减少 source location 追踪 |
| 4 | `development.rb`: log_level → :info | 减少日志 I/O |
| 5 | `docker-compose.dev.yml`: 增加 tmpfs 给 bootsnap | 加速代码加载 |

## 影响范围

- `backend/config/environments/development.rb`
- `backend/docker-compose.dev.yml`
