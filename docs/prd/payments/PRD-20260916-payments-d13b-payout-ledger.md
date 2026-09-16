# PRD-20260916-payments-d13b-payout-ledger

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D13 切片2 结算（Payout）台账 —— CSV 导入 + 交易匹配 + 差异进对账队列（业务方案 §78-D13 / §70.2） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-security`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260916-payments-d13-reconciliation-cases`（切片1：差异队列，本批差异出口）、`PRD-20260906-payments-fin-p4-5/6`（provider 财务事实与只读对账） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D13 结算台账 —— 导入 provider 结算报表明细 → 匹配 `payout ↔ 交易集合 ↔ 手续费 ↔ 退款`；状态：在途 / 已结算 / 差异；按结日与账户汇总；支持多币种与部分结算。
- **背景（代码事实）**：
  - **已有**：`Payment`（`response_code` = provider 引用）、`PaymentSession#external_id`、`Refund#transaction_id`（provider 退款单号）、`ProviderFinancialDetails`（fee/net/settlement_status 只读事实，P4-5）；D13 切片1 已交付**对账差异队列**（`ReconciliationCase` + `SyncCases` + 后台工作台）。
  - **缺口（6 层搜索）**：`Payout` / `payout` **零命中**（app / core / api / admin / platform 全层）；无结算台账、无导入、无匹配，`§70.2` 完全未落地 ⇒ 「日终可对平」缺一半（本地有账、provider 侧结算无台账）。
- **目标**：把 provider 结算报表（CSV）变成**可核对台账**：导入 → 逐行匹配本地支付/退款 → 行级状态（matched / unmatched / amount_mismatch）+ 台账状态（在途 / 已结算 / 差异）→ 差异**自动进入对账队列**（切片1）。
- **成功指标**：① 同一份报表**重复导入幂等**（不产生重复 payout/line）；② 每行匹配结果可解释（引用 + 金额差）；③ 存在差异的行 100% 出现在对账队列且可被人工处置；④ 状态/汇总（gross/fee/net、按结日）与导入行一致；⑤ **零资金副作用**。

## 2. 用户故事 / 场景

- 作为**财务运营**，我把 provider 的结算 CSV 导入系统，看到每个 payout 的**总额/手续费/净额**与逐行匹配结果。
- 作为**财务运营**，我要看到哪些行**对不上**（本地无记录 / 金额不一致），并让它们**进入对账队列**处理。
- 作为**财务主管**，我要按 provider / 状态 / 结日查看台账，判断「日终是否已对平」。
- 场景：① 导入一份报表 → 生成 payout + 行 → 自动匹配；② 重复导入同一文件 → 幂等（`lines_skipped`）；③ 某行金额与本地支付不一致 → 行 `amount_mismatch` + payout `difference` + 队列出现案例；④ 补正后重新匹配 → 行 `matched` → payout 变 `settled`/`in_transit`，队列案例**自动销案**；⑤ 导入空文件/缺列 → 返回错误且不落库。

## 3. 功能需求（FR）

- **FR-001　台账模型** —— 两张新表 + 模型：
  - `PallasTrade::Payout`：`store_id` / `provider`（api_type）/ `reference`（provider payout id）/ `status`（`in_transit` / `settled` / `difference`）/ `currency` / `gross_total` / `fee_total` / `net_total` / `period_start` / `period_end` / `settled_at` / `imported_at` / `import_source` / `metadata`；唯一键 `(store_id, provider, reference)`。
  - `PallasTrade::PayoutLine`：`payout_id` / `kind`（`charge` / `refund` / `fee` / `adjustment`）/ `provider_reference` / `gross_amount` / `fee_amount` / `net_amount` / `currency` / `match_status`（`pending` / `matched` / `unmatched` / `amount_mismatch`）/ `match_details`（jsonb：本地引用、金额对照）/ `matched_at` / `payment_id` / `refund_id` / `raw`（导入行快照）；唯一键 `(payout_id, provider_reference, kind)`。
  - 状态语义：`difference` = 任一行 `unmatched`/`amount_mismatch`；`settled` = 无差异且 `settled_at` 存在；否则 `in_transit`。
- **FR-002　CSV 导入（唯一写入口）** —— `Reconciliations::Payouts::ImportCSV.call(store:, provider:, csv:, source: nil, actor: nil)`：
  - 必需列：`payout_reference, kind, provider_reference, gross`；可选列：`fee`（默认 0）、`net`（默认 gross − fee）、`currency, arrived_on, period_start, period_end`；
  - 按 `payout_reference` 分组 → upsert payout（幂等）+ 逐行 upsert line（唯一键去重，重复行计入 `lines_skipped`）→ 由行汇总 `gross_total/fee_total/net_total`；
  - 行级错误**收集不中断**（`errors: [{row:, message:}]`）；缺列/空文件 → 失败且**不落库**；
  - 只写台账表 + 审计；**绝不**触碰 Payment/Refund/Journal/Order/库存。
