# REQ-20260915-d9-credentials

| 项 | 值 |
|---|---|
| 关联 PRD | `docs/prd/payments/PRD-20260915-payments-d9-支付凭据与环境.md` |
| 任务类型 | feature（新功能） |
| 风险初判 | standard（支付配置路径；无资金算法变更） |
| 用户确认 | 2026-09-15 用户选择「确认实施（按 PRD 全量）」 |

## Step 0：跨层搜索（6 层）

| 层 | 搜索关键词 | 命中 | 结论 |
|---|---|---|---|
| App | preferences / webhook / environment | 仅生成类型 + `ai/provider.html.erb` | 无业务实现（保持） |
| Core | `preferences` / `test_connection` / `rotate` / `environment` | `payment_method.rb`（`public_preferences`、`public_preference_keys`、`test_connection`、`payment_option*`）、`Preferences::{Preferable,Masking}`、`PaymentMethods::TestConnection`、`PaymentSession#find_or_create_payment!` | ⚠️ 加密/脱敏/体检已备；**缺** environment、轮换/过期、reveal、test 隔离 |
| API | admin serializer / reveal | `admin/payment_method_serializer.rb`（`preferences → serialized_preferences`） | ⚠️ 投影已脱敏；缺 environment / credential_status / reveal 端点 |
| Admin | payment_methods views / controller / webhook | `payment_methods_controller.rb`（test_connection @16、permitted_resource_params @57）、`_form/_options/…`、`webhook_endpoints_controller`（**出站** webhook） | ⚠️ 无环境切换 / reveal / 凭据健康卡 / PSP 签名密钥管理 |
| Storefront | NEXT_PUBLIC / client_config | 13 文件含 `NEXT_PUBLIC_*` | ❌ 属 **D10**，本期不碰 |
| Platform | PaymentMethod 类型 | admin SDK `PaymentMethod.ts`（typelizer 生成） | ⚠️ 仅类型再生成 |

**关键实现点（代码事实）**：
1. `preferences` 是**序列化列**（`serialize :preferences, type: Hash`）；`preferred_*` getter 经 `get_preference` → `preferences[name]`。
2. `public_preference_keys`（protected，默认 `[]`）= **publishable 分级**；`:password` 类型 = secret 分级；Stripe `webhook_keys` 表 = webhook_secret 分级（已存在，无后台）。
3. 会话→支付唯一创建点：`PaymentSession#find_or_create_payment!`（`payment_session.rb:101`）。
4. `PaymentSessions::Start#call` 组装 `session_data`（含 `idempotency_key`）→ 落 `PaymentSession#external_data`。
5. 前台收集：`Order#payment_methods` / `Resolver.providers(scope:)`（D8 已统一）。

## Step 1：Skill 文件咨询

| Skill | 关键结论（引用条款） |
|---|---|
| `pallastrade-security` | 凭据分级 + 明文零落盘 + 敏感动作审计；`filter_parameter_logging` 已覆盖 `:secret/_key` |
| `pallastrade-payments` | 支付路径加字段须 additive（`external_data`/`metadata`）；不得改变 Start 幂等与锁语义 |
| `pallastrade-admin` | 后台动作用 member route + `link_to data: { turbo_method: :post }`；面包屑三要素；i18n en + zh-CN |
| `pallastrade-api-v3` | admin 投影 additive；store 契约不变；契约经 `scripts/ci/contracts.sh` 再生成 |
| `pallastrade-data-model` | 新列需迁移（不得改旧迁移）；`metadata` = `private_metadata` 别名（写用 `update_columns(private_metadata:)`） |
| `pallastrade-testing` | 规格环境无关（CI 预置国家/店铺币种差异）；断言数据/权限而非实现细节 |
| `pallastrade-customization` | 优先级 1（Settings）→ 6（Decorator）→ 8（直接改 gem）；本期改 gem 源码（与 D1/D8 一致，加 `PALLAS-CUSTOM:` 注释） |

## 设计要点（实施基线）

1. **环境列**：迁移 `add_column :pallastrade_payment_methods, :environment, :string, default: 'live', null: false`；模型 `ENVIRONMENTS = %w[test live]` + inclusion 校验 + `test_environment?`/`live_environment?`；**存量 = live（零回归）**。
2. **test 隔离（硬规则）**：前台收集（`Resolver.providers(scope: :frontend)`）排除 `test` provider；后台（`back_end`）保留；切到 test 时后台保存强制 `storefront_visible = false`。白名单店铺 → 记录为后续（本期不做）。
3. **test 标记**：`Start` 在 `session_data['test_mode'] = true`（test provider）；`PaymentSession#find_or_create_payment!` 创建 Payment 时写 `metadata['test_mode'] = true`。
4. **凭据分级**：沿用既有三档（`:password` → secret；`public_preference_keys` → publishable；`webhook_keys` 表 → webhook_secret）；本期补 `PallasTrade::PaymentMethods::Credentials` 常量 + `credential_level(key)` 读取 API（不改 provider 声明语法）。
5. **`env:` 引用（本期只做存储 + 解析 API）**：值形如 `env:STRIPE_SECRET_KEY` → 落库只存引用；新增 `PaymentMethod#resolved_preference(key)`（解析 `env:` → `ENV[...]`，缺失返回 nil）；**provider 网关的读取路径统一改造随 D10**（PRD §10 记变更）。
6. **reveal**：`POST /admin/payment_methods/:id/reveal_credential`（body `key`）→ 权限 = `can?(:update, payment_method)` **且** `can?(:manage, PallasTrade::Role.default_admin_role)`（owner 等价），否则 403；成功返回 `{ key:, value: }`（JSON，`Cache-Control: no-store`）+ 审计 `payment_method_credential_revealed`（key + actor，**不含值**）。
7. **轮换/过期**：凭据元数据落 `private_metadata['credentials'][key] = { 'rotated_at' =>, 'expires_on' => }`；`PaymentMethod#credential_status` 归一（含 `days_left` / `alert_level` = `none|30d|7d|1d|expired`）；`PaymentMethods::CredentialExpiryCheckJob`（每日）遍历 provider → 写 `credential_alerts`（去重：同一 key+level 只告警一次）+ AuditLog；详情页 banner。
8. **Webhook 卡**：详情页展示端点 URL（`/api/v3/webhooks/payments/:pm_prefixed_id`，含环境徽标）+ 复制按钮 + Stripe 签名密钥表单（保存到 `pallastrade_stripe_webhook_keys`，页面只回后 4 位）+ 24h 投递健康（读 `webhook_deliveries`，只读）。

