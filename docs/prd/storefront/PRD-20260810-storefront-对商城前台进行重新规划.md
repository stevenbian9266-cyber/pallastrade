# PRD-20260810-storefront-对商城前台进行重新规划

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-10 |
| 来源 | 对商城前台进行重新规划 |
| 分类 | storefront（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260810-storefront-对商城前台进行重新规划

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-10 |
| 来源 | 对商城前台进行重新规划 |
| 分类 | storefront（自动判定） |
| 关联 Skill | pallastrade-storefront |
| 关联 REQ | REQ-20260810-storefront-redesign.md |
| 关联 PRD | N/A（全新需求，查重无命中） |
| 需求类型 | 新功能（前端整体重构） |

> 🔁 **查重回写**：`harness prd new` 已自动查重（标题相似度 ≤ 0.3，无命中），确认为全新需求。
> 用户澄清（2026-08-10）：范围=**全面整体重构**（重点首页布局）；依据=**无参考，凭专业经验**；目标=**提升专业感与视觉品质**。

## 1. 背景与目标

- **一句话需求原文**：对商城前台进行重新规划（补充要求：SEO 与 GEO（生成式引擎优化）友好）
- **背景（现状诊断）**：当前商城前台基于模板默认样式，存在以下问题：
  1. **首页过于简陋**：仅 `HeroSection` + `FeaturedProductsSection` 两个板块，无分类导览、无品牌故事、无信任区、无订阅区
  2. **导航入口藏得深**：分类导航**功能存在但不可见**——桌面端仅藏在 Header 汉堡菜单（`MobileMenu` Sheet 抽屉，含分类树）与 Footer 底部分类链接中，无**常驻顶部分类导航条**；用户需点击汉堡/滚动到底部才能浏览分类，信息架构不直观
  3. **demo 遗留内容**：Hero/Footer 含 `githubUrl="#"`/`quickstartUrl="#"` 等 Demo-only 链接，不适用于生产商城
  4. **设计系统未成体系**：`globals.css` token 混杂（`:root` 用灰色 oklch，`@theme` 另有蓝色 `primary-500`），无统一品牌色板/间距/圆角规范
  5. **Footer 结构简单**：分类/政策/联系信息不完整，含 demo 链接
  6. **品牌调性缺失**：兔狲 Pallas cat 品牌资产（logo/og/favicon 已就位）未融入首页与整体视觉
  7. **SEO/GEO 不完整**：已有 Product/Organization/Breadcrumb/ItemList JSON-LD 与 canonical/hreflang，但**缺 `WebSite+SearchAction`、`FAQPage`、`llms.txt`（LLM 站点说明）**，语义 HTML 层级与“可摘录内容”不足——AI 搜索引擎（ChatGPT/Perplexity/AI Overviews）难以高效理解站点结构
- **目标**：以电商最佳实践为蓝本，对商城前台做一次**全面整体重构**——建立规范设计系统、重构全局布局（导航/页脚）、重塑首页为多板块信息架构，提升专业感与视觉品质；同时**构建 SEO/GEO 双友好的内容与结构**，让传统搜索引擎与生成式引擎都能高效索引、理解、引用站点内容。保留现有 Server Components + `@pallastrade/sdk` 架构与性能特性。
- **成功指标**：
  - 首页从 2 板块扩展为 **≥6 个功能板块**（Hero / 分类导览 / 精选商品 / 促销横幅 / 信任区 / 品牌故事 / 订阅）
  - 顶部分类导航在桌面 + 移动端均可用（可达分类页）
  - 全站 **0 个 demo-only 遗留链接**
  - 设计 token 统一（单一品牌色板，无散落硬编码色）
  - 性能不劣化：保留 Server Components 架构，无新增客户端重逻辑
  - **SEO**：全站含 WebSite+SearchAction / FAQPage JSON-LD；语义 HTML 层级完整；canonical/hreflang/OG 回归正常
  - **GEO**：`/llms.txt` 可访问；首页含“可摘录”权威段落（品牌故事/FAQ）；结构化数据覆盖实体关系（Organization→WebSite→Product）

## 2. 用户故事 / 场景

- 作为 **新访客**，我希望首页一眼看懂"这是卖什么的"并能快速进入感兴趣的分类，以便快速决策是否继续浏览
- 作为 **老顾客**，我希望通过顶部导航直达分类、通过首页快速发现新品/精选，以便高效找到目标商品
- 作为 **店主**，我希望商城看起来专业可信（信任区/品牌故事/联系方式齐全），以便提升转化与复购

