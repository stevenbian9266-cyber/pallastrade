# PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics

| 元数据 | 值 |
|---|---|
| 状态 | approved（用户 2026-09-13 回复「实施」） |
| 创建日期 | 2026-09-13 |
| 来源 | 需求：DSP-P7-9 部分争议与多争议语义（partial dispute / 同一支付多 dispute + provider 能力矩阵只读降级，补齐 P7-0 O1–O3） |
| 分类 | payments |
| 关联 Skill | pallastrade-payments / pallastrade-data-model / pallastrade-admin |
| 关联 REQ | REQ-20260913-dsp-p7-9-partial-and-multi-dispute-semantics.md（实施时回填） |
| 关联 PRD | 上游：PRD-20260911-payments-dsp-p7-0（§9 开放项）/ PRD-20260912-payments-dsp-p7-3（幂等键）/ PRD-20260913-payments-dsp-p7-8（写契约）；源计划 §68 边界 C |
| 需求类型 | 优化迭代（把源计划 §68「advanced dispute capabilities」收窄为 Stripe 侧可验证范围） |

---

## 1. 背景与目标

- **一句话需求原文**：用户确认把源计划 §68（DSP-P7-8 Provider Expansion）的「advanced dispute capabilities」收窄为 **边界 C**：partial dispute / 同一 payment 多 dispute 语义 + provider 能力矩阵驱动的只读降级，Stripe 侧可真实验证；P7-0 的 O1–O5 缺口随本片顺带消化；Adyen / PayPal 暂不处理。
- **背景**（均为本次实测取证，非推断）：
  1. **争议手续费在账本上完全不可见**：`pallastrade_disputes.fee_amount` 列在 P7-1 迁移中已建（`20260911000002_create_pallastrade_disputes.rb:38`），但**全仓无任何写入方**（仅 migration / schema / 测试日志命中）；`fetch_dispute_details`（`pallastrade_stripe/gateway.rb:343`）只回 `balance_transaction_references`（BT id 列表），不含 `amount / fee / net`；`FinancialFact::FACT_TYPES` 与 `FinancialLedgerEntry::ENTRY_TYPES` 均无 fee 类型。而 P7-0 §9.2 已明确要求：扣款与 fee 在**同一条** `adjustment` BT（`amount=-争议额, fee=1500, net=-(争议额+1500)`）→ **必须拆两条流水**，fee 独立入账、**胜诉不退、不可冲回**。
  2. **partial 语义未显式化**：模型无 `partial?`；Console 不显示部分争议；无 fixture 断言「`amount < payment.amount` 时全链路按 dispute 快照金额走」。P7-0 §9.2 已定铁律：金额**一律取 dispute 自身快照**，禁止用 `payment_intent.amount` 推导；O2 因 Stripe test helper 仅能产生全额争议而**未实测**。
  3. **多争议缺 payment 级视图**：幂等键已由 P7-3 修好（`fact_posting_key` 的 dispute 最高优先级分支 + `financial_ledger_entries.dispute_id`），但无「同一 payment 争议数 / 合计争议额 / 剩余可争议额度」的只读聚合，也无「合计是否超过支付额」的校验。
  4. **provider 能力仍为隐式探测**：P7-8 用 `PaymentMethod` 类方法 owner + 非空 `dispute_evidence_catalog` 探测能力，控制台只对「无能力」给一条提示；没有**显式只读能力面**，不满足源计划 RV-D10「无 contract → `UNSUPPORTED`、不得猜状态/资金」的可审计要求。
- **目标**：让「部分争议 / 多争议 / 争议费用」在**事实、账本、对账、控制台**四个面上语义完整且可断言；把 provider 能力从隐式探测升级为**显式只读矩阵**，控制台按矩阵优雅降级。
- **成功指标**：① fee 在账本可见且对账可断言「已扣、未返还」；② `Σ dispute.amount` 与 `payment.amount` 可比且可提示超限；③ partial 语义有 fixture 级断言（provider 无法构造时以 fixture + 文档标注未实测）；④ 零新增资金自动化动作（负向断言钉死）。
- **边界（本片不做）**：❌ 自动抗辩 / AI 生成证据 / 自动退款 / 自动补货（源计划 §71）；❌ Adyen / PayPal 适配（无 sandbox 凭据）；❌ 修改 `Dispute` 状态机语义；❌ 新增迁移（`fee_amount` 列已存在）；❌ 任何绕过 provider webhook 的资金写入。

