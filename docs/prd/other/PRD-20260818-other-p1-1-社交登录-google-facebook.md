# PRD-20260818-other-p1-1-社交登录-google-facebook

| 元数据 | 值 |
|---|---|
| 状态 | verifying |
| 创建日期 | 2026-08-18 |
| 来源 | 实施 C1[P1-1 社交登录+钱包]实施社交登录，可以先实现 Google、Facebook（RESEARCH-20260814 路线图 P1-1） |
| 分类 | other（自动判定 0 命中；语义上属安全/认证域，因不新增认证关键词故归 other） |
| 关联 Skill | pallastrade-security、pallastrade-api-v3、pallastrade-storefront、pallastrade-typescript-sdk、pallastrade-data-model |
| 关联 REQ | REQ-20260818-p1-1-social-login.md |
| 关联 PRD | N/A（全新需求；查重未命中现有 PRD） |
| 需求类型 | 新功能 |

> **范围声明**：本 PRD 仅实施 **社交登录（Google + Facebook）**。**钱包支付（Apple Pay / Google Pay）为 P1-1 的另一半，本期不实施**，后续单独立项。
>
> **凭证准备教程**：见 `docs/guides/social-login-credentials-setup.md`（用户已确认自行申请）。未配置凭证时前端按钮自动隐藏、后端优雅返回错误，不影响实施与测试。

---

## 1. 背景与目标

- **一句话需求原文**：实施 C1[P1-1 社交登录+钱包]实施社交登录，可以先实现 Google、Facebook
- **背景**：
  - 对标 Shopify 路线图（`docs/research/RESEARCH-20260814-...md`）P1-1「社交登录+快速结账」：Shopify 支持 Apple/Google Sign-in 降低注册门槛、提升转化。
  - 现状：仅邮箱+密码注册/登录。独立站海外场景下，社交登录可显著降低注册摩擦、提高 CVR。
  - 架构现状（跨层搜索结论）：**后端认证框架已为 OAuth 预留完整插槽**——`UserIdentity` 模型（含 `find_or_create_from_oauth`）、`StrategyRegistry` + `BaseStrategy`、Store/Admin `AuthController` 已支持 `provider` 参数分发；SDK 已定义 `ProviderLogin` 类型。**缺的是：具体 provider 策略实现（token 验证）、前端登录/注册页社交按钮、配置、测试与文档**。
- **目标**：客户可用 Google 或 Facebook 账号一键登录/注册，自动创建本地账户并关联身份，获得与邮箱登录一致的 JWT 会话。
- **成功指标**：登录页可见 Google/Facebook 按钮；任一 provider 登录后返回标准 `AuthResponse`；同一邮箱已存在账户时正确绑定而非重复创建。

## 2. 用户故事 / 场景

- 作为 **新客户**，我希望用 Google/Facebook 一键注册，以便省去填表步骤。
- 作为 **老客户**（已用邮箱注册），我希望用同一邮箱的 Google 账号登录，以便不再记密码。
- 作为 **再次访问的客户**，我希望用社交账号直接登录，以便快速进入账户。

**场景列表**：
1. 正常流：新用户点「Continue with Google」→ 弹 Google 授权 → 后端验证 token → 创建 User + UserIdentity → 返回 JWT → 进入账户页。
2. 正常流：老用户（邮箱已存在）用 Google 登录 → 后端按 email 绑定到现有 User（不重复创建）→ 登录成功。
3. 正常流：已绑定身份的 Google 用户再次登录 → 命中 UserIdentity → 更新 tokens → 返回现有 User。
4. 边界：Google 授权取消/失败 → 前端捕获并展示错误，不崩溃。
5. 边界：provider 未配置（无 GOOGLE_CLIENT_ID）→ 前端不渲染 Google 按钮；后端返回 `invalid_provider`。
6. 异常：Google ID token 无效/过期/audience 不匹配 → 后端 `authentication_failed`，前端提示。
7. 异常：Facebook access_token 验证失败 → 同上。
8. 安全：登录端点保持限流（已有 rate_limit）；社交登录仍受 IP 限流保护。

## 3. 功能需求（FR）

