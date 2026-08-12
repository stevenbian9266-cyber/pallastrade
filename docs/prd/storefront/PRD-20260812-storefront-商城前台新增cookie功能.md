# PRD-20260812-storefront-商城前台新增cookie功能

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-12 |
| 来源 | 商城前台新增cookie功能 |
| 分类 | storefront |
| 关联 Skill | pallastrade-storefront / pallastrade-security / pallastrade-deployment |
| 关联 REQ | REQ-20260812-storefront-cookie-consent |
| 关联 PRD | N/A（全新需求，已确认与 tawk-to / 重新规划 / turnstile 仅同属 storefront 场景，功能不同） |
| 需求类型 | 新功能（纯前端，无接口变更） |

> 🔁 **查重回写**：`harness prd new` 检测到 3 个相似 PRD（43%），均因同属"商城前台"关键词命中；逐一核对功能不同（tawk-to 客服接入 / 商城重新规划 / turnstile 真人验证），确属全新需求，`--force` 新建。

---

## 1. 背景与目标

- **一句话需求原文**：商城前台新增cookie功能
- **背景**：
  - 商城前台已在大量使用 cookies：购物车 token（`_pallastrade_cart_token`）、登录 JWT（`_pallastrade_jwt` / `_pallastrade_refresh_token`）、locale/country（`pallastrade_country` / `pallastrade_locale`）
  - 已接入多个第三方脚本：GTM（`GTM_ID`）、Vercel Analytics / SpeedInsights、Sentry（`NEXT_PUBLIC_SENTRY_DSN`）、Tawk.to 客服挂件
  - **但没有任何 Cookie 同意（consent）机制**——不满足 GDPR / CCPA 等隐私法规对"非必需 cookie 与第三方跟踪需用户同意"的要求
  - 用户已确认范围：**Cookie 同意横幅 + Cookie 设置页**
- **目标**：
  1. 首次访问显示 Cookie 同意横幅（全部接受 / 仅必需 / 自定义）
  2. 提供独立 Cookie 设置页（`/cookies`），可随时查看/修改偏好
  3. 按用户选择门控第三方脚本（分析 / 营销类）；必需 cookie 不受影响
- **成功指标**：
  - 无 consent cookie 时首次访问 100% 渲染横幅
  - 用户做出选择后写入 consent cookie，后续访问不再重复弹出
  - 拒绝 analytics/marketing 后，对应第三方脚本 DOM 中不可见（不加载）
  - 设置页可随时打开修改，保存后即时生效

## 2. 用户故事 / 场景

- 作为访客，我第一次访问商城时看到 Cookie 横幅，可选择"全部接受 / 仅必需 / 自定义"
- 作为注重隐私的访客，我希望随时打开 Cookie 设置页修改之前的偏好选择
- 作为管理员，我希望拒绝分析的访客不会触发 GTM / 分析脚本（合规）
- 作为购物用户，购物车 / 登录 / 地区语言切换等必需功能不因 cookie 选择而失效

**正常流**
- 全部接受：首次访问 → 横幅出现 → 点「全部接受」→ 写入 consent（4 分类全开）→ 横幅消失 → 第三方脚本按需加载
- 仅必需：首次访问 → 点「仅必需」→ 写入 consent（仅 necessary）→ 横幅消失 → 不加载第三方脚本
- 自定义：首次访问 → 点「自定义」→ 展开分类开关面板 → 勾选 → 保存 → 写入所选分类
- 设置页：已选择后 → 页脚「Cookie 设置」链接 → 打开 `/cookies` → 修改开关 → 保存 → 即时生效

**边界**
- 已有有效 consent cookie → 不显示横幅
- consent cookie 损坏 / 格式非法 → 视为未同意，重新显示横幅
- 拒绝后再次访问 → 横幅不重复弹出（尊重选择）；用户可通过设置页主动改回

**异常**
- cookie / cookieStore 写入失败 → 横幅按"未同意"处理，不崩溃、不阻塞页面核心内容
- 无 JS 环境 → 横幅不渲染（页面内容正常），属可接受降级

## 3. 功能需求（FR）

- FR-001：新增 Cookie 分类定义与映射常量（`necessary` / `functional` / `analytics` / `marketing`），集中声明各分类对应的现有 cookies 与第三方脚本（`src/lib/constants/cookies.ts`）
- FR-002：无 consent cookie 时，首次访问渲染 Cookie 同意横幅（底部固定），提供「全部接受 / 仅必需 / 自定义」三个操作
- FR-003：用户选择后写入 consent cookie（建议名 `pallastrade_cookie_consent`，值含各分类布尔 + 版本 + 时间戳；consent cookie 本身属于 necessary，豁免同意）
- FR-004：新增 Cookie 设置页路由 `/[country]/[locale]/cookies`（`(storefront)` 组），渲染各分类开关；`necessary` 始终开启且不可关闭；保存后更新 consent cookie 并即时生效
- FR-005：页脚「Policies」区新增「Cookie 设置」链接（i18n 5 语言），指向设置页
- FR-006：新增客户端 Cookie 同意上下文 `CookieConsentProvider`（`src/contexts/CookieConsentContext.tsx`），统一读取/写入 consent，横幅与设置页共用；SSR 无 hydration mismatch（客户端 effect 内读取）
- FR-007：门控第三方脚本——Tawk.to（marketing）、Vercel Analytics / SpeedInsights（analytics）、GTM（analytics/marketing）：仅当对应分类同意时才加载；未同意时 DOM 无对应 script；同意变更后即时挂载/卸载
- FR-008：Sentry 客户端采集（`instrumentation-client.ts`）受 analytics 同意门控——通过 `beforeSend` / `beforeSendTransaction` 在未同意时丢弃事件
- FR-009：横幅、设置页、分类说明的全部文案补齐 5 语言（en / de / es / fr / pl，`messages/*.json`）
- FR-010：回归兼容——购物车 / 登录 / locale / country 等必需 cookie 流程不变（`setStoreCookies`、`CartProvider`、`AuthProvider` 不改动）