**场景列表：**

| 场景 | 类型 | 描述 |
|---|---|---|
| S-001 | 正常 | 桌面端首页依次展示 Hero → 分类导览 → 精选商品 → 促销横幅 → 信任区 → 品牌故事 → 订阅 |
| S-002 | 正常 | 顶部导航含根分类，hover 展示子分类下拉，点击进入分类页 |
| S-003 | 正常 | 移动端汉堡菜单展开分类树 + 账户 + 搜索入口 |
| S-004 | 正常 | 各板块链接正确（商品→PDP、分类→分类页、品牌→关于页） |
| S-005 | 边界 | 分类为空时分类导览板块不渲染或显示占位，不报错 |
| S-006 | 边界 | 商品为空时精选板块显示空态，不崩溃 |
| S-007 | 边界 | 关闭 JavaScript 仍可浏览（SSR 渲染的板块内容可见） |
| S-008 | 异常 | 数据接口失败 → 板块降级（不阻塞其他板块渲染） |

## 3. 功能需求（FR）

### Phase 1 — 设计系统基础（Foundation）
- FR-101：定义统一品牌色板与语义 token（primary/accent/neutral 全阶），替换 `globals.css` 中散落/混杂的 token；品牌色与兔狲品牌调性协调
- FR-102：统一 Typography / 间距 / 圆角 / 阴影规范（在 storefront skill 样式规范中登记）

### Phase 2 — 全局布局（Shell）
- FR-201：Header **新增常驻顶部分类导航条**（根分类 + 子分类下拉，桌面端 hover/点击；沿用现有数据源 `getCategories`；`MobileMenu` 抽屉保留并作为移动端/窄屏入口）
- FR-202：MobileMenu 升级为完整分类树 + 账户/搜索入口（现有分类树已具备，补齐搜索/账户快捷入口与交互一致性）
- FR-203：Footer 重构——移除 demo 链接；补齐品牌信息、分类、政策、联系方式、订阅入口；融入兔狲品牌元素

### Phase 3 — 首页板块重构（重点）
- FR-301：Hero 重构——品牌主张 + 视觉化背景（兔狲品牌资产图/渐变）+ 主 CTA「立即选购」+ 次 CTA「浏览分类」；移除 demo 链接
- FR-302：**分类导览板块**——根分类卡片网格（图标/图片 + 名称 + 子分类入口）
- FR-303：精选商品板块——保留/优化现有（标题 + 查看全部 + 商品网格/Suspense）
- FR-304：**促销横幅区**——宽幅 banner（可配置文案 + CTA）
- FR-305：**品牌信任区**——4 卖点图标条（免运费 / 正品保障 / 无忧退换 / 在线客服）
- FR-306：**品牌故事区**——兔狲 Pallas cat 品牌故事 + 品牌图
- FR-307：**邮件订阅区**——邮箱输入 + 提交（前端校验 + 成功态；后端可后续接 webhook）

### Phase 4 — 内容清理与 i18n
- FR-401：全站移除 demo-only 链接（`githubUrl`/`quickstartUrl` 等 `href="#"` 遗留）
- FR-402：首页/导航/页脚 i18n 文案全面更新（**全部支持语言 en/de/pl/es/fr**，含新增板块文案）

### Phase 5 — SEO / GEO 强化
- FR-501：新增 **WebSite + SearchAction** JSON-LD（全站注入，`potentialAction` 指向 `/{country}/{locale}/search?q={search_term_string}`，配合现有 Organization schema 形成实体关系）
- FR-502：新增 **FAQPage JSON-LD + 首页 FAQ 板块**（3-5 个高价值问答：配送/退换/支付/客服；JSON-LD 与可见内容一致，**全部支持语言**）——GEO 高价值可摘录内容
- FR-503：新增 **`/llms.txt`**（`app/llms.txt/route.ts` 动态生成，按 llmstxt.org 规范：站点标题/品牌简介/分类与商品导航/关键页面/联系与结构化数据说明）——让 LLM 高效理解站点
- FR-504：**语义 HTML 强化**（首页每板块用 `section`/语义标题 H1→H2→H3 层级；图片 `alt` 完整；品牌故事区为简洁权威“可摘录段落”首句直答）
- FR-505：**SEO 元数据回归**（重构后 home/category/product 各路由 title/description/canonical/OG/hreflang 保持正确；`robots.ts`/`sitemap.ts` 审查确认可索引）

