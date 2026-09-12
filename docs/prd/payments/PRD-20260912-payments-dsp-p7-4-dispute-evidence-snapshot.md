# PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot（争议证据快照）

| 元数据 | 值 |
|---|---|
| 状态 | done（2026-09-12 实施 / 验证 / 知识同步完成；已提交 `7780922b`）|
| 创建日期 | 2026-09-12 |
| 来源 | 用户指令「继续」→ 承接 DSP-P7-3 的下一切片（P7-3 PRD 已显式预留 Evidence） |
| 分类 | payments（`harness prd new` 自动判定，关键词「退款」命中） |
| 关联 Skill | `pallastrade-payments`、`pallastrade-data-model`、`pallastrade-customization`、`pallastrade-testing` |
| 关联 REQ | `REQ-20260912-dsp-p7-4-dispute-evidence-snapshot.md` |
| 关联 PRD | 源计划 `豆包梳理业务需求/P7 — Dispute & Chargeback Orchestration.md` §41/§42/§43；前置：`PRD-20260911-payments-dsp-p7-1-*`（模型+入站）、`-p7-2-*`（事实裁决）、`PRD-20260912-payments-dsp-p7-3-*`（入账+对账） |
| 需求类型 | 新功能（只读证据投影；**0 migration**、0 API/UI） |

> **切片定位（源计划 §43）**：P7 Core 第一阶段只要求 **Evidence Snapshot + Deadline + Admin visibility**。
> 本切片 = **Evidence Snapshot**（确定性只读投影）；Deadline/Sweeper = P7-5，Admin 展现 = P7-7，
> **提交证据给 provider（`submit_dispute_evidence`）明确不在本切片**（源计划列为 P7 后期能力，归 P7-8）。
> **不做**：自动提交/自动代表商户决策、`delivered_at` 推导、结构化客户沟通记录。

---

## 1. 背景与目标

- **一句话需求原文**：「继续」（承接 P7-3 交付后的下一包）。
- **背景**：
  1. **争议需要证据，但系统目前没有任何证据视图**：operator 面对 chargeback 只能手工去 Order/Shipment/Refund/账本各处翻数据；
     源计划 §66 要求 Admin 展示 Evidence Snapshot，§41 定义其内容（Order / CommerceTransaction / Payment refs / Refund history /
     Shipment+tracking+shipped_at / customer-billing-shipping / policy references）。
  2. **最容易犯的错是「伪造事实」**（源计划 §42）：系统**没有**可靠的 `delivered_at`、`proof_of_delivery`、
     结构化客户沟通记录；若把 `shipped_at` 当作「已送达」，等于在资金纠纷里提交不实证据。必须显式 `not available`。
  3. **只读投影即可满足第一阶段**：源计划 §41 明确「第一版不一定需要表」——确定性投影（可重跑、零副作用）就能服务
     P7-5 告警、P7-6 收敛判断、P7-7 展示；持久化/审计留待 Admin 切片。
  4. **前置已就绪**：P7-1 提供 dispute 主体与 provider 只读契约基座、P7-2 提供事实+确认度裁决、P7-3 提供账本与只读对账，
     本切片只是**把既有事实投影成一张可审阅的证据卡**，不引入新的资金语义。
- **目标**：
  1. 落地 `Disputes::EvidenceSnapshot`（transient 只读 VO）+ `Disputes::BuildEvidenceSnapshot.call(dispute:, fetch: false)`：
     分段（order / transaction / payment / refunds / fulfillment / customer_communication / policy / provider / journal / reconciliation），
     **每段显式携带 `availability` + `reason`（封闭枚举）**，不可得即 `not_available`，**绝不推导**。
  2. `missing_evidence[]`（封闭枚举）供 P7-5 告警 / P7-7 展示 / P7-6 收敛输入；`submission_ready?` 恒为 `false`（本切片不提交）。
  3. **零写、默认零 provider 网络 I/O**（`fetch: true` 且 capability 存在时才取只读快照；不可用 → `unsupported`/`unavailable`，不猜）。
  4. 不触碰任何状态机与资金链路；无 migration / API / UI。
