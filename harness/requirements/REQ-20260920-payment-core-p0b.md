# REQ-20260920-payment-core-p0b（P0-B 厂商层可配置）

> 任务：`TASK-20260920104930-233696c1` ｜ Gate：`GATE-2026-09-20T10-49-31` ｜ 风险：critical
> 关联 PRD：`docs/prd/checkout/PRD-20260920-checkout-支付核心统一-...md`（P0-B 切片）
> 前置切片：P0-A（`REQ-20260920-payment-core-unification.md`，已提交 `e31647aa`）

## Step 0：跨层搜索（6 层）

关键词：`provider_account` / `account_config` / `payment_options` / `update_columns(private_metadata` / `Audit.record` / `member do`

| 层 | 路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/` | 无支付相关命中 | ❌ |
| Core | `pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/payment_method.rb`（`metadata` ↔ `private_metadata` 写入范式：`soft_disable!` / D9 凭据 / D11 熔断均用 `update_columns(private_metadata:)`）；`services/pallastrade/payments/providers/{config,state,validate}.rb`（P0-A 刚交付：账户配置**只读**归一，缺写入口） | ⚠️ 读已有、**写缺** |
| API | `pallastrade_gems/pallastrade_api/app/` | 本切片不新增 API 端点（后台配置面） | ❌ 不涉及 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `controllers/.../payment_methods_controller.rb`（`test_connection` / `reveal_credential` / `soft_disable` / `soft_enable` 四个 member 动作 + `Audit.record` + `authorize!` + `flash` + `redirect_to edit` 范式，本次照抄）；`config/routes.rb:262` `resources :payment_methods` member 块；`views/.../payment_methods/_provider_diagnostics.html.erb`（P0-A 只读卡，本次在其中加写表单） | ⚠️ 需扩展（新 member 动作 + 表单） |
| Storefront | `storefront/src/` | 只读消费，本切片不改 | ❌ |
| Platform | `platform/packages/` | 无契约变化 | ❌ |

**结论**：本切片 = ①账户配置**写入原语**（core，新增 `Providers::Account`）②后台 member 动作 + 表单（照抄既有 `soft_disable` 范式）③三家能力声明落地（`provider_capability` 类方法）④`Config` 一处健壮性修正（provider 声明若省略 `methods` → 回落目录推导，避免把已有入口判成"未声明"）。**不新建表**、不改 API 契约、不改前台。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ 已读（P0-A 同源） | 改 gem 直接落地 + `# PALLAS-CUSTOM:`；不复制到 Host App（AP-008） |
| `pallastrade-payments` | ✅ 已读（本轮补 P0-A 章节） | 账户配置在 `metadata['account']`（零迁移）；写入用 `update_columns(private_metadata:)` 范式（不触发 provider 校验/远端调用） |
| `harness-prd` | ✅ 已读 | PRD 已在册（状态 implementing），P0-B 作为切片推进，不需新 PRD |
| `pallastrade-admin` | ✅ 已读（口径沿用） | 后台 = ERB + Turbo；member 动作范式（authorize → 服务 → flash → redirect edit）；样式走既有 class（`card` / `badge` / `form-select`） |
| `pallastrade-i18n` | ✅ 已读（口径沿用） | 新 key 必须 en ↔ zh-CN 双向齐备；改 locale 后需重启容器 |

## 需求

让 P0-A 引入的「账户配置」**可被运营编辑**，并让三家预接厂商具备**真实能力声明**，从而把「能力 ∩ 账户 ∩ 市场」收窄从只读诊断变成可运营闭环：

1. **账户配置写路径**（core `Providers::Account.write!`）：白名单化写入 `methods` / `currencies` / `countries`（kind 必须 ∈ 能力声明；币种 ⊆ 店铺支持币种；国家 ⊆ 店铺市场国家），非法值**记入 rejected 并忽略**（不 raise、不写脏数据）；写入 `source: manual` + `synced_at: nil` + `updated_at` + `updated_by`；**零资金副作用**。
2. **后台 member 动作** `POST /admin/payment_methods/:id/provider_account`：`authorize! :update` → 写入 → `Audit.record('payment_method_provider_account_updated')`（只记数量与来源，不记明文敏感值）→ flash → 302 回编辑页。
3. **表单**：诊断卡内「账户配置」区（三个多选 + 保存），选项来自 ①能力声明 ∩ 目录 ②店铺支持币种 ③店铺市场国家。
4. **三家能力声明**：Stripe / Adyen / PayPal 定义类方法 `provider_capability`（声明**稳定事实**：会话模式 / 幂等 / 争议 / 结算 / 退款能力；`methods` 省略 → 由各自能力目录推导，不猜未实现的入口；币种与国家**不声明**（账户侧事实，不写死））。
5. **健壮性修正**：`Config.normalize_capability` 在 provider 已声明但省略 `methods` 时回落目录推导（否则会把既有启用入口误判 `kind_not_declared`）。

**不做**：PSP 侧账户信息同步作业（`source: synced` 预留）、写路径强制拒绝（仍不阻断既有 D1/D8 行为）、路由（P3）。

## AC

| AC | 判定 | 验证 |
|---|---|---|
| AC-1 | `Account.write!` 白名单：未声明的 kind / 非店铺币种 / 非市场国家被拒并计入 rejected，合法值写入 `metadata['account']` | 服务 spec |
| AC-2 | 写入 `source: manual` / `synced_at: nil` / `updated_at` / `updated_by`；重复写入幂等（同值不产生额外副作用） | 服务 spec |
| AC-3 | 零资金副作用：`Payment` / `PaymentSession` 计数与 `updated_at` 不变（仅 metadata 变化） | 服务 spec |
| AC-4 | 后台保存后诊断卡即时反映收窄结论（生效方式/币种/国家行随之变化，`ok` 依诊断码变化） | 请求 spec |
| AC-5 | 权限：无 update 权限 → 302/403 且**零写入** | 请求 spec |
| AC-6 | 声明省略 `methods` 时能力回落目录（不产生 `kind_not_declared`） | 服务 spec（回归） |
| AC-7 | 审计留痕：动作 `payment_method_provider_account_updated` + 计数元数据 | 请求 spec |
| AC-8 | i18n en ↔ zh-CN 键集相等 | `harness verify admin-i18n-rspec` |

## 测试计划

`harness verify payment-providers-rspec`（扩展：+ `spec/services/pallastrade/payments/providers/account_spec.rb`、+ `spec/requests/pallastrade/admin/payment_provider_account_spec.rb`）

## 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-20 | 1.0 | 初稿：账户配置写路径 + 后台表单 + 三家能力声明 + 一处能力归一健壮性修正（AC-1..AC-8） | AI |
