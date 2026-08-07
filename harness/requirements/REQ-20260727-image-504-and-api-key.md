# 需求文档：修复图片加载504超时 + 管理后台图片慢 + 统一API Key

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | active_storage, image_url, api_key | `backend/app/controllers/pallastrade/admin/ai_controller.rb` (AI provider API key, 无关) | ❌ 无直接相关 |
| App — views/decorators | `backend/app/` | image_tag, cdn_image | 无 | ❌ |
| Core Gem — models | `pallastrade_core/app/models/` | ApiKey, cdn_image | `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/api_key.rb` (API Key 模型) | ✅ 已有 API Key 模型 |
| Core Gem — services | `pallastrade_core/app/services/` | Seeds, ApiKeys | `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/seeds/api_keys.rb` (Seeder 创建默认 key) | ✅ Seeder 逻辑 |
| Core Gem — routes | `pallastrade_core/config/routes.rb` | cdn_image, proxy, redirect | `backend/pallastrade_gems/pallastrade_core/config/routes.rb` (cdn_image direct route — **核心问题所在**) | ⚠️ 使用 proxy 模式导致性能问题 |
| Core Gem — helpers | `pallastrade_core/app/helpers/` | pallastrade_image_tag, cdn_image_url | `backend/pallastrade_gems/pallastrade_core/app/helpers/pallastrade/images_helper.rb` (图片 helper) | ✅ 使用 cdn_image_url |
| API Gem — serializers | `pallastrade_api/app/serializers/` | image_url_for, cdn_image_url | `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/base_serializer.rb` (image_url_for), `media_serializer.rb` (variant URLs) | ✅ 使用 cdn_image_url 生成图片 URL |
| Admin Gem — views | `pallastrade_admin/app/views/` | pallastrade_image_tag | `backend/pallastrade_gems/pallastrade_admin/app/helpers/pallastrade/admin/avatars_helper.rb` (头像), `table_helper.rb` (表格缩略图) | ✅ 使用 pallastrade_image_tag |
| Storefront | `storefront/src/` | ProductImage, _next/image, remotePatterns | `storefront/src/components/ui/product-image.tsx` (Next.js Image), `storefront/src/components/products/MediaGallery.tsx` (媒体画廊), `storefront/next.config.ts` (remotePatterns) | ⚠️ Next.js Image 双重代理 |
| Platform | `platform/packages/` | api_key, image_url | `platform/packages/sdk/src/client.ts` (SDK client), `platform/packages/dashboard/vite.config.ts` (代理配置) | ✅ SDK 使用 publishableKey |

### 搜索结论
- 图片加载的**根本问题**在 `pallastrade_core/config/routes.rb` 的 `cdn_image` direct route，使用 Active Storage **proxy 模式**导致双重代理（Next.js `/_next/image` → Rails proxy → Disk）
- API Key 模型和 Seeder 已存在，但 `backend/.env` 中的 `PALLASTRADE_API_KEY` 变量实际未被后端代码使用；前端通过 `PALLASTRADE_PUBLISHABLE_KEY` 与后端通信
- 管理后台图片同样走 `cdn_image_url` → proxy 模式，开发环境 Rails 单线程 + 代码重载导致慢

---

## Step 1：Skill 文件咨询

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：设置/Config → 事件/Subscriber → DI → Admin扩展 → Generator → Decorator → Extension → 直接Gem修改。本次修改 Gem 源文件（routes.rb），属于 Priority 8 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 管理后台使用 `pallastrade_image_tag` helper 渲染图片，底层调用 `cdn_image_url` |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | Store API 使用 publishable key (`pk_` 前缀)，Admin API 使用 secret key (`sk_` 前缀)。publishable key 用于公开客户端 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | Storefront 通过 `@pallastrade/sdk` 使用 publishable key 认证。图片通过 Next.js `<Image>` 组件渲染，URL 来自 API 响应 |

---

## 需求标题
修复：1) 前台图片 Next.js 代理 504 超时 2) 管理后台图片加载慢 3) 统一前后台 API Key 并清理数据库重复

## 任务类型
Bug修复

## 需求描述

### 问题1：前台图片 504 Gateway Timeout
Storefront (localhost:3001) 通过 Next.js `<Image>` 组件加载产品图片时，图片 URL 经过 `/_next/image` 优化代理。源图片 URL 由 `cdn_image_url` 生成，使用 Active Storage proxy 模式（`/rails/active_storage/blobs/proxy/...`）。这形成双重代理：浏览器 → Next.js → Rails Proxy → 磁盘。开发环境 Rails 单线程，双重代理导致超时。

### 问题2：管理后台图片加载慢/不显示
管理后台同样使用 `pallastrade_image_tag` → `cdn_image_url` → Active Storage proxy 模式。开发环境 Rails 中间件开销大，图片加载极慢。

### 问题3：API Key 不统一
- `storefront/.env` 使用 `PALLASTRADE_PUBLISHABLE_KEY=pk_9edDTtUyY6SxuugSVNDCbcTE`
- `backend/.env` 使用 `PALLASTRADE_API_KEY=pk_9edDTtUyY6SxuugSVNDCbcTE`（未被后端代码使用）
- 数据库 `pallastrade_api_keys` 表中可能存在多个重复 key（多次 seed/手动创建导致）
- 需要统一变量名并清理 DB 中多余 key

## 影响范围

| 文件 | 修改类型 | 说明 |
|---|---|---|
| `backend/pallastrade_gems/pallastrade_core/config/routes.rb` | 修改 | cdn_image route: proxy → redirect |
| `backend/.env` | 修改 | 删除未使用的 `PALLASTRADE_API_KEY`，或改为 `PALLASTRADE_PUBLISHABLE_KEY` |
| `storefront/.env` | 无需修改 | 已正确使用 `PALLASTRADE_PUBLISHABLE_KEY` |
| 数据库 `pallastrade_api_keys` 表 | 清理 | 删除重复/多余的 key |

## 技术方案

### Fix 1+2: Active Storage proxy → redirect
修改 `cdn_image` direct route，将 `:rails_service_blob_proxy` 改为 `:rails_service_blob_redirect`，将 `:rails_blob_representation_proxy` 改为 `:rails_blob_representation`。

**理由**: 
- Redirect 模式返回 302 重定向到磁盘文件 URL
- 磁盘文件由 Rails public file server 直接服务，不经过 Rails 中间件
- 对于 Next.js `/_next/image`，它自动跟随重定向，性能大幅提升
- 对于管理后台，浏览器直接访问文件，绕过 Rails 中间件
- 产品图片为公开资源，无需 proxy 模式的权限控制

**风险**: 
- Variant 首次访问时可能未生成，需要测试 redirect 模式是否会自动生成 variant
- 如果 redirect 对 variant 不支持，则仅对原始 blob 使用 redirect，variant 保持 proxy

### Fix 3: API Key 统一
1. 在 `backend/.env` 中删除未使用的 `PALLASTRADE_API_KEY`（该变量未被任何后端代码引用）
2. 数据库清理：保留一个有效的 publishable key，删除其他重复的（通过 Rails console 或迁移脚本）
3. 确认 `storefront/.env` 中的 `PALLASTRADE_PUBLISHABLE_KEY` 值与数据库中保留的 key 一致

## 风险点
- Redirect 模式可能在 variant 未预生成时失败 → 需要验证
- 清理 API key 需要确认当前正在使用的 key → 先查询再删除
- 需要重启 Rails 和 Next.js 服务使更改生效
