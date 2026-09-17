# REQ-20260917-d15c-three-d-secure

> 关联 PRD：`docs/prd/checkout/PRD-20260917-checkout-d15-切片3-3ds-sca-支付认证策略与-provider-下发-高风险订单只给-redirect-3ds.md`
> 任务：`TASK-20260917060142-cb969cf9` / gate `GATE-2026-09-17T06-01-54`（feature，critical）

---

## Step 0：跨层搜索（6 层，强制）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `3ds` / `three_d_secure` / `risk` / `payment_option` | 仅 `app/javascript/types/serializers/*`（`considered_risky`）与 CSS 徽章 | ❌ 零命中 |
| App — views/decorators | `backend/app/` | 同上 | 无 | ❌ 零命中 |
| Core Gem — models | `pallastrade_gems/pallastrade_core/app/models/` | `payment_option` / `risk` | `payment_method.rb`（`payment_option_catalog` / `effective_payment_options` / `optionized?` / `default_option_kind`）、`payment_risk_assessment.rb`（`DECISIONS` / `FLAGGED_DECISIONS` / `signals`）、`payment_session.rb`（`external_id` / `status` / `metadata` 路由） | ⚠️ 部分（入口目录与决策底座齐；**无 3DS 策略/判定**） |
| Core Gem — services | `pallastrade_gems/pallastrade_core/app/services/` | `availability` / `payment_sessions` / `risk` | `payments/availability/{resolver,rule_set,evaluator,context}.rb`（**入口可用性唯一求值点**）、`payment_sessions/start.rb`（建会话 + 入口级门禁 + 422 `payment_option_not_available`）、`risk/assess.rb`（`DECISION_SEVERITY`）、`risk/rules/{schema,evaluate}.rb`、`payments/error_codes.rb`（`authentication_failed` 归类） | ⚠️ 部分（**求值点可扩展**；缺策略归一/判定/provider 指令三件套） |
| API Gem — controllers | `pallastrade_gems/pallastrade_api/app/controllers/` | `payment_sessions` / `payment_option` | `v3/store/orders/payment_sessions_controller.rb`（create/show/update/complete + 错误渲染）、`v3/store/carts/payment_sessions_controller.rb`（legacy） | ⚠️ 部分（错误码透出可就位；缺 `reason` 字段） |
| Admin Gem — controllers | `pallastrade_gems/pallastrade_admin/app/controllers/` | `payment_option` / `optionized` | `payment_methods_controller.rb`（`merge_payment_options_into` / `normalize_payment_option` / `merged_payment_option_rule_set`：**选项化 = `metadata['options']` + `optionized`**） | ⚠️ 部分（入口表可加列；缺门店策略区块） |
| Admin Gem — views | `pallastrade_gems/pallastrade_admin/app/views/` | `frontend_kind` / `rule_set` | `payment_methods/_options.html.erb`（入口表 **已有 `frontend_kind` 列**）、`risk_rules/{index,show,preview}.html.erb`（动作词汇与预览）、stores 表单（`private_metadata` 先例） | ⚠️ 部分 |
| Storefront | `storefront/src/` | `express` / `inline` / `redirect` | `components/checkout/OrderPaymentContent.tsx`（单选列表 + `method.display_name ?? name` + Stripe 内嵌卡表单）、`components/checkout/ExpressCheckoutButton.tsx`（钱包 express）、`lib/checkout/express-canonical.ts` | ⚠️ 部分（已按服务端列表渲染；缺「无可用入口」提示） |
| Platform | `platform/packages/` | `method_key` / `frontend_kind` | `sdk/src/types/generated/StoreCheckoutCheckout.ts`（`frontend_kind` / `method_key` / `client_config`）、`README.md`（入口口径） | ⚠️ 生成物，随 OpenAPI 同步 |

### 搜索结论