- **成功指标**（可验证）：
  1. 给定订单+发货+退款齐全的争议 → 各段 `available` 且字段与源记录**逐字段一致**（断言）；
  2. `delivered_at` **恒** `not_available`，且 `shipped_at` 存在时**不产生**任何「已送达」推断（显式断言）；
  3. 调用前后相关表**行数与属性零变化**（只读快照断言）；
  4. provider 段在无 capability 时**不发任何网络请求**（零调用断言），有 capability 时归一字段正确；
  5. 回归：P7-1/2/3 + FIN-P4 全量 specs 全绿；`generated:check` / `doc-impact` 通过。

## 2. 用户故事 / 场景

- 作为**运营/风控**：我希望一键看到这笔争议「我们手里到底有什么证据」，以便在截止前决定是否应诉，而不是四处翻数据。
- 作为**财务**：我希望证据卡直接带上资金事实（账本行 + 对账结论 + 退款重叠），避免把「退款」和「争议扣款」混为一谈。
- 作为**工程**：我希望证据的缺失是**显式枚举**而不是「查不到就是空」，避免在资金纠纷里提交不实材料。

| # | 场景 | 类型 | 描述 |
|---|---|---|---|
| S1 | 证据齐全的正常单 | 正常 | 已发货（有 tracking + shipped_at）+ 有交易/支付/订单 → 相应段 available |
| S2 | 未发货/无单号 | 边界 | fulfillment 段 available 但 `TRACKING_MISSING` / `SHIPPED_AT_MISSING` 进 missing_evidence |
| S3 | 送达证明 | **不变式** | `delivered_at` 恒 `not_available`（`not_recorded`）；**禁止**由 `shipped_at` 推导 |
| S4 | 客户沟通 | 不变式 | `customer_communication` 恒 `not_available`（系统无结构化记录） |
| S5 | provider 无能力 | 异常 | Adyen/PayPal 等无 `fetch_dispute_details` → provider 段 `unsupported` + reason，**零网络调用** |
| S6 | provider 故障 | 异常 | 有契约但调用失败 → `unavailable` + reason（**不猜**、不阻断其他段） |
| S7 | 无订单/无支付锚点 | 异常 | 各段 `not_available` + 明确 reason；不炸、不臆造 |
| S8 | 部分退款重叠 | 边界 | refunds 段含历史与合计；重叠检测结果进 missing_evidence/标记（供人工判断） |
| S9 | 只读复跑 | 边界 | 连续两次构建，除 `generated_at` 外输出一致；DB 零变化 |
| S10 | PII 保护 | 安全 | 日志/错误不回显邮箱、地址等 PII（仅 ids + 段名 + reason） |

## 3. 功能需求（FR）

- **FR-P74-01**：新增 `PallasTrade::Disputes::EvidenceSnapshot`（transient 不可变 VO，白名单属性，超集键报错）：
  `dispute_id` / `fact_type` / `fact_status` / `resolution` / `sections` / `missing_evidence` / `submission_ready` /
  `generated_at` / `source`；常量 `SECTIONS`、`AVAILABILITIES = %w[available not_available]`、`MISSING_REASONS`（封闭枚举）。
- **FR-P74-02**：新增 `PallasTrade::Disputes::BuildEvidenceSnapshot.call(dispute:, fetch: false)`（只读编排）：
  复用 P7-2 `Disputes::ResolveFact`（事实/确认度/裁决）与 P7-3 账本/对账读取；返回 `ServiceModule::Result`；
  **零写**（不落库、不改状态）。