- **FR-003　匹配** —— `Reconciliations::Payouts::Match.call(payout:, actor: nil)`：
  - `charge` 行 → 本地 `Payment`（`response_code`）或经 `PaymentSession#external_id` → payments；`refund` 行 → `Refund#transaction_id`；`fee`/`adjustment` 行 = provider 侧项目，直接 `matched`；
  - 找到且金额一致（±0.01）→ `matched`；找到但金额不一致 → `amount_mismatch`（记录本地金额与差值）；找不到 → `unmatched`；
  - 汇总后刷新 payout 状态（`difference` / `settled` / `in_transit`）；结果写审计。
- **FR-004　差异进队列（与切片1 打通）** —— `Reconciliations::Payouts::SyncCases.call(payout:)`：
  - 对 `unmatched` / `amount_mismatch` 行 → upsert `ReconciliationCase`（`kind: 'payout'`，`difference_type: payout_unmatched` / `payout_amount_mismatch`，`dedupe_key = "payout:<payout_id>:<provider_reference>:<signature>"`，`severity: attention`）；
  - 行已恢复 `matched` → 对应开放案例**自动销案**（`fixed` + auto）；人工判定（explained/dismissed）**不被覆盖**（沿用切片1 语义）。
- **FR-005　后台台账** —— `/admin/payouts`：index（筛选 provider/status/结日 + 汇总 gross/fee/net + 分页）+ show（payout 事实 + 行表（kind/引用/金额/匹配状态/本地引用）+ 「重新匹配」动作）；
  `/admin/payouts/new` + `POST /admin/payouts/import`（粘贴 CSV 或上传文件 → 导入结果提示：payouts/lines/errors）。
- **FR-006　权限与导航** —— `can :manage, PallasTrade::Payout`（`configuration_management`）；导航 Orders → 结算台账（position 57）；导航一致性 spec 同步。
- **FR-007　零资金副作用 + 降级** —— 导入/匹配/案例同步只写台账表 + 案例表 + 审计（spec 断言 Payment/Refund/Journal 行数与金额不变）；页面在关联缺失时降级仍 200。

## 4. 非功能需求（NFR）

- **安全**：导入与匹配写 `Audit`（actor = 后台用户/系统）；CSV 内容不落凭证；上传大小有界。
- **性能**：单 payout 匹配按 provider_reference 索引查询（每行 ≤ 常数级）；导入按行处理，10k 行内可用。
- **兼容**：新增表 + 新增页面，不改既有对账语义与 API v3 契约（零端点变更）；切片1 队列模型仅**扩枚举**（`kind: payout`、两个 difference_type），旧数据零回归。
- **范围纪律（本切片不做）**：§70.3 费率模型与成本报表、§70.4 汇率快照；provider API 自动拉取结算单（本切片仅 CSV 导入）；dispute 类结算行。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：模型口径（状态合成规则、唯一键、行汇总）正确；`difference` 由行级状态推导。
- **AC-002** ← FR-002：导入创建 payout + 行并汇总总额；同一文件重复导入**幂等**（无重复行，计入 skipped）。
- **AC-003** ← FR-002：缺列/空 CSV → 失败且不落库；行级错误被收集（不影响其他行）。
- **AC-004** ← FR-003：`charge`/`refund` 行按 provider 引用匹配本地记录；金额不一致 → `amount_mismatch`（含差值）；无记录 → `unmatched`；`fee` 行 → `matched`。
- **AC-005** ← FR-004：差异行进入对账队列（kind=payout、类型/严重级正确、dedupe 幂等）；恢复匹配 → 自动销案；人工判定不被覆盖。
- **AC-006** ← FR-005：index 筛选/汇总/分页正确；show 渲染行表与匹配状态；「重新匹配」动作刷新状态并写审计；导入表单成功/失败提示正确。
- **AC-007** ← FR-007：导入+匹配+案例同步**零资金副作用**（Payment/Refund/FinancialLedgerEntry 行数与金额不变）；无权限用户被拒。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `Payout` / `settlement` | 无命中 | ❌ 未满足 |
| Core | `pallastrade_core/app/` | `payout` / `settlement` / `import` | `ProviderFinancialDetails`（只读 fee/net/settlement_status，P4-5）、`Reconciliations::*`（只读对账 + 切片1 案例队列）、`PallasTrade::Import` / `ImportRow` / `ImportMapping` / `ImportSchema`（通用导入框架，面向商品等列映射场景）；**无 payout 台账/导入/匹配** | ⚠️ 部分（资金事实与队列已有，台账缺） |
| API | `pallastrade_api/app/` | `payout` / `imports` | 通用导入 API（`api/v3/admin/imports_controller.rb`）；**无 payout 端点** | ✅ 无需变更（本批走 admin HTML） |
| Admin | `pallastrade_admin/app/` | `payout` / `imports` | `imports_controller`（通用导入 UI）、`reconciliation_cases`（切片1 工作台）、`payments_ops` / `refunds_ops`（只读财务页范式） | ⚠️ 部分（需新增台账页 + 导入 + 重匹配动作） |
| Storefront | `storefront/src/` | — | 不涉及财务运营 | ✅ 无需变更 |
| Platform | `platform/packages/` | `payout` | 无命中 | ✅ 无需变更 |

