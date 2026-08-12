# REQ-20260812-storefront-cookie-consent

> 对应 PRD：`docs/prd/storefront/PRD-20260812-storefront-商城前台新增cookie功能.md`（approved）

## Step 0：跨层搜索（已执行，见 PRD §6）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | cookie/consent | 无匹配 | 不涉及 |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | cookie/consent | `newsletter/link_user.rb`（营销同意传播，无关） | 不涉及 |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | cookie/consent | admin `auth_cookies.rb`（管理端 refresh token cookie） | 不涉及（管理端） |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/app/` | cookie/consent | `locale_concern.rb`（admin locale cookie） | 不涉及（管理端） |
| Storefront | `storefront/src/` | cookie/consent/banner | `lib/utils/cookies.ts`、`lib/pallastrade/cookies.ts`、`components/policy/PolicyConsent.tsx`（条款同意，非 cookie consent）、`layout/TawkToWidget.tsx`、`app/layout.tsx`（GTM/Vercel）、`instrumentation-client.ts`（Sentry） | **需新建**（无 cookie 同意横幅/设置页/门控） |
| Platform | `platform/packages/` | cookie/consent | SDK auth cookie 文档、newsletter consent 文档 | 不涉及 |

**搜索结论**：全仓库无现成 cookie consent 设施，纯 storefront 层新增。后端/SDK/API/DB 零改动。`PolicyConsent` 为结账/注册条款同意，语义不同，不合并。

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：本需求为 storefront 层纯前端展示/交互改动（`Storefront vs backend` 表："Add a custom page like /about, /shipping → Storefront"；"anything customer-visible is the storefront"），不涉及 backend 模式选择 |
| `ai/skills/pallastrade-admin/SKILL.md` | ⬜ 不涉及 | 管理端 skill，本需求零管理端改动 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⬜ 不涉及 | 商品/类目 skill，本需求不涉及 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-storefront` | ✅ | ✅ 已读 | §Common patterns：`TawkToWidget` 为可选第三方挂件模式（env 缺失渲染 null，`next/script` `afterInteractive` 不阻塞首屏）→ 门控脚本沿用此模式；§Common gotchas：动态内联样式为 AP-001/006 例外；i18n 为 storefront 职责（`next-intl`，`messages/*.json`）；`NEXT_PUBLIC_*` 仅用于第三方客户端 SDK key（GTM/Sentry 等 public id 可用） |
| `pallastrade-api-v3` | ⬜ | ⬜ | 本需求无接口变更 |
| `pallastrade-security` | ⬜ 评估 | ⬜ | 涉及隐私合规（GDPR/CCPA），但为前端门控 + cookie 属性安全（SameSite），无需后端安全设施；实施时按需复核 |
| `pallastrade-testing` | ✅ 评估 | ⬜ | 测试按 storefront 既有 vitest 模式（`components/**/__tests__/*.test.tsx`，见 `CartContext`/`TawkToWidget` 测试），AC↔测试映射见 PRD §8 |
| `pallastrade-i18n` | ✅ 评估 | ⬜ | 复用现有 `next-intl` 模式：`messages/{en,de,es,fr,pl}.json` 新增 `cookie` 命名空间；5 语言同步 |

> ⛔ 表中"不涉及/评估"项均已在 PRD §6/§8 说明理由；本次实际编码涉及的 skill（customization + storefront + testing/i18n 模式）均已确认。

---

## 需求标题

商城前台新增 Cookie 同意横幅 + Cookie 设置页（分类管理、第三方脚本门控）。

## 任务类型

新功能（纯前端）

## 需求描述

1. 首次访问（无 consent cookie）显示 Cookie 同意横幅（全部接受 / 仅必需 / 自定义）
2. 提供 `/cookies` 设置页，可随时修改分类偏好（necessary 固定开启）
3. 按用户选择门控第三方脚本：Tawk.to(marketing)、Vercel Analytics/SpeedInsights(analytics)、GTM(analytics/marketing)、Sentry 客户端采集(analytics)
4. 页脚新增「Cookie 设置」链接；文案 5 语言
5. 购物车/登录/locale 等必需 cookie 流程零改动

## 影响范围（harness affected 输出）

实施时执行 `harness affected --base origin/main`。预期影响：storefront 全部（新增组件/上下文/常量/页面 + 修改 layout/Footer/TawkToWidget/instrumentation-client/messages ×5）。

## 技术方案（初步）

- **分类定义**：`src/lib/constants/cookies.ts` — `necessary/functional/analytics/marketing` 枚举 + 分类↔脚本/现有 cookie 映射
- **consent 存储**：cookie `pallastrade_cookie_consent`（JSON：各分类布尔 + version + timestamp），复用 `src/lib/utils/cookies.ts` 的 cookieStore/document.cookie 模式；consent cookie 本身为 necessary
- **上下文**：`src/contexts/CookieConsentContext.tsx` 客户端 Provider，读取/写入/暴露状态；挂在 `[country]/[locale]/layout.tsx`
- **横幅**：`src/components/cookie/CookieBanner.tsx`（底部固定，三个操作）
- **设置面板**：`src/components/cookie/CookieSettings.tsx`（分类开关，横幅"自定义"与设置页共用）
- **脚本门控**：`src/components/cookie/ScriptGate.tsx` 客户端组件按 consent 条件渲染 GTM/Vercel Analytics/SpeedInsights；`TawkToWidget` 读 marketing；Sentry `beforeSend` 读 analytics
- **设置页**：`src/app/[country]/[locale]/(storefront)/cookies/page.tsx`
- **i18n**：`messages/*.json` 新增 `cookie` 命名空间

## 风险点

- **最高风险**：SSR/hydration 不一致（consent 客户端读取 → 必须在 effect 中读取，服务端渲染占位）
- **回滚难度**：低（纯前端新增 + 门控改动，无数据/接口变更；回滚 = revert 提交）
- **次要风险**：GTM 从 root layout 移入门控组件后行为变化 → 保留 env 判断 + 同意后加载

## 决策节点

> ✅ 用户已于 2026-08-12 明确确认 PRD（"确认，实施"）。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 前端组件/页面 | `src/components/cookie/*`、`src/contexts/CookieConsentContext.tsx`、`src/app/.../cookies/page.tsx` | `pnpm test`（新增组件/上下文测试）+ 浏览器截图（横幅、设置页、门控 DOM） | | ⬜ |
| i18n | `messages/{en,de,es,fr,pl}.json` | `pnpm test`（i18n 完整性）+ 5 语言 key 对比 | | ⬜ |
| 布局/门控 | `src/app/layout.tsx`、`[country]/[locale]/layout.tsx`、`Footer.tsx`、`TawkToWidget.tsx`、`instrumentation-client.ts` | `pnpm build` / `pnpm lint` + 既有测试回归 | | ⬜ |
| 整体 | storefront 全量 | `harness check --profile quick`（或 storefront 等价 `pnpm lint + test + build`） | | ⬜ |

### 验证结论

（实施后填写）