## 2. 用户故事 / 场景

- 作为**财务运营**，我希望看到某笔支付被争议了**几笔、合计多少钱、还剩多少可争议额度**，以便判断是否需要人工介入。
- 作为**对账人员**，我希望每笔争议被扣的**手续费**在账本上有独立条目，并明确**胜诉时手续费不退**（净损失口径），以便与 provider 账单逐笔核对。
- 作为**后台运营**，我希望在争议详情页一眼看到该 provider **支持哪些动作**（提交证据 / 接受争议 / 采费）；不支持时页面明确显示只读与原因，而不是渲染出会报错的表单。
- 场景：① 全额争议（现状路径）；② **部分争议**（`amount < payment.amount`；provider 无法构造 → fixture 驱动）；③ **同一 payment 两笔争议**（同秒乱序事件，含 `created`/`funds_withdrawn`/`closed`/`funds_reinstated`）；④ 无 payment 锚点（既有 `unlinked_payment`）；⑤ 未实现写契约的 provider（`UNSUPPORTED`）。

## 3. 功能需求（FR）

- **FR-P79-01 partial 语义显式化**：`Dispute#partial?` = `payment` 存在且 `amount.to_d < payment.amount.to_d`；`payment` 缺失 → `false`（未知不等于部分争议，不猜）。只读派生，**不新增列**。
- **FR-P79-02 金额来源唯一性（铁律落地）**：Fact 解析 / 入账 / 对账 / 证据快照 / 控制台**一律**取 dispute 自身快照金额；任何路径不得用 `payment.amount` 推导争议金额。新增负向断言（含 grep 级断言）。
- **FR-P79-03 dispute fee 采集**：`fetch_dispute_details` 扩展返回 `balance_transaction_details`（`[{ reference, type, amount, fee, net, currency }]`）与派生 `fee_amount` / `fee_currency`（取 `type == 'adjustment'` 且 `fee > 0` 的 BT，零小数货币不除 100）；字段缺失 → `nil`（不猜）。
- **FR-P79-04 fee 落库（首次观测写入）**：`Dispute#fee_amount` / `fee_currency` 仅当**由空变非空**时写入，重放不覆盖（对齐 `funds_withdrawn_at` 既有语义），写入方为既有时序：`Disputes::HandleProviderEvent`（webhook 路径）/ `Disputes::ResolveFact`（快照路径）。
- **FR-P79-05 fee 入账**：新增财务事实类型与账行类型 `DISPUTE_FEE`（`PSP_FEE` 语义，负数），与 `DISPUTE_FUNDS_WITHDRAWN` **共享同一 provider BT 引用**但为**独立条目**；`FACT_TYPES` / `ENTRY_TYPES` 追加式扩展，非 dispute 路径的 `fact_posting_key` 逐字节不变；fee 条目**永不冲销**（胜诉只记 `DISPUTE_FUNDS_REINSTATED`）。
- **FR-P79-06 对账扩展**：`Reconciliations::ReconcileDispute` 期望账行 = funds 时间戳集合 +（fee 已证 → 恰好一条 `DISPUTE_FEE`）；**复用既有分类枚举**（不新增下游无法消费的值）：fee 缺失 → `journal_missing` + reason `JOURNAL_POSTING_MISSING_DISPUTE_FEE`（可由 P7-6 `Recover` 自动补记）；账本有 fee 但无 provider 证据 → `orphan_entry` + `UNEXPECTED_ENTRY`；结果新增只读 `fee` 视图 `{ evidence:, amount:, currency:, posted:, entry_id:, returned: false }`（`returned` 恒 false = 手续费永不退回），won 场景可断言「fee 已扣且未返还」。
- **FR-P79-07 payment 级多争议聚合（只读）**：新增只读投影（`Disputes::PaymentDisputeSummary` 或等价）→ `{ dispute_count, active_count, disputed_total, remaining_amount, exceeds_payment, dispute_ids }`；`exceeds_payment` 仅作提示（不新增 `attention_reason` 取值），**绝不触发资金动作、绝不写库**。
- **FR-P79-08 provider 能力矩阵（只读、显式）**：`PaymentMethod#dispute_capabilities` 基类返回 `UNSUPPORTED` 形态（`{ supported: false, reason: 'unsupported_provider' }`）；Stripe 适配返回 `{ supported: true, evidence_submission: true, accept_dispute: true, fee_capture: true, evidence_text_keys: [...], evidence_file_keys: [...] }`；控制台按矩阵渲染 —— 不支持的动作**不渲染表单**并给出原因，未知 provider 一律 `UNSUPPORTED`（RV-D10）。

