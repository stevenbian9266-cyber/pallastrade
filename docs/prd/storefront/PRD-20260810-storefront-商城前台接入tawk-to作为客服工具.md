# PRD-20260810-storefront-商城前台接入tawk-to作为客服工具

| 元数据 | 值 |
|---|---|
| 状态 | draft |
| 创建日期 | 2026-08-10 |
| 来源 | 商城前台接入tawk.to作为客服工具 |
| 分类 | storefront（自动判定） |

> ⚠️ AI：请按 docs/prd/_TEMPLATE.md 完整扩充本文档（背景/FR/AC/跨层搜索/测试计划/文档同步清单），再进入用户确认。

---

# PRD-20260810-storefront-商城前台接入tawk-to作为客服工具

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-10 |
| 来源 | 商城前台接入tawk.to作为客服工具 |
| 分类 | storefront（自动判定） |
| 关联 Skill | pallastrade-storefront |
| 关联 REQ | REQ-20260810-tawk-to-widget.md |
| 关联 PRD | N/A（全新需求，查重无命中） |
| 需求类型 | 新功能 |

> 🔁 **查重回写**：`harness prd new` 已自动查重（标题相似度 ≤ 0.3，无命中），
> 确认为全新需求，正常新建本 PRD。

## 1. 背景与目标

- **一句话需求原文**：商城前台接入 tawk.to 作为客服工具
- **背景**：当前商城（storefront）仅有邮件支持渠道（`customer_support_email` / `STORE_SUPPORT_EMAIL`），客户咨询需等待邮件回复，缺少实时在线沟通能力。tawk.to 是免费（基础版）的在线客服 SaaS，通过一段嵌入脚本即可在任意网站右下角显示聊天挂件，无需自建后端。
- **目标**：在商城前台所有页面右下角显示 tawk.to 客服聊天挂件，访客可实时与客服沟通；未配置时不加载任何脚本，零影响。
- **成功指标**：
  - 配置后所有 storefront 页面（含首页/列表/详情/购物车/结算）均显示客服挂件
  - 挂件脚本异步加载（`afterInteractive`），不阻塞首屏渲染（LCP 无劣化）
  - 未配置环境变量时页面零额外请求、零控制台报错

## 2. 用户故事 / 场景

- 作为 **商城访客**，我希望在浏览/下单遇到问题时能**实时咨询客服**，以便快速解决疑问、提升下单意愿
- 作为 **店主/客服**，我希望通过 tawk.to 后台统一接待所有访客会话，以便无需自建聊天系统

**场景列表：**

| 场景 | 类型 | 描述 |
|---|---|---|
| S-001 | 正常 | 已配置 Property ID + Widget ID → 所有页面右下角显示挂件，点击可发起会话 |
| S-002 | 正常 | 挂件异步加载，页面首屏渲染不受阻塞 |
| S-003 | 边界 | 仅配置其中一个 ID（缺另一个）→ 不加载脚本，视为未启用 |
| S-004 | 边界 | 完全未配置 → 页面无任何 tawk.to 相关 DOM/请求/报错 |
| S-005 | 异常 | tawk.to 服务不可达 → 挂件静默不显示，不影响页面其他功能 |

## 3. 功能需求（FR）

- FR-001：通过环境变量 `NEXT_PUBLIC_TAWK_TO_PROPERTY_ID`（Property ID）与 `NEXT_PUBLIC_TAWK_TO_WIDGET_ID`（Widget ID）配置 tawk.to；**两个均设置**才启用客服挂件，任一缺失视为未启用
- FR-002：在根布局 `<body>` 内注入客服挂件加载逻辑，作用于全站所有页面
- FR-003：挂件脚本使用 `next/script` 的 `afterInteractive` 策略异步加载（src 为 `https://embed.tawk.to/{propertyId}/{widgetId}`），不阻塞首屏渲染
- FR-004：未启用时组件渲染 `null`，不产生任何 DOM 节点、外部请求或控制台错误
- FR-005：环境变量在 `storefront/.env.example`、`storefront/README.md`、`platform/docs/developer/storefront/nextjs/deployment.mdx` 三处文档化（标注"留空禁用"）

## 4. 非功能需求（NFR）

