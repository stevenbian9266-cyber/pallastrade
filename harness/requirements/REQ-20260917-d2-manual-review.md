# REQ-20260917-d2-manual-review

> 关联 PRD：`docs/prd/payments/PRD-20260917-payments-d2-交易排障台-manual_review-审核动作-通过并捕获-拒绝并释放.md`
> 任务：`TASK-20260917121019-0a3b504b` / gate `GATE-2026-09-17T12-10-30`（feature）
> 业务方案：§78-D2（锚点「一页看全 / 审核动作合规 / manual_review 永不自动」）、§60.2-3（流程层 P2）、§63.2（排障台）

---

## 1. 需求摘要

`manual_review` 交易今天**只能看、不能动**（唯一出口是 console 改状态）。本切片补上**人工裁决**这一层：
「通过并捕获」走既有捕获 + `Transactions::Finalize`；「拒绝并释放」不捕获 + void 授权 + 释放库存 + 订单取消；
两动作均需**权限 + 双重确认 + 原因必填 + 审计**，且**只能由人触发**（`manual_review` 永不自动）。

---

## 2. Step 0：跨层搜索（6 层，强制）

| 层 | 搜索路径 | 关键词（含同义词） | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App — 宿主 | `backend/app/` | `manual_review` / `transactions` / `capture` | 仅 `app/javascript/types/serializers/PallasTradeApiV3StoreCommerceTransaction.ts`（`manual_review_at`）与 `admin/application.css` 徽章类 | ❌ 零命中 |
| Core — 框架 | `backend/pallastrade_gems/pallastrade_core/app/` | `manual_review` / `capture!` / `can_capture?` / `Finalize` / `Cancel` | `models/pallastrade/commerce_transaction.rb`（`state :manual_review` + `NEEDS_ATTENTION_STATES` + 显式出口迁移）、`services/pallastrade/transactions/{recover,finalize,on_payment_success,payment_fact_resolver,start}.rb`、`models/pallastrade/payment/processing.rb#capture!`、`models/pallastrade/payment_method/{check,store_credit}.rb#can_capture?`、`orders/cancel*`（`OrderCancellation`）、`jobs/pallastrade/transactions/recover_sweeper_job.rb` | ⚠️ **部分**：底座齐全（状态机 / 捕获 / 释放 / Finalize / 恢复引擎），**缺人工裁决服务** |
| API — v3 | `backend/pallastrade_gems/pallastrade_api/app/` | `transactions` / `manual_review` | `store/orders/transactions_controller.rb`（顾客启动）、`store/transactions_controller.rb#resume`、`serializers/…/commerce_transaction_serializer.rb`（`manual_review_at`）；**admin v3 无交易端点** | ✅ 无影响（零 v3 契约变更） |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | `transactions` / `recover` / `metrics` | `controllers/pallastrade/admin/transactions_controller.rb`（`index` / `recover` / `txn_metrics` / `authorize_admin`）、`views/pallastrade/admin/transactions/{index,show}.html.erb`、`spec/requests/pallastrade/admin/transactions_spec.rb`（TXN-P2-7 slice2 基线） | ⚠️ **部分**：**缺 `manual_review` 两个动作**（控制器 / 视图 / 路由 / i18n / spec） |
| Storefront | `storefront/src/` | `manual_review` | 无命中（用户侧已是既有 §34「人工核对中」文案） | ✅ 无影响 |
| Platform | `platform/packages/` | `manual_review` | 仅生成物（`sdk/src/types/generated/StoreCommerceTransaction.ts` + `zod/generated/…`） | ✅ 无影响（不重生成） |

**防重复判定（AP-SEARCH-1/2/3）**：`recover` = **自动恢复**（`recovery_required`/`finalizing` → 异步 `Transactions::RecoverJob`）；本切片 = **人工裁决**（`manual_review` → 同步动作）。二者语义不同、互不调用（AC-012 守卫），**不合并**。

---

## 3. 实施方案（文件清单）

