# PRD-20260812-storefront-商城前台注册面板接入-turnstile-真人验证

| 元数据 | 值 |
|---|---|
| 状态 | approved（用户已确认 2026-08-12） |
| 创建日期 | 2026-08-12 |
| 来源 | 商城前台注册面板接入 Turnstile 真人验证（site key + secret key 已提供） |
| 分类 | storefront |
| 关联 Skill | pallastrade-storefront / pallastrade-security / pallastrade-api-v3 / pallastrade-deployment |
| 关联 REQ | 实施时回填 |
| 关联 PRD | N/A（全新需求，与 tawk PRD 仅同属 storefront 第三方接入，功能不同） |
| 需求类型 | 新功能（含接口变更） |

---

## 1. 背景与目标

- **一句话需求原文**：商城前台注册面板接入 Turnstile，用户注册时要进行真人验证（site key / secret key 已提供）
- **背景**：`POST /api/v3/store/customers` 注册端点目前无任何真人验证，存在机器人批量注册、撞库、垃圾账号风险。接入 Cloudflare Turnstile（免费、无感、隐私友好）在注册时做人机验证。
- **目标**：
  1. 注册表单渲染 Turnstile 挂件，提交时携带 token
  2. 后端用 secret key 调 siteverify 校验，失败则拒绝注册
  3. 未配置密钥时优雅降级（本地开发不阻塞）
- **成功指标**：
  - 配置环境（dev/prod）下注册请求 100% 经过 Turnstile 校验
  - siteverify 失败/无效 token → 注册被拒（返回明确错误）
  - 未配置 secret key 的环境（本地）注册流程不阻塞

## 2. 用户故事 / 场景

- 作为访客，我在注册账号时看到 Turnstile 验证，通过后才能提交注册
- 作为机器人，我无法绕过 Turnstile 批量创建账号
- 作为开发者，本地未配置密钥时注册流程不被阻塞
- **正常流**：填写表单 → Turnstile 通过（生成 token）→ 提交 → 后端 siteverify 通过 → 注册成功
- **边界**：site key 未配置 → 挂件不渲染、不加载脚本，注册仍可走（后端无 secret 也跳过）
- **异常**：token 缺失 / 过期 / 伪造 → 后端 siteverify 失败 → 422 拒绝，不创建用户
- **异常**：Cloudflare 服务不可达 → 保守失败（fail-closed，安全优先）

## 3. 功能需求（FR）

- FR-001：注册页在 site key 配置时渲染 Turnstile 挂件（异步加载 `https://challenges.cloudflare.com/turnstile/api.js`，`afterInteractive` 不阻塞首屏）
- FR-002：未配置 site key 时不渲染挂件、不加载第三方脚本（优雅降级，参考 `TawkToWidget` 模式）
- FR-003：注册提交时携带 Turnstile token（`cf-turnstile-response`），token 缺失时前端提示
- FR-004：SDK `RegisterParams` 增加可选 `turnstile_token` 字段，`customers.create` 透传到 `POST /customers`
- FR-005：backend `CustomersController#create` 校验 turnstile token——用 `TURNSTILE_SECRET_KEY` 调 `POST https://challenges.cloudflare.com/turnstile/v0/siteverify`（表单：secret/response/remoteip），失败 → 422 + 明确错误码
- FR-006：未配置 `TURNSTILE_SECRET_KEY` 时后端跳过校验（本地开发可用），配置了则强制
- FR-007：Turnstile 校验逻辑抽成独立 service（lib 层，可单测）；siteverify 请求带超时（≤5s）
- FR-008：**secret key 绝不进入代码库/提交**（仅服务器 `.env.dev`/`.env.prod` 与本地 `.env`）；site key 为公开值，走 `NEXT_PUBLIC_TURNSTILE_SITE_KEY` 构建环境变量

## 4. 非功能需求（NFR）

