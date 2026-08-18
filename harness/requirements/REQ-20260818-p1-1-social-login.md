# 需求文档：P1-1 社交登录（Google + Facebook）

> 关联 PRD：`docs/prd/other/PRD-20260818-other-p1-1-社交登录-google-facebook.md`（approved）
> 任务：`TASK-20260818145901-b170cf13`，Gate：`GATE-2026-08-18T14-59-18`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | omniauth / social / oauth / 社交登录 | 无 | 否，需新建（策略放 Core） |
| App — views/decorators | `backend/app/` | 社交登录 / social login | 无 | 否 |
| Core Gem — models | `pallastrade_core/app/models/` | UserIdentity / find_or_create_from_oauth / StrategyRegistry | `models/pallastrade/user_identity.rb`（含 OAuth 创建逻辑）、`authentication/strategy_registry.rb`、`authentication/strategies/base_strategy.rb`、`email_password_strategy.rb` | **部分满足**：框架就绪，缺 google/facebook 策略类 |
| Core Gem — services | `pallastrade_core/app/services/` | oauth / token 验证 | 无 | 需新建 token 验证逻辑（可放 strategies/ 或独立类） |
| API Gem — controllers | `pallastrade_api/app/controllers/` | AuthController / provider / authenticate | `.../v3/store/auth_controller.rb`、`.../v3/admin/auth_controller.rb`（均支持 provider 分发） | **满足**：无需改控制器 |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/` | 社交登录 / social | 无 | 本期不做 Admin 社交登录（N/A） |
| Admin Gem — views | `pallastrade_admin/app/views/` | 社交登录 | 无 | N/A |
| Storefront | `storefront/src/` | auth/login / login / register / AuthContext | `src/lib/data/customer.ts`（login/register）、`src/contexts/AuthContext.tsx`、`app/[country]/[locale]/(storefront)/account/page.tsx`、`account/register/page.tsx` | **部分满足**：需新增 loginWithProvider + 社交按钮组件 |
| Platform | `platform/packages/` | ProviderLogin / LoginCredentials / auth.login | `sdk-core/src/types.ts`（ProviderLogin 已定义）、`sdk/src/store-client.ts`（auth.login 已支持 provider 透传） | **满足**：SDK 无需改动 |

### 搜索结论

后端认证框架（`UserIdentity` + `StrategyRegistry` + `BaseStrategy` + provider 分发 + SDK `ProviderLogin` 类型）**均已存在且就绪**。本需求**不是从零搭建社交登录**，而是：
1. Core 新增 `GoogleStrategy` / `FacebookStrategy`（token 验证 + 复用 `find_or_create_from_oauth`）
2. Core 注册两策略进 store 策略注册表（engine.rb）
3. Storefront 新增社交登录按钮组件 + `loginWithProvider` 流程 + i18n
4. 配置（.env.example）+ 文档同步

技术选型：**token 验证**方案（前端经 provider JS SDK 获取凭据 → 调 `auth/login`），**不引入 OmniAuth 重定向流**——与现有 headless API + provider 分发架构契合。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树：认证类扩展 →「Pull in a third-party gem (Stripe, Adyen, search, i18n, **social login**) → `pallastrade-extensions`」；但本项目已有原生策略插槽（StrategyRegistry + UserIdentity），无需第三方 gem，直接按 `BaseStrategy` 接口新增策略类即可（等价于比装饰器更安全的"配置/策略"层级）。 |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | Secrets 不进仓库：OAuth Client Secret（Facebook App Secret）只放后端 env，**绝不进 NEXT_PUBLIC_ 或前端**；第三方 token 必须服务端验证（类比 webhook HMAC 验签思路），禁止信任前端原始 token。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 一句话需求 → PRD → 用户确认 → gate → 实施 → 测试/验收 → API 文档同步 → 知识同步门。新功能需用户明确确认后才能清除 user-confirmed。 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | Store API 认证：publishable key (`pk_`) + 登录客户 JWT；`auth/login` 端点限流 `rate_limit_login` = 5/60s per IP（社交登录同样受此保护）；OpenAPI 权威在 `node_modules/@pallastrade/docs/dist/api-reference/store.yaml`。 |
| `pallastrade-decorators` | ⬜ | ⬜ | 不涉及 |
| `pallastrade-dependencies` | ⬜ | ⬜ | 不涉及 |
| `pallastrade-events-webhooks` | ⬜ | ⬜ | 不涉及（社交登录不触发业务事件，仅创建用户） |
| `pallastrade-storefront` | ✅ | ✅ 已读 | 客户登录流：`pallastrade.auth.login({...})` → `{ token, refresh_token, user }`；**client 组件禁止从 `@/lib/pallastrade` barrel 导入**（server-only），需从 `@/lib/pallastrade/config` 取 getClient 或经 `src/lib/data/` 的 "use server" action；可选组件模式参考 `TurnstileWidget`（env 缺失时渲染 null，`next/script` afterInteractive 加载）；i18n 用 next-intl 5 语言。 |
| `pallastrade-testing` | ⬜ | ⬜ | 未单独读；测试模式沿用项目既有 RSpec/Vitest 约定 |
| `pallastrade-i18n` | ⬜ | ✅ 间接 | storefront Skill 确认 5 locale 文件（en/de/es/fr/pl），新增 key 需全语言一致，`pnpm check:locales` 校验 |

> ✅ 无"未读"项残留，需求文档有效，可进入编码阶段。

---

## 需求标题

新增客户社交登录：支持 Google、Facebook 一键登录/注册（P1-1 前半，钱包另立 PRD）

## 任务类型

新功能

## 需求描述

独立站客户目前只能邮箱+密码注册/登录。本需求让客户可以用 Google 或 Facebook 账号一键登录：点击社交按钮 → provider 授权 → 后端验证 token → 自动创建/绑定本地账户 → 获得与邮箱登录一致的 JWT 会话。同一邮箱已有账户时绑定而非重复创建。未配置凭证时按钮隐藏、后端优雅报错，不影响现有邮箱登录。

## 影响范围（harness affected 输出）

实施时运行确认。预计影响：core auth 策略、storefront account 登录/注册页、SDK 文档、store.yaml。

## 技术方案（初步）

按 customization 决策树：认证扩展走**框架原生策略插槽**（无需第三方 gem）：
1. **Core 新增** `authentication/strategies/google_strategy.rb` + `facebook_strategy.rb`（继承 `BaseStrategy`，实现 `authenticate` + `provider`）
   - Google：接收 `id_token`，调 `https://oauth2.googleapis.com/tokeninfo?id_token=...` 验证（校验 aud == GOOGLE_CLIENT_ID），提取 email/name → `find_or_create_user_from_oauth`
   - Facebook：接收 `access_token`，用 App token（FACEBOOK_APP_ID + FACEBOOK_APP_SECRET 生成）调 `debug_token` 验证 + 校验 `data.app_id`，再调 `me?fields=id,name,email` → `find_or_create_user_from_oauth`
   - 未配置对应 client_id/app_id 时返回明确 failure（不 500）
   - token 验证 HTTP 调用封装为可注入验证器（便于测试 stub）
