# REQ-20260809-storefront-brand-assets

## 需求
品牌资产（pallastrade-brand-assets）放置到正确位置显示：主 logo/favicon/og/邮件图片。

## 背景
- 品牌资产已提供（SVG 主图 + favicon×4 + 邮件 PNG + og PNG）
- storefront 当前为占位 logo（320B）、占位 social-image.webp、无 favicon
- 按 docs/standards/logo.md 规范部署

## 方案
1. 复制到 `storefront/public/`：`pallastrade-logo.svg`（替换）、`favicon.ico`+16/32/48 png、`pallastrade-og.png`、`pallastrade-logo-email.png`
2. `storefront/src/lib/seo.ts`：`SOCIAL_IMAGE_PATH` → `/pallastrade-og.png`
3. backend：dev/prod store attach `mailer_logo`（rails runner，上传品牌邮件 PNG）
4. `.env*`：`STORE_LOGO_URL` 指向品牌图 URL

## Skill 咨询证据表
| Skill | 关键结论 |
|---|---|
| pallastrade-storefront | 资源放 public/，Header 用 /pallastrade-logo.svg |
| docs/standards/logo.md | 各使用位置格式尺寸要求 |
| pallastrade-deployment | 不适用 |

## 验证
- 本地 storefront：页头 logo、favicon、og 图 200
- 服务器 dev：部署后页面/favicon/og 200
- 邮件：dev backend mailer_logo 渲染

## 跨层搜索
- storefront：Header.tsx（/pallastrade-logo.svg）、home.ts（SOCIAL_IMAGE_PATH）、seo.ts（STORE_LOGO_URL）
- backend：_mailer_logo.html.erb（store.mailer_logo 附件）
- 结论：资源替换 + seo.ts 指向 + store attach，无重复实现