- **FR-001**：后端新增 `PallasTrade::Authentication::Strategies::GoogleStrategy`，接收 `{ provider: 'google', id_token: '<google-id-token>' }`，验证 Google ID token（audience 校验 + 签名/过期），提取 email/name，调用 `PallasTrade::UserIdentity.find_or_create_from_oauth` 返回用户。
- **FR-002**：后端新增 `PallasTrade::Authentication::Strategies::FacebookStrategy`，接收 `{ provider: 'facebook', access_token: '<fb-user-token>' }`，通过 Facebook Graph API 验证 token 并获取 profile（id/name/email），调用 `find_or_create_from_oauth` 返回用户。
- **FR-003**：将 `google`、`facebook` 策略注册到 `PallasTrade.store_authentication_strategies`（Store 端；Admin 端本期不开放社交登录）。
- **FR-004**：后端配置项 `PallasTrade::Api::Config[:google_client_id]`、`[:facebook_app_id]`、`[:facebook_app_secret]`（读 ENV `GOOGLE_CLIENT_ID` / `FACEBOOK_APP_ID` / `FACEBOOK_APP_SECRET`）；未配置时策略优雅返回 `invalid_provider`/明确错误。
- **FR-005**：SDK `auth.login` 已支持 `ProviderLogin`（`{ provider, ... }`），无需改 SDK 类型；确认 `store-client.ts` 透传 body 即可（如有缺失补全）。
- **FR-006**：Storefront 登录页（`account/page.tsx`）新增「Continue with Google」「Continue with Facebook」按钮；点击加载对应 provider SDK（Google Identity Services / Facebook JS SDK），获取凭据后调用新 `loginWithProvider` 流程。
- **FR-007**：Storefront `customer.ts` 新增 `loginWithProvider(provider, credentials)`，调用 `auth.login({ provider, ... })` 并复用 `finalizeAuth` 完成会话建立。
- **FR-008**：`AuthContext` 新增 `loginWithProvider`，登录成功跳转逻辑与邮箱登录一致（支持 `redirect` 参数）。
- **FR-009**：注册页（`account/register/page.tsx`）同样展示社交登录按钮（与登录页一致，注册页社交登录即一键注册）。
- **FR-010**：i18n 新增社交登录文案（5 语言：en/de/es/fr/pl）。
- **FR-011**：`.env.example`（backend + storefront）补充 OAuth 配置项说明。

## 4. 非功能需求（NFR）