- **FR-P74-03**：`order` 段：number、email、currency、total、completed_at、billing/shipping 地址摘要（country/state/city/zip/name）。
- **FR-P74-04**：`transaction` 段：`commerce_transaction` 的 prefixed id、amount、currency、state、created_at。
- **FR-P74-05**：`payment` 段：payment prefixed id、`provider_payment_reference`、`provider_charge_reference`、金额、币种、状态。
- **FR-P74-06**：`refunds` 段：退款列表（prefixed id、金额、币种、状态、provider ref、时间）+ `total`；
  以及 `overlap`（是否存在与争议金额相关的退款）标记（只描述事实，不判断法律后果）。
- **FR-P74-07**：`fulfillment` 段：shipments（number、state、tracking、carrier 若有、`shipped_at`、`fulfilled_at`）；
  **`delivered_at` 恒为 `not_available`（reason `not_recorded`）**，且**禁止**由 `shipped_at` 推导（源计划 §42）。
- **FR-P74-08**：`customer_communication` 段：恒 `not_available`（reason `not_recorded`）——系统无结构化沟通记录，不臆造。
- **FR-P74-09**：`policy_references` 段：系统**无结构化政策文档模型** → 恒 `not_available`（reason `not_recorded`），仅附 `store_url` 供人工参考（不复制法律文本、不伪造政策链接）。
- **FR-P74-10**：`provider` 段：仅当 `fetch: true` **且** `fetch_dispute_details` capability 存在（**类级**判定：`payment_method.class.instance_method(...).owner != PaymentMethod`，
  避免 RSpec 实例打桩把 stub 误当成「已实现契约」）时取只读快照并归一
  （provider_status / amount / currency / reason / network_reason_code / evidence_due_at / evidence_submitted_at / has_evidence）；
  否则 `not_available` + reason（`not_requested`（未申请取数）/ `not_supported` / `provider_unavailable` / `unlinked_payment`）——**默认路径零网络 I/O**。
- **FR-P74-11**：`journal` 段：该 dispute 的账行摘要（entry_type / amount / state / effective_at / provider_reference）。
- **FR-P74-12**：`reconciliation` 段：复用 `Reconciliations::ReconcileDispute` 的 `classification` + `reasons`（只读；不重复实现）。
- **FR-P74-13**：`missing_evidence[]` 封闭枚举（如 `PROOF_OF_DELIVERY_NOT_AVAILABLE`、`CUSTOMER_COMMUNICATION_NOT_RECORDED`、
  `TRACKING_MISSING`、`SHIPPED_AT_MISSING`、`PROVIDER_SNAPSHOT_UNSUPPORTED`、`PROVIDER_SNAPSHOT_UNAVAILABLE`、
  `ORDER_MISSING`、`PAYMENT_ANCHOR_MISSING`、`JOURNAL_MISSING`、`REFUND_OVERLAP_PRESENT`）。
- **FR-P74-14**：`submission_ready` **恒为 `false`**，并在 VO 注释与本 PRD 注明：本切片**不提交**任何证据给 provider
  （源计划 §43/§67：Submit Evidence 属危险操作，归 P7-8 且必须 permission + confirmation + audit）。
- **FR-P74-15**：边界——无 migration、无 API/UI、无自动决策（不自动接受争议、不自动退款、不自动提交）、
  不改 P7-1/2/3 任何既有行为（除只读调用）。
- **FR-P74-16**：日志/错误处理**不回显 PII**：仅 `dispute_id` + 段名 + reason（email/地址只在 VO 内返回，不进日志）。

## 4. 非功能需求（NFR）

- **只读/确定性**：零写；同输入同输出（`generated_at` 除外）；可安全重跑。
- **零隐式 I/O**：默认不触网；`fetch: true` 才取 provider 只读快照，且失败降级为显式 reason。
- **不猜（FIN-INV-09 精神）**：任何缺失/不可得一律 `not_available` + 封闭 reason，禁止默认值填充或推导。
- **PII**：VO 内携带必要字段（业务需要），但**日志、错误、metrics 不含 PII**。
- **性能**：固定查询数（按段一次性取数，无 N+1）；单 dispute 构建为常数级查询。
- **兼容**：无 schema/API/SDK 变更 → `generated:check` 无差异；不触碰 P7-1/2/3 行为。