- **无重复实现**：`Payments::Availability::Resolver` 是 D8 确立的**唯一求值点**（前台列表 / `Order#payment_methods` / `PaymentSessions::Start` 同源），本切片**扩展**它（新增 `three_d_secure` 原因维度），**禁止**新建第二套筛选（否则违反 §66.5 同源硬约束、复发「选得上、付不了」）。
- **需新建（core gem 内）**：`Payments::ThreeDSecure::{Policy,Required,ProviderHint}`（策略归一 / 订单级判定 / provider 指令）。
- **需小改**：`Risk::Rules::Schema`（动作 `force_3ds`）、`Risk::Assess`（严重度）、`PaymentRiskAssessment`（决策集）、`PaymentSessions::Start`（消费闸门）、Stripe `payment_option_catalog` + `CheckoutSessionPresenter`（能力声明 + 下发）、checkout 投影（`requires_authentication`）、后台门店表单与入口表列。
- **防重复判定**：钱包入口的隐藏**不在** storefront 客户端实现（前端零筛选），由服务端求值输出（AP-SEARCH-1/2/3 兜底检查：三处均无既有 3DS 判定逻辑）。

---

## Step 1：Skill 文件咨询（强制）

| Skill 文件 | 状态 | 关键结论引用（真实结论） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：**Settings → Configuration → Events → Dependencies → Admin/Ransack → Generators → Decorators → Extensions**；「加一个后台页面的区块」→ `PallasTrade.admin.partials` / 直接改 gem 视图（本仓库约定：gem 为一等公民，改动加 `# PALLAS-CUSTOM:` 标记）；「行为变更用 Events，不用 `after_save`」。→ **本切片落在 gem 服务层 + gem 视图/控制器，不用 Host Decorator**（与 D8/D11/D16 先例一致）。 |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | D8 段落：**「同源硬约束（§66.5）：`Order#payment_methods` 与 `PaymentSessions::Start` 必须用同一份 `Resolver` 求值——禁止任何一侧自算」**；**「Start 判不可用 → 422 `payment_option_not_available`（不建会话）；前台收到该码 → 刷新支付方式列表 + 提示重选」**；D11 段落：闸门「先判 `soft_disabled?`」，`Resolver.evaluate` 给 `{dimension:'breaker', reason:'breaker_open'}` 便于解释。→ 本切片**沿用**该模式：新维度 `three_d_secure`，落后于既有失败码（加 `reason`），不改客户端既有处理。 |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | 规则引擎段：**「动作：`allow` / `review` / `block`（本切片）；`force_3ds` 属切片3（3DS/SCA 与 provider 下发）」**；**「决策合并（唯一口径）：白名单命中 → `allow` 短路；否则取最严者（`allow(0)<review(1)<block(2)`）——规则不得把名单判定放宽」**；留痕写 `signals['rule_engine']`。→ 本切片插入 `force_3ds`（严重度 2，位于 `review` 与 `block` 之间），**不改变**「取最严者 + 白名单短路」口径。 |
| `ai/skills/pallastrade-checkout/SKILL.md` | ✅ 已读 | 结账投影与 `PaymentSessions::Start` 的关系：前台只消费服务端列表，不做客户端筛选；「选得上、付不了」由同源求值防住（D8 段）。→ 本切片 checkout 只**新增字段**与「无可用入口」提示，不加筛选逻辑。 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | 阶段 0：`prd new` 查重 > 0.3 阻止新建 → 命中相似必须回写；本需求评审后 `--force` 新建（理由记入 PRD 元数据）；写完必须 `node scripts/ci/prd-status-sync.mjs --check`；阶段 1 必须**用户明确确认**。 |

**按需 Skill（本次涉及）**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | 契约变更必须同步 `backend/public/api-docs/{store,admin}.yaml` + `generated:check`；本项目 checkout 投影为 **SDK 生成类型**来源（`StoreCheckoutCheckout.ts`）。 |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | 新事件 = 名称 + payload（**无 PII**）+ 订阅者注册；事件系统未启用/发布失败**不得阻断**业务路径（与 D15 切片2 同口径）。 |
| `pallastrade-admin` | ✅ | ✅ 已读 | 后台页面三要素（标题/面包屑/图标）+ `data-*` 测试钩子 + 权限（`can :manage, ...`）；新增授权资源必须登记 `pallastrade_permission_registry.rb`（**本切片不新增资源**）。 |
| `pallastrade-data-model` | ✅（读取口径） | ✅ 已读 | `private_metadata` additive 迁移先例（D13 汇率策略 / D14c 拒付率策略）；**本切片零迁移**。 |
| `pallastrade-storefront` | ✅ | ✅ 已读 | 组件样式用 Tailwind + 设计 token（AP-001/AP-006）；i18n 文案走既有 dictionary；**禁止客户端绕过服务端求值**。 |
| `pallastrade-testing` | ✅ | ✅ 已读 | 「本地绿 CI 红」清单：**fixture 不得依赖默认店铺的 market/币种状态**（本切片涉及币种比较，必须遵守）；零 provider 用 stub 断言载荷。 |

