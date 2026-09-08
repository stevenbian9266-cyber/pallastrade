# REQ-20260908-storefront-mobile-account-and-menu-search

> 关联 PRD：`docs/prd/storefront/PRD-20260908-storefront-小屏下个人中心入口可见与移动菜单search弹出搜索框.md`
> 任务：TASK-20260908055653-4232edcb · Gate：GATE-2026-09-08T05-57-xx

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | account/header/search/移动 | 无前端代码 | ❌ 不涉及 |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ |
| Core Gem — models | `.../pallastrade_core/app/models/` | 同上 | 无 | ❌ |
| Core Gem — services | `.../pallastrade_core/app/services/` | 同上 | 无 | ❌ |
| API Gem — controllers | `.../pallastrade_api/app/controllers/` | 同上 | 无 | ❌ |
| Admin Gem — controllers/views | `.../pallastrade_admin/` | 同上 | 无 | ❌ |
| Storefront | `storefront/src/components/layout/` | Header/account hidden/MobileMenu/SearchToggle/SearchBar | `Header.tsx`（账户 `hidden md:block` = 小屏隐藏）；`MobileMenu.tsx`（Search 行 Link→/products；页脚 My Account）；`SearchToggle.tsx`（searchOpen + `#search-overlay` + SearchBar，唯一搜索浮层）；`search/SearchBar.tsx` | ⚠️ 部分——账户断点放开 + 菜单 Search 接浮层 |
| Platform | `platform/packages/` | 无 | 无 | ❌ |

### 搜索结论

搜索浮层能力已存在（SearchToggle 单例，自动聚焦 SearchBar）；缺「菜单 Search 触发它」的联动 + 小屏顶部账户可见。修复全部收敛在 storefront `layout/` 3 个组件 + 1 个 Context；前端既有账户门控（account/layout client）无需改。移动菜单账户入口（PRD-20260810 AC-103）保留。移动视口（390px）实测：头部账户 display:none；菜单 Search 仅跳 /products。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：UI 交互状态共享 → 用 Context 保持单一数据源；不新建重复 UI 组件（菜单 Search 复用 SearchToggle 浮层而非自建输入框） |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | §Home/CategoryNav：`MobileMenu`（`md:hidden` trigger）是小屏入口（AC-103：含分类树+账户+搜索入口）；§Components：搜索建议用 `SearchBar`（Meilisearch/quick search 由 products search 驱动）；i18n 由前端负责（header/search/openSearch/account/myAccount 复用，不新增 key） |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | PRD 流程：draft→approved→gate+REQ→AC↔测试→知识同步（storefront 组件改动须同步 storefront Skill §Components + scenarios） |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | 否 | — | 无 API 改动 |
| `pallastrade-testing` | 否 | — | 按 storefront vitest 惯例（jsdom + mock next-intl/useStore）新增组件测试 |

---

## 需求标题

小屏模式：① 顶部个人中心入口可见；② 左侧菜单点「Search」弹出搜索框

## 任务类型

功能优化（UI/响应式）

## 需求描述

`<md` 视口下 Header 账户图标被 `hidden md:block` 隐藏（仅桌面）；移动菜单「Search」行只是跳 `/products` 链接、不弹搜索框。目标：账户图标全断点可见；菜单 Search → 关闭菜单并打开 SearchToggle 搜索浮层（自动聚焦），复用同一搜索 UI。

## 影响范围（harness affected 输出）

- `storefront/src/components/layout/SearchToggle.tsx`（新增 SearchOverlayContext/useSearchOverlay）
- `storefront/src/components/layout/MobileMenu.tsx`（Search 行 Link→Button 触发 openSearch）
- `storefront/src/components/layout/Header.tsx`（账户图标去 hidden 包裹）
- 新增 `storefront/src/components/layout/__tests__/SearchOverlayMobile.test.tsx`
- 知识同步：storefront SKILL §Components + scenarios.json（GS-067）

## 技术方案（初步）

1. `SearchToggle.tsx`：定义 `SearchOverlayContext`（value `{ open, openSearch, closeSearch }`）并 export `useSearchOverlay`；Provider 包裹 `<header>` 内部全部内容（left 槽含 MobileMenu）。
2. `MobileMenu.tsx`：主面板 Search 行改 `<button>`（保留 Search icon + `t("search")`、`md:hidden`），onClick = `searchOverlay?.openSearch(); setOpen(false)`（无 Context 时回退跳 `/products`）。
3. `Header.tsx`：账户图标外层 `hidden md:block` div 移除 → 全断点渲染（注释更新）。

## 风险点

- 低。纯前端交互；复用既有浮层，无新样式/API/i18n。
- 共享文件 scenarios.json 含并行 REV-P6-7 未提交行 → 提交只带本行（additive）。
- 验证：vitest 组件测试 + biome；部署后 390px 浏览器 DOM 验证（AC-001/002/003）。

## 决策节点

> ✅ 用户明确「实施」（2026-09-08），PRD approved。进入实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| TSX | SearchToggle/MobileMenu/Header | vitest（新测试文件 + 相关回归）+ biome | | ⬜ |
| UI | 390px 视口 | dev 浏览器 DOM：账户图标可见 & 菜单 Search 弹浮层 | | ⬜ |
| 类型 | storefront | tsc（CI storefront 也会跑） | | ⬜ |

### 验证结论

<!-- 实施后填写 -->
