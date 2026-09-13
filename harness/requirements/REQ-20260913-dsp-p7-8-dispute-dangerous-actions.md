# REQ-20260913-dsp-p7-8-dispute-dangerous-actions

> 关联 PRD：`docs/prd/payments/PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission.md`（状态 approved）
> 任务：`TASK-20260913033838-fe7f725c` · Gate：`GATE-2026-09-13T03-38-52` · 风险：**critical**

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | `dispute` / `evidence` | **无命中** | ❌ 需在 gem 内新建（沿用 P7 线约定） |
| App — views/decorators | `backend/app/` | `dispute` / `evidence` | **无命中** | ❌ 同上 |
| Core Gem — models | `pallastrade_core/app/models/` | `fetch_dispute_details` / `submit_dispute` | `pallastrade/payment_method.rb:167`（**只读**契约，基类 raise） | ⚠️ 需**新增写契约**（同范式） |
| Core Gem — services | `pallastrade_core/app/services/pallastrade/disputes/` | `evidence` / `submission` | `build_evidence_snapshot.rb`（只读投影，`submission_ready` 恒 false） | ❌ 提交能力需新建 |
| API Gem — controllers | `pallastrade_api/app/controllers/` | `dispute` | **无命中** | ✅ 不适用（本片不新增 API v3） |
| Admin Gem — controllers | `pallastrade_admin/app/controllers/pallastrade/admin/` | `disputes_ops` | `disputes_ops_controller.rb`（P7-7，5 个**安全**动作 + `authorize_admin` + `load_dispute`） | ⚠️ 需**扩展 +2 危险动作**，复用既有范式 |
| Admin Gem — views | `pallastrade_admin/app/views/pallastrade/admin/disputes_ops/` | `show` | `show.html.erb`（七卡只读投影 + `page_actions` 权限门） | ⚠️ 需新增「危险操作卡」（表单 + 文件字段 + 二次确认） |
| Storefront | `storefront/src/` | `dispute` | **无命中** | ✅ 不适用 |
| Platform | `platform/packages/` | `dispute` | **无命中** | ✅ 不适用 |
| 附加：provider 适配 | `pallastrade_stripe/app/models/pallastrade_stripe/gateway.rb` | `fetch_dispute_details` | `:343` 只读实现（`retrieve_dispute` + 归一化快照） | ⚠️ 需新增写实现（`Stripe::Dispute.update` / `close` / `Stripe::File.create`） |
| 附加：事件 | `pallastrade_core/lib/pallastrade/events.rb` + events Skill | `dispute.recovery_*` | P7-6 已确立 `dispute.*` 命名空间（开放命名） | ✅ 新增 2 个事件，机制复用 |

### 搜索结论

1. **零可复用写能力**：全仓（含 Stripe 适配器）没有任何"向 provider 提交证据/接受争议"的写路径——P7-0…P7-7 刻意把它排除在外，并由负向断言钉死。
2. **可复用的是"范式"而非代码**：只读契约的能力探测（类级 owner 检查，零 I/O）、P7-7 管理台的动作/权限/降级骨架、P7-6 的事件命名空间与 `PallasTrade::Audit` 用法。
3. **不重复建设**：App / API / Storefront / Platform 四层零命中 → 本片**不新增** API v3 端点、不动 SDK；一切落在 core/贴 stripe/admin 三个 gem 内。
4. **数据层新增 1 张不可变表**（用户已确认），不改既有表、不改 `Dispute#state` 语义。

---

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 「Building a private extension gem for one-app customization → put the code directly in `app/`」；决策树第 7/8 级：**直接改 Gem 源** + `# PALLAS-CUSTOM:` 注释（本仓 Git 追踪 gem，升级即 merge）—— 本片全部改动按此落地 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 面包屑**自动推导**（`BreadcrumbConcern` 按 `request.path` 匹配导航项，别在 action 内手写 crumb）；表单统一用 `form_with model:` + `PallasTrade::Admin::FormBuilder`；列表过滤需模型侧 `whitelisted_ransackable_attributes`，否则过滤被静默忽略 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⬜ 未读 | **N/A**：本片与商品域无关（争议证据/危险操作），无商品模型、无类目、无搜索变更 |

**按需 Skill（本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | §Admin Ops 明文约定：危险操作需 `turbo_confirm`；P7-7 段确立「控制台动作只能叠在既有服务之上，5 个安全动作之外的危险操作留给 P7-8」——本片正是补上这一段 |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | 自定义事件 `publish_event('name', payload)`；`SubscriberJob` 默认异步；**自定义事件在调用点派发，可能仍在事务内** → 必须在回执落库后再发布（本片实现顺序约束） |
| `pallastrade-security` | ✅ | ✅ 已读 | 权限来自 `PallasTrade::Ability`（DB `RolePermission` 优先，否则代码 Permission Sets）；资源需登记在 `PallasTrade::PermissionRegistry`；**变更权限/注册表后必须跑** `rake pallastrade:permissions:validate STRICT=1` + `pallastrade:admin:nav_validate` |
| `pallastrade-data-model` | ✅ | ✅ 已读 | 资金/账本类新表先例：直接放 `backend/db/migrate/`（如 `20260906000001` 建 `pallastrade_financial_ledger_entries`，**不可变**语义用模型层强制）；本片新表按同一位置与命名约定 |
| `pallastrade-testing` | ✅ | ✅ 已读 | 栈是 **RSpec + Factory Bot**（非 Minitest/fixtures）；文件类测试夹具放 `spec/fixtures/files/`（示例用 printf 造 PNG 头）；`pallastrade_dev_tools` 提供授权 stub / `wait_for_turbo` 等助手 |
| `pallastrade-i18n` | ✅ | ✅ 已读（沿用 P7-7 结论） | admin 文案 key 放 gem `config/locales/en.yml` + 宿主 `backend/config/locales/admin_nav.zh-CN.yml` **成对添加**，双语硬门 `nav_validate` 强制 |
| `pallastrade-api-v3` | ⬜ | ⬜ | N/A（本片零 API v3 变更） |
| `pallastrade-decorators` | ⬜ | ⬜ | N/A（不改既有类结构，新增契约方法 + 新服务） |
| `pallastrade-dependencies` | ⬜ | ⬜ | N/A（无依赖注入点变更） |
| `pallastrade-storefront` | ⬜ | ⬜ | N/A（不涉及商城前端） |

