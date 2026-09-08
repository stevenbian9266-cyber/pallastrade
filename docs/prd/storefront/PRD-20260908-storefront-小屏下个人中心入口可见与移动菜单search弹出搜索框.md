# PRD-20260908-storefront-小屏下个人中心入口可见与移动菜单search弹出搜索框

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-08 |
| 来源 | 优化：1、小屏模式下，个人中心入口被隐藏了 2、小屏模式下，左侧菜单面板中，点击 search，没有显示搜索框 |
| 分类 | storefront（AI 语义微调：自动判定为 catalog 因标题含「搜索」；实际为前端头部/移动菜单 UI，归属 storefront） |
| 关联 Skill | pallastrade-storefront |
| 关联 REQ | REQ-20260908-storefront-mobile-account-and-menu-search.md（实施时回填） |
| 关联 PRD | PRD-20260810-storefront-对商城前台进行重新规划（FR-202/AC-103：移动菜单含账户+搜索入口） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：优化：1、小屏模式下，个人中心入口被隐藏了；2、小屏模式下，左侧菜单面板中，点击 search，没有显示搜索框
- **背景**：
  - 移动视口（390×844）实测：头部顶部栏右侧只有 Search、Cart 两个图标——账户图标被 `Header.tsx` 的 `hidden md:block` 包裹（注释 “Account - desktop only”），**<md 时 display:none**（DOM 宽高 0）；用户需先开汉堡菜单再滑到底部才有「My Account」（菜单页脚，`md:hidden`）。→ 顶部个人中心入口对小屏「被隐藏」，与桌面不一致。
  - 移动菜单主面板「Search」行当前实现为 `SheetClose + Link → /products`（PRD-20260810 FR-202 仅要求“搜索入口”），点击只是跳商品列表页，**并不弹出搜索框**；用户预期与头部搜索图标一致：点击即弹出含搜索框的浮层（`SearchToggle` 的 search-overlay，含自动聚焦的 `SearchBar`）。
- **目标**：① 小屏顶部栏提供与桌面一致的「个人中心」图标入口；② 移动菜单点「Search」→ 关闭菜单并弹出头部搜索浮层（带搜索框/自动聚焦）。
- **成功指标**：<md 视口 Header 可见 Account 图标（非 display:none）且点击进入 `/account`；移动菜单点 Search 后菜单关闭、`#search-overlay` 打开且输入框自动聚焦。

## 2. 用户故事 / 场景

- 作为手机用户，我希望在顶部栏直接看到个人中心图标，以便不打开菜单也能进入账户/订单。
- 作为手机用户，我希望在左侧菜单点「Search」立刻看到搜索框，以便直接输入关键词搜索商品。
- 场景：
  - 正常流（FR-001）：手机访问 → 顶栏见 搜索/个人中心/购物车 三图标 → 点人像 → `/account`（未登录由 `account/layout.tsx` 客户端门控跳登录并回跳）。
  - 正常流（FR-002）：开汉堡菜单 → 点「Search」→ 菜单关闭、头部搜索浮层展开（输入框自动聚焦）→ 输入/选择建议/回车。
  - 边界：桌面（≥md）不受影响——顶部账户图标本来可见；搜索仍由头部搜索按钮控制。
  - 边界：菜单「My Account」（页脚）保留（AC-103 不回归），与顶栏图标并存。
  - 异常：浮层打开后点 Esc/点外部关闭（既有行为保持）。

## 3. 功能需求（FR）

- FR-001：`Header` 的账户（个人中心）入口在所有断点可见——移除 `hidden md:block` 包裹，小屏顶部栏展示人像图标（aria-label=header.account），点击进入 `{basePath}/account`。
- FR-002：`MobileMenu` 主面板「Search」行由“跳转 /products 的链接”改为“按钮：关闭菜单并调用 SearchToggle 打开搜索浮层（`#search-overlay`，`SearchBar` 自动聚焦）”。通过 `SearchToggle` 提供的搜索浮层 Context（`useSearchOverlay().openSearch`）实现跨组件联动，不复制第二套搜索 UI。
- FR-003（回归保持）：桌面头部搜索按钮、Esc/外部点击关闭、移动菜单「My Account」入口、AC-103 菜单结构均不回归。

## 4. 非功能需求（NFR）

