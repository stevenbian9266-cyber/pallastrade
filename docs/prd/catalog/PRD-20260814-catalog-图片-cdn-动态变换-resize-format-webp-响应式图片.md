# PRD-20260814-catalog-图片-cdn-动态变换-resize-format-webp-响应式图片

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-08-15 已验证：主图 srcset 端到端生效） |
| 创建日期 | 2026-08-14 |
| 来源 | 阶段一：图片 CDN 动态变换（对标 Shopify）——resize/format webp 响应式图片 |
| 分类 | catalog（自动判定） |
| 关联 Skill | pallastrade-storefront、pallastrade-deployment |
| 关联 REQ | REQ-20260815-image-cdn-transform.md（实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 优化迭代 |

> 📌 **范围修正（2026-08-15 盘点）**：OSS/后端已实现 **webp 多尺寸 variant**（`Asset` 定义 mini/small/medium/large/xlarge/og_image 全部 `format: "webp"` + saver + preprocessed，经 CDN 提供），`media_serializer` 已暴露全部 `*_url`。
>
> 📌 **二次修正（实施期）**：图片 URL 是 **Rails webp variant（CDN）**而非 OSS 直链 → **OSS `x-oss-process` 自定义 loader 不适用**（webp/resize 已被 variant 覆盖）。本次**聚焦真实缺口：ProductImage 组件响应式 `srcset`**（用现有多尺寸 webp URL）。

## 1. 背景与目标

- **一句话需求原文**：实施 RESEARCH-20260814 阶段一（P0-5 图片 CDN 变换）
- **背景**：RESEARCH 文档提出图片 URL 参数化变换（resize/format webp）；2026-08-15 盘点确认后端已实现 **6 个 webp variant**（mini/small/medium/large/xlarge/og_image，Rails ActiveStorage + CDN），media_serializer 暴露全部 *_url。真正差距是 **ProductImage 未用多尺寸 srcset**（响应式图片）。
- **目标**：ProductImage 组件支持响应式 `srcset`（用现有多尺寸 webp URL），提升 LCP 与带宽。
- **成功指标**：商品图 `<img srcset>` 多尺寸（如 256w/720w/2000w）；浏览器按视口选尺寸。

## 2. 用户故事 / 场景

- 作为访客，我希望图片按视口尺寸加载（小图不拉大图），以便页面更快
- 作为访客，我希望浏览器自动使用 webp 格式，以便省流量
- 作为运营，我希望无需重新上传图片即可获得各尺寸，以便零成本响应式
- 边界：非 OSS 图（本地/local 服务、外部图）走原 loader 降级；无参数 URL 回退原图

## 3. 功能需求（FR）

- FR-001：`ProductImage` 组件支持 `srcSet` prop（多尺寸 webp URL，`url 256w, url 720w` 格式）透传给 next/image
- FR-002：关键使用处（ProductCard/MediaGallery/CartDrawer/Summary/LineItemCard/SearchBar）传入多尺寸 srcSet（用 SDK media 的 small/medium/large URL）
- FR-003：缺 srcSet 时降级为单 URL（现有行为不变）

## 4. 非功能需求（NFR）

- 性能：srcset 显著降低移动端带宽/LCP
- 兼容：无 srcSet 时不改变现有渲染；webp variant 已存在无需后端改动

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：ProductImage 支持 srcSet prop，渲染到 `<img srcset>`
- AC-002 ← FR-002：关键使用处传入多尺寸 srcSet（≥2 尺寸）
- AC-003 ← FR-003：无 srcSet 时单 URL 渲染不变

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 图片、media | 无 | 不涉及 |
| Core | `pallastrade_core/` | media、image | `media.rb`、asset 相关 | 尺寸 URL 已有；无需改 |
| API | `pallastrade_api/` | original_url、og_image | `media_serializer.rb` | 已暴露多尺寸；无需改 |
| Admin | `pallastrade_admin/` | image、media | 无 | 不涉及 |
| Storefront | `storefront/src/` | next/image、ProductImage、loader | `components/ui/product-image.tsx`、`next.config.ts`、`components/products/MediaGallery.tsx` | **loader/srcset 需补** |
| Platform | `platform/packages/` | image、url | SDK Media 类型 | 已含尺寸字段；无需改 |

**结论**：多尺寸 URL 已有；需在 storefront 实现自定义 loader + srcset（聚焦 storefront 层）。

## 7. 技术影响

- 涉及：storefront（`next.config.ts` loader/loaderFile + `product-image.tsx` srcset + 测试）
- 数据库：无
- 影响面：storefront skill（样式/组件约定）、可能 image 域名白名单调整

## 8. 测试计划

- 新增：`product-image.test.tsx`（srcset 输出）、loader 单测（OSS 参数拼接 + 白名单钳制 + 降级）
- 更新：`pallastrade-storefront/SKILL.md`
- AC 映射：AC-001→loader 单测、AC-002→组件测试、AC-003→loader 单测、AC-004→loader 单测

## 9. 文档同步清单（知识同步门）

- [x] Skill 文档：pallastrade-storefront
- [x] README / 规范：按 `sync-check` 矩阵
- [x] 场景库：scenarios.json（如需）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-15 | 0.1 | 初稿（基于 RESEARCH 阶段一 + 真实盘点范围修正） | AI |
| 2026-08-15 | 0.2 | 用户确认聚焦真实缺口（loader + srcset） | AI |