## 4. 非功能需求（NFR）

- **只读优先**：本片零新增资金自动化动作；所有资金结果仍由 provider webhook + P7-6 收敛驱动（铁律不变）。
- **幂等**：fee 首次观测写入；fee 账行的 `fact_posting_key` 以 dispute + `DISPUTE_FEE` 维度去重，同一秒的两笔争议互不覆盖。
- **兼容**：`FACT_TYPES` / `ENTRY_TYPES` 追加式扩展；`fact_posting_key` 非 dispute 分支输出逐字节不变；控制台既有断言不回退（AP-001 无内联样式 / AP-006 无硬编码色 / AP-008 直接改 gem 视图 + `# PALLAS-CUSTOM:`）。
- **可测性**：partial 无法由 Stripe test helper 构造（P7-0 O2）→ 必须 fixture + 服务级断言；provider 未实测项在 PRD 与 Skill 标注「未实测」，**不得写死常量**（fee 从 provider 读数）。
- **降级**：聚合/能力服务失败时控制台逐项 rescue → `unavailable` 卡片，页面绝不 500（沿用 P7-7 约定）。

## 5. 验收标准（AC，与测试一一映射）

- AC-P79-01 ← FR-P79-01：`partial?` 三态断言（全额 → false / 部分 → true / 无 payment → false 且不推断）
- AC-P79-02 ← FR-P79-02：fixture 注入 `amount < payment.amount` → 账行金额 = dispute 金额（负数）且对账 `aligned`；负向：全链路不读 `payment.amount` 作为争议金额
- AC-P79-03 ← FR-P79-03：`fetch_dispute_details` 返回 BT 明细（含 `fee`）；字段缺失为 `nil` 不猜测（网关 spec）
- AC-P79-04 ← FR-P79-04：fee 首次观测写入 + 重放不覆盖 + `nil` 不写
- AC-P79-05 ← FR-P79-05：fee → 恰好 1 条 `DISPUTE_FEE` 账行（负数、`dispute_id` 溯源、与 withdrawn 同 BT 引用但 key 不同）
- AC-P79-06 ← FR-P79-05：won 场景 → 存在 `DISPUTE_FUNDS_REINSTATED`、**无 fee 冲销条目**（负向断言）
- AC-P79-07 ← FR-P79-06：fee 缺失 → `journal_missing` + `JOURNAL_POSTING_MISSING_DISPUTE_FEE`（且可被 `Recover` 补记）；`fee` 视图 `evidence/posted/returned(false)` 可断言；won 时「fee 已扣未返还」判定稳定
- AC-P79-08 ← FR-P79-07：payment 级聚合数值正确（两笔争议合计、剩余额度、超限标记）；负向：聚合零写（不产生 ledger / fact / payment / order 变更）
- AC-P79-09 ← FR-P79-08：能力矩阵基类 `UNSUPPORTED`、Stripe 矩阵内容断言；控制台按矩阵降级（不支持时不渲染表单 + 给出原因）
- AC-P79-10 ← FR-P79-07/08：控制台新增只读卡片（payment 聚合 + 能力矩阵）双语成对（en + zh-CN）
- AC-P79-11 ← 源计划 O3 回归：同一 payment 两笔 dispute + 同秒乱序事件 → 两行独立、各自账行独立、互不覆盖（fixture 驱动）
- AC-P79-12 ← 全局：全量注册 verifier `backend-rspec` 绿 + `generated:check` 无漂移 + `doc-impact` synced + `eval-ai --scenarios` 通过