### 扩展项（本 PRD 不实施，标注后续）
- 商品列表页/详情页深度重构、结算流程优化、促销系统接入、AI 商品问答（Product Q&A）

## 4. 非功能需求（NFR）

- **性能**：所有板块保持 Server Components（async 服务端渲染）；图片用 `product-image` 组件 + next/image；无重型客户端库
- **可访问性**：导航语义化（`nav`/`aria`）、键盘可操作、焦点可见；保留现有 sr-only 分类链接兜底
- **响应式**：桌面/平板/移动三档适配；导航与板块在移动端合理折叠
- **可维护性**：板块组件化（`components/home/*`），数据获取集中在 `lib/data/*`；i18n 文案收敛到 messages
- **反模式合规**：禁 `style={{}}`/硬编码 hex（AP-001/AP-006）；颜色走 CSS 变量；组件用 Tailwind 语义类
- **兼容**：保留 Next.js 16 App Router 现有路由结构（`[country]/[locale]/(storefront)`）

## 5. 验收标准（AC，与测试一一映射）

- AC-101 ← FR-101：`globals.css` 无散落/冲突 token，品牌色板全阶定义；全站无硬编码 hex（除数据驱动）
- AC-102 ← FR-201：桌面 Header 显示根分类导航条；hover 展开子分类；链接指向 `/{country}/{locale}/c/{permalink}`
- AC-103 ← FR-202：移动菜单含分类树 + 账户 + 搜索入口，可正常展开/关闭
- AC-104 ← FR-203：Footer 无 `href="#"` demo 链接；含品牌/分类/政策/联系四区块
- AC-105 ← FR-301：Hero 渲染品牌主张 + 主 CTA（链接到商品列表）+ 次 CTA（链接到分类），无 demo 链接
- AC-106 ← FR-302：首页渲染分类导览板块；分类为空时降级不报错
- AC-107 ← FR-303：精选商品板块保留（商品网格 + 查看全部链接）
- AC-108 ← FR-304/305/306：首页含促销横幅 / 信任区（≥3 卖点）/ 品牌故事板块
- AC-109 ← FR-307：订阅区渲染邮箱输入 + 提交按钮；空邮箱/非法邮箱前端拦截提示
- AC-110 ← FR-401/402：全站无 `href="#"` demo 链接；全部支持语言文案齐全（新增文案 en/de/pl/es/fr）
- AC-111 ← NFR：`pnpm build` 通过；`pnpm vitest run` 全绿；Lighthouse 移动端性能分不劣化
- AC-112 ← FR-501：首页 HTML 含 WebSite + SearchAction JSON-LD，`SearchAction.target` 指向搜索端点
- AC-113 ← FR-502：首页含可见 FAQ 板块（≥3 问答）+ 对应 FAQPage JSON-LD，内容一致且全部支持语言可用
- AC-114 ← FR-503：`GET /llms.txt` 返回 200，内容含站点标题/品牌简介/分类导航/关键页面链接
- AC-115 ← FR-504：首页语义检查通过（唯一 H1、板块用 section/语义标题、图片 alt 完整）
- AC-116 ← FR-505：home/category/product 路由 metadata 测试回归全绿（canonical/OG/hreflang 正确）

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | 首页、导航、banner、订阅 | 无相关（纯前端需求） | ❌ 无 |
| Core | `pallastrade_gems/pallastrade_core/app/` | banner、navigation、home | 无首页/横幅业务模型 | ❌ 无 |
| API | `pallastrade_gems/pallastrade_api/app/` | banner、navigation | 无相关端点 | ❌ 无 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | banner、navigation | 无首页配置管理 | ❌ 无 |
| Storefront | `storefront/src/` | home、Hero、Featured、Header、Footer、navigation | `components/home/`（2 板块）、`layout/Header/Footer`、`navigation/Breadcrumbs`、`products/FeaturedProducts`；`globals.css` token 混杂；messages 有 home/header/footer | ❌ 现有能力不足以支撑"专业商城"目标 |
| Platform | `platform/packages/` | banner、home | 无相关 | ❌ 无 |

**结论**：6 层均无现成的首页/横幅/导航管理系统。本需求为 **storefront 纯前端重构**（组件 + 样式 + i18n），不涉及后端/API/平台。数据源复用现有 `getCategories`/`getProducts`（`lib/data/`）与 SDK。防重复：无重复 PRD、无已实现板块（除 Hero/Featured 需重构）。