**结论**：承载 点 = **Core**（2 表 + 3 服务：ImportCSV / Match / SyncCases + 切片1 枚举扩展）+ **Admin**（台账页 + 导入 + 重匹配 + 权限/导航）；API / Storefront / Platform ** 零改动**；复用 `Payment#response_code`、`PaymentSession#external_id`、`Refund#transaction_id` 作为匹配锚点，**不新建资金写路径**。
**不复用通用导入框架的决策**：`PallasTrade::Import` 面向「列映射到应用字段」的通用数据导入（含 mapping UI / import_row staging）；结算报表是 **provider 原样明细 + 幂等台账 + 匹配语义**，复用会引入不必要的一层且有重复幂等风险 ⇒ 本批写专用解析器；若后续多 provider 列名差异扩大，再引入 mapping 层（REQ 已记录）。

## 7. 技术影响

- **Core**：迁 移（`pallastrade_payouts`、`pallastrade_payout_lines`）；模型 `Payout` / `PayoutLine`；服务 `Reconciliations::Payouts::{ImportCSV,Match,SyncCases}`；`ReconciliationCase` 枚举与键扩展。
- **Admin**：`PayoutsController`（index/show/new/import/match）+ 3 视图 + 路由 + 导航 + 权限 + i18n（gem en + 宿主 zh-CN）。
- **数据库**：只新增表与索引。
- **测试**：模型（状态合成）、导入（幂等/错误收集）、匹配（三种结果）、队列打通（创建/销案/人工保护）、后台（筛选/动作/权限/零副作用）。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 模型 | `backend/spec/models/pallastrade/d13b_payout_spec.rb` | AC-001 |
| 服务 | `backend/spec/services/pallastrade/reconciliations/payouts/d13b_import_csv_spec.rb` | AC-002/003 |
| 服务 | `backend/spec/services/pallastrade/reconciliations/payouts/d13b_match_spec.rb` | AC-004 |
| 服务 | `backend/spec/services/pallastrade/reconciliations/payouts/d13b_sync_cases_spec.rb` | AC-005 |
| 请求 | `backend/spec/requests/pallastrade/admin/d13b_payouts_spec.rb` | AC-006/007 |
| 回归 | `finance-reconciliation-rspec` + `d13-reconciliation-cases-rspec` + 导航一致性 | 零回归 |

## 9. 收口清单

- [x] 本 PRD（approved → done）
- [x] REQ：`harness/requirements/REQ-20260916-d13b-payout-ledger.md`
- [x] gate + prep 清理（critical：恢复计划 `REC-f0267198a8f060`）
- [x] 用户确认：用户 2026-09-16「继续」（承接 §78 D13 批次）
- [x] 知识同步：`pallastrade-payments` / `pallastrade-admin` Skill + runbook + AGENTS §6 verifier 行 + 场景库 GS-145 + 业务方案 §70.2 回写

### 9.1 实施记录（2026-09-16）

| 项 | 内容 |
|---|---|
| 交付物 | 迁移（`pallastrade_payouts` / `pallastrade_payout_lines`）；模型 `Payout` / `PayoutLine`；服务 `Reconciliations::Payouts::{ImportCSV,Match,SyncCases}`；`ReconciliationCase` 枚举/键扩展（`key_for`）；后台 `PayoutsController`（index/show/new/import/match）+ 3 视图 + 路由 + 导航（position 57）+ 权限 + i18n（en/zh-CN 双份） |
| 验证器 | `npx harness verify d13b-payouts-rspec` → **52 examples, 0 failures**（模型 5 / 导入 5 / 匹配 4 / 队列 5 / 请求 6 + 导航一致性 27） |
| 决策偏差 | ① 列集合收敛为「`gross` 必填，`fee`/`net` 可缺省（net 缺省 = gross − fee）」；② 台账主键用整数 id（页内使用，不进 API 契约）；③ 列表页差异行计数用一次聚合查询（避免逐行 N+1） |
| 踩坑（已记入 repo 记忆） | ① Rails 将 `CSV` 注册为 acronym → `import_csv.rb` 必须定义 `ImportCSV`（Zeitwerk 报 `uninitialized constant …ImportCsv`）；② `PallasTrade` 命名空间内裸 `CSV::MalformedCSVError` 会解析为 `PallasTrade::CSV::…` → 统一 `::CSV`；③ 同一订单多笔 `completed` 支付受订单金额上限校验 → spec 每笔支付用独立订单 |
| 零资金副作用 | spec 断言：导入/匹配/入队前后 `Payment/Refund/Order/FinancialLedgerEntry` 行数与金额不变 |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片2：payout 台账 + CSV 导入 + 匹配 + 差异进队列；费率/成本与汇率留后续切片） |
| 1.0 | 2026-09-16 | 实施完成：52 examples 全绿；PRD → done；知识同步（Skill ×2 + runbook + AGENTS §6 + GS-145） |