---

## 需求标题

在争议管理后台为运营提供**两个危险操作**（提交证据 / 接受争议），并新增 capability-gated 的 provider 写契约与不可变回执表；Stripe 先行实现（含文件类证据），资金权威仍归 webhook。

## 任务类型

新功能（feature）· 风险等级 **critical**（provider 写路径 + 支付域 + 新增表）

## 需求描述

运营在证据截止前，需要把交付/沟通证据**提交给支付提供方**；在明确放弃抗辩时，需要**接受争议**。两者都是不可逆的对外动作：
必须（1）只有有权限的人看得见、点得动；（2）点击时二次确认；（3）每次执行留下 durable 回执与审计；
（4）**绝不动本地资金账本**——真正的资金结果仍由 provider webhook 回来驱动既有 P7-3/P7-6 链路。

## 影响范围（`harness affected --base origin/dev` 输出）

```
（见下方 execution 命令输出；预期：core disputes 服务/模型契约 + stripe 适配器 + admin 控制台 + 权限注册表 + 事件 + 1 个 migration）
```

## 技术方案（初步）

1. **契约（core）**：`PaymentMethod#submit_dispute_evidence(dispute:, evidence:)` / `#accept_dispute(dispute:, reason:)` —— 基类 `raise NotImplementedError`；
   能力探测沿用 `fetch_dispute_details` 的**类级 owner 检查**（零 I/O、不受 RSpec 打桩干扰）。
2. **证据目录（core）**：`Disputes::EvidenceCatalog` —— Stripe 支持的键（文本：`customer_name` / `customer_email_address` / `product_description` /
   `uncategorized_text` …；文件：`shipping_documentation` / `receipt` / `customer_communication` …）+ 每键类型/必填/长度限制 + 未知键拒绝。
3. **编排（core）**：`Disputes::SubmitEvidence`（校验 → provider 写 → 不可变回执 → `PallasTrade::Audit.record` → `publish_event`）与
   `Disputes::AcceptDispute`（同上，不可逆语义 + 必填 reason）；逾期提交按用户决策：**允许** + 二次确认 + 回执 `late: true`。
4. **适配（stripe）**：文本 → `Stripe::Dispute.update(ref, evidence: {...})`；文件 → `Stripe::File.create(purpose: 'dispute_evidence', file: …)` 后把 `file_…`
   引用写入对应 evidence 键；接受 → `Stripe::Dispute.close(ref)`。返回归一化回执（provider 引用 / status / submitted_at）。
5. **数据（core）**：新表 `pallastrade_dispute_evidence_submissions`（append-only，模型层禁 update/destroy）+ 1 个 migration 于 `backend/db/migrate/`。
6. **管理台（admin）**：`disputes_ops#submit_evidence` / `#accept_dispute`（POST）+ show 页「危险操作卡」（表单 + 文件字段 + 二次确认 + 无权限/不支持的降级）；
   权限仍走 `:update`（CanCanCan），并登记能力到 `PermissionRegistry`。
7. **事件（core）**：`dispute.evidence_submitted` / `dispute.accepted`（回执落库后发布）。

## 风险点

- **最高风险**：误把「提交证据/接受争议」当成资金动作 → 必须用负向断言（Payment/Refund/Ledger/Order/Inventory/Txn 计数与金额前后不变）+ 代码注释铁律钉死；回滚 = 删路由/动作即停用（provider 侧已发生的写不可撤销，属业务语义）。
- **provider 写失败**：网络/校验失败必须返回明确 failure 且**不落半成品回执**（或落 failed 回执，二选一在实现时定稿并测试）。
- **文件上传**：大小/类型白名单；上传失败不得回滚已成功的文本字段（分段回执）；测试用 `spec/fixtures/files/` 小夹具。
- **幂等**：同 payload 重复提交不得重复调用 provider（回执按 `payload_digest` 去重）。
- **兼容**：非 Stripe 网关（Bogus/Check/StoreCredit）必须优雅降级（按钮禁用 + 422，非 500）；P7-1…P7-7 行为逐字节不变。

## 决策节点

> ✅ **用户已于 2026-09-13 明确确认实施**（问答工具，非模糊同意）：
> ① 范围 = **仅 Stripe 危险操作**（Adyen/PayPal 延后至凭证齐备）；② 证据形态 = **含文件上传**（Stripe File + ActiveStorage）；
> ③ 逾期 = **允许 + 二次确认 + 审计 `late: true`**；④ 回执 = **新建不可变表**。
> 确认后进入实施（gate 已建：`GATE-2026-09-13T03-38-52`）。