## 切片 1：core 环境 + 凭据生命周期

1. 迁移（environment 列）+ `PaymentMethod` 环境 API/校验。
2. 前台收集排除 test（`Resolver`）+ `Start` 打 `test_mode` + `find_or_create_payment!` 打标。
3. `PaymentMethods::Credentials`（分级 + `env:` 解析）+ `PaymentMethod#{resolved_preference, credential_status}`。
4. `PaymentMethods::CredentialExpiryCheckJob` + 告警去重。
5. RSpec：`payment_method_environment_spec.rb`（AC-001/003）、`credential_expiry_check_spec.rb`（AC-005）、扩展 `start_spec.rb`（AC-002）。

## 切片 2：admin + API

1. 控制器：`environment` 参数归一（test → 强制 `storefront_visible=false`）+ `reveal_credential` 动作 + 审计。
2. 视图：`_form` 环境选择；新增「凭据健康」卡 + 「Webhook」卡（含 reveal 按钮 + 密钥掩码表单）。
3. admin serializer：`environment` / `credential_status`；`scripts/ci/contracts.sh` 再生成。
4. RSpec：`admin/payment_method_credentials_spec.rb`（AC-004/006）+ 扩展 `admin/payment_methods_spec.rb`（AC-001/007）。
5. i18n：gem `en.yml` + 宿主 `*.zh-CN.yml`。

## 收口（两切片共用）

- 注册验证器 `d9-credentials-rspec`（`harness.config.mjs`）+ `AGENTS.md` §6 行；
- 知识同步：`pallastrade-security` / `pallastrade-payments` / `pallastrade-admin` / `pallastrade-api-v3` / `pallastrade-data-model` Skill、业务方案 §68 状态回写、`harness/scenarios/scenarios.json` 新场景、PRD §9/§10（含 `env:` provider 侧改造移 D10 的变更）、README 索引；
- `prd verify`（AC↔测试同行标记）、`doc-impact`、`sync-check --ack`。

---

# 实施记录（2026-09-15，切片 1+2 完成）

## 关键决策（含实施中发现的坑）

1. **环境列而非 metadata**：`environment` 用真实列（`default: 'live', null: false`）——可索引、可校验；存量零回归。
2. **前台硬隔离**：`Resolver.providers(scope: :frontend)` 直接 `where.not(environment: 'test')`（后台 `back_end` 不过滤，沙箱/培训可用）；切 test 时控制器强制 `storefront_visible = false`。
3. **分级口径**：`secret` = `:password` 型 preference；`publishable` = provider `public_preference_keys`；其余 `internal`；**webhook 签名密钥不在 preference 体系**（Stripe `webhook_keys` 独立表）。
4. **`env:` 引用只存不解析到网关**：读取侧 `resolved_preference(key)`（string/symbol 键兼容；ENV 缺失 → nil）；provider 网关直读 `preferences[...]` 的统一改造随 D10。
5. **归一链顺序坑（实测回归）**：`permitted_resource_params` 必须 `merge_environment_into(merge_payment_options_into(attributes))` —— 后者**返回新 Hash**（`attributes.to_h.merge(metadata:)`），丢弃返回值会让入口配置（optionized/rule_set）全部失效（D1/D8 规格 5 例齐挂，已修）。
6. **`environment` 不在 permit 名单**：从 `params.dig(:payment_method, :environment)` 读取并白名单校验；白名单外的值忽略（保持旧表单/旧客户端可用）。
7. **reveal 双重门禁**：`authorize! :update` + `can?(:manage, PallasTrade::Role.default_admin_role)`（owner 等价）；响应 turbo_stream / json；审计只记 key。

## 验证（本地）

- `d9-credentials-rspec`（8 文件）：**99 例 0 失败**（新增 24 例：环境隔离/分级/env 引用/到期巡检/reveal 权限审计/后台卡片 + D1/D8 全量回归）。
- `harness eval-ai --scenarios`：136/136 valid（含 GS-131）。
- 契约再生成：`scripts/ci/contracts.sh`（admin SDK `PaymentMethod` 增 `environment` / `credential_status`；`api-docs/admin.yaml` 同步）。
- 迁移：`backend/db/migrate/20260915140000_add_environment_to_payment_methods.rb`（dev + test 均已 migrate）。

