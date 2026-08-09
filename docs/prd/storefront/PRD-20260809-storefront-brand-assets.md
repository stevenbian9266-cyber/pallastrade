# PRD-20260809-storefront-brand-assets

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-09 |
| 来源 | 需求：品牌资产部署（pallastrade-brand-assets 图片放置到正确位置显示） |
| 分类 | storefront（品牌资源） |
| 关联 Skill | pallastrade-storefront、docs/standards/logo.md（Logo 规范） |
| 关联 REQ | （实施时回填） |
| 需求类型 | 优化迭代（品牌资源部署） |

## 1. 背景与目标

- **一句话需求原文**：D:\pallastrade\pallastrade-brand-assets 有相关图片了，可自行重新移动文件路径，把这些涉及的图片在正确的地方显示
- **背景**：品牌资产已提供（`pallastrade-brand-assets/`：主 SVG、favicon 多尺寸、邮件 PNG、og 图）；当前 storefront 用的是 320B 占位 logo、占位 social-image.webp、无 favicon.ico
- **目标**：按 `docs/standards/logo.md` 规范把品牌资产放到正确位置，前端/邮件/SEO 正确显示
- **成功指标**：商城页头/结算显示新 logo、浏览器标签页出现 favicon、og:image 为品牌图、邮件头显示品牌 logo

## 2. 用户故事 / 场景

- 作为访客：看到品牌 logo（页头/结算/favicon/分享卡片）
- 作为收件人：邮件头显示品牌 logo 而非店名文本
- 场景：本地/服务器商城、社交分享、邮件

## 3. 功能需求（FR）

- FR-001：主 logo `pallastrade-logo.svg` → `storefront/public/`（替换占位，Header/checkout 立即生效）
- FR-002：favicon 系列（`favicon.ico` + 16/32/48 png）→ `storefront/public/`（Next.js 自动识别 favicon.ico）
- FR-003：og 图 `pallastrade-og.png` → `storefront/public/`，`seo.ts` `SOCIAL_IMAGE_PATH` 指向新图
- FR-004：邮件 logo `pallastrade-logo-email.png` → attach 到 backend store 的 `mailer_logo`（dev/prod）
- FR-005：`STORE_LOGO_URL` env（schema.org Organization logo）指向品牌图

## 4. 非功能需求（NFR）

- 兼容：文件名/路径遵循 Logo 规范（docs/standards/logo.md）；SVG 矢量、PNG 透明、og 1200×630
- 可维护：源资产保留在 `pallastrade-brand-assets/`（存档），部署产物进 storefront/public

## 5. 验收标准（AC）

- AC-001 ← FR-001：商城页头与结算页显示新品牌 logo（SVG）
- AC-002 ← FR-002：浏览器标签页 favicon 为品牌图标
- AC-003 ← FR-003：页面 openGraph images 为 `pallastrade-og.png`；`curl` 该路径 200
- AC-004 ← FR-004：dev backend store 的 mailer_logo 已 attach；`_mailer_logo` 渲染图片
- AC-005 ← FR-005：`STORE_LOGO_URL` 已配置

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | logo | 无 | 不适用 |
| Core | `pallastrade_gems/pallastrade_core/app/` | mailer_logo | `views/pallastrade/shared/_mailer_logo.html.erb`（store 附件）、`permitted_attributes.rb`（mailer_logo 字段） | ✅ 复用 |
| API | `pallastrade_gems/pallastrade_api/**` | logo | 无 | 不适用 |
| Admin | `pallastrade_gems/pallastrade_admin/**` | logo | 设置页上传 logo | 复用 |
| Storefront | `storefront/src/` | logo/favicon/og | `components/layout/Header.tsx`（/pallastrade-logo.svg）、`lib/metadata/home.ts`（SOCIAL_IMAGE_PATH）、`lib/seo.ts`（STORE_LOGO_URL） | 需替换资源 + seo.ts 指向 |
| Platform | `platform/packages/` | 无 | 不涉及 | 不适用 |

**结论**：前端资源替换 + `seo.ts` 一行指向 + backend store attach mailer_logo；无重复实现。

## 7. 技术影响

- 新增（storefront/public）：`pallastrade-logo.svg`（替换）、`favicon.ico`、`favicon-*.png`、`pallastrade-og.png`、`pallastrade-logo-email.png`
- 修改：`storefront/src/lib/seo.ts`（SOCIAL_IMAGE_PATH）
- 运行时：dev/prod backend store attach mailer_logo；`.env*` 配 STORE_LOGO_URL
- 依赖：无

## 8. 测试计划

- 本地 storefront：页头 logo / favicon / og 图 200
- 服务器 dev：部署后验证（页面 + favicon + og）
- 邮件：dev backend mailer_logo attach 后渲染
- 映射：AC-001~005

## 9. 文档同步清单（知识同步门）

- [ ] `docs/standards/logo.md`（若路径/资产变化）
- [x] `docs/prd/README.md` 索引
- [x] PRD 状态更新

**知识评估结论**（sync-check）：storefront 资源与 `seo.ts` 变更属于品牌资源部署，`pallastrade-storefront` SKILL 的组件/样式章节无需变更（无新组件/样式约定）；`docs/standards/logo.md` 已覆盖各使用位置要求，无需更新。已 ack。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿 | AI |
| 2026-08-09 | 0.2 | 实施完成：品牌资产部署 storefront/public（logo/favicon×4/og/email）、seo.ts SOCIAL_IMAGE_PATH、mailer_logo attach（本地+dev）、STORE_LOGO_URL env、dev storefront 镜像部署验证 200。prod 待 prod 栈启动时同步 | AI |
