# PRD-20260917-payments-d2-交易排障台-manual_review-审核动作-通过并捕获-拒绝并释放

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-17 |
| 来源 | 需求：D2 交易排障台 manual_review 审核动作（通过并捕获 / 拒绝并释放） |
| 分类 | payments（自动判定，5 个关键词命中） |
| 关联 Skill | `pallastrade-payments` / `pallastrade-admin` |
| 关联 REQ | REQ-20260917-d2-manual-review.md（实施时回填） |
| 关联 PRD | N/A（`prd new` 未命中相似 PRD） |
| 需求类型 | 新功能 |

> 🔁 **查重回写记录**：`harness prd new` 未命中相似 PRD（< 0.3）→ 新建。
> ⚠️ 附带修正：首次自动分类因「交易/排障/manual_review/捕获/释放」全无关键词而误归 `other`，
> 已在 `harness/policies/prd-categories.json` 的 `payments` 补入这批词汇（并同步 `pallastrade-prd` SKILL §2.2），
> 本 PRD 因此落入 `payments`（5 命中）。

---

## 1. 背景与目标

- **一句话需求原文**：`需求：D2 交易排障台 manual_review 审核动作（通过并捕获 / 拒绝并释放）`
- **业务方案依据**：§78-D2（验收锚点：**一页看全 tx→session→payment→webhook→财务事实；审核动作合规；manual_review 永不自动**）、§60.2-3「流程层（P2）：高风险订单自动转 `manual_review`（**不自动捕获**；采用 manual capture + 人工通过后捕获）；**审核动作进后台（交易排障台）**」、§63.2 交易排障台（只读一页看全）、§34/§60.3（待人工审核 → 结果页「人工核对中」文案，不出现「重新支付」诱导）。
- **现状（跨层搜索结论见 §6）**：
  - 排障台**已有**：`index`（列表 + metrics 卡：`recovery_required` / `manual_review` / `stuck` 计数）、`show`（`CommerceTransaction#trace` 只读读模型）、`recover`（**仅** `recovery_required` / `finalizing` → 异步 `Transactions::RecoverJob`）；授权为 `authorize! :admin` + `:update`。
  - 交易状态机**已有** `manual_review` 态与「显式重开」出口（`CommerceTransaction` 注释：review 批2 bugfix B1 之前 `manual_review` 无任何出向迁移，只能 console 改状态）。
  - 捕获底座**已有**：`Payment` 的 `pending`（已授权未捕获）→ `completed`（已捕获）状态与 `Payment#capture!` / `PaymentMethod#can_capture?`；释放底座**已有**：`Orders::Cancel`（含库存预留释放）与订单 `void` 路径。
  - **缺**：`manual_review` 的**人工裁决出口**——运营今天没有任何合规动作可用（无权限校验、无双重确认、无审计、无幂等），只能靠 console 改状态；「通过并捕获 / 拒绝并释放」这两个动作根本不存在。
- **目标**：把 `manual_review` 从「只能看、不能动」变成**有唯一人工出口、动作合规、资金语义明确**的闭环，交付锚点「**审核动作合规**」与「**manual_review 永不自动**」。
- **成功指标**：
  1. `manual_review` 交易的**唯一**人工出口 = 后台动作（权限 + 双重确认 + **原因必填** + 审计），且**没有任何 job/sweeper 会调用它**（「永不自动」可断言）；
  2. 「通过并捕获」= 走**既有**捕获与 `Transactions::Finalize` 链路（订单完成、库存提交），**不新建交易、不重复扣款**（§30 原则）；
  3. 「拒绝并释放」= 不捕获 → void 授权（若存在）→ 释放库存预留 → 订单取消；**不产生退款、不改写历史 Payment/Refund/账本**；
  4. 幂等：同一决策重复提交 → **零副作用**返回（`already_applied`）；非 `manual_review` 交易被拒（结构化错误）；
  5. 失败不半途：捕获失败则交易状态不变 + 审计失败原因（给出可读 reason 与 provider 返回码）。

**铁律（本切片不破）**：不新增第二套状态机；所有资金动作经**既有**服务（`Payment#capture!` / `Transactions::Finalize` / `Orders::Cancel`）；不改 `Transactions::Recover` 的既有语义与 `recover` 动作；`manual_review` **只在人工动作下**离开该状态。

