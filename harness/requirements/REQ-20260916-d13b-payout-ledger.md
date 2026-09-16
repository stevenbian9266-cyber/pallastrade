# REQ-20260916-d13b-payout-ledger

| 项 | 值 |
|---|---|
| 任务 | D13 切片2 结算（Payout）台账（业务方案 §78-D13 / §70.2） |
| PRD | `docs/prd/payments/PRD-20260916-payments-d13b-payout-ledger.md` |
| 类型 | feature（critical 风险：涉及资金对账语义 → 需恢复计划 + test/review/approval/knowledge 四类证据） |
| 用户确认 | 用户 2026-09-16「继续」（承接 §78 D13 批次） |
| 恢复计划 | `REC-f0267198a8f060`（manual-only） |

## 6 层跨层搜索结果（gate 强制）

| 层 | 路径 | 关键词 | 结果 | 满足 |
|---|---|---|---|---|
| App | `backend/app/` | `Payout`/`settlement` | 无命中 | ❌ |
| Core | `pallastrade_core/app/` | `payout`/`settlement`/`import` | `ProviderFinancialDetails`（只读 fee/net/settlement_status）、`Reconciliations::*`（只读 + 切片1 队列）、`PallasTrade::Import/ImportRow/ImportMapping/ImportSchema`（通用列映射导入） | ⚠️ 部分 |
| API | `pallastrade_api/app/` | `payout`/`imports` | 通用导入 API；无 payout 端点 | ✅ 无需变更 |
| Admin | `pallastrade_admin/app/` | `payout`/imports | `imports_controller`、`reconciliation_cases`（切片1）、`payments_ops`/`refunds_ops` | ⚠️ 部分 |
| Storefront | `storefront/src/` | — | 不涉及 | ✅ |
| Platform | `platform/packages/` | `payout` | 无命中 | ✅ |

## Skill Consultation Evidence Table（gate 强制，真实结论）

| Skill | 关键结论（本批采用） |
|---|---|
| `pallastrade-payments` | 资金事实边界：对账/台账**只读或只写自己的台账**，绝不触发资金动作（P4 §44/§46）；provider 引用锚点 = `Payment#response_code` / `PaymentSession#external_id` / `Refund#transaction_id`；settlement 语义已存在于 `ProviderFinancialDetails.settlement_status`（只读事实），台账是**新的一层**而非改写它 |
| `pallastrade-admin` | 财务 ops 页范式（BaseController + 筛选 + `safe_value` 降级 + `audit_actor`）；导航项需同步 `navigation_consistency_spec.rb`；admin 路径参数 prefixed_id（本批台账主键用整数 id，页面内部使用） |
| `pallastrade-data-model` | 新表必须带 `store_id` + 唯一键（`(store_id, provider, reference)` / `(payout_id, provider_reference, kind)`）+ 索引（status/结日）；jsonb 存快照；迁移只建表不回填 |
| `pallastrade-security` | 导入 = 财务敏感写：`authorize! :update` + 审计（actor + 文件来源）；CSV 不落凭证；行级错误回显不泄露内部数据 |
| `pallastrade-testing` | 验证器登记 + 幂等/错误路径/零副作用/权限覆盖；spec 环境无关 |

## 设计要点（实施依据）

1. **唯一写入口**：导入 `Reconciliations::Payouts::ImportCSV`、匹配 `…::Match`、差异出队 `…::SyncCases`；控制器只调服务。
2. **幂等键**：payout `(store_id, provider, reference)`；line `(payout_id, provider_reference, kind)`；案例 `payout:<payout_id>:<provider_reference>:<signature>`。
3. **状态合成**（唯一权威，模型方法）：`difference` 优先（任一行 unmatched/amount_mismatch）→ `settled`（无差异且有 settled_at）→ `in_transit`。
4. **匹配锚点顺序**（禁止散落判断）：`charge` → `Payment.response_code` → `PaymentSession.external_id` → payments；`refund` → `Refund.transaction_id`；`fee`/`adjustment` → 直接 matched（provider 侧项目）。
5. **金额比较**：`(local - line).abs <= 0.01` 视为一致；差值写入 `match_details['difference']`。
6. **与切片1 打通**：扩展 `ReconciliationCase`（`kind: 'payout'`、difference types `payout_unmatched`/`payout_amount_mismatch`、key 前缀可配）；自动销案/人工判定保护沿用切片1 语义。
7. **不复用通用导入框架**：`PallasTrade::Import` 面向列映射场景；结算报表需要 provider 原样明细 + 幂等 + 匹配语义 ⇒ 专用解析器（后续多 provider 列名差异扩大时再引入 mapping 层）。
8. **零资金副作用**：只写 `pallastrade_payouts*` + `pallastrade_reconciliation_cases*` + `AuditLog`。

## 切片拆分

- 切片 2（本批）：台账模型 + CSV 导入 + 匹配 + 差异进队列 + 后台（列表/详情/导入/重匹配）。
- 后续：§70.3 费率模型与成本报表、§70.4 汇率快照、provider API 自动拉取结算单、dispute 类结算行。

## 实施记录（收口时补全）

| 项 | 内容 |
|---|---|
| 改动清单 | **Core**：`db/migrate/20260916180000_create_pallastrade_payouts.rb`；`pallastrade_core/app/models/pallastrade/{payout,payout_line}.rb`；`…/reconciliations/payouts/{import_csv,match,sync_cases}.rb`；`reconciliation_case.rb`（KINDS/DIFFERENCE_TYPES/REASON_DIFFERENCE_TYPES/KEY_PREFIXES/`key_for`）。**Admin**：`payouts_controller.rb` + `views/…/payouts/{index,show,new}.html.erb` + `config/routes.rb` + `pallastrade_admin_navigation.rb` + `configuration_management.rb`（权限）+ `locales/en.yml` + 宿主 `config/locales/admin_payouts.zh-CN.yml`。**测试**：5 个 spec 文件 + `navigation_consistency_spec.rb` 断言扩展 |
| 验证器 | `harness.config.mjs` 登记 `d13b-payouts-rspec`；实测 **52 examples, 0 failures** |
| 用例分布 | 模型 5（状态合成/汇总/唯一键/筛选/容差）、导入 5（分组建批次/幂等/行级错误/拒绝路径/零副作用）、匹配 4（response_code/会话 external_id/refund/容差与幂等/零副作用）、队列 5（入队/类型映射/自动销案+人工保护/签名取代/零副作用）、请求 6（筛选汇总/详情/粘贴导入+自动匹配/上传+重匹配/失败回显/权限拒绝） |
| 偏差 | ① FR-002 列集合收敛（gross 必需，fee/net 可缺省）；② 台账页用整数 id（不进 API）；③ 列表差异计数用聚合查询避免 N+1 |
| 踩坑 | Zeitwerk acronym：`import_csv.rb` 必须定义 `ImportCSV`；`PallasTrade` 内裸 `CSV::…` 需写 `::CSV`；spec 中同一订单多笔 completed 支付触发订单上限校验 → 每笔支付独立订单。均已写入 repo 记忆 |
