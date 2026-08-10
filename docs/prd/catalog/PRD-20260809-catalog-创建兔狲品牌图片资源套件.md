# PRD-20260809-catalog-创建兔狲品牌图片资源套件

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-09 |
| 来源 | 用户要求按指定格式和尺寸创建兔狲（帕拉斯猫）卡通品牌图片资源，并保存到项目根目录的新文件夹 |
| 分类 | catalog（CLI 自动分类；实际影响为跨商城、邮件、SEO 与管理后台的品牌资产） |
| 关联 Skill | `imagegen`、`pallastrade-prd`、`pallastrade-customization`、`pallastrade-storefront`、`pallastrade-admin`、`pallastrade-catalog` |
| 关联 REQ | `REQ-20260810-pallas-cat-brand-assets.md` |
| 关联 PRD | N/A |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **需求原文**：商城页头/结算使用 90×32 SVG，邮件头使用高 60–80px 且不超过 200KB 的 PNG，SEO/og:image 使用 1200×630 PNG/JPG，favicon 使用 16/32/48 ICO/PNG，管理后台使用同规格 90×32 SVG/PNG；以兔狲设计卡通呆萌形象，先保存到项目根目录新文件夹。
- **背景**：仓库已有纯文字 SVG、旧邮件 logo 与 favicon，但没有统一的兔狲品牌视觉，也没有符合 1200×630 的专用社交分享图。
- **目标**：交付一套风格一致、尺寸可验证、可直接被各使用点采用的兔狲品牌资源，不修改现有页面引用或运行时代码。
- **成功指标**：所有文件尺寸、格式、透明度和文件大小符合要求；同一兔狲形象在 16px favicon 到 1200×630 OG 图中保持可识别；最终资源集中在项目根目录单一文件夹。

## 2. 用户故事 / 场景

- 作为品牌负责人，我希望商城、邮件、SEO、favicon 与后台使用统一的兔狲形象，以建立清晰的 PallasTrade 品牌识别。
- 正常场景：设计在浅色背景、邮件客户端、浏览器标签页和社交分享卡片中清晰可辨。
- 边界场景：在 16×16 下保留宽脸、低耳和困倦眼神三项核心特征；SVG 按 90×32 渲染时不变形。
- 异常场景：若透明边缘或文字在导出后出现锯齿、色边、裁切或文件超限，重新导出并再次验证。

## 3. 功能需求（FR）

- FR-001：在项目根目录新增 `pallastrade-brand-assets/`，只保存本次品牌图片交付物。
- FR-002：创建 `pallastrade-logo.svg`，画布比例约 2.8:1，可按 90×32 渲染；包含呆萌兔狲图形与 `PallasTrade` 字标，背景透明，商城页头、结算和管理后台共用该源文件。
- FR-003：从统一矢量源导出 `pallastrade-logo-email.png`，尺寸 225×80，透明背景，文件不超过 200KB。
- FR-004：创建 `pallastrade-og.png`，尺寸严格为 1200×630，延续同一兔狲形象与品牌配色，文字只出现一次且为 `PallasTrade`。
- FR-005：创建 `favicon-16x16.png`、`favicon-32x32.png`、`favicon-48x48.png` 和包含 16/32/48 三帧的 `favicon.ico`。
- FR-006：使用内置 ImageGen 生成兔狲形象锚点作为设计参考；最终小尺寸图标采用简化矢量结构，避免直接缩小复杂毛发图导致不可辨识。
- FR-007：不替换 `storefront/public/pallastrade-logo.svg`、现有 favicon、邮件配置或 Admin 资源；本阶段只在根目录交付资源。

## 4. 非功能需求（NFR）

- 视觉：宽脸、低位圆耳、蓬松脸颊、困倦琥珀眼、微呆表情；扁平矢量卡通，不做写实毛发。
- 配色：暖灰/沙棕毛色、琥珀强调色、深炭轮廓，保证浅色背景上的识别度。
- 兼容：SVG 不依赖外部图片；PNG 使用标准 RGBA/RGB；ICO 包含 16、32、48 三种尺寸。
- 可维护：页头/结算/Admin 共用一个矢量源，邮件与 favicon 从同一源导出；不引入运行时依赖。
- 安全：不包含商标仿制、第三方 logo、水印或额外文案。

## 5. 验收标准（AC）