## 6. 跨层搜索记录（6 层，gate 强制）

搜索关键词：`dispute` / `chargeback` / `partial` / `fee_amount` / `DISPUTE_FEE` / `capabilit*` / `fact_posting_key`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App | `backend/app/` | 仅宿主注册点与文案：`config/initializers/pallastrade_admin_*.rb`、`config/locales/admin_nav.zh-CN.yml` | ❌ 无 dispute 领域代码；需补双语 keys |
| Core | `pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/{dispute,financial_ledger_entry,financial_fact,payment_method}.rb`；`services/pallastrade/disputes/*`（resolve_fact / handle_provider_event / build_evidence_snapshot / recover / scan_* / evidence_catalog / submit_evidence / accept_dispute）；`services/pallastrade/{financial_ledger/post_dispute,financial_facts/resolve_dispute,reconciliations/reconcile_dispute}.rb` | ⚠️ **主战场**：`fact_posting_key` dispute 分支已就绪（P7-3）；但 `fee_amount` 零写入、无 fee 类型、无 partial 派生、无 payment 级聚合、`dispute_capabilities` 不存在 |
| API | `pallastrade_gems/pallastrade_api/app/` | 无命中 | ✅ 无接口变更（后台走 Admin HTML） |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `controllers/pallastrade/admin/disputes_ops_controller.rb`、`views/pallastrade/admin/disputes_ops/{index,show}.html.erb`、`config/routes.rb`、`app/helpers/.../disputes_ops_helper.rb` | ⚠️ 控制台已存在（P7-7/P7-8）；本片只**新增只读卡片**（payment 聚合 + 能力矩阵）+ 降级分支 |
| Storefront | `storefront/src/` | 无命中 | ✅ 不涉及 |
| Platform | `platform/packages/` | 无命中 | ✅ 不涉及 |

**结论**：能力集中在 **core**（事实→账本→对账闭环）与 **admin**（只读投影）；六层搜索未发现任何重复实现。需新建的是四处：① fee 采集→落库→入账→对账闭环；② partial 派生语义与断言；③ payment 级只读聚合；④ provider 能力矩阵。**无重复能力、无新表、无迁移**。

## 7. 技术影响

- **组件**：core gem（`Dispute` / `PaymentMethod` / `FACT_TYPES` / `ENTRY_TYPES` / `FinancialLedger::PostDispute` / `FinancialFacts::ResolveDispute` / `Reconciliations::ReconcileDispute` + 新增只读服务）、pallastrade_stripe（`fetch_dispute_details` 扩展 + `dispute_capabilities`）、pallastrade_admin（controller / view / 双语 locales）。
- **数据库**：**无迁移**（`pallastrade_disputes.fee_amount` 列 P7-1 已存在；无新表）；若实施中发现需要唯一约束/新列，另行申请并单独立 AC。
- **接口**：无 API v3 变更（Admin HTML 路由）→ `generated:check` 应无漂移；如新增后台路由则同步 `config/routes.rb` + 权限（沿用既有 `can?(:read/:update, PallasTrade::Dispute)`，**不新增权限项**）。
- **风险**：
  ① **fee 类型扩展触碰跨域常量**（`FACT_TYPES`/`ENTRY_TYPES`）→ 按 `AGENTS.md` §7 同步 payments / data-model Skill + scenarios；
  ② **provider fee 读数缺失**（BT 未返回 fee / 旧事件无 BT）→ 必须 `nil` + 对账 `fee_missing`，**不得猜 $15**；
  ③ **聚合服务故障**不得让控制台 500（逐项 rescue → `unavailable`）；
  ④ **partial 无法真实验证**（Stripe test helper 限制）→ 以 fixture + PRD/Skill 标注「未实测」为交付边界。