**范围纪律（本切片不做）**：复核队列视图（优先级 / 停留时长 / **SLA 倒计时**）与「请求补充材料」动作 → **D15 切片4**；风控看板与 3DS 挑战率/队列时长指标 → **D3**；Stripe Radar 规则后台 → **D4**；自动恢复 / 自动判定 → 明确不做（`manual_review` 定义即人工）。

---

## 2. 用户故事 / 场景

- 作为**客服/运营**，我希望在排障台一眼确认「钱到底扣了没」，并**直接**做出裁决（继续完成 or 释放取消），以便不用等工程同学进 console。
- 作为**风控运营**，我希望高风险订单被拦到人工队列后，我能按证据放行（捕获）或拒绝（释放），且**每次决定都留原因**，以便事后审计。
- 作为**财务/审计**，我希望每个裁决都有操作人、原因、动作前后状态与时间，以便对账与追责。
- 作为**工程**，我希望裁决**只能由人触发**，任何后台任务都不得替人做决定（资金事实不可逆）。

场景（正常 / 边界 / 异常）：

1. **正常（通过并捕获）**：交易 `manual_review`，其 Payment 处于 `pending`（已授权未捕获）→ 运营填原因 + 确认 → 捕获成功 → 订单进入完成链路 → 交易 `completed`。
2. **正常（拒绝并释放）**：交易 `manual_review`，授权仍在 → 运营填原因 + 确认 → **不捕获** → void 授权 + 释放库存预留 → 订单取消（`canceled`）。
3. **边界（无 pending 授权）**：交易 `manual_review` 但本地无 `pending` Payment（例如 provider 侧权威事实缺失）→ 选择「通过并捕获」→ **拒绝执行**并提示需先确认事实（不猜、不凭空捕获）。
4. **边界（幂等）**：同一交易、同一决策重复提交（双击/刷新重放）→ 第二次**零副作用**返回 `already_applied`。
5. **异常（状态不符）**：交易已 `completed` / `canceled`，或处于 `recovery_required`（应走既有 `recover`）→ 动作被拒（结构化错误 + flash），**状态不变**。
6. **异常（provider 捕获失败）**：捕获网关报错 → 交易**保持** `manual_review`、订单不变、审计记失败原因；运营可重试（幂等）。
7. **异常（越权）**：无 `update` 权限的账号 → 403/拒绝，且不写任何审计成功记录。
8. **异常（未填原因）**：原因为空 → 拒绝提交（服务层 + 表单双重），零副作用。

---

## 3. 功能需求（FR）

### FR-001 裁决服务（唯一入口，人工专用）
- 新服务 `Mutations::…`？→ 取名 **`Transactions::Review`**（`pallastrade_core/app/services/pallastrade/transactions/review.rb`，`ServiceModule::Result`）：
  - 入参：`transaction:`、`decision:`（`'capture'` / `'release'`）、`reason:`（**必填**）、`actor:`（可选，落审计）、`provider_reference:`（可选，人工核对到的 provider 引用，仅作证据留痕）。
  - 前置：`transaction.state == 'manual_review'`（其它状态 → failure，含结构化 `reason` 字段，前端可读）。
  - 幂等键：`(transaction_id, decision)` —— 已应用过同决策 → success(`already_applied: true`)，**零副作用**（不重复调 provider、不重复写审计成功行）。
  - **人工专用**：服务自身不做任何自动重试；**不得**被 job / sweeper / 订阅者调用（spec 断言：仓库内除 admin 控制器外无调用点）。
- 返回值：`{ action:, transaction:, payment:, already_applied:, detail: }`。

### FR-002 「通过并捕获」语义（复用既有链路）
- 前置：该交易下存在 `pending`（已授权未捕获）Payment（`PaymentMethod#can_capture?` 为真）；否则 failure（不猜、不凭空捕获）。
- 执行：`Payment#capture!` → **既有** `Transactions::Finalize`（订单完成 + 库存 commit；与「支付成功」既有链路同源，不新建第二套）。
- 结果：交易 → `completed`（或既有 `finalizing → completed` 路径）；订单 `payment_state` 与实际一致。
- **禁止**：新建 `CommerceTransaction`、重复创建 `PaymentSession`、调用 `PaymentSessions::Start`（§30）。