## 4. 非功能需求（NFR）

- **隐私合规**：符合 GDPR / CCPA 最小必要原则；consent cookie 本身豁免同意；不追踪已拒绝用户
- **性能**：横幅渲染不阻塞首屏；第三方脚本沿用 `afterInteractive` 按需加载策略
- **兼容**：SSR 无 hydration mismatch（consent 客户端读取）；无 JS 环境优雅降级；现有 5 语言一致
- **可维护**：分类→脚本映射单点定义（常量）；ConsentProvider 单点读写；i18n 单一来源
- **安全**：consent cookie 不存敏感信息；`SameSite=Lax`；不引入新依赖（复用现有 cookie 工具）

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-002：无 consent cookie 时组件测试渲染横幅；已有 consent 时不渲染
- AC-002 ← FR-003：点「全部接受」写入 consent cookie（4 分类全 true）；点「仅必需」写入（仅 necessary=true）
- AC-003 ← FR-003/002：点「自定义」展开分类面板，勾选后保存写入所选分类
- AC-004 ← FR-004：`/cookies` 页渲染各分类开关；`necessary` 禁用不可改；修改保存后 cookie 更新
- AC-005 ← FR-007：analytics/marketing 拒绝时 TawkTo / GTM / Vercel Analytics 组件不渲染对应 script；同意后渲染
- AC-006 ← FR-008：Sentry `beforeSend` 在 analytics 拒绝时返回 null 不发送事件（单测）
- AC-007 ← FR-009：5 语言 messages 文件包含全部新增 key（i18n 完整性校验）
- AC-008 ← FR-005：页脚显示「Cookie 设置」链接且可导航至 `/cookies`
- AC-009 ← FR-010：既有购物车 / 登录 / locale 相关测试全绿（回归）

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | cookie/consent | 无匹配 | 不涉及（纯前端功能） |
| Core | `pallastrade_gems/pallastrade_core/app/` | cookie/consent | `newsletter/link_user.rb`（营销同意传播，与 cookie consent 无关） | 不涉及 |
| API | `pallastrade_gems/pallastrade_api/app/` | cookie/consent | admin `auth_cookies.rb`（refresh token cookie，管理端鉴权） | 不涉及（管理端，非商城前台） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | cookie/consent | `locale_concern.rb`（admin locale cookie） | 不涉及（管理端） |
| Storefront | `storefront/src/` | cookie/consent/banner | `lib/utils/cookies.ts`（客户端 cookie 工具）、`lib/pallastrade/cookies.ts`（cart/auth cookie helpers）、`components/policy/PolicyConsent.tsx`（结账/注册条款同意复选框）、`layout/TawkToWidget.tsx`、`app/layout.tsx`（GTM/Vercel）、`instrumentation-client.ts`（Sentry） | **需新建**：无任何 cookie 同意横幅/设置页/门控；`PolicyConsent` 是条款同意，与 cookie consent 无关 |
| Platform | `platform/packages/` | cookie/consent | SDK auth cookie 文档、newsletter consent 文档 | 不涉及（前端功能无需 SDK 变更） |

**结论**：全仓库无现成 cookie consent 设施（全新功能）。改动全部落在 storefront 层（新增 banner + settings + provider + 常量 + 门控；改 root/locale layout、Footer、TawkToWidget、instrumentation-client、messages）。后端 / SDK / 数据库 / API 零改动。无重复代码风险（`PolicyConsent` 为条款同意，语义不同，不合并）。

## 7. 技术影响

- **新增文件（storefront）**：
  - `src/lib/constants/cookies.ts` — 分类定义 + 分类↔脚本/现有 cookie 映射
  - `src/contexts/CookieConsentContext.tsx` — 客户端 Provider（读/写 consent cookie，暴露分类状态与操作）
  - `src/components/cookie/CookieBanner.tsx` — 首次访问横幅（全部接受 / 仅必需 / 自定义）
  - `src/components/cookie/CookieSettings.tsx` — 分类开关面板（横幅"自定义"与设置页共用）
  - `src/components/cookie/ScriptGate.tsx`（或等价客户端门控组件）— 按 consent 条件渲染 GTM / Vercel Analytics / SpeedInsights / TawkTo
  - `src/app/[country]/[locale]/(storefront)/cookies/page.tsx` — 设置页（含 metadata）