- **安全**：secret 仅服务端持有；siteverify 走 HTTPS；token 过期（约 300s）由 Cloudflare 处理；错误响应不泄露内部信息
- **性能**：脚本异步加载不阻塞首屏；siteverify 超时保护（≤5s）避免拖慢注册
- **兼容**：无 JS 环境挂件不渲染；与现有注册 i18n（5 语言）一致
- **可维护**：校验逻辑单点（service）+ 配置集中在 env + 文档同步
- **隐私**：Turnstile 符合 GDPR/CCPA（Cloudflare 隐私承诺），无需额外用户同意

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001/002：site key 配置时注册页渲染 Turnstile 挂件；未配置时不渲染且不加载脚本（组件测试）
- AC-002 ← FR-003/004：提交注册时请求体包含 `turnstile_token`（SDK + storefront 数据层测试）
- AC-003 ← FR-005：后端收到有效 token（siteverify success）→ 正常创建用户（controller spec）
- AC-004 ← FR-005：后端收到无效/伪造 token（siteverify failed）→ 422 拒绝且不创建用户（controller spec）
- AC-005 ← FR-006：未配置 `TURNSTILE_SECRET_KEY` → 后端跳过校验，注册正常（controller spec）
- AC-006 ← FR-003/007：验证失败错误消息经 i18n 展示（注册页 + `messages/*.json`）
- AC-007 ← FR-008：grep 确认 secret key 未出现在源码/提交历史；site key 仅出现在构建 env 配置（非敏感）

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | register/signup | `app/models/pallastrade/user.rb`（devise registerable） | 无 turnstile/captcha；前台注册走 API 层，无需改 App |
| Core | `pallastrade_gems/pallastrade_core/app/` | turnstile/captcha/Net::HTTP | `search_provider/meilisearch.rb` 等 | 无验证设施；backend 已有 Faraday 2.14/HTTParty 0.24 可复用，无需新依赖 |
| API | `pallastrade_gems/pallastrade_api/app/` | customers/registrations | `store/customers_controller.rb`（`create` + `permitted_params` 无 turnstile 字段） | **需改**：create 前加 turnstile 校验 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | register | `admin/admin_users_controller.rb`（邀请注册） | 不在需求范围（仅商城前台） |
| Storefront | `storefront/src/` | register/tawk | `account/register/page.tsx`、`contexts/AuthContext.tsx`、`lib/data/customer.ts`、`layout/TawkToWidget.tsx`（脚本加载参考） | **需改**：加 Turnstile 挂件 + token 透传 |
| Platform | `platform/packages/` | customers/RegisterParams | `sdk/src/store-client.ts`（`customers.create`→POST /customers）、`sdk/src/types/index.ts`（`RegisterParams`） | **需改**：加 `turnstile_token` 字段 |

**结论**：全仓库无现成 turnstile/captcha 设施（全新功能）。注册链路共 5 处改动点（register page → AuthContext → customer.ts → SDK → backend controller），无重复代码风险。tawk PRD（31% 相似）仅同属 storefront 第三方接入，功能不同，非重复。

## 7. 技术影响

- **Storefront**：新 `components/auth/TurnstileWidget.tsx`（客户端组件，参考 TawkToWidget 封装 `next/script`）；改 `account/register/page.tsx`、`contexts/AuthContext.tsx`、`lib/data/customer.ts`、`messages/{en,de,es,fr,pl}.json`；`.env`/部署 `.env.storefront.*` 加 `NEXT_PUBLIC_TURNSTILE_SITE_KEY`
- **Platform SDK**：`src/types/index.ts`（`RegisterParams`）+ `src/store-client.ts`（透传）
- **Backend**：`store/customers_controller.rb`（create 校验）+ 新 `PallasTrade::Turnstile` service（lib 层）；`.env`/服务器 `.env.dev`/`.env.prod` 加 `TURNSTILE_SECRET_KEY`；无 Gemfile 变更
- **接口变更**：`POST /api/v3/store/customers` 请求体新增可选字段 `turnstile_token`（向后兼容，缺省按未配置/降级处理）
- **DB**：无变更
- **影响面**：`harness affected --base origin/main`（实施时执行）

## 8. 测试计划

- **新增**：
  - `storefront/src/components/auth/__tests__/TurnstileWidget.test.tsx`（AC-001：渲染/条件渲染/不加载脚本）
  - `backend/spec/lib/pallastrade/turnstile_spec.rb`（AC-003/004：service siteverify 成功/失败/超时）
- **更新**：
  - `storefront/src/lib/data/__tests__/customer.test.ts`（AC-002：register 透传 turnstile_token）
  - `platform/packages/sdk/tests/customer.test.ts`（AC-002：customers.create 请求体含 turnstile_token）
  - `backend/spec/.../store/customers_spec.rb`（AC-003/004/005：controller 校验三分支）
- **AC 映射**：AC-001→TurnstileWidget.test；AC-002→SDK+storefront 测试；AC-003/004/005→backend spec；AC-006→i18n/页面测试；AC-007→grep 检查

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/store.yaml`（customers create 加 `turnstile_token`）+ `platform/docs/api-reference/*.yaml`
- [ ] Skill：`pallastrade-storefront`（§Components）、`pallastrade-api-v3`、`pallastrade-security`、`pallastrade-deployment`（env 密钥配置说明）
- [ ] 部署文档：`deploy/README.md` 或 `.env.example`（`NEXT_PUBLIC_TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY` 配置说明，**secret 仅环境变量不入库**）
- [ ] `docs/prd/README.md` 索引 + 本 PRD 状态更新
- [ ] 反模式 / 场景库：安全类可补一条验证场景（如涉及）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-12 | 0.1 | 初稿：跨层搜索 + 方案设计 + 安全约束 | AI |
| 2026-08-12 | 0.2 | 用户确认实施（approved） | 用户 |
