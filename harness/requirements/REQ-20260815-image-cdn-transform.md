# REQ-20260815-image-cdn-transform

| 元数据 | 值 |
|---|---|
| PRD | PRD-20260814-catalog-图片-cdn-动态变换-resize-format-webp-响应式图片 |
| 类型 | 优化迭代（阶段一 P0-5，聚焦真实缺口） |

## 需求

ProductImage 组件响应式 `srcset`（用现有多尺寸 webp URL）。

**背景**：后端已实现 6 个 webp variant（mini/small/medium/large/xlarge/og_image，Rails ActiveStorage + CDN），media_serializer 暴露全部 *_url。

**⚠️ 范围修正**：图片 URL 是 Rails webp variant（CDN）而非 OSS 直链 → OSS `x-oss-process` loader 不适用；聚焦 ProductImage srcset。

## 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| App | backend/app/ | 图片 | 无 | 不涉及 |
| Core | pallastrade_core/ | media | media.rb | 无需改 |
| API | pallastrade_api/ | original_url | media_serializer.rb | 已暴露多尺寸；无需改 |
| Admin | pallastrade_admin/ | image | 无 | 不涉及 |
| Storefront | storefront/src/ | next/image、loader | product-image.tsx、next.config.ts | **loader/srcset 需补** |
| Platform | platform/packages/ | image | SDK Media 类型 | 已含字段；无需改 |

## 改动清单

1. `product-image.tsx`：支持 `srcSet` prop（透传 next/image）
2. 关键使用处（ProductCard/MediaGallery/CartDrawer/Summary/LineItemCard/SearchBar）：传多尺寸 srcSet
3. 无 srcSet 时降级单 URL
4. 测试：组件测试（srcset 渲染 + 降级）
5. 文档：pallastrade-storefront skill

## 验收（AC）

- AC-001：ProductImage 支持 srcSet prop，渲染 `<img srcset>`
- AC-002：关键使用处传入多尺寸 srcSet（≥2 尺寸）
- AC-003：无 srcSet 时单 URL 渲染不变

## Skill 咨询证据表

| Skill | 结论 |
|---|---|
| pallastrade-storefront | 样式/组件约定（AP-001 禁 inline style、AP-006 禁硬编码色）；ProductImage 组件扩展 |
| pallastrade-deployment | OSS 存储/图片服务部署约定；next/image 配置 |
| pallastrade-customization | 决策树：图片 loader 属 storefront 表现层，直接改组件/配置 |
| pallastrade-prd | 一句话需求 → PRD 流程已走（查重、用户确认） |