- **安全**：token 验证必须校验签名/过期/audience（Google）；Facebook 必须用 App token 调 `debug_token` 校验 + 校验 app_id 归属。**禁止信任前端原始 token 不验证**。
- **安全**：社交登录仍走 `auth/login` 端点的现有 rate_limit（防爆破）。
- **安全**：OAuth 创建的用户使用随机密码（现有 `SecureRandom.hex(32)` 逻辑），不可用社交密码登录。
- **兼容**：未配置 provider 时前端隐藏按钮、后端返回明确错误，不破坏现有邮箱登录。
- **隐私**：仅保存 OAuth 返回的最小信息（email/name/avatar），不保存原始 token 于前端。
- **可维护性**：策略实现遵循 `BaseStrategy` 接口（`authenticate` + `provider`），复用 `find_or_create_user_from_oauth`。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：`GoogleStrategy#authenticate` 在 id_token 有效时返回 success + 用户；无效/过期/audience 不匹配时返回 failure。→ `backend/spec/models/pallastrade/authentication/strategies/google_strategy_spec.rb`
- **AC-002** ← FR-002：`FacebookStrategy#authenticate` 在 access_token 有效时返回 success + 用户；无效时 failure。→ `backend/spec/models/pallastrade/authentication/strategies/facebook_strategy_spec.rb`
- **AC-003** ← FR-003：`PallasTrade.store_authentication_strategies` 含 `:google` 与 `:facebook`；`admin_authentication_strategies` 不含。→ `backend/spec/.../engine_spec.rb` 或 core_spec
- **AC-004** ← FR-004：未配置 `GOOGLE_CLIENT_ID` 时 Google 策略返回明确错误而非 500。→ 同上策略 spec
- **AC-005** ← FR-006/007/008：登录页渲染 Google/Facebook 按钮；`loginWithProvider` 成功后 `finalizeAuth` 建立会话并跳转。→ `storefront/src/lib/data/__tests__/customer.test.ts`（新增 loginWithProvider 用例）+ 组件渲染测试
- **AC-006** ← FR-009：注册页渲染社交登录按钮。→ 组件测试
- **AC-007** ← FR-010：5 语言 `check:locales` 通过（新增 key 全语言一致）。→ `pnpm check:locales`
- **AC-008** ← FR-011：`.env.example` 含 OAuth 配置说明。→ 人工检查

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | omniauth / social / oauth / 社交登录 | 无 | 否，需新建（策略放 Core） |
| Core | `pallastrade_gems/pallastrade_core/app/` | UserIdentity / find_or_create_from_oauth / StrategyRegistry / BaseStrategy | `models/pallastrade/user_identity.rb`（含 OAuth 创建逻辑）、`models/pallastrade/authentication/strategy_registry.rb`、`strategies/base_strategy.rb`、`strategies/email_password_strategy.rb` | **部分满足**：框架就绪，缺 google/facebook 策略类 |
| API | `pallastrade_gems/pallastrade_api/app/` | AuthController / provider / authenticate | `controllers/.../store/auth_controller.rb`、`.../admin/auth_controller.rb`（均支持 provider 分发） | **满足**：无需改控制器 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 社交登录 / social | 无 | 本期不做 Admin 社交登录（N/A） |
| Storefront | `storefront/src/` | auth/login / login / register / AuthContext | `src/lib/data/customer.ts`（login/register）、`src/contexts/AuthContext.tsx`、`src/app/[country]/[locale]/(storefront)/account/page.tsx`、`account/register/page.tsx` | **部分满足**：需新增 loginWithProvider + 社交按钮 |
| Platform | `platform/packages/` | ProviderLogin / LoginCredentials / auth.login | `sdk-core/src/types.ts`（ProviderLogin 已定义）、`sdk/src/store-client.ts`（auth.login 已支持 provider 透传） | **满足**：SDK 无需改动 |

**结论**：后端认证框架（UserIdentity + 策略注册 + provider 分发 + SDK 类型）**均已存在且就绪**，这是重要发现——**本需求不是从零搭建社交登录，而是补齐 provider 策略实现 + 前端入口**。策略类按现有 `BaseStrategy` 接口新增（放 Core gem），遵循「不新建重复能力」原则。技术选型采用 **token 验证**（前端经 provider JS SDK 获取凭据 → 调 `auth/login`），**不引入 OmniAuth 重定向流**——与现有 headless API + provider 分发架构契合（无需重定向路由/会话/CSRF，改动面最小）。此点与研究文档建议的 OmniAuth 有偏差，理由记录于此。

## 7. 技术影响

**涉及文件（预估）**：
- 新增：`backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/authentication/strategies/google_strategy.rb`、`facebook_strategy.rb`
- 新增：`backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/authentication/strategies/oauth_token_validator.rb`（可选：封装 Google/FB token 验证 HTTP 调用，便于测试注入）
- 修改：`backend/pallastrade_gems/pallastrade_core/lib/pallastrade/core/engine.rb`（注册 google/facebook 策略）
- 修改：`backend/pallastrade_gems/pallastrade_core/lib/pallastrade/api/config.rb`（新增配置项）或等价配置读取
- 新增测试：`backend/spec/models/pallastrade/authentication/strategies/{google,facebook}_strategy_spec.rb`
- 修改：`storefront/src/lib/data/customer.ts`（loginWithProvider）、`storefront/src/contexts/AuthContext.tsx`
- 新增：`storefront/src/components/auth/SocialLoginButtons.tsx`（Google+FB 按钮，GIS/FB SDK）
- 修改：`storefront/src/app/[country]/[locale]/(storefront)/account/page.tsx`、`account/register/page.tsx`（挂载社交按钮）
- 修改：`storefront/messages/{en,de,es,fr,pl}.json`
- 修改：`backend/.env.example`、`storefront/.env.example`
- 修改：`backend/public/api-docs/store.yaml`（补充 google/facebook provider 说明）
- SDK 生成类型/文档：`platform/docs/api-reference/`（如 store.yaml 变更）