- **修改文件（storefront）**：
  - `src/app/layout.tsx` — GTM / Vercel Analytics / SpeedInsights 移入门控组件（保留 env 判断）
  - `src/app/[country]/[locale]/layout.tsx` — 挂载 `CookieConsentProvider` + `CookieBanner`
  - `src/components/layout/TawkToWidget.tsx` — 读取 consent（marketing）决定是否加载
  - `src/components/layout/Footer.tsx` — Policies 区加「Cookie 设置」链接
  - `src/instrumentation-client.ts` — Sentry `beforeSend` / `beforeSendTransaction` 门控（analytics）
  - `messages/{en,de,es,fr,pl}.json` — 新增 `cookie` 命名空间
- **不涉及**：backend / SDK / 数据库 / 接口（无 API 变更，无需 `generated:check`）
- **依赖**：无新增依赖（复用现有 `next/script`、UI 组件 button/switch、`lib/utils/cookies.ts` 模式）
- **影响面**：`harness affected --base origin/main`（实施时执行）

## 8. 测试计划

- **新增测试**：
  - `storefront/src/contexts/__tests__/CookieConsentContext.test.tsx`（AC-001/002/003：consent 读写、默认值、损坏值处理）
  - `storefront/src/components/cookie/__tests__/CookieBanner.test.tsx`（AC-001/002/003：渲染条件、三个按钮行为）
  - `storefront/src/components/cookie/__tests__/CookieSettings.test.tsx`（AC-003/004：开关交互、necessary 禁用、保存写入）
  - `storefront/src/components/cookie/__tests__/ScriptGate.test.tsx`（AC-005：各分类同意/拒绝时脚本渲染与否）
- **更新测试**：
  - `storefront/src/components/layout/__tests__/TawkToWidget.test.tsx`（AC-005：marketing 同意才渲染）
  - `storefront/src/app/[country]/[locale]/(storefront)/cookies/__tests__/page.test.tsx`（AC-004/008：页面渲染与保存）
  - i18n 完整性（AC-007）：新增 key 校验（对比 5 语言文件）
- **E2E（可选）**：`storefront/e2e/` cookie banner 首访→选择→不再弹出的流程
- **AC 映射**：AC-001/002/003→CookieConsentContext+Banner 测试；AC-004→Settings+page 测试；AC-005→ScriptGate+TawkTo 测试；AC-006→Sentry 单测；AC-007→i18n 校验；AC-008→page+Footer 测试；AC-009→既有测试回归
- **验证证据**：UI 变更 → 浏览器截图（横幅渲染、设置页开关、拒绝后无第三方 script）+ `pnpm test` 全绿

## 9. 文档同步清单（知识同步门）

- [x] API 文档：不涉及（无接口变更，`generated:check` 无需）
- [x] Skill：`ai/skills/pallastrade-storefront/SKILL.md`（§Components 新增 Cookie consent 小节：Provider/Banner/CookieSettings/GatedScripts/Sentry 门控）；`ai/skills/pallastrade-deployment/SKILL.md`（build-arg 说明加入 GTM ID）
- [x] README / Agent 文件：`storefront/CLAUDE.md`（已评估——结构树为通用路由组描述，无需逐路由登记；样式零改动，无需样式规范更新）
- [x] 反模式 / 任务规则 / 场景库：无新反模式（gate 机制无违反）；`harness/scenarios/scenarios.json` 新增 **GS-025**（Storefront cookie consent: banner + settings page + third-party gating）
- [x] 部署文档：`storefront/.env.example`（`GTM_ID` → `NEXT_PUBLIC_GTM_ID`，说明公开非密钥）；`deploy/.env.storefront.prod.example` + `deploy/docker-compose.{dev,prod}.yml`（新增 `NEXT_PUBLIC_GTM_ID` build-arg）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

> **sync-check 结论（2026-08-12）**：`harness sync-check --id PRD-20260812-storefront-商城前台新增cookie功能` 列出的 backend/CLI/SDK/workflow/globals.css 等大量变更属 dev 与 origin/main 的历史差异，非本任务改动；本任务实际涉及资产（storefront skill / deployment skill / 场景库 / env 文档 / PRD 索引）已全部处理。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-12 | 0.1 | 初稿：范围确认（横幅+设置页）+ 6 层跨层搜索 + 方案设计 | AI |
| 2026-08-12 | 0.2 | 用户确认实施（approved） | 用户 |
| 2026-08-12 | 0.3 | 实施完成：新增 8 文件（常量/纯逻辑/Context/Banner/CookieSettings/GatedScripts/cookies 页）+ 修改 6 文件（root+locale layout/Footer/instrumentation-client/messages×5）+ 5 组 28 个新测试；修复跨流式分段 hydration 错误（mounted 本地化）；完整回归 191 测试全绿 + lint/typecheck/locale 通过 + 生产构建成功；浏览器验证（横幅三操作/cookie 写入/设置页/脚本门控/页脚链接）+ 截图证据（`artifacts/harness-evidence/cookie-*.png`）；知识同步门完成 | AI |