### FR-003 「拒绝并释放」语义
- 执行（按可用性降级，各自幂等）：① 不捕获；② 若存在未捕获授权 → 走既有 void/取消授权路径；③ 释放库存预留（既有释放服务）；④ 订单取消（既有 `Orders::Cancel` 语义）。
- 结果：交易 → `canceled`；订单 → `canceled`；**不产生退款**（未捕获即无资金移动）；历史 Payment / Refund / 账本行**零改写**。
- 若某一步不可用（例如授权已过期）→ 记录并继续其余步骤，最终结论写审计（不静默）。

### FR-004 权限、审计与事件
- 权限：沿用 `authorize! :admin` + `:update`（与 `recover` 同口径）；`can :manage` 的超管可用。
- 审计（`Audit.record`，动作名固定）：`transaction_review_captured` / `transaction_review_released`，含 `before_state` / `after_state` / `decision` / `reason` / `provider_reference` / 失败时的 `error_code`。
- 失败审计：`transaction_review_failed`（同样含 reason）。
- 事件（可选，无 PII）：复用状态机既有事件；**不新增**事件家族（保持与 `CommerceTransaction` 现有 publish 约定一致）。

### FR-005 后台 UI（排障台 show 页）
- show 页在 `manual_review` 状态下显示「人工复核」卡：动作两个（通过并捕获 / 拒绝并释放）+ **原因必填** + **双重确认**（沿用既有确认组件约定，`data-turbo-method` 提交 + confirm 文本）。
- 非 `manual_review` 状态：卡片显示「无需复核」并说明当前状态与可用动作（例如 `recovery_required` → 指向既有「重试恢复」）。
- index 页 `manual_review` 计数卡可一键筛选（与筛选同源计数，避免「计数 3、列表 2」）。
- i18n：gem `en.yml` + 宿主 `admin_*.zh-CN.yml` **键集相等**（本切片新增键归入 `admin.transactions.*`）。

### FR-006 解释性与互跳
- 复核卡展示判定所需的最小事实：交易状态 / 最近一次 Payment 状态与金额 / 是否存在未捕获授权 / 库存预留状态；**全部只读**。
- 与既有面板互链：订单页风控卡（D15 切片1：最近评估与决策）、Webhook 事件（D12）、拒付看板（D14 切片3）。
- 留痕可读：审计行与 show 页的「复核历史」区块展示 `operator / decision / reason / 时间`。

---

## 4. 非功能需求（NFR）

- **资金安全**：全部动作在**单事务**内完成（provider 调用在事务边界内但失败即回滚本地状态）；幂等键防重复；失败不留半状态（捕获成功但本地未落 → 由既有 Finalize/Recover 兜底，本切片不新增自动兜底）。
- **不外呼扩散**：provider 调用只经既有 `Payment#capture!` / void 契约；不新增 HTTP 直连。
- **权限与合规**：动作必须 `authorize! :update`；服务层再做一次状态与业务前置校验（控制器不可绕过）。
- **可观测**：metrics 卡保留 `manual_review` 计数（不新增 SLA 指标，见 D15 切片4）；审计可查。
- **兼容（零回归）**：`index` / `show` / `recover` 行为不变；`Transactions::Recover` 语义不变；状态机不新增状态与迁移；不影响前台结账与 `Checkout::Preflight`。
- **可维护性**：裁决语义**只**在 `Transactions::Review` 一处；控制器只做授权 + 调用 + flash。