2. **engine.rb**：`store_authentication_strategies` 注册 `google` + `facebook`（admin 不注册）
3. **配置**：Core 读取 ENV `GOOGLE_CLIENT_ID` / `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET`（经 `PallasTrade::Api::Config` 或 ENV 直接读）
4. **Storefront**：新增 `components/auth/SocialLoginButtons.tsx`（client 组件，参考 TurnstileWidget 模式：env 缺失隐藏、动态加载 provider SDK）；`customer.ts` 新增 `loginWithProvider`；`AuthContext` 暴露 `loginWithProvider`；登录/注册页挂载；i18n 5 语言
5. **SDK**：无需改动（`ProviderLogin` 已支持），确认 `store-client.ts` 透传即可
6. **文档**：store.yaml 补充 provider 说明、.env.example、Skills 同步

**不新增 gem / 不新增 npm 依赖**（Net::HTTP + 动态加载 provider script）。

## 风险点

- **token 验证安全性**（最高）：必须服务端验证签名/audience，禁止信任前端原始 token。Google 用官方 tokeninfo；Facebook 用 debug_token + app_id 校验。
- **凭证缺失时优雅降级**：未配置 → 按钮隐藏 + 后端明确错误（不 500、不破坏邮箱登录）。
- **回滚难度**：低——无 schema 变更（复用 UserIdentity 表），改动为新增策略类 + 前端组件，回滚即删除。

## 决策节点

> ✅ **已确认**：用户明确确认范围（钱包支付后续单独立项），PRD 已 approved，可进入 gate 实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Ruby 策略 | `google_strategy.rb` / `facebook_strategy.rb` + spec | `harness check --profile quick` + 策略 spec | | ⬜ |
| Storefront 组件/流程 | `SocialLoginButtons.tsx` / `customer.ts` / `AuthContext` + 测试 | `pnpm test`（相关）+ `pnpm check` | | ⬜ |
| 配置 | `.env.example` ×2 | 人工检查 + `harness check` | | ⬜ |
| API 文档 | `store.yaml` | `npx harness generated:check` | | ⬜ |
| UI | 登录/注册页 | 浏览器验证（按钮渲染/隐藏逻辑） | | ⬜ |