---

## 需求标题

D15 切片3：3DS / SCA 支付认证策略与 provider 下发 —— 交付业务方案 §78-D15 验收锚点「**高风险订单只给 redirect+3DS**」。

## 任务类型

新功能（跨 core gem 服务层 + API 契约 + Admin + Storefront 文案；零迁移）。

## 需求描述

把「要不要做 3DS 挑战」从**provider 默认**变成**商家可配置策略 + 订单级风险决策**的闭环：

1. 门店可配 3DS/SCA 策略（`always` / `risk_based` 默认 / `off`）+ 豁免（低金额 TRA / 国家白名单 / 入口白名单）；
2. 规则引擎新增动作 `force_3ds`（严重度位于 `review` 与 `block` 之间）；
3. 单一判定 `Payments::ThreeDSecure::Required`（只读、零 provider）输出「本单是否需要认证」+ 可解释结论；
4. 认证需求为真时，**入口闸门**（扩展现有 `Availability::Resolver`）让「无法保证认证」的入口消失（express 钱包等），`PaymentSessions::Start` 对不合规入口在建会话前 422 拒绝；
5. 建会话时向**声明了能力**的 provider 下发「强制挑战」（Stripe：`request_three_d_secure='any'`；未声明就不下发、不猜）；
6. 全程留痕（`signals['three_d_secure']` + 事件 `payment.three_d_secure_required`）与后台可见（订单风控卡、门店策略区块、入口认证能力列）。

## 影响范围（harness affected 输出）

```json
{ "filesChanged": 4, "affectedComponents": ["backend"], "errors": [], "estimatedTests": 12 }
```
（在 PRD 落地前的基线；实施后按最终 diff 复核。重点回归：D8 可用性、D11 熔断、D16 入口展示、切片1/2 风控、Checkout 收尾收敛 B4。）

## 技术方案（初步）

- **决策树落点（customization skill）**：Settings（门店策略走 `private_metadata`，与 D13d/D14c 同先例）→ 服务层唯一入口（core gem 新服务三件套）→ **不**用 Host Decorator；「行为变更」放在既有服务/闸门里（不用 `after_save`）。
- **唯一口径**：认证判定 = `ThreeDSecure::Required`；入口可用性 = `Availability::Resolver`（扩展维度）；provider 指令 = `ThreeDSecure::ProviderHint`。
- **同源硬约束**：前台列表、`Order#payment_methods`、`PaymentSessions::Start` 共用 `Resolver`（§66.5），本切片只加一个维度。
- **零感兼容**：默认 `risk_based` + 无风险信号 = 入口集合与今天逐项相同；`off` 与未配置门店等价。

## 风险点

1. **回归风险最高**：`Resolver` 是前台列表与 Start 的公共路径 → 必须以「默认策略下入口集合逐项相同」的回归断言兜底（AC-010）。
2. **provider 语义**：`request_three_d_secure` 只对 Stripe 卡有效；未声明能力的入口**不猜**（不下发），且该入口在需求为真时**不可选**（避免「选了再失败」）。
3. **决策集扩展**：`PaymentRiskAssessment::DECISIONS` 增加 `force_3ds` 会影响 `flagged?` 语义与后台展示 → 明确「`force_3ds` 属 flagged」，并回归切片1/2 既有 spec。
4. **回滚难度**：**低** —— 零迁移、策略存在门店 `private_metadata`（删除键即回到默认行为）；回退只需 revert 提交（见 recovery plan）。

## 决策节点

⏸️ **请确认**：以上范围（策略/判定/动作 `force_3ds`/入口闸门/provider 下发/留痕/后台，且**不含** Adyen 落地、MIT、挑战率看板、3DS 失败重试编排）是否符合预期？

确认后 AI 将：开 gate 剩余项 → 实施（TDD）→ 验证器 `d15c-three-d-secure-rspec` → 契约同步 → 知识同步门 → dev 验证。