---

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件（可验证） |
|---|---|---|
| AC-001 | FR-001 | 服务仅接受 `manual_review`；其它状态 → failure 且**零副作用**（状态/审计/Payment 不变） |
| AC-002 | FR-001 | 原因必填（空/空白 → failure，零副作用）；`decision` 非法 → failure |
| AC-003 | FR-001 | 幂等：同决策二次提交 → `already_applied`，provider 调用次数与审计成功行数**不增加** |
| AC-004 | FR-001 | **永不自动**：仓库内 `Transactions::Review` 的调用点只有 admin 控制器（spec 断言 + 无 job/sweeper 引用） |
| AC-005 | FR-002 | 通过并捕获：`pending` → `completed`（Payment）、订单按既有 Finalize 完成、交易 `completed`；**未**新建交易/会话 |
| AC-006 | FR-002 | 无 `pending` 授权 → 通过并捕获被拒（结构化 reason），零副作用 |
| AC-007 | FR-003 | 拒绝并释放：不捕获；订单 `canceled`；库存预留释放；**新增退款数 = 0**；历史 Payment/Refund/账本行零改写 |
| AC-008 | FR-004 | 两条成功路径各写**恰好一条**审计（含 reason/actor/before_after）；失败写 `transaction_review_failed` |
| AC-009 | FR-004 | 权限：无 `update` 权限 → 不出现成功审计、状态/资金不变（拒绝式响应） |
| AC-010 | FR-005 | show 页：`manual_review` 显示复核卡（两动作 + 原因必填 + 双重确认）；非该状态显示说明且**不出现**动作按钮；i18n en↔zh-CN 键集相等 |
| AC-011 | FR-005 | index：`manual_review` 计数与一键筛选结果**同源**（计数 == 列表条数） |
| AC-012 | NFR | 零回归：`recover` 行为不变（`recovery_required` 仍可 enqueue、`manual_review` 仍被 `recover` 拒绝）；既有 `transactions_spec` 全绿 |
| AC-013 | NFR | dev 冒烟：构造 `manual_review` 交易 → 两动作各跑一次（在事务内回滚）→ 断言状态/审计/零资金副作用；HTTP 探活 |

---

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`manual_review` / `transactions` / `capture` / `void` / `release` / `recovery_required` / `Finalize` / `Orders::Cancel`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App（宿主） | `backend/app/` | 仅序列化类型（`PallasTradeApiV3StoreCommerceTransaction#manual_review_at`）与 CSS 徽章 | ❌ 零命中 |
| Core | `pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/commerce_transaction.rb`（state 含 `manual_review` + `NEEDS_ATTENTION_STATES` + 显式出口）、`transactions/{recover,finalize,on_payment_success,payment_fact_resolver,start}.rb`、`payment/processing.rb#capture!`、`payment_method/{check,store_credit}.rb#can_capture?`、`orders/cancel`（`OrderCancellation` needs_attention）、`jobs/pallastrade/transactions/recover_sweeper_job.rb` | ⚠️ 部分（底座齐全，**缺人工裁决服务**） |
| API | `pallastrade_gems/pallastrade_api/app/` | store 侧 `orders/transactions_controller.rb`（顾客端启动）、`store/transactions_controller.rb#resume`；**admin v3 无交易端点** | ✅ 无影响（本切片是 admin engine 页面，零 v3 契约变更） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `controllers/…/transactions_controller.rb`（`index` / `recover` / `txn_metrics` / `authorize_admin`）、`views/…/transactions/{index,show}.html.erb`、`spec/requests/pallastrade/admin/transactions_spec.rb` | ⚠️ 部分（**缺 `manual_review` 两个动作**：控制器、视图、i18n、spec） |
| Storefront | `storefront/src/` | 仅 SDK 生成类型出现 `manual_review_at`（无 UI） | ✅ 无影响（用户侧已有 §34「人工核对中」语义） |
| Platform | `platform/packages/` | `sdk/src/types/generated/StoreCommerceTransaction.ts` + `zod/generated/…`（含 `manual_review_at`） | ✅ 生成物，本切片不改契约 → 无需重生成 |

**结论**：**无重复实现风险** —— 状态机、捕获、释放、Finalize、恢复引擎全部已存在，本切片**只补「人工裁决」这一层**（一个服务 + 两个后台动作 + 审计 + 权限 + 测试），不新增状态、不新增第二套捕获/释放路径。

**防重复判定（AP-SEARCH-1/2/3 兜底）**：`recover` 是**自动恢复入口**（仅 `recovery_required`/`finalizing`，异步 job），与人工裁决**语义不同**，二者不合并、不互相调用（AC-012 守卫）。