## 5. 验收标准（AC，与测试一一映射）

- **AC-P74-01 ← FR-P74-03/04/05/06/11/12**：订单+支付+退款+账行齐全时，各段 `available`，字段与源记录**逐字段一致**。
- **AC-P74-02 ← FR-P74-07**：`delivered_at` 恒 `not_available`（reason `not_recorded`）；`shipped_at` 存在时输出中**不存在**任何
  表示「已送达」的字段/值（禁推导，源计划 §42）。
- **AC-P74-03 ← FR-P74-08**：`customer_communication` 恒 `not_available`（reason `not_recorded`）。
- **AC-P74-04 ← FR-P74-10**：无 capability 时 provider 段 `not_available` + `PROVIDER_SNAPSHOT_UNSUPPORTED`，且
  **断言零 provider 调用**（对 payment_method 打桩并断言未收到调用）；有 capability 时归一字段正确。
- **AC-P74-05 ← FR-P74-10/13**：provider 契约抛错 → `unavailable` + `PROVIDER_SNAPSHOT_UNAVAILABLE`，**不阻断**其他段。
- **AC-P74-06 ← FR-P74-13**：missing_evidence 分类正确（无 tracking → `TRACKING_MISSING`；无 shipped_at → `SHIPPED_AT_MISSING`；
  无送达证明 → `PROOF_OF_DELIVERY_NOT_AVAILABLE`；退款重叠 → `REFUND_OVERLAP_PRESENT`）。
- **AC-P74-07 ← FR-P74-15**：只读断言——调用前后 Dispute/Payment/Order/Refund/FinancialLedgerEntry 行数与属性零变化。
- **AC-P74-08 ← FR-P74-02/15**：无 order / 无 payment 锚点 → 对应段 `not_available` + reason（`ORDER_MISSING` /
  `PAYMENT_ANCHOR_MISSING`），构建成功不抛错。
- **AC-P74-09 ← FR-P74-01**：VO 不可变（frozen）、白名单校验（未知键 → ArgumentError）。
- **AC-P74-10 ← FR-P74-16**：日志断言——构建过程中 logger 收到的消息**不含** email/地址等 PII（只含 ids/段名/reason）。
- **AC-P74-11 ← FR-P74-14**：`submission_ready == false`（恒），且代码中**不存在**任何对 provider 的写/提交调用。
- **AC-P74-12 ← FR-P74-15**：回归——P7-1/2/3 + FIN-P4 specs 全绿、无既有断言修改（除新增用例文件）。

## 6. 跨层搜索记录（6 层，gate 强制）

关键词：`evidence` / `snapshot` / `proof_of_delivery` / `delivered_at` / `shipment` / `tracking` / `Dispute`

| 层 | 路径 | 找到的文件 | 是否满足需求 |
|---|---|---|---|
| App | `backend/app/` | 无命中（争议域能力全在 core gem） | ❌ 无既有能力 → 在 core gem 新增（AGENTS §3 第 8 级，`# PALLAS-CUSTOM`） |
| Core | `pallastrade_core/app/` | `services/pallastrade/disputes/{dispute_fact,resolve_fact,handle_provider_event,provider_payload}.rb`、`models/pallastrade/{dispute,financial_ledger_entry}.rb`、`services/pallastrade/reconciliations/reconcile_dispute.rb`、`services/pallastrade/financial_ledger/post_dispute.rb` | ⚠️ 事实/账本/对账已有可复用只读输入；**证据投影不存在** → 本切片补 |
| API | `pallastrade_api/app/` | 无 dispute/evidence 命中 | ❌ 本切片无 API 变更（展现归 P7-7） |
| Admin | `pallastrade_admin/app/` | 无 dispute 命中 | ❌ 本切片无 Admin UI（归 P7-7） |
| Storefront | `storefront/src/` | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | 无命中（仅支付集成文档文本） | ❌ 无 SDK 变更 |