| 层 | 文件 | 动作 |
|---|---|---|
| Core | `pallastrade_core/app/services/pallastrade/transactions/review.rb` | 新增（唯一裁决入口：`decision` / `reason` / 幂等 / 审计 / 复用既有链路） |
| Admin | `pallastrade_admin/app/controllers/pallastrade/admin/transactions_controller.rb` | 改：`approve_and_capture` / `release_and_cancel` |
| Admin | `pallastrade_admin/config/routes.rb` | 改：member 两条 POST |
| Admin | `pallastrade_admin/app/views/pallastrade/admin/transactions/show.html.erb` | 改：复核卡 + 复核历史 |
| Admin | gem `config/locales/en.yml` + 宿主 `backend/config/locales/admin_transactions.zh-CN.yml` | 改：新键（键集相等） |
| Spec | `spec/services/pallastrade/transactions/d2_review_spec.rb`、`spec/requests/pallastrade/admin/d2_transaction_review_spec.rb` | 新增 |
| Harness | `harness.config.mjs`（verifier `d2-manual-review-rspec`）、`AGENTS.md` §6、`harness/scenarios/scenarios.json`（GS-172） | 改 |

**零迁移、零 v3 契约变更、零新事件名。**

---

## 4. Skill 咨询证据表（R2 强制，真实结论）

| Skill | 咨询到的问题 | 结论（已据此设计） |
|---|---|---|
| `pallastrade-customization` | 「给既有 admin 页面加动作」走哪一层？ | 决策树：**直接改 gem 内 admin controller/view**（AP-008 定式）——host app 只放 net-new 模块；不引入 decorator |
| `pallastrade-payments` | 捕获/释放的既有语义与状态？ | `Payment`：`pending`=已授权未捕获 → `completed`=已捕获；存在 `Payment#capture!` 与 `PaymentMethod#can_capture?`；**不新增第二套捕获**；`void` 语义用于释放 |
| `pallastrade-payments` | 恢复/裁决是否要新建交易？ | 业务方案 §30 原则「一切恢复路径以**同一交易的新支付尝试**为原则，严禁为恢复而新建交易/重复扣款」→ 裁决**不新建**交易 |
| `pallastrade-admin` | 危险动作的既有约定？ | 危险动作 = `authorize!` + **confirm（双重确认）** + **审计**；**写路径全部走服务**，控制器不直接写模型（避免口径分叉）；`data-turbo-method` 提交（Turbo 栈无 rails-ujs） |
| `pallastrade-testing` | 本切片的测试陷阱？ | ① 「永不自动」用**调用点扫描断言**（不是文档承诺）；② 资金动作 spec 要断言**审计条数 + 零退款 + 历史行零改写**；③ 共享 `@default_store` 场景下写 metadata 前先 `reload`（本切片主要用自建 store，仍遵守） |
| `pallastrade-prd` | 分类/查重流程 | 已按 §2 执行；并修正 `prd-categories.json` 的 payments 关键词（本 PRD 内已记录） |

---

## 5. 验收与证据计划

| AC | 证据类型 | 命令/断言 |
|---|---|---|
| AC-001..004 | test（verifier） | `harness verify d2-manual-review-rspec` |
| AC-005..008 | test（verifier） | 同上（服务层断言 Payment/Order/审计/退款计数） |
| AC-009..011 | test（verifier） | 请求 spec（权限 403 / 视图与计数同源 / i18n 键集） |
| AC-012 | test（verifier 回归） | 既有 `transactions_spec` + recovery spec + 捕获 spec 全绿 |
| AC-013 | test（dev 冒烟） | `tmp-toy/d2_dev_smoke.rb`（事务回滚）+ HTTP 探活 |
| 全部 | review / approval / knowledge | 按 R6/R7 与知识同步门 |

---

## 6. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 裁决动作被误用于**自动**路径（资金不可逆） | 服务无 job 调用；spec 断言调用点唯一；`manual_review` **无**任何自动迁移 |
| 「通过并捕获」在无授权时凭空捕获 | 服务层硬前置：必须有 `pending` Payment 且 `can_capture?`；否则 failure（不猜） |
| 「拒绝并释放」漏释放库存 → 超卖 | 复用既有释放服务 + spec 断言预留状态；失败写审计不静默 |
| 幂等失效（双击 → 双次捕获/双次审计） | `(transaction_id, decision)` 幂等键 + 二次提交 `already_applied` 零副作用断言 |
| 与 `recover` 语义混淆（人工 vs 自动） | 控制器对 `manual_review` 明确拒绝 `recover`（既有行为），对新动作明确拒绝非 `manual_review`；AC 双向守卫 |