---

## 7. 技术影响

| 层 | 文件（新/改） | 说明 |
|---|---|---|
| Core（新） | `transactions/review.rb` | 唯一裁决入口（决策 + 幂等 + 审计 + 复用既有捕获/释放链路） |
| Core（改） | `models/pallastrade/commerce_transaction.rb` | **新增两条出向边**：`approve_after_review`（`manual_review → finalizing`）、`release_after_review`（`manual_review → canceled`）；两者均入 bang 事件表；`reopen_review` / `retry_*` / `repair_completed` **不动** |
| Admin（改） | `controllers/…/transactions_controller.rb` | 新增 `approve_and_capture` / `release_and_cancel`（`authorize! :update` + 服务 + flash + 失败码 → i18n 映射） |
| Admin（改） | `views/…/transactions/show.html.erb` | 复核卡（两动作 + 原因必填 + 双重确认 + 复核历史表；非 `manual_review` 只给说明） |
| Admin（改） | `config/routes.rb` | member 两条 POST 路由（沿用现有 transactions 资源） |
| Admin（改） | gem `locales/en.yml` + 宿主 `config/locales/admin_orders.zh-CN.yml`（**沿用既有交易键所在文件，不新建 locale 文件**） | 新键（en↔zh-CN 键集相等） |
| 契约 | — | **零变更**（admin engine 内部动作，无 v3 API、无 SDK 生成物影响） |
| 数据库 | **零迁移** | 复用 `commerce_transactions` / `payments` / `audit_logs` |
| 事件 | **新增 2 个状态机事件**（`approve_after_review` / `release_after_review`） | 仅新增两条**边**（不新增状态、不新增事件发布）；理由见下方「实现期决定」 |

**实现期决定（与初稿偏差及原因，均为「不猜 / 不重复」原则的落地）**：

1. **新增两条出向边而不是复用 `reopen_review`**：`Finalize::FINALIZABLE_STATES` 含 `recovery_required`，理论上可「重开 → Finalize」，但那样会把人工裁决的**捕获分支**交给 `RecoverSweeperJob` 的自动闭环（存在并发接管窗口）；`release` 分支更是无 `recovery_required → canceled` 边。因此新增两条**显式**边：`approve_after_review`（进既有 `finalizing` 闭环，随后调既有 `Finalize`）、`release_after_review`（落地 `canceled`）。仍**不新增状态、不新建第二套完成/取消实现**。
2. **前置条件用「已授权未捕获（`pending`）」而非 `PaymentMethod#can_capture?`**：跨层搜索发现基类 `PaymentMethod` **未定义** `can_capture?`（只有 `check` / `store_credit` / payment source 实现），调用它会在其它 provider 上 `NoMethodError`——按「不可证明不猜」改用**状态事实**作为前置。
3. **`OrderCancellation#reason` 是枚举**（`customer/declined/fraud/inventory/staff/other/expired`）：人工裁决一律归 `staff`，操作人自由文本写 `note`（并进审计），**不污染枚举语义**。
4. **幂等判定必须先于状态守卫**：否则捕获成功后的重放会因 `state=completed` 得到 `transaction_not_reviewable`，与「幂等返回 `already_applied`」矛盾。
5. **finalize 失败不是「零副作用」**：资金已真实捕获，按既有引擎语义落到 `recovery_required` + `last_error`（交恢复闭环），审计记 `finalize_failed`；拒绝/异常路径保持原状。此点已在服务注释与 AC-005 文案中写明。
6. **release 分支的 void 失败整体回滚**：宁可不释放，也不静默留一枚可用授权（否则事后仍可能被捕获扣款）。

**影响面**：`harness affected` 见 REQ；重点回归 = 既有排障台（`transactions_spec`）、恢复引擎（`Transactions::Recover`）、订单取消与库存释放、支付捕获（`Payment#capture!` 既有 spec）。