**结论**：6 层均无证据快照能力 → 新增；可复用只读输入 = P7-2 事实裁决 + P7-3 账行/对账 + 既有 Order/Shipment/Refund 模型；
落点 `pallastrade_core`（框架自研产品线，第 8 级 + `# PALLAS-CUSTOM` 注释）。

## 7. 技术影响

- **代码**：core gem 新增 2 文件（VO + service）+ specs；无 migration、无 API/UI、无 subscriber/事件。
- **数据**：零写；不新增表（源计划 §41「第一版不一定需要表」）。
- **兼容**：不改 P7-1/2/3 行为；仅只读调用既有服务。
- **回滚**：纯新增服务，删除即回滚（无 schema/数据影响）。
- **风险**：①把不可得证据「填默认值」（AC-P74-02/03 兜住）；②意外触网（AC-P74-04 零调用断言兜住）；
  ③PII 进日志（AC-P74-10 兜住）；④跨模型 N+1（性能断言：常数级查询）。

## 8. 测试计划（AC ↔ 测试文件）

| AC | 测试文件（新增） | 类型 |
|---|---|---|
| AC-P74-01/06/08/09/11 | `backend/spec/services/pallastrade/disputes/build_evidence_snapshot_spec.rb` | 服务/单元 |
| AC-P74-02/03/07/10 | 同上（禁推导 / 恒 not_available / 只读 / PII 日志断言） | 服务/单元 |
| AC-P74-04/05 | 同上（provider capability 打桩 + 零调用断言 + 故障降级） | 服务/单元 |
| AC-P74-12 | P7-1/2/3 + FIN-P4 既有 specs 全量回归 | 回归 |

命令：`docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec <files>"`。

## 9. 文档同步清单（实施后必做）

| 资产 | 计划 |
|---|---|
| `ai/skills/pallastrade-payments/SKILL.md` | 新增 DSP-P7-4 段（证据快照分段/可得性枚举/禁推导铁律/零触网/submission 边界） |
| `harness/scenarios/scenarios.json` | 新增 GS 场景（证据快照「不伪造」不变式 + 零 provider I/O） |
| `docs/prd/README.md` | 登记本 PRD 索引行 |
| `ai/skills/pallastrade-data-model/SKILL.md` | 评估后不更新（无 schema 变更） |
| API 文档 / SDK | 评估后不更新（`generated:check` 应无差异） |

## 10. 变更记录

| 日期 | 变更 | 说明 |
|---|---|---|
| 2026-09-12 | 创建（draft） | 承接 P7-3 预留的 Evidence 切片；源计划 §41/§42/§43；待用户确认后实施 |
| 2026-09-12 | draft → approved | 用户问答工具选择『确认实施 P7-4』；批准证据已记录；Gate `GATE-2026-09-12T12-40-37` preparation 已清 |
| 2026-09-12 | 实施（待验证） | 新增 `Disputes::EvidenceSnapshot`（VO）+ `Disputes::BuildEvidenceSnapshot`（只读投影）+ 12 例 spec（全绿）；rubocop 干净。实现注释：①policy 段实现为恒 `not_recorded` + `store_url` 参考（FR-P74-09 已同步）；②capability 判定改为**类级**（`class.instance_method.owner`）——实例级会被 RSpec 打桩干扰（`expect(pm).not_to receive(...)` 会把方法装到 singleton 上 → 误判为「实现了契约」），这一坑由 AC-P74-04 用例暴露；③provider 段新增 `not_requested` 原因（默认不取数 ≠ 不支持）。 |
| 2026-09-12 | 验证完成 → done | 注册 verifier `backend-rspec` 全量套件绿（EVD-20260912134552-26c8cdd131）；定向 12 examples / 0 failures；rubocop 3 文件 0 违规；`eval-ai --scenarios` 96/96（新增 GS-095）、`--check-freshness` 0 error、`doc-impact` synced、`generated:check` 无漂移；Gate `GATE-2026-09-12T12-40-37` 已关闭，已提交推送 `7780922b` |