- 性能：搜索浮层为既有单例（不重复实例化 SearchBar）；Context 开销可忽略。
- 兼容：不新增 i18n key（复用 `header.search/openSearch/account/myAccount`）；不改 API/SDK。
- 可访问性：Search 行仍为可聚焦控件；打开浮层后输入框自动聚焦（沿用 SearchBar autoFocus 机制）。
- 可维护：单一数据源——菜单与头部共用同一个 `searchOpen` 状态（Context），避免两套开关不同步。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：`<md` 视口语义下 Header 账户链接不再被 `hidden`/`md:hidden` 隐藏（组件测试断言无隐藏类包裹；浏览器 390px DOM 实测可见、宽高>0），href=`/account`。
- AC-002 ← FR-002：MobileMenu 点「Search」→ 触发 `openSearch` 且关闭菜单（组件测试 spy）；浏览器 390px：点菜单 Search 后 `#search-overlay` 打开、可见 `input[placeholder*="Search"]` 且自动聚焦、URL 不变（不跳 /products）。
- AC-003 ← FR-003：桌面行为不回归：头部搜索按钮仍可开合浮层（组件测试/浏览器 ≥md 抽查）；菜单页脚「My Account」仍存在。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | account/header/search（host app） | 无前端代码 | ❌ 不涉及 |
| Core | `pallastrade_core/app/` | 同上 | 无 | ❌ 不涉及 |
| API | `pallastrade_api/app/` | 同上 | 无 | ❌ 不涉及 |
| Admin | `pallastrade_admin/app/` | 同上 | 无 | ❌ 不涉及 |
| Storefront | `storefront/src/components/layout/` | Header / MobileMenu / SearchToggle / SearchBar | `Header.tsx`（账户 `hidden md:block`）；`MobileMenu.tsx`（Search 行=Link→/products；页脚 My Account）；`SearchToggle.tsx`（searchOpen 状态 + `#search-overlay` + SearchBar）；`search/SearchBar.tsx` | ⚠️ 部分——账户断点放开 + 菜单 Search 接浮层需改 |
| Platform | `platform/packages/` | 无 | 无 | ❌ 不涉及 |

**结论**：搜索浮层能力已存在（SearchToggle 单例），缺的是“菜单内 Search 触发它”的联动与“小屏头部账户可见”；无重复实现。改动收敛在 storefront `layout/` 三个组件 + 新增 Context，不新增页面/SDK。移动菜单账户入口（AC-103）保留不动。

## 7. 技术影响

- 文件：
  - `storefront/src/components/layout/SearchToggle.tsx`：新增 `SearchOverlayContext` + `useSearchOverlay()`（值：`{ open, openSearch, closeSearch }`），Provider 包裹 header 内容（含 `left`/MobileMenu）。
  - `storefront/src/components/layout/MobileMenu.tsx`：主面板「Search」Link→Button，onClick=`openSearch()` + `setOpen(false)`（无 Context 时回退跳 `/products`）。
  - `storefront/src/components/layout/Header.tsx`：移除账户图标 `hidden md:block` 包裹，全断点渲染。
  - 新增测试：`storefront/src/components/layout/__tests__/SearchOverlayMobile.test.tsx`（+ Header 账户断言）。
  - 知识同步：`ai/skills/pallastrade-storefront/SKILL.md` §Components（Header/MobileMenu/SearchToggle 行为说明）→ 追加；`harness/scenarios/scenarios.json` 增 GS 场景。
- 无 DB/API/路由/i18n/SDK 变更。
- 影响面：仅 storefront 头部/移动菜单；桌面与既有账户门控不回归。

## 8. 测试计划

- 新增 `storefront/src/components/layout/__tests__/SearchOverlayMobile.test.tsx`：
  - AC-001 → Header 渲染账户链接且外层无 `hidden`/`md:hidden` 类（mock next/dynamic 为桩 + next-intl/server + lib/store）。
  - AC-002 → 渲染 `SearchToggle`（left 内嵌 `MobileMenu`，包 Provider，mock StoreContext/useCountrySwitch/next-intl/next-navigation）：点菜单「Search」→ `openSearch` 被调 + 菜单关闭；浮层 `#search-overlay` 内出现搜索输入框。
  - AC-003 → 头部搜索按钮开合浮层既有用例保持（SearchToggle 单测）；菜单页脚「My Account」存在。
- 浏览器验证（dev）：390px 视口 DOM 检查（AC-001/002）+ ≥md 抽查（AC-003）。
- AC 映射：AC-001/002/003 → SearchOverlayMobile.test.tsx；既有 `pnpm check`（biome）+ vitest 相关套件保持绿。

## 9. 文档同步清单（知识同步门）

- [x] Skill：`ai/skills/pallastrade-storefront/SKILL.md` §Components 追加（Header 全断点账户 + 菜单 Search→浮层联动）
- [x] 场景库：`harness/scenarios/scenarios.json` 增 GS（移动菜单搜索/账户可见性）
- [ ] API 文档 / README / Agent / 反模式 / 任务规则 —— 不涉及（评估 reviewed-no-change）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-08 | 0.1 | 初稿（390px 视口实测取证） | AI |
| 2026-09-08 | 0.2 | 用户确认实施：Header 账户去 `hidden md:block`；SearchToggle 新增 SearchOverlayContext/useSearchOverlay；MobileMenu Search 行→button 开浮层；组件测试 5 例 + layout 14 例全绿；commit 19475e6 | AI |
