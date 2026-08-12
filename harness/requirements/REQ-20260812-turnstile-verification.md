# 需求文档：商城前台注册面板接入 Turnstile 真人验证

> 关联 PRD：`docs/prd/storefront/PRD-20260812-storefront-商城前台注册面板接入-turnstile-真人验证.md`（approved 2026-08-12）
> 任务：TASK-20260812001441-8002d8d8 ｜ Gate：GATE-2026-08-12T00-14-57

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models | `backend/app/` | register/signup | `app/models/pallastrade/user.rb`（devise registerable） | 无 turnstile/captcha；前台注册走 API 层，无需改 |
| App — controllers | `backend/app/` | register/signup | —（前台注册不在 App 层） | 无需改 |
| Core Gem — models | `pallastrade_core/app/models/` | turnstile/captcha | — | 无验证设施 |
| Core Gem — services | `pallastrade_core/app/services/` | turnstile/captcha/Net::HTTP | `search_provider/meilisearch.rb`（HTTP 生态） | 无 turnstile；backend 已有 Faraday/HTTParty |
| API Gem — controllers | `pallastrade_api/app/controllers/` | customers/registrations | `store/customers_controller.rb`（`create` + `permitted_params`） | **需改**：create 前加 turnstile 校验 |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | register | `admin/admin_users_controller.rb`（邀请注册） | 不在范围（仅商城前台） |
| Admin Gem — views | `pallastrade_admin/app/views/` | register | — | 不在范围 |
| Storefront | `storefront/src/` | register/tawk | `account/register/page.tsx`、`contexts/AuthContext.tsx`、`lib/data/customer.ts`、`layout/TawkToWidget.tsx`（脚本加载参考） | **需改**：Turnstile 挂件 + token 透传 |
| Platform | `platform/packages/` | customers/RegisterParams | `sdk/src/store-client.ts`（`customers.create`→POST /customers）、`sdk/src/types/index.ts`（`RegisterParams`） | **需改**：加 `turnstile_token` 字段 |

### 搜索结论

全仓库无现成 turnstile/captcha 设施（全新功能）。注册链路共 5 处改动点（register page → AuthContext → customer.ts → SDK → backend controller），无重复代码风险。tawk PRD（31% 相似）仅同属 storefront 第三方接入，功能不同，非重复。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树："Pull in a third-party gem/service" → 本项目 Git 跟踪 gem 可直接改；对外部服务验证属 controller 层行为，直接改 `store/customers_controller.rb`（gem 层，非 Host App 复制）。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD → 用户确认（approved）→ gate → REQ → 实施 → 测试 → 知识同步门；AC 必须与测试一一映射。 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | 不手写 fetch——统一用 `@pallastrade/sdk`；第三方脚本用 `next/script`（`afterInteractive` 不阻塞首屏，参考 TawkToWidget 模式）。 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | Store API `POST /customers` 属顾客注册端点；请求体用扁平 `params.permit(...)`（Strong Params 白名单），`turnstile_token` 作为可选字段无需持久化。 |
| `pallastrade-security` | ✅ | ✅ 已读 | Secrets 绝不进 repo——用环境变量/Rails credentials；泄漏需立即轮换。Turnstile secret key 只能放服务器 `.env.dev`/`.env.prod` 与本地 `.env`，site key 为公开值可进构建 env。 |
| `pallastrade-decorators` | ❌ | — | 不涉及（直接改 gem 源文件） |
| `pallastrade-dependencies` | ❌ | — | 不涉及 |
| `pallastrade-events-webhooks` | ❌ | — | 不涉及（无事件订阅） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 新功能必须有测试：SDK 单测 + storefront 组件/数据层测试 + backend rspec；UI 变更需浏览器证据。 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | 注册错误消息需 5 语言（en/de/es/fr/pl）同步 `messages/*.json`。 |

> ✅ 无"未读"必读项，需求文档有效。

---

## 需求标题

商城前台注册面板接入 Cloudflare Turnstile 真人验证：注册时验证访客为真人，拦截机器人批量注册。

## 任务类型

新功能（含接口变更：`POST /api/v3/store/customers` 请求体新增可选 `turnstile_token`）

## 需求描述

- 注册页（`/account/register`）在配置 site key 时渲染 Turnstile 挂件，用户通过验证后提交注册
- 注册请求携带 Turnstile token，后端用 secret key 调 Cloudflare siteverify 校验，失败则拒绝注册（422）
- 未配置密钥时优雅降级（本地开发可用）
- **secret key 只进环境变量，绝不入库**

## 影响范围（harness affected 输出）

实施时执行 `harness affected --base origin/main` 确认。预估影响：
- `storefront/src/components/auth/TurnstileWidget.tsx`（新）
- `storefront/src/app/[country]/[locale]/(storefront)/account/register/page.tsx`
- `storefront/src/contexts/AuthContext.tsx`
- `storefront/src/lib/data/customer.ts` + `__tests__/customer.test.ts`
- `storefront/messages/{en,de,es,fr,pl}.json`
- `platform/packages/sdk/src/types/index.ts`（RegisterParams）+ `src/store-client.ts` + `tests/customer.test.ts`
- `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/customers_controller.rb`
- `backend/pallastrade_gems/pallastrade_api/lib/pallastrade/turnstile.rb`（新 service）
- `backend/pallastrade_gems/pallastrade_api/spec/...`（controller + service spec）
- `backend/public/api-docs/store.yaml`（接口文档）

## 技术方案（初步）

1. **Storefront**：新 `TurnstileWidget` 客户端组件（`next/script` + `afterInteractive` 加载 `https://challenges.cloudflare.com/turnstile/api.js`，参考 TawkToWidget；site key 从 `NEXT_PUBLIC_TURNSTILE_SITE_KEY` 读取，未配置则 `null`）；注册页表单内渲染，提交前校验 token 存在
2. **SDK**：`RegisterParams` 加 `turnstile_token?: string`，`customers.create` 透传
3. **Backend**：新 `PallasTrade::Turnstile` service（`lib/`，用 Faraday/HTTParty 调 siteverify，超时 ≤5s，fail-closed）；`CustomersController#create` 开头校验——`TURNSTILE_SECRET_KEY` 未配置则跳过，配置则 siteverify 必须 success，否则 422
4. **配置**：`NEXT_PUBLIC_TURNSTILE_SITE_KEY`（storefront env）+ `TURNSTILE_SECRET_KEY`（backend env，服务器 `.env.dev`/`.env.prod`）
5. **i18n**：register 错误消息 5 语言

## 风险点

- **最高风险**：secret key 泄漏入库（AP 类违规）→ 全程只走环境变量，PRD/REQ/代码均不出现 secret 值
- **次风险**：siteverify 引入外部依赖，网络故障拖慢注册 → 超时保护 + fail-closed
- **回滚难度**：低（后端校验可经 env 移除；前端组件独立）

## 决策节点

> ⏸️ 用户已确认 PRD（"实施"），REQ 为 PRD 的提炼。请确认本 REQ 后继续实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| SDK | `platform/packages/sdk` | `pnpm test`（sdk tests） | | ⬜ |
| Storefront | `storefront/src` | `pnpm vitest run` + `pnpm typecheck` | | ⬜ |
| Backend | `pallastrade_api` | rspec（customers + turnstile spec） | | ⬜ |
| API 文档 | `backend/public/api-docs/store.yaml` | `harness generated:check` | | ⬜ |
| 全量 | 所有改动 | `harness check --profile quick` | | ⬜ |
| 浏览器 | 注册页 | 浏览器实测：site key 配置时挂件渲染 | | ⬜ |

### 验证结论

（实施后回填）
