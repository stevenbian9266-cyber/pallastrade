# PallasTrade Logo 使用规范

> 主源文件：`storefront/public/pallastrade-logo.svg`（矢量，唯一源）
> 规范定位：样式/视觉规范的一部分（见 `docs/standards/README.md`）

## 1. 使用位置与格式/尺寸要求

| # | 使用位置 | 代码路径 | 格式 | 尺寸要求 |
|---|---|---|---|---|
| 1 | **商城页头（Header）** | `storefront/src/components/layout/Header.tsx` → `/pallastrade-logo.svg` | **SVG**（矢量） | 渲染 `width=90 height=32`，`object-contain`，宽高比 ≈ **2.8:1**；任意缩放宽高比不破 |
| 2 | **结算页布局** | `storefront/src/app/[country]/[locale]/(checkout)/layout.tsx` → `/pallastrade-logo.svg` | **SVG** | 与 Header 一致（90×32，object-contain） |
| 3 | **邮件头 Logo** | `backend/pallastrade_gems/pallastrade_emails/app/helpers/pallastrade/mail_helper.rb`（`store_logo` → `current_store.mailer_logo \|\| logo`）→ `_mailer_logo.html.erb` | **PNG**（推荐，邮件客户端不保证 SVG 支持） | 高度 **60–80px**，透明背景，宽高比固定（同 2.8:1），文件 ≤200KB |
| 4 | **SEO / 社交分享图（og:image）** | `storefront/src/lib/seo.ts`（`STORE_LOGO_URL` env） | **PNG / JPG** | **1200×630**（og:image 标准，≥600×315 可接受），文件 ≤1MB |
| 5 | **站点图标（favicon）** | `storefront/public/favicon.ico` | **ICO / PNG** | 多尺寸 ICO（16/32/48）或 32×32 PNG |
| 6 | **管理后台（如启用）** | PallasTrade admin（`logo`/`mailer_logo` preference） | SVG / PNG | 与 Header 一致（90×32） |

## 2. 通用要求

- **唯一矢量源**：所有位图产物（PNG/ICO/og 图）必须从 `pallastrade-logo.svg` 导出，禁止手绘/截图替代
- **透明背景 + 双主题可见**：深色/浅色背景均需清晰（logo 本身含品牌色，背景透明）
- **留白安全区**：logo 四周保留 ≥ 其高度 25% 的留白，不与文字/图标挤压
- **不拉伸变形**：任何使用点必须保持原始宽高比（≈2.8:1），用 `object-contain` 而非 `object-fill`
- **命名**：源文件保持 `pallastrade-logo.svg`；导出位图按用途命名（`pallastrade-logo.png` / `pallastrade-logo-og.png` / `favicon.ico`）

## 3. 变更流程

- 更换品牌 Logo → 只替换 `pallastrade-logo.svg` 源文件，其余位图从源导出并同步替换
- 新增使用点 → 遵循上表格式/尺寸要求，并在此登记
- 修改本文件 → 运行 `harness docs:check` 验证引用