- **性能**：`afterInteractive` 异步加载，不参与 SSR 首屏；脚本带 `async` 语义
- **安全**：Property/Widget ID 为公开标识（类似 Stripe publishable key），允许 `NEXT_PUBLIC_` 前缀；不涉及任何密钥
- **兼容**：支持 Next.js 16 / React 19 App Router；`next/script` 原生支持
- **可维护性**：组件独立文件 + 单元测试；环境变量集中文档化，便于多环境（dev/prod）配置
- **隐私**：默认不开启任何用户信息预填；如需预填访客信息（Tawk_API 钩子）留作未来扩展点

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：设置两个 env 后组件渲染 `next/script`，且 `src === https://embed.tawk.to/{propertyId}/{widgetId}`
- AC-002 ← FR-001/FR-004：两个 env 均未设置（或任一缺失）时，组件渲染 `null`（无 script 节点）
- AC-003 ← FR-002：根布局 `layout.tsx` 中已挂载 `<TawkToWidget />`，全站生效
- AC-004 ← FR-003：脚本 strategy 为 `afterInteractive`
- AC-005 ← FR-005：`.env.example`、`storefront/README.md`、`deployment.mdx` 三处均含两个新 env 变量的说明

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | tawk、客服、chat、support、customer.service | `application_controller.rb`（无关）；无客服工具实现 | ❌ 无 |
| Core | `pallastrade_gems/pallastrade_core/app/` | tawk、chat、support | 仅 `ActiveSupport::Concern` 等误报；`customer_support_email` 为邮件支持邮箱 | ❌ 无 |
| API | `pallastrade_gems/pallastrade_api/app/` | tawk、chat、support | 无客服工具相关端点 | ❌ 无 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | tawk、chat、support | `_set_customer_support_email.html.erb`、`customer_support_email` 字段、`PallasTrade.t(:support)` 菜单项（均为邮件支持配置，非在线客服） | ❌ 无 |
| Storefront | `storefront/src/` | tawk、客服、chat、support.widget、intercom、crisp、zendesk | `lib/seo.ts` 仅 `contactType: "customer service"`（schema.org 标记）；无任何第三方客服注入 | ❌ 无 |
| Platform | `platform/packages/` | tawk、chat、support | 仅 SDK 文档中 `supports` 字样误报 | ❌ 无 |

**结论**：全 6 层均无在线客服/聊天工具实现，唯一相关能力是 `customer_support_email`（邮件支持）。本需求为**全新前端集成**，在 storefront 层新建组件，不动后端。防重复判定：无重复实现，无重复 PRD。

## 7. 技术影响

- **新增文件**：
  - `storefront/src/components/layout/TawkToWidget.tsx`（客户端组件，`"use client"`）
  - `storefront/src/components/layout/__tests__/TawkToWidget.test.tsx`（Vitest + Testing Library）
- **修改文件**：
  - `storefront/src/app/layout.tsx`（挂载 `<TawkToWidget />`）
  - `storefront/.env.example`（新增 2 个 env 变量 + 注释）
  - `storefront/README.md`（env 表新增 2 行）
  - `platform/docs/developer/storefront/nextjs/deployment.mdx`（env 表新增 2 行）
  - `ai/skills/pallastrade-storefront/SKILL.md`（§Components 记录新组件）
- **依赖**：无新增依赖（`next/script` 为 Next.js 内置）
- **数据库 / 接口**：无变更（纯前端环境变量驱动，无 API 变更，无需更新 OpenAPI）
- **影响面**：仅 storefront 层；`harness affected` 预计仅波及 storefront 相关 workflow

## 8. 测试计划

- **新增测试**：`storefront/src/components/layout/__tests__/TawkToWidget.test.tsx`
  - 用例 1（AC-001）：mock env 双 ID → 渲染 `next/script` 且 src 正确
  - 用例 2（AC-002）：env 为空 → 渲染 `null`
  - 用例 3（AC-002）：仅一个 ID → 渲染 `null`
  - 用例 4（AC-004）：断言 strategy 为 `afterInteractive`
- **更新测试**：无（layout.tsx 仅新增一行挂载，现有测试不受影响）
- **AC 映射**：AC-001/002/004 → `TawkToWidget.test.tsx`；AC-003 → 代码审查（layout 挂载）；AC-005 → 文档审查
- **验证命令**：`pnpm --filter storefront test`（或 storefront 目录 `pnpm vitest run`）+ `pnpm --filter storefront build`（本地）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：**不涉及**（无接口变更）
- [x] Skill 文档：`ai/skills/pallastrade-storefront/SKILL.md`（§Components 新增 TawkToWidget）
- [x] README / 部署文档：`storefront/.env.example`、`storefront/README.md`、`platform/docs/developer/storefront/nextjs/deployment.mdx`
- [ ] 反模式库 / 任务规则 / 场景库：评估——`harness/scenarios/scenarios.json` 可加 GS 场景（tawk 挂件加载）
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-10 | 0.1 | 初稿（查重无命中，全新需求；6 层搜索完成） | AI |
| 2026-08-10 | 0.2 | 用户确认 → approved；用户提供 tawk.to ID | 用户 + AI |
| 2026-08-10 | 0.3 | 实施完成（GATE-2026-08-10T02-38-39 全清）；组件+测试+文档落地；单测 142 通过 + build 成功 + 浏览器实测挂件渲染 → done | AI |

> **tawk.to 配置（用户已提供 2026-08-10）**：
> - Property ID：`6a32b7a845840f1d49424bd9`（→ `NEXT_PUBLIC_TAWK_TO_PROPERTY_ID`）
> - Widget ID：`1jrb1qrcu`（→ `NEXT_PUBLIC_TAWK_TO_WIDGET_ID`）
> - 来源：用户提供的官方嵌入脚本 `https://embed.tawk.to/6a32b7a845840f1d49424bd9/1jrb1qrcu`
> - 实施时写入本地 `.env.local` 与服务器 `.env.storefront.dev` / `.env.storefront.prod`