---

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 服务 | `spec/services/pallastrade/transactions/d2_review_spec.rb` | AC-001..AC-008（15 例）+ AC-004 调用点扫描 |
| 请求 | `spec/requests/pallastrade/admin/d2_transaction_review_spec.rb` | AC-009 / AC-010 / AC-011（7 例） |
| 回归 | `spec/requests/pallastrade/admin/transactions_spec.rb`、`spec/models/pallastrade/commerce_transaction_spec.rb`、`spec/models/pallastrade/commerce_transaction_recovery_spec.rb`、`spec/services/pallastrade/transactions/**` | AC-012 |
| 断言辅助 | 「永不自动」：扫描 `app/**`+`pallastrade_gems/**`+`lib/**`+`config/**` 中 `Transactions::Review` 的调用点，断言**唯一调用者**是 admin 控制器；job 文件零命中两个新事件 | AC-004 |

**实测**：`d2-manual-review-rspec` 共 **110 例 0 失败**（服务 15 + 请求 7 + 回归 88）。

**验证器**：`d2-manual-review-rspec`（上述集合 + 导航一致性）。
**dev 冒烟**：`tmp-toy/d2_dev_smoke.rb`（事务包裹 + 结束回滚）—— 构造 `manual_review` 交易 → `capture` / `release` 各一次 → 断言状态、审计条数、零退款、幂等；HTTP 探活 `/admin/transactions`。

---

## 9. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-payments/SKILL.md`：`manual_review` 人工裁决（两动作 + 幂等 + 人工专用 + 复用既有链路 + 两条新边）
- [ ] `ai/skills/pallastrade-admin/SKILL.md`：排障台复核卡（权限/confirm/审计/历史）——⚠️ **本文件正被并行会话修改（Catalog Health 健康分）**，按用户裁决（选项 A）**暂留工作区**，待对方提交后补一条小提交
- [ ] `AGENTS.md` §6：`d2-manual-review-rspec` 行——同上（已写入工作区，随共享文件后补）
- [ ] `harness/scenarios/scenarios.json`：GS-172（已写入工作区，随共享文件后补）→ `eval-ai --scenarios` 全绿
- [x] `harness/policies/prd-categories.json` 变更 → `ai/skills/pallastrade-prd/SKILL.md` §2.2（已同步）
- [ ] 业务方案 §78-D2 / §60.2-3 回写（本地文档，不进仓库）
- [ ] `docs/prd/README.md` 索引行——同上（已写入工作区，随共享文件后补）
- [x] 接口文档：**不适用**（admin engine 内部动作，零 v3 契约；`generated:check` 自证零漂移）

**知识同步门（`harness sync-check`）评估结论**（2026-09-17）：

- 「API 端点变更」（`pallastrade_admin/config/routes.rb`）→ **不适用**：新增的是 admin engine 的 **member 路由**（`/admin/transactions/:id/approve_and_capture|release_and_cancel`，服务端渲染页面动作），**不是** `/api/v3/{store,admin}/**` JSON 端点；因此 `backend/public/api-docs/{store,admin}.yaml`、`pallastrade-api-v3` Skill、SDK 生成类型均**无需变更**（`generated:check` 自证零漂移）；场景库部分已由 GS-174 覆盖。
- 「Skill / PRD 机制文件」→ 已更新：`ai/skills/pallastrade-payments/SKILL.md`（D2 小节）、`ai/skills/pallastrade-prd/SKILL.md` §2.2（payments 关键词）、`harness/scenarios/scenarios.json`（GS-174）、`AGENTS.md` §6（`d2-manual-review-rspec` 行）、`docs/prd/README.md`（索引行）。
- `copilot-instructions.md` → **不适用**：R8 只引用 `prd new` 的分类流程，**不枚举关键词**；关键词权威在 `harness/policies/prd-categories.json`（本次已改，SKILL §2.2 已同步）。

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-09-17 | 初稿（D2；业务方案 §78-D2 / §60.2-3 / §63.2；`prd new` 未命中相似 PRD；跨层搜索见 §6；附带修正 `prd-categories.json` 的 payments 关键词） |
| 2026-09-17 | 实施完成：`Transactions::Review` + 两条状态机边 + 后台两动作/复核卡/历史 + 双语键 + 服务/请求规格（22 例）+ 回归（合计 110 例 0 失败）；§7 补「实现期决定」6 条；verifier `d2-manual-review-rspec` 注册；状态 → done |