**依赖**：
- 后端 token 验证：Google ID token 用 `https://oauth2.googleapis.com/tokeninfo?id_token=...`（Net::HTTP，无需新 gem）；Facebook 用 Graph API `debug_token` + `me`（同样 Net::HTTP）。**不新增 gem**（避免网络/构建负担，符合海外网络降级经验）。
- Storefront：Google Identity Services（`accounts.google.com/gsi/client` script 动态加载）、Facebook JS SDK（`connect.facebook.net` 动态加载）——均为运行时 script 加载，不新增 npm 依赖。

**影响面**：`harness affected --base origin/main`（实施时运行确认）。预计影响 storefront account 相关 + core auth 策略 + SDK 文档。

## 8. 测试计划

**新增测试文件**：
- `backend/spec/models/pallastrade/authentication/strategies/google_strategy_spec.rb` → AC-001、AC-004
- `backend/spec/models/pallastrade/authentication/strategies/facebook_strategy_spec.rb` → AC-002
- `backend/spec/models/pallastrade/authentication/strategies/strategy_registration_spec.rb` → AC-003（或并入现有 engine spec）
- `storefront/src/components/auth/__tests__/SocialLoginButtons.test.tsx` → AC-005、AC-006（渲染测试：按钮可见/隐藏逻辑、点击触发 SDK 加载）
- `storefront/src/lib/data/__tests__/customer.test.ts`（新增 loginWithProvider 用例）→ AC-005

**更新测试文件**：
- `storefront/src/contexts/__tests__/AuthContext.test.tsx`（新增 loginWithProvider mock 覆盖）→ AC-005
- `backend/public/api-docs/store.yaml` 校验（`generated:check`）→ AC（文档同步）

**AC 映射**：AC-001~AC-008 → 上表对应文件。测试头部标注 `# PRD-20260818-other-p1-1 AC-xxx`。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/store.yaml`（补充 google/facebook provider 字段说明）+ `platform/docs/api-reference/store.yaml`；验证 `npx harness generated:check`
- [ ] Skill 文档：`ai/skills/pallastrade-security/SKILL.md`（社交登录/安全）、`pallastrade-api-v3/SKILL.md`（auth provider 说明）、`pallastrade-storefront/SKILL.md`（登录/注册组件）、`pallastrade-typescript-sdk/SKILL.md`（ProviderLogin 用法）
- [ ] README / Agent 文件：`backend/CLAUDE.md`（如需）、`storefront/CLAUDE.md`（如需）
- [ ] 反模式库 / 任务规则 / 场景库：如新增「OAuth token 必须验证」类反模式 → `harness/policies/anti-patterns.json` + AGENTS.md §5 + copilot-instructions
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-18 | 0.1 | 初稿（范围：社交登录 Google+Facebook，不含钱包） | AI |
| 2026-08-18 | 0.2 | 用户确认范围（钱包另立 PRD）；状态 → approved；提供凭证教程 | AI |
| 2026-08-18 | 0.3 | 实施完成：后端策略+验证器+注册、前端组件+流程+i18n、测试 61 个全过、API 实测通过；状态 → verifying | AI |

## 5. 验收标准（AC，与测试一一映射）

> ⚠️ 以下为示例，正式内容请删除注释标记并替换为真实 AC：
- <!-- AC-001 ← FR-001：<可验证的判定条件> -->
- <!-- AC-002 ← ... -->

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | | | |
| Core | `pallastrade_gems/pallastrade_core/app/` | | | |
| API | `pallastrade_gems/pallastrade_api/app/` | | | |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | | | |
| Storefront | `storefront/src/` | | | |
| Platform | `platform/packages/` | | | |

**结论**：哪些层已有能力 / 哪些需新建 / 防重复判定

## 7. 技术影响

- 涉及组件 / 文件 / 依赖 / 数据库 / 接口
- 影响面（`harness affected --base origin/main` 输出）

## 8. 测试计划

- 新增测试文件（路径清单）
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射（AC-xxx → 测试文件）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |
