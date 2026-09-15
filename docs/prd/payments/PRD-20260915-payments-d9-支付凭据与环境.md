# PRD-20260915-payments-d9-支付凭据与环境

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-15 |
| 来源 | 需求：D9 支付凭据与环境（Test/Live 双环境切换 + 凭据保管/脱敏审计 + 轮换过期提醒 + Webhook 签名密钥） |
| 分类 | payments（自动判定，关键词命中 1） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-api-v3`、`pallastrade-security`、`pallastrade-data-model`、`pallastrade-testing` |
| 关联 REQ | `harness/requirements/REQ-20260915-d9-credentials.md` |
| 关联 PRD | `PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口`（D1：入口模型 + Test connection + 页面/API 脱敏）；设计依据：业务方案 §68.1–§68.7、§74（落地形态）、§78-D9 |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D9 支付凭据与环境 —— Test/Live 双环境切换 + 凭据保管/脱敏审计 + 轮换过期提醒 + Webhook 签名密钥。
- **背景（代码事实）**：
  - D1（切片1–3）已落地入口模型、后台「支付方式」页签、`PaymentMethods::TestConnection`（本地凭证体检 + provider 可选远端探测；报告写 `metadata['last_test_connection']` + `AuditLog`）与**页面/API 脱敏**（`PallasTrade::Preferences::Masking`：`••••` + 后 4 位）。
  - `PaymentMethod#preferences` 走 Active Record Encryption（`rake encrypt_preferences/verify`）；`public_preferences` / `serialized_preferences` 已区分对外投影；Stripe gem 已有 webhook 签名密钥表（`pallastrade_stripe_webhook_keys`）但**后台无管理界面**。
  - 缺失（grep 事实）：无 `environment`（test/live）字段与切换入口；无凭据轮换/过期提醒；无 reveal（查看明文）动作与审计；无 maker-checker。
  - 业务方案 §68.1 明确「切换 = 改 provider 的环境字段，**不重启、不重建镜像**」；§78-D9 验收锚点：后台可切 Test/Live 且不重启；页面/API/日志均脱敏。
- **目标**：给 provider 增加**环境维度**（test/live）与**凭据全生命周期**（分级保管 → 轮换 → 到期提醒 → 可审计的明文 reveal），并把 webhook 端点与签名密钥纳入后台可见；全部 additive、零重启生效。
- **成功指标**：
  1. 后台把 Stripe provider 切到 `test` → 前台列表随即不含它（无需重启/重建镜像），切回 `live` 立即恢复；
  2. 明文凭证只能经 **owner 的 reveal 动作**取得，且每次 reveal 落一条审计（记 key + actor，**不记值**）；无权限用户 403；
  3. 凭据到期前 30/7/1 天在 provider 详情页出现告警（并有审计记录）；
  4. Webhook 端点 URL（含环境语义）与签名密钥（只读掩码）可在后台查看。

## 2. 用户故事 / 场景

- **运营/开发者**：希望给同一支付商配置沙箱与生产两套凭据并在后台一键切换，验收/培训不影响真实资金。
- **owner**：希望敏感动作（看明文、改凭据）有更高权限门槛与审计，出问题能追责。
- **财务/运营**：希望在凭据/证书/signing secret 到期前收到提醒，提前轮换、避免掉单。
- **边界/异常场景**：provider 无 `environment`（历史数据）→ 视同 `live`；`env:` 引用指向未设置的环境变量 → 解析为 `nil`（不抛错）；reveal 未知 key → 422；轮换期间旧值保留至到期阈值。

## 3. 功能需求（FR）

- **FR-001　环境维度（test/live）**：`PaymentMethod` 增 `environment`（枚举 `test` / `live`，列默认 `live`，存量零迁移语义）；后台 provider 详情页可切换；切换**即时生效**（不得依赖进程级缓存/环境变量）。
- **FR-002　test 环境隔离**：`environment = test` 时——① 前台收集排除该 provider（`Payments::Availability::Resolver` frontend scope）；② `PaymentSessions::Start` 产出的会话/支付打 `test_mode: true`；③ 后台保存切 test 时强制 `storefront_visible = false`。
- **FR-003　凭据分级与保管**：分级沿用既有三档（`:password` 类型 = `secret`；`public_preference_keys` = `publishable`；其余 = `internal`）并补读取 API（`PaymentMethod#credential_level(key)`）；支持「环境变量引用」写法（值形如 `env:STRIPE_SECRET_KEY`）——**本期只做存储 + 解析 API**（`resolved_preference(key)`），**provider 网关读取路径的统一解析随 D10**。
- **FR-004　脱敏与 reveal**：页面/API 默认脱敏（沿用 D1）；新增 reveal 动作 `POST /admin/payment_methods/:id/reveal_credential`（body：`key`）——**仅 owner 等价权限**（`update` + 默认管理员角色）、二次确认、返回明文**一次**，落审计 `payment_method_credential_revealed`（`key` + `actor`，**不含值**）。
- **FR-005　轮换与过期提醒**：凭据可标注 `rotated_at` / `expires_on`（`private_metadata['credentials']`）；provider 详情页展示「最近轮换 / 到期日 / 剩余天数 / 告警级别」；每日作业 `PaymentMethods::CredentialExpiryCheckJob` 在 **30 / 7 / 1 天**阈值生成告警（写 `credential_alerts` + `AuditLog`，同级别幂等）。
- **FR-006　Webhook 端点与签名密钥**：provider 详情页展示 webhook 端点 URL（`/api/v3/webhooks/payments/:pm_prefixed_id`，无需 API key）+ 签名密钥**只读掩码**（Stripe `webhook_keys`）。
- **FR-007　权限与审计**：reveal / 改 environment / 改凭据一律写审计；权限不足 → 403。
- **FR-008　零回归**：无 `environment` 的历史 provider = `live`；既有 Test connection / 脱敏 / 入口选项化 / 适用范围行为逐字节不变；store API 契约不变（admin 侧 additive）。

## 4. 非功能需求（NFR）

- **安全**：明文只出现在 reveal 响应体一次；日志/审计/序列化绝不含明文；`env:` 引用在 DB 中不得出现明文（spec 断言）。
- **兼容**：全部 additive（新列有默认值；新字段可选）；老客户端字段不变；`environment` 不在 permit 名单时由控制器从 params 白名单校验后合并。
- **可维护**：环境/分级/阈值以常量表声明；provider 差异走 provider 钩子而非核心分支。
- **性能**：到期巡检按日批处理、零 provider 网络调用；详情页新增卡片不引入 N+1。
- **i18n**：新增文案 en + zh-CN（gem `en.yml` + 宿主 `*.zh-CN.yml`）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001 ← FR-001/002**：切换 `environment` 保存后立即生效：`test` → 前台列表不含该 provider（后台录单仍可用）；`live` → 恢复出现；非法值忽略（RSpec：model + admin 请求规格）。
- **AC-002 ← FR-002**：`environment = test` 时 `PaymentSessions::Start` 产出的 session 带 `external_data['test_mode'] = true`，其 `find_or_create_payment!` 产出的 Payment `metadata['test_mode'] = true`（RSpec：start_spec 扩展）。
- **AC-003 ← FR-003**：每 key 可解析出分级（`secret` / `publishable` / `internal`；webhook 签名密钥属独立表，见 FR-006）；`env:XXX` 形式的凭据**只存引用**（DB 值断言）且 `resolved_preference` 能解析出 ENV 值（缺失 → `nil`，不报错）。
- **AC-004 ← FR-004**：无 owner 等价角色调 reveal → 403 且无审计；owner 调 → 返回明文且审计含 key/actor、不含值；未知 key → 422（RSpec：admin 请求规格）。
- **AC-005 ← FR-005**：设置 `expires_on` 落在 30/7/1 天阈值 → 作业运行后写 `credential_alerts` + 审计；同级别重复运行不重复告警；过期后级别升为 `expired`（RSpec：model + job spec）。
- **AC-006 ← FR-006**：详情页渲染 Webhook 卡（端点 URL 含 `pm_` + 签名密钥掩码）与「凭据健康」卡（环境选择器 + 掩码值），页面不含明文（RSpec：admin 请求规格 + DOM 断言）。
- **AC-007 ← FR-008**：历史 provider（无 environment/凭据元数据）行为与本期前一致；未知环境值不改变记录（RSpec：回归断言）。
- **AC-008 ← 收口**：注册验证器 `d9-credentials-rspec` 全绿（`harness.config.mjs` + `AGENTS.md` §6）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | preferences / webhook / environment | 仅生成类型 + `ai/provider.html.erb` | ❌ 无业务实现（保持） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `preferences` / `test_connection` / `rotate` / `environment` | `payment_method.rb`（`public_preferences:342`、`test_connection:491`、`payment_option*`）、`Preferences::{Preferable,Masking}`、`PaymentMethods::TestConnection`、`PaymentSession#find_or_create_payment!:101` | ⚠️ 加密/脱敏/体检已备；**缺** environment、轮换/过期、reveal、test 隔离 |
| API | `pallastrade_gems/pallastrade_api/app/` | admin serializer / reveal | `admin/payment_method_serializer.rb`（`preferences → serialized_preferences`） | ⚠️ 投影已脱敏；本期补 `environment` / `credential_status` / reveal 端点 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_methods views / controller / webhook | `payment_methods_controller.rb`（`test_connection:16`、`permitted_resource_params:57`）、`_form/_options`、`webhook_endpoints_controller`（出站 webhook） | ⚠️ 本期补环境控件 / 凭据健康卡 / Webhook 卡 / reveal |
| Storefront | `storefront/src/` | NEXT_PUBLIC / client_config | 13 文件含 `NEXT_PUBLIC_*` | ❌ 属 **D10**，本期不碰 |
| Platform | `platform/packages/` | PaymentMethod 类型 | admin SDK `PaymentMethod.ts`（typelizer 生成） | ⚠️ 仅类型再生成 |

**结论**：凭据加密/脱敏/体检三条腿 D1 已就位；本 PRD 只补**环境维度 + 生命周期（轮换/过期/reveal/审计）+ Webhook 端点与密钥可见**，除 1 个 `environment` 列迁移外不建表、不动 store 契约、不改前台渲染。

## 7. 技术影响

- **Core**：`PaymentMethod` 增 `environment`（列 + 白名单校验 + `test_environment?`）、`credential_level` / `credential_status` / `credentials_status` / `credential_metadata` / `resolved_preference`；新增 `PaymentMethods::{Credentials,CredentialExpiryCheckJob}`；`Resolver.providers(scope: :frontend)` 过滤 test；`Start` 打 `test_mode`；`PaymentSession#find_or_create_payment!` 继承标记。
- **迁移**：1 个（`pallastrade_payment_methods.environment`，`default: 'live'`, `null: false`），无回填。
- **API**：admin serializer 增 `environment` / `credential_status`（**不含值**）；新增 reveal 动作（member route）；store 侧契约不变。
- **Admin**：`_form` 环境选择 + `_credentials` 卡（凭据健康 + reveal + Webhook）；helper `environment_options` / `credential_health_rows` / `payment_webhook_endpoint_url` / `masked_webhook_signing_key`。
- **影响面**：`harness affected --base origin/dev`（实施时执行）。

## 8. 测试计划

| 测试文件 | 类型 | 覆盖 AC |
|---|---|---|
| `backend/spec/models/pallastrade/d9_payment_method_environment_spec.rb`（新增） | RSpec | AC-001、AC-003、AC-005（读取侧） |
| `backend/spec/jobs/pallastrade/payment_methods/credential_expiry_check_job_spec.rb`（新增） | RSpec | AC-005（调度与幂等） |
| `backend/spec/requests/pallastrade/admin/payment_method_credentials_spec.rb`（新增） | RSpec | AC-001、AC-004、AC-006、AC-007 |
| `backend/spec/services/pallastrade/payment_sessions/start_spec.rb`（扩展） | RSpec | AC-002 |
| `backend/spec/requests/pallastrade/admin/payment_methods_spec.rb`（回归） | RSpec | AC-007（D1 门控回归） |
| `backend/spec/models/pallastrade/payment_method_options_spec.rb`、`spec/services/pallastrade/payments/availability/resolver_spec.rb`、`spec/services/pallastrade/payment_methods/test_connection_spec.rb`（回归） | RSpec | AC-007 |
| `harness.config.mjs` + `harness verify d9-credentials-rspec` | 验证器注册 | AC-008 |

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/admin.yaml` + platform 副本（`environment` / `credential_status`）+ admin SDK 生成类型（`scripts/ci/contracts.sh` 再生成）
- [x] Skill：`pallastrade-security`（分级/reveal 审计/env 引用）、`pallastrade-payments`（环境与轮换语义）、`pallastrade-admin`（环境控件 + 凭据健康/Webhook 卡 + 归一链顺序坑）、`pallastrade-api-v3`（admin 投影 + reveal 动作）、`pallastrade-data-model`（environment 列 + credentials/credential_alerts 元数据）、`pallastrade-typescript-sdk`（生成类型）
- [x] 业务方案：§68 首版状态回写（含「未实施」清单：白名单店铺 / 前端下发 D10 / maker-checker）
- [x] `harness/scenarios/scenarios.json`：新增 GS-131（环境隔离 + reveal 审计 + 到期告警）→ `harness eval-ai --scenarios` 全绿（136/136）
- [x] 本 PRD 状态更新（→ done）+ `docs/prd/README.md` 索引（`prd-status-sync` 同步）
- [x] 评估（已覆盖，无需额外更新）：**Model/DB 变更**（`environment` 列）→ `pallastrade-data-model` Skill + 领域 Skill + 测试 + 场景库均已更新；**API 端点变更**（reveal member route）→ `api-docs` + `pallastrade-api-v3` Skill + SDK 生成类型 + 场景库；**安全策略变更** → `pallastrade-security` Skill 已更新，`AGENTS.md` §8「危险操作」清单**无需变更**（reveal 是有权限门槛 + 审计的正常动作，非危险命令拦截项）；**机制类资产** → `AGENTS.md` §6 已加 `d9-credentials-rspec` 行；`pallastrade-prd` Skill / `copilot-instructions.md` **已评估，无需更新**（PRD 流程与 R0–R9 未变）。

**不在本期（记录以免误判为遗漏）**：前端密钥下发 `client_config` 与 `NEXT_PUBLIC_*` 清理（**D10**）；**`env:` 引用的 provider 网关侧统一解析**（随 D10）；**Webhook 签名密钥的写入/编辑**（首版只读展示；写入需逐 provider 适配，随 **D12 Webhook 治理**）；test provider 的**白名单店铺**放行（§68.1 附图注）；maker-checker 双人复核完整流（§68.7 后半，随 D14/D15）；KMS/HSM 包裹；路由与熔断（D11）。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-15 | 0.1 | 初稿：据业务方案 §68.1–§68.7、§78-D9 + 6 层搜索（D1 已就位部分明确标出；缺口环境/轮换/reveal/签名密钥管理）；`prd new` 自动分类 payments（关键词命中 1） | AI |
| 2026-09-15 | 0.2 | 用户「确认实施（按 PRD 全量）」→ 状态 approved；建立 REQ（`REQ-20260915-d9-credentials.md`）。**实施前侦察后的两处范围收窄**：① `env:` 引用本期只做存储 + 解析 API，provider 网关侧统一解析随 D10；② test provider 的店铺白名单本期不做（只做硬隔离 + 默认 `storefront_visible=false`）。 | AI |
| 2026-09-15 | 1.0 | **实施完成（切片1+2）→ done**：environment 列（1 迁移，默认 live 零回归）+ 前台过滤/test_mode 打标 + `PaymentMethods::{Credentials,CredentialExpiryCheckJob}`（分级/env 引用/30-7-1 告警幂等）+ admin 环境控件与 reveal（owner 门禁 + 审计只记 key）+ 凭据健康/Webhook 卡 + admin API 投影与契约再生成 + 验证器 `d9-credentials-rspec`（99 例全绿，含 D1/D8 回归）。**AC-003 分级口径定为 `secret / publishable / internal`**（webhook 签名密钥属独立表）；**Webhook 签名密钥编辑（FR-006 后半）延后**至 D12（首版只读展示，避免半成品写 UI）。 | AI |