## 7. 技术影响

- **新增文件（预计）**：
  - `storefront/src/components/home/CategoryShowcase.tsx`（分类导览）
  - `storefront/src/components/home/ValueProps.tsx`（信任区）
  - `storefront/src/components/home/BrandStory.tsx`（品牌故事）
  - `storefront/src/components/home/PromoBanner.tsx`（促销横幅）
  - `storefront/src/components/home/NewsletterSignup.tsx`（订阅，客户端组件）
  - `storefront/src/components/layout/CategoryNav.tsx`（顶部分类导航条）
  - 对应 `__tests__/*.test.tsx`
- **修改文件（预计）**：
  - `storefront/src/app/globals.css`（token 规范化）
  - `storefront/src/app/[country]/[locale]/(storefront)/page.tsx`（首页板块编排）
  - `storefront/src/components/layout/Header.tsx` / `Footer.tsx` / `MobileMenu.tsx`
  - `storefront/src/components/home/HeroSection.tsx` / `FeaturedProductsSection.tsx`
  - `storefront/messages/en.json` / `de.json` / `pl.json` / `es.json` / `fr.json`（i18n 文案，全 5 语言同步）
- **依赖**：无新增依赖（图标用 lucide-react、图片用 next/image）
- **数据库 / 接口**：无变更（纯前端；订阅提交若接后端为后续扩展）
- **影响面**：storefront 层 + 文档；`harness affected` 预计仅波及 storefront workflow

## 8. 测试计划

- **新增测试**（每板块一测，标注 `# PRD-20260810-storefront-... AC-xxx`）：
  - `components/home/__tests__/CategoryShowcase.test.tsx`（AC-106：渲染/空态降级/链接）
  - `components/home/__tests__/ValueProps.test.tsx`（AC-108：≥3 卖点渲染）
  - `components/home/__tests__/BrandStory.test.tsx`（AC-108）
  - `components/home/__tests__/PromoBanner.test.tsx`（AC-108：banner + CTA）
  - `components/home/__tests__/NewsletterSignup.test.tsx`（AC-109：校验/成功态）
  - `components/home/__tests__/FaqSection.test.tsx`（AC-113：FAQ 渲染 + 与 JSON-LD 一致）
  - `components/layout/__tests__/CategoryNav.test.tsx`（AC-102：导航渲染/子分类/链接）
  - `components/layout/__tests__/Footer.test.tsx`（AC-104：无 demo 链接/区块齐全）
  - `app/llms.txt/__tests__/route.test.ts`（AC-114：返回 200 + 内容含标题/品牌/分类）
  - `lib/__tests__/seo.test.ts`（AC-112/116：WebSite+SearchAction JSON-LD 结构；metadata builders 回归）
- **更新测试**：
  - `components/home/HeroSection` 相关（AC-105：CTA 与文案变更）
  - `Header`/`MobileMenu` 相关（AC-103）
  - 现有 `ProductCard` 等回归
  - 首页集成测试（AC-115：唯一 H1、section 语义、alt 完整）