- AC-001 → FR-001：根目录存在 `pallastrade-brand-assets/`，交付清单中的所有图片均位于其中。
- AC-002 → FR-002：SVG 的 `viewBox` 比例为 2.8:1 左右，透明背景，包含兔狲图形和准确的 `PallasTrade` 字标，90×32 预览无拉伸或裁切。
- AC-003 → FR-003：邮件 PNG 为 225×80、带 alpha、文件大小 ≤200KB。
- AC-004 → FR-004：OG PNG 为 1200×630，主体和字标不贴边，社交卡片缩略预览清晰。
- AC-005 → FR-005：三个 PNG 分别为 16×16、32×32、48×48；ICO 可枚举出 16/32/48 三帧。
- AC-006 → FR-006：兔狲在 16×16 下仍能辨识出低耳、宽脸和双眼；各资源视觉一致。
- AC-007 → FR-007：`git diff/status` 显示未替换现有商城、邮件或 Admin 图片文件。

## 6. 跨层搜索记录（6 层）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | logo、favicon、og:image、email logo、brand、mascot | 无 | 否 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | 同上 | `assets/images/logo.png`、`views/pallastrade/shared/_mailer_logo.html.erb` | 部分；有旧 logo 与邮件渲染入口，无兔狲套件 |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | 同上 | 无 | 不涉及 |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | 同上 | `assets/images/favicon_256x256.png`、Admin favicon 引用 | 部分；缺少 90×32 兔狲 logo |
| Storefront | `storefront/src/` | 同上 | `Header.tsx`、checkout `layout.tsx` 引用 `/pallastrade-logo.svg`；已有 favicon 与 OpenGraph metadata | 部分；现有 logo 为纯文字，缺少专用 OG 图 |
| Platform | `platform/packages/` | 同上 | 无相关品牌资产实现 | 不涉及 |

**结论**：现有使用入口完整，但图片资产分散且视觉不统一。本任务无需新增业务代码；通过根目录资源文件夹交付，后续可由独立集成任务替换各入口。

## 7. 技术影响

- 预计新增：`pallastrade-brand-assets/` 下 7 个图片文件。
- 不修改：数据库、API、SDK、页面组件、邮件模板和 Admin 视图。
- `harness affected --base origin/main` 当前报告 145 个已变更文件，涉及 harness/ai/backend/platform/storefront；这些属于现有工作区状态，本任务避免触碰。
- ImageGen 只用于生成设计锚点；最终资源通过可控矢量结构与本地格式导出生成。

## 8. 测试计划

- AC-001/AC-007：`tests/pallas-cat-brand-assets.test.mjs` 验证目录仅含 7 个交付图片，且既有 Storefront logo 未被替换。
- AC-002：测试确认 SVG 显示尺寸 90×32、viewBox 比例 2.8125:1、无 `<image>` 位图嵌入且字标准确。
- AC-003：测试确认邮件 PNG 为 225×80 RGBA、透明边角、11,930 bytes（≤200KB）。
- AC-004：测试确认 OG PNG 为 1200×630、背景不透明、91,092 bytes；最终图经视觉检查无裁切或合成边界线。
- AC-005：测试确认 PNG 为 16/32/48，ICO 目录包含 16/32/48 三帧。
- AC-006：16px 测试确认主体覆盖、深色轮廓、琥珀眼和颜色对比保留；48px 与 OG/邮件图经视觉检查一致。
- 自动化结果：`node --test tests/pallas-cat-brand-assets.test.mjs` → 7 passed / 0 failed；`harness prd verify` → 全部 AC 有测试覆盖。
- 仓库结果：`harness check --profile quick` 通过（仅报告 10 条既有 Storefront warning，0 error）；`harness doc-impact --base origin/main` → 8 synced / 0 missing。

## 9. 文档同步清单（知识同步门）

- [x] API 文档：已评估，无接口变化，无需更新。
- [x] Skill 文档：已评估，只新增根目录图片，不改变 Storefront/Admin 组件规范，无需更新。
- [x] README / Agent / 样式规范 / 技术规范：`docs/standards/logo.md` 已覆盖本次尺寸与格式，无需修改。
- [x] 反模式库 / 任务规则 / 场景库：无规则或能力变化，无需更新。
- [x] 本 PRD 状态与 `docs/prd/README.md` 索引在实施完成后更新。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿：明确统一兔狲视觉、文件清单、尺寸与验证方式 | AI |
| 2026-08-10 | 0.2 | 用户确认实施；确定单一矢量源、多格式导出方案 | AI |
| 2026-08-10 | 0.3 | 完成 7 个图片资源、7 项资产契约测试、视觉检查与文档影响检查 | AI |
| 2026-08-10 | 1.0 | 知识同步评估确认完成，验收关闭 | AI |
