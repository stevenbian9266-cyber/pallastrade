# 需求文档：商城前台全面重新规划（含 SEO/GEO）

> 关联 PRD：`docs/prd/storefront/PRD-20260810-storefront-对商城前台进行重新规划.md`（v0.4 approved）
> 关联 Gate：`GATE-2026-08-10T05-18-09`
> 创建日期：2026-08-10

---

## Step 0：跨层搜索（已执行，结论复用 PRD §6）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | 首页、导航、banner、订阅 | 无相关（纯前端需求） | ❌ 无 |
| Core | `pallastrade_gems/pallastrade_core/app/` | banner、navigation、home | 无首页/横幅业务模型 | ❌ 无 |
| API | `pallastrade_gems/pallastrade_api/app/` | banner、navigation | 无相关端点 | ❌ 无 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | banner、navigation | 无首页配置管理 | ❌ 无 |
| Storefront | `storefront/src/` | home、Hero、Featured、Header、Footer、navigation、MobileMenu | `components/home/`（2 板块）；`layout/Header`（汉堡菜单）、`Footer`（分类链接）、`MobileMenu`（Sheet 抽屉分类树）；`navigation/Breadcrumbs`；`globals.css` token 混杂；messages 有 home/header/footer；seo.ts 有 Product/Org/Breadcrumb/ItemList | ❌ 现有能力不足以支撑"专业商城"目标（需重构 + SEO/GEO 补充） |
| Platform | `platform/packages/` | banner、home | 无相关 | ❌ 无 |

### 搜索结论

6 层均无现成首页/横幅/导航管理系统。本需求为 **storefront 纯前端重构**（组件 + 样式 + i18n + SEO/GEO），不涉及后端/API/平台。数据源复用现有 `getCategories`/`getProducts`（`lib/data/`）与 `@pallastrade/sdk`。导航**功能存在但入口深**（汉堡菜单 + Footer），需新增常驻顶部分类导航条。

---

## Step 1：Skill 文件咨询（已完成）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 前端定制属 storefront 层；本项目不改后端（无需 decorator/subscriber/dependency）；"Settings/Config"优先级体现为环境变量与 token 规范 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | ① 组件放 `storefront/src/components/`；② 图片用 `product-image` 组件；③ `NEXT_PUBLIC_*` 仅第三方客户端 key；④ 反模式 AP-001/AP-006（禁 inline style/硬编码 hex）；⑤ ProductCard 测试断言规则 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 每个 AC 映射测试并标注 `# PRD-xxx AC-x`；按改动类型跑最小验证；知识同步门 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | 后端为 RSpec；**storefront 前端测试为 Vitest + Testing Library**（`src/components/**/__tests__/*.test.tsx`，jsdom，globals:true） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 否（无接口变更） | ⬜ | — |
| `pallastrade-i18n` | ✅ 是 | ✅ 已读约定 | storefront 用 `next-intl`，文案在 `messages/{en,zh}.json`，`useTranslations`/`getTranslations` 按 namespace（home/header/footer）读取 |
| `pallastrade-decorators` | ⬜ 否 | ⬜ | — |
| `pallastrade-events-webhooks` | ⬜ 否（订阅接后端为扩展） | ⬜ | — |

---

## 需求标题

商城前台全面重新规划（P1 设计系统 / P2 布局 Shell / P3 首页板块 / P4 清理 i18n / P5 SEO·GEO）

## 任务类型

新功能（前端整体重构，PRD approved）

## 需求描述

以电商最佳实践重构商城前台：统一设计 token、新增常驻顶部分类导航条、Footer 重构去 demo 链接、首页扩展为 8 个功能板块（Hero/分类导览/精选/促销/信任/品牌故事/订阅/FAQ）、全站 i18n 双语言、SEO/GEO 强化（WebSite+SearchAction、FAQPage、/llms.txt、语义 HTML、metadata 回归）。纯前端，无后端/API/数据库变更。

## 影响范围（harness affected 输出）

> 实施时运行 `node scripts/harness/cli.mjs affected --base origin/main` 确认；预期仅波及 storefront 组件/样式/i18n/SEO 与相关文档。

## 技术方案（初步，按 Phase）

- **P1**：`globals.css` token 规范化（统一品牌色板全阶 + 间距/圆角/阴影规范登记到 skill）
- **P2**：`Header.tsx` 挂 `CategoryNav.tsx`（常驻分类条 + 子分类下拉，服务端组件）；`MobileMenu.tsx` 补搜索/账户入口；`Footer.tsx` 重构（4 区块、去 demo、兔狲元素）
- **P3**：`page.tsx` 编排 8 板块；新建 `CategoryShowcase`/`ValueProps`/`BrandStory`/`PromoBanner`/`NewsletterSignup`（客户端）/`FaqSection`；重构 `HeroSection`（品牌化 + 去 demo）；保留 `FeaturedProductsSection`
- **P4**：全站移除 `href="#"` demo 链接；messages en/zh 补全新板块文案
- **P5**：`seo.ts` 新增 `buildWebsiteJsonLd`（WebSite+SearchAction）+ `buildFaqJsonLd`；根布局注入 WebSite schema；`app/llms.txt/route.ts` 动态生成；语义 HTML（唯一 H1、section、alt）

数据源：`getCategories`（`expand:["children.children"]`）、`getProducts`/`FeaturedProducts`（现有）。无新增依赖。遵守 AP-001/AP-006（禁 inline style/硬编码 hex，动态数据驱动例外）。

## 风险点

- 大改动面（首页/Header/Footer/i18n/SEO）→ 分 Phase 实施，每 Phase 跑测试 + 浏览器验证
- `NewsletterSignup` 无后端 → 前端校验 + 成功态占位（不做假提交），后端接 webhook 为扩展
- JSON-LD 与可见内容一致性（FAQ）→ 测试断言双向一致
- `MobileMenu` Sheet 交互复杂 → 仅补入口不改交互核心，回归测试兜底
- 无 demo 链接扫描 → CI/lefthook 无现成规则，实施时 grep 验证 + 可考虑 GS 场景

## 决策节点

> ✅ 用户已确认 PRD（2026-08-10「确认」），直接进入实施（分 Phase）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 组件/样式 | `storefront/src/components/**` + `globals.css` | `pnpm vitest run`（storefront 全量）+ `pnpm build` | | ⬜ |
| 布局 | `Header/Footer/MobileMenu/CategoryNav` | 浏览器实测（dev）：导航条渲染/下拉/移动菜单 | | ⬜ |
| 首页 | `page.tsx` + `components/home/**` | 浏览器实测：8 板块齐全 + 链接正确 | | ⬜ |
| i18n | `messages/*.json` | grep `href="#"` 归零 + en/zh 文案完整性检查 | | ⬜ |
| SEO/GEO | `seo.ts` + `llms.txt` + 布局 | `curl /llms.txt` 200 + 首页 JSON-LD 提取校验 + metadata 测试 | | ⬜ |
| 文档 | skill/README | `harness doc-impact --base origin/main` | | ⬜ |

### 验证结论

<!-- 实施后填写 -->