- **AC 映射**：AC-101/102/103/104/105/106/107/108/109 → 对应组件测试；AC-110 → 全局扫描（grep `href="#"`）+ i18n 审查；AC-111 → build + 全量测试；AC-112/113/114/115/116 → SEO/GEO 专项测试
- **验证命令**：`pnpm vitest run`（storefront）+ `pnpm build` + 浏览器实测（dev 环境）；`curl /llms.txt`、首页 JSON-LD 提取校验（`script[type=application/ld+json]`）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：**不涉及**（无接口变更）
- [x] Skill 文档：`ai/skills/pallastrade-storefront/SKILL.md`（§Components + Style Guide + SEO/GEO 章节更新）
- [x] 样式规范：`storefront/CLAUDE.md` / skill Style Guide（token 规范登记）
- [ ] 场景库：`harness/scenarios/scenarios.json`（可加 GS 场景：首页重构 / demo 清理 / GEO llms.txt）
- [x] README：`storefront/README.md`（如有结构说明变更）
- [x] SEO 文档：`docs/standards/`（如有 SEO/GEO 规范则登记）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-10 | 0.1 | 初稿（查重无命中；用户澄清范围=全面重构/重点首页；6 层搜索完成；现状诊断 6 项） | AI |
| 2026-08-10 | 0.2 | 用户补充要求：SEO + GEO 友好 → 新增 Phase 5（WebSite+SearchAction / FAQPage / llms.txt / 语义 HTML / metadata 回归），FR-501~505 + AC-112~116 | AI |
| 2026-08-10 | 0.3 | 用户修正：导航**功能存在但入口深**（Header 汉堡菜单 + Footer 分类链接），非缺失 → 修正诊断第 2 条；FR-201 改为「新增常驻顶部分类导航条」（MobileMenu 保留为移动端入口），FR-202 调整为补齐搜索/账户入口 | AI |
| 2026-08-10 | 0.4 | 用户确认「确认」→ **approved**；准备开 gate 分阶段实施 | 用户 + AI |
| 2026-08-10 | 0.5 | 实施中发现：支持语言为 **en/de/pl/es/fr（无中文）** → 全文「en/zh」表述修正为全部支持语言；新增文案同步 5 语言文件 | AI |
| 2026-08-10 | 0.6 | 实施完成（GATE-2026-08-10T05-18-09 14/14 全清）：P1 token 品牌蓝统一；P2 CategoryNav 常驻导航条+Footer 去 demo；P3 首页 8 板块；P4 demo 链接归零+5 语言 i18n；P5 WebSite+SearchAction/FAQPage/llms.txt/语义 HTML。156 测试通过（含 10 新增）+ build 成功 + 浏览器实测（8 板块/导航/JSON-LD/llms.txt 200）→ done | AI |
| 2026-08-10 | 0.7 | 用户 review 迭代（GATE-2026-08-10T06-35-54 14/14）：① Footer 改深色 bg-gray-950（去品牌蓝整底）；② CategoryNav 加横向滚动 overflow-x-auto+nowrap（类目多不溢出）；③ 移除 CategoryShowcase（与导航重复，首页 8→7 板块）；④ PromoBanner 重定位为「Limited-Time Offers」促销主题（避免与精选重复）。154 测试通过 + build 成功 + 浏览器实测 | AI |
| 2026-08-10 | 0.8 | bug 修复（GATE-2026-08-10T07-09-12 14/14）：CategoryNav 纯 hover → 改为**客户端组件**支持 hover+点击展开（chevron toggle）+ 三级联动（root→child→grandchild）；服务器 dev 预设三级分类示例（Kitchen/Coffee Machines→Espresso/Drip/Capsule Coffee Makers）。单测 3 通过 + 全量 156 + build 成功 + 浏览器实测点击展开 | AI |
| 2026-08-10 | 0.9 | bug 强化（GATE-2026-08-10T07-59-41 14/14）：CategoryNav 改为**点击一级分类名 → 展开 mega 子分类菜单面板**（grid 列展示全部二级 + 列内三级 + "View all" 链接；点击外部关闭；hover 兼容）。单测 3 通过 + 全量 156 + build 成功 + 浏览器实测面板展开 | AI |
| 2026-08-10 | 1.0 | 讨论落地 + bug 修复（GATE-2026-08-10T08-48-45 14/14）：① 重新实现 nav **hover 弹出次级分类面板**（hover 打开 + click 锁定，双模式）；② **移除 sr-only「Category navigation」nav**（与可视化 Categories nav 重复）；③ **汉堡按钮加 md:hidden**（移动端保留，桌面统一用 CategoryNav）。单测 4 通过（click+hover）+ 全量 157 + build 成功 + 浏览器实测 hover | AI |
| 2026-08-10 | 1.1 | bug 根因修复（GATE-2026-08-10T09-29-59 14/14）：**次级面板视觉不可见根因 = UL `overflow-x-auto` 创建裁剪容器**（CSS 规范：overflow-x 非 visible 时 overflow-y 计算为 auto，裁剪了 li 内 absolute 面板）。移除 UL overflow-x-auto 后 elementFromPoint 命中面板（topElementInPanel=true）。157 测试 + build 成功 + 截图确认 | AI |
| 2026-08-10 | 1.2 | 优化（GATE-2026-08-10T09-41-06 14/14）：桌面 CategoryNav 加 `sticky top-16 z-40`——**导航条随 Header 固定显示，不随页面滚动消失**（紧贴 Header 下方 64px）。157 测试 + build 成功 + 浏览器实测（滚动 1200px 后 nav top=64 可见） | AI |
