# 需求文档：商城前台接入 tawk.to 客服工具

> 关联 PRD：`docs/prd/storefront/PRD-20260810-storefront-商城前台接入tawk-to作为客服工具.md`（已 approved）
> 关联 Gate：`GATE-2026-08-10T02-38-39`
> 创建日期：2026-08-10

---

## Step 0：跨层搜索（已执行，结论复用 PRD §6）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | tawk、客服、chat、support | `application_controller.rb`（无关） | ❌ 无 |
| App — views/decorators | `backend/app/` | tawk、客服、chat | 无 | ❌ 无 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | tawk、chat、support | `customer_support_email`（邮件支持邮箱） | ❌ 无 |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | tawk、chat、support | 无 | ❌ 无 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | tawk、chat、support | 无客服工具端点 | ❌ 无 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | tawk、chat、support | `customer_support_email` 相关 | ❌ 无 |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | tawk、chat、support | `_set_customer_support_email.html.erb`（邮件支持配置） | ❌ 无 |
| Storefront | `storefront/src/` | tawk、客服、chat、support.widget、intercom、crisp、zendesk | `lib/seo.ts` 仅 schema.org `contactType`；无客服注入 | ❌ 无 |
| Platform | `platform/packages/` | tawk、chat、support | 仅文档 `supports` 误报 | ❌ 无 |

### 搜索结论

全 6+ 层均无在线客服/聊天工具实现，唯一相关能力为 `customer_support_email`（邮件支持）。本需求为**全新前端集成**：在 storefront 层新建 `TawkToWidget` 组件并挂载根布局，不动后端。防重复判定：无重复实现、无重复 PRD。

---

## Step 1：Skill 文件咨询（已完成）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：前端集成属 storefront 层定制；本项目不改后端，无后端定制需求（无需 decorator/subscriber/dependency）。最高优先级"Settings/Config"在此场景体现为 storefront 环境变量开关 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | ① `NEXT_PUBLIC_*` 仅用于第三方客户端 key（Stripe/PayPal publishable key），tawk.to ID 属同类公开标识 ✅ 符合；② 组件放 `storefront/src/components/`，测试用 Vitest + Testing Library |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | PRD 流程 §5：每个 AC 必须映射测试，测试标注 `# PRD-xxx AC-x`；§7 按改动类型跑最小验证 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ 否（无接口变更） | ⬜ | — |
| `pallastrade-decorators` | ⬜ 否（不动后端） | ⬜ | — |
| `pallastrade-dependencies` | ⬜ 否（不动后端） | ⬜ | — |
| `pallastrade-events-webhooks` | ⬜ 否（无事件） | ⬜ | — |
| `pallastrade-testing` | ✅ 是 | ✅ 已读约定（来自 storefront skill + 现有测试） | 测试目录约定 `src/components/**/__tests__/*.test.tsx`（已有 `ProductCard.test.tsx` 等先例）；`next/script` 组件可用 `render` + 断言 script 节点 |
| `pallastrade-i18n` | ⬜ 否（无文案新增） | ⬜ | — |

---

## 需求标题

商城前台接入 tawk.to 在线客服工具（全站右下角聊天挂件）

## 任务类型

新功能（PRD 已 approved）

## 需求描述

通过环境变量 `NEXT_PUBLIC_TAWK_TO_PROPERTY_ID` + `NEXT_PUBLIC_TAWK_TO_WIDGET_ID` 配置 tawk.to，两个 ID 均设置时在 storefront 全站注入 tawk.to 聊天挂件（异步加载，不阻塞首屏）；未配置时零影响。

- Property ID：`6a32b7a845840f1d49424bd9`（用户已提供）
- Widget ID：`1jrb1qrcu`（用户已提供）
- 挂件 src：`https://embed.tawk.to/6a32b7a845840f1d49424bd9/1jrb1qrcu`

## 影响范围（harness affected 输出）

> 实施时运行 `node scripts/harness/cli.mjs affected --base origin/main` 确认；预期仅波及 storefront 组件与文档，无后端/平台影响。

## 技术方案（初步）

1. **新增** `storefront/src/components/layout/TawkToWidget.tsx`（`"use client"`）
   - 读取 `process.env.NEXT_PUBLIC_TAWK_TO_PROPERTY_ID` / `NEXT_PUBLIC_TAWK_TO_WIDGET_ID`
   - 任一缺失 → `return null`
   - 双 ID 齐全 → `<Script id="tawk-to" strategy="afterInteractive" src={`https://embed.tawk.to/${propertyId}/${widgetId}`} />`
2. **修改** `storefront/src/app/layout.tsx`：`<body>` 内挂载 `<TawkToWidget />`（放在 Suspense 之后、`</body>` 前）
3. **测试**：`storefront/src/components/layout/__tests__/TawkToWidget.test.tsx`
   - mock `process.env`（vi.stubEnv 或手动 save/restore）
   - 用例：双 ID → script 渲染且 src 正确；空/单 ID → null；strategy=afterInteractive
4. **文档**：`.env.example` / `storefront/README.md` / `platform/docs/developer/storefront/nextjs/deployment.mdx` 增加 2 个 env 变量说明（留空禁用）
5. **Skill**：`ai/skills/pallastrade-storefront/SKILL.md` §Components 记录新组件
6. **本地配置**：`storefront/.env.local` 填入真实 ID 用于实测

决策依据：决策树"Settings/Config"级（环境变量开关）→ 最简、最安全、可升级；无新增依赖（`next/script` 内置）；不引入后端改动。

## 风险点

- `next/script` 在测试环境渲染行为：需用 Testing Library 断言 script 元素（`afterInteractive` 下 script 在客户端注水后出现；SSR 时组件渲染 null 或 script 占位——测试用 `render` 检查 src/strategy）
- 环境变量在测试中需隔离（vitest 全局污染）→ 用 `vi.stubEnv` + `vi.unstubAllEnvs`
- tawk.to 脚本为第三方，若不可达静默失败（不阻塞页面）——符合预期，无回滚风险（未配置即禁用）

## 决策节点

> ✅ 用户已确认 PRD（2026-08-10「确认」），本需求文档与 PRD 一致，直接进入实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| TSX 组件 | `storefront/src/components/layout/TawkToWidget.tsx` | `pnpm --filter storefront test`（新增测试通过）+ `pnpm --filter storefront build` | | ⬜ |
| 布局 | `storefront/src/app/layout.tsx` | `pnpm --filter storefront build` + 浏览器实测（配置 ID 后挂件出现） | | ⬜ |
| 文档 | `.env.example` / `README.md` / `deployment.mdx` / skill | `harness doc-impact --base origin/main` | | ⬜ |

### 验证结论

<!-- 实施后填写 -->