- **回滚**：纯代码 revert（无 schema 变更；`fee_amount` 留空语义 = 未观测，不影响既有行为）。

## 8. 测试计划

| AC | 测试文件 | 类型 |
|---|---|---|
| AC-P79-01/02 | `backend/spec/models/pallastrade/dispute_partial_semantics_spec.rb`（新增） | 模型/契约 |
| AC-P79-03 | `backend/spec/models/pallastrade_stripe/gateway_fetch_dispute_details_spec.rb`（修改：BT 明细 + fee） | 网关 |
| AC-P79-04/11 | `backend/spec/services/pallastrade/disputes/handle_provider_event_spec.rb`（修改：fee 首次观测 / 双争议乱序）+ `resolve_fact` 相关 spec | 服务 |
| AC-P79-05/06 | `backend/spec/services/pallastrade/financial_ledger/post_dispute_fee_spec.rb`（新增） | 账本 |
| AC-P79-07 | `backend/spec/services/pallastrade/reconciliations/reconcile_dispute_spec.rb`（修改：fee_missing / fee_unexpected / won 不冲回） | 对账 |
| AC-P79-08 | `backend/spec/services/pallastrade/disputes/payment_dispute_summary_spec.rb`（新增） | 服务（只读投影） |
| AC-P79-09/10 | `backend/spec/requests/pallastrade/admin/disputes_ops_capability_spec.rb`（新增） | 请求（权限/降级/双语） |
| AC-P79-12 | 注册 verifier `backend-rspec`（全量）+ `generated:check` + `doc-impact` | 回归 |

> partial 场景一律 fixture 驱动（Stripe test helper 仅能产生全额争议，见 P7-0 §9.2 O2）；PRD/Skill 中明确标注「provider 侧未实测」。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：N/A（无接口变更）→ 以 `generated:check` 无漂移为证
- [ ] `ai/skills/pallastrade-payments/SKILL.md`：fee 采集/落库/入账/不冲回语义 + 能力矩阵 + partial 铁律（金额只取 dispute 快照）
- [ ] `ai/skills/pallastrade-data-model/SKILL.md`：`DISPUTE_FEE` 事实/账行 + `fee_amount` 写者 + 多争议只读聚合语义
- [ ] `ai/skills/pallastrade-admin/SKILL.md`：控制台只读卡片与能力矩阵降级约定（评估后决定）
- [ ] `harness/scenarios/scenarios.json`：新增 **GS-101**（部分争议/多争议/争议费用 + 能力矩阵只读降级，资金零自动化）
- [ ] `docs/prd/README.md`：本 PRD 索引行（状态随实施推进）
- [ ] `harness/requirements/REQ-20260913-dsp-p7-9-partial-and-multi-dispute-semantics.md`：实施前生成（含 6 层搜索 + Skill 咨询证据表）
- [ ] 反模式库 / 任务规则：评估后决定（本片不新增全局门禁）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-13 | 0.1 | 初稿：把源计划 §68「advanced dispute capabilities」收窄为边界 C（partial / 多争议 / provider 能力矩阵），并纳入 P7-0 O1（fee 缺口）、O2（partial 未实测）、O3（乱序序列）的消化；含 6 层跨层搜索取证与「无迁移」结论 | AI |
| 2026-09-13 | 0.2 | **用户确认（approved）**：边界 C + 顺带消化 O1–O3；用户回复「实施」；Adyen/PayPal 暂不处理 | AI |
| 2026-09-13 | 0.3 | 实施完成：`Dispute#partial?`、`Disputes::CaptureFee`（只写 `fee_amount` 一列）、`DISPUTE_FEE` 事实/账行（永不冲销）、`fetch_dispute_details` BT 明细+`fee_amount`、`ReconcileDispute` fee 期望 + 只读 `fee` 视图、`Disputes::PaymentDisputeSummary`（零写）、`PaymentMethod#dispute_capabilities`（基类 UNSUPPORTED）、控制台只读卡片（双语）；新增 7 个 spec 文件 + 修正 2 处字面清单断言；定向 40 例 + 争议域回归 361 例全绿 | AI |
