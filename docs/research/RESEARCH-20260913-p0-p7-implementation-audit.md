# RESEARCH-20260913 — P0–P7 实现审计报告

| 元数据 | 值 |
|---|---|
| 审计对象 | 源规格 `豆包梳理业务需求/` 的 **P0 / P2 / P3 / P4 / P5 / P6 / P7** 七条线（及其旁线：checkout / promotions / admin / catalog / infra） |
| 审计日期 | 2026-09-13 |
| 审计类型 | 审计（`TASK-20260913083052-54a7e245` / gate `GATE-2026-09-13T08-30-58`） |
| 审计范围 | ① 规格↔PRD↔代码工件存在性；② 治理状态与证据链；③ 测试规模；④ 部署事实；**不含**逐条 AC 复算与逐章节规格覆盖率证明（见 §6 未覆盖项） |
| 结论摘要 | **实现面显著领先于治理面**：P0/P4/P6/P7 已交付并收口；**P2 全线与 P3 的 PRD 未收口（approved/draft）但代码已落地**；另发现 **README 索引与 PRD 文件状态漂移** 2 处 |
| 总体评级 | 实现：**B+**（可运行、有测试、已上线 dev）／治理：**C+**（113 个 PRD 中 28 个未 done，且存在状态漂移） |

---

## 1. 审计方法（可复现）

| 证据源 | 命令/位置 | 结果 |
|---|---|---|
| PRD 全景 | `docs/prd/README.md` 状态列聚合 | **113 个 PRD**：done 85 / approved 18 / draft 6 / reviewing 2 / implementing 1 / merged 1 |
| PRD 分类 | 同上（分类列） | payments 47 · checkout 13 · admin 11 · promotions 10 · storefront 8 · catalog 6 · other 6 · shipping 3 · infra 3 · api 3 · harness 3 |
| 源规格范围 | `豆包梳理业务需求/*.md` 一二级标题计数 | P0=47 · P2=108 · P3=122 · P4=130 · P5=73 · P6=151 · P7=149 章节；旁线 `promotion模块架构`=174、`Checkout Domain Consolidation`=64、`多市场架构升级`=86 |
| 代码工件 | `backend/pallastrade_gems/pallastrade_core/app/{models,services}/**` | 见 §3 各线矩阵 |
| 测试规模 | `backend/spec/**` 关键词计数 | dispute 30 · financial/ledger 36 · promotion 26 · refund 23 · txn 21 · inventory 12（文件数） |
| 全量回归 | 注册验证器 `backend-rspec` | **1661 examples / 0 failures / 6 pending**（2026-09-13，`EVD-20260913071415-e7c36f0977`，Line 75.7% / Branch 42.53%） |
| 流水线 | GitHub Actions（commit `81aaf582`） | AI CI ✅ · Monorepo Contract ✅ · Deploy ✅ · Backend CI ✅ |
| 部署事实 | 阿里云 dev 栈 `pull-deploy` | `state=81aaf582`；容器内 dispute 域文件与常量已就位；线上 `/admin/disputes` → 302 |

---

## 2. 关键发现（按严重度）

### F1 — 【高】P2 线「实现完成、治理未收口」
- 代码证据：`services/pallastrade/transactions/` **8 个服务**（`start` `resume` `on_payment_success` `finalize` `recover` `payment_fact_resolver` `inventory_fact_resolver` `reserve_inventory`）+ `models/pallastrade/commerce_transaction.rb` + 21 个 spec 文件。
- 治理证据：`TXN-P2-1 … P2-7` 与 `txn-p2-closure-report` 的 PRD 状态**全部为 `approved`**（直接读文件头确认：p2-3/p2-4/p2-5/p2-6）。
- 影响：无法从文档判断 P2 究竟「已验收」还是「仅实现未验证」；P3/P4/P6/P7 的许多设计前提（Consumption、Fact Resolver、Finalization boundary）都以 P2 为上游。

### F2 — 【高】P3 线 PRD 停在 `draft`，但实体已存在
- 代码证据：`models/pallastrade/stock_reservation.rb` 存在；`transactions/reserve_inventory.rb`、`transactions/inventory_fact_resolver.rb` 存在；inventory 域 12 个 spec。
- 治理证据：`PRD-20260905-shipping-库存事务集成与预留生命周期-p3-…` = **draft**。
- 影响：P3 是「库存与交易解耦」的关键语义层，长期 draft 会让后续线（P6/P7 的退货、库存隔离）失去权威依据。

### F3 — 【中】README 索引与 PRD 文件**状态漂移**（治理一致性缺陷）
| PRD | 索引状态 | 文件头状态 |
|---|---|---|
| `PRD-20260902-payments-payment-p0-foundation-hardening-…` | done | **approved** |
| `PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting` | done | **approved** |
- 影响：索引是"唯一状态入口"，漂移会让任何依赖索引的统计/门禁得出错误结论（本次审计即为实证）。

### F4 — 【中】P5 与 admin / checkout 旁线存在未收口 PRD
- `PRD-20260906-admin-core-p5-8-operational-hardening…` = approved（P5 线唯一未 done）。
- checkout 线 3 个：`订单流程标准电商改造` / `订单模块（多笔组合支付）` / `下单链路规范化统一化` 全为 approved。
- admin 线：多店铺管理（draft）、菜单配置收敛（draft）、后台可视化菜单配置（reviewing）、移除 integrations 菜单（draft）等。
- 影响：P5 目标是「Commerce Core 收敛 + Legacy 退场」，P5-8 的运营加固（Legacy 路径使用计数、指标埋点）未收口意味着 **legacy 退场缺少量化依据**。

### F5 — 【中】单环境风险（dev-only）
- 仓库策略：仅 `dev` 分支、无 `main`、无 prod 服务器；所有"已上线"= **dev 环境验证**。
- 影响：审计只能证明"dev 可运行 + CI 绿"，**无法证明**生产级 SLA、容量、回滚演练与数据修复流程。P0/P4/P6/P7 的账本与资金路径尤其需要一次"回滚演练 + 对账修复演练"才能算完整。

### F6 — 【低-中】实现速率 > 收口速率（系统性债务）
- 数据：113 个 PRD 中 **28 个未 done（24.8%）**；而代码工件与服务几乎全部落地（见 §3）。
- 推断：团队把 PRD 当作"施工许可"，施工完成后未回写状态与 §10 证据（P7 线今天的实践恰恰相反，可作为模板）。

### F7 — 【低】已明确挂起的实现项（非缺陷，需备案）
- P7 §68 的 **Adyen / PayPal 适配**：缺 sandbox 凭据 + provider contract + 真实 E2E（用户 2026-09-13 明确暂不处理）。
- P7 §68 其余候选（pre-arbitration / arbitration、争议网络费语义、reason-code 证据策略层）：边界未定。
- P5-8 的 Legacy 使用计数与运营指标埋点：未收口。

---

## 3. 逐线矩阵

| 线 | 源规格 | 实现证据（代表工件） | 测试 | 治理状态 | 部署 | 结论 |
|---|---|---|---|---|---|---|
| **P0** 支付基础加固 | `P0任务.md`（47 章：安全网 / FK / Webhook Store+Retry / Express 幂等 / 金额权威 / Secret 加密 / Contract-Error-Trace-Audit / Legacy Guardrail） | `payments/handle_webhook.rb`、`webhook_event_store.rb`、`replay_webhook_event.rb`、`gateway_preferences_encryption`、`audit`、`error_codes` | payments 域内多 spec（含 `p0-payment-rspec` 验证器集） | PRD 索引 done（文件头 approved → F3） | dev ✅ | **已交付**，需修状态漂移 |
| **P2** 交易编排与恢复 | `P2 — Commerce Transaction Orchestration & Recovery.md`（108 章） | `commerce_transaction.rb` + `transactions/{start,resume,on_payment_success,finalize,recover,*_fact_resolver,reserve_inventory}` | 21 spec 文件 | **approved（全部）** → F1 | dev ✅ | **实现可疑为完成，治理未收口** |
| **P3** 库存事务集成 | `P3 — Inventory Transaction Integration & Reservation Lifecycle.md`（122 章） | `stock_reservation.rb`、`reserve_inventory.rb`、`inventory_fact_resolver.rb`、迁移 `pallastrade_stock_reservations` | 12 spec 文件 | **draft** → F2 | dev ✅ | **实现存在，规格未收口** |
| **P4** 资金账本与对账 | `P4 — Transaction Financial Ledger & PSP Reconciliation Foundation.md`（130 章） | `financial_fact.rb`、`financial_ledger_entry.rb`、`financial_ledger/*`（9）、`reconciliations/*`（7，含 payment/refund/transaction/dispute） | 36 spec 文件 | FIN-P4-1…4-8 **全部 done** ✅ | dev ✅ | **交付完整**（本审计确认为标杆线） |
| **P5** 核心收敛与 Legacy 退场 | `P5 — Commerce Core Consolidation & Legacy Convergence.md`（73 章） | CORE-P5-0 审计（`docs/research/RESEARCH-20260906-p5-0-…`）+ 导航单一布局/tabs、admin 收敛产物 | admin 域 spec | P5-1..P5-7 done；**P5-8 approved** | dev ✅ | **基本交付**，Legacy 量化收尾缺失 |
| **P6** 退款 / 取消 / 争议 | `P6 — Refund, Cancellation & Dispute Orchestration.md`（151 章） | `refunds/{request,execute,recover,manual_retry,mark_manual_review,orphan_pairing,backfill_provider_refund}` + `reconcile_refund` + 取消编排 | 23 spec 文件 | REV-P6-1..6-8d 多数 done；**rev-p6-7 状态漂移** | dev ✅ | **交付完整**（争议部分由 P7 线承接并已 done） |
| **P7** 争议与拒付 | `P7 — Dispute & Chargeback Orchestration.md`（149 章） | `dispute.rb`、`dispute_evidence_submission.rb`、`disputes/*`（15 服务）、`disputes_ops` 控制台 | 30 spec 文件 | **P7-0…P7-9 全部 done** ✅（含今日 P7-9） | dev ✅（`state=81aaf582`，容器/线上核验） | **交付完整 + 治理完整**（本轮即为范例） |
| 旁线 checkout | `Checkout Domain Consolidation.md`（64）+ 订单/链路 PRD | checkout 域 13 个 PRD 相关工件 | checkout spec 集 | 3 个 approved → F4 | dev ✅ | 部分未收口 |
| 旁线 promotions | `promotion模块架构.md`（174） | promotions 域工件 + 26 spec 文件 | promotions 批次日志（`pallastrade-promotion-batches`） | 10 个 PRD 全 done ✅ | dev ✅ | **交付完整** |
| 旁线 admin / storefront / infra | 多份 PRD | 导航重构、品牌资产、OSS cache-control 等 | 相应 spec | 混合（draft/reviewing/approved/merged） | dev ✅ | 收口不全 |

---

## 4. 治理与证据链评价

**做得好的（可复用）**
1. **gate + 证据链闭环**：`harness gate`（6 层搜索 / Skill 咨询 / 用户确认）、四类证据（test/review/approval/knowledge）、critical 任务的恢复计划、`evidence verify` 与 staged-tree 绑定，实际拦下过"未验证即提交"。
2. **CI 与部署**：四件套 workflow + 服务器拉取式部署 + smoke 校验；今日 P7-9 的 `state=81aaf582` 可直接从 state 文件核对。
3. **知识同步**：29 个 Skill + `doc-impact` + `sync-check` + 场景库（103 个 GS 场景）——本次审计中 `doc-impact`/`generated:check`/freshness 均为 0 漂移。
4. **反模式机器执行**：`anti-patterns.json`（AP-009a/b 降级循环、AP-010 资金副作用等）在 CI 与 pre-commit 双层拦截。

**薄弱点**
1. **状态漂移与未收口**（F1/F2/F3/F4）：PRD 状态未被门禁强制与代码事实对齐——建议在 `harness` 增加"PRD 状态一致性检查"（索引 vs 文件头 vs 代码存在性）。
2. **缺少"规格覆盖率"证据**：本审计只能证明"工件存在 + 测试通过"，不能证明源规格 149/130/122 章节逐条落地（无章节↔AC↔测试三级映射台账）。
3. **单环境**（F5）：无 prod，无回滚演练记录。
4. **provider 依赖项**（F7）：Adyen/PayPal 与若干 provider 事实（O 项）仍受凭据/环境限制。

---

## 5. 建议行动（按优先级）

| 优先级 | 行动 | 产出 | 预估 |
|---|---|---|---|
| P0 | **状态漂移修复**：修正 README 索引与 2 处文件头（P0-foundation、rev-p6-7），并在 harness 增加一致性检查（`prd verify --status-drift`） | docs + harness 能力 | 0.5 天 |
| P0 | **P2 线收口评审**：对 TXN-P2-1…P2-7 逐条确认「实现/验证/上线」，补 §10 交付记录并置 done（或明确降级为"部分实现"） | 7 个 PRD 状态 + 证据 | 1–2 天 |
| P1 | **P3 线收口**：把 draft PRD 提升为 approved 或补做缺失实现（Reservation lifecycle 与 P2 的 Consumption 契约） | PRD + 可能的补做 | 1–3 天 |
| P1 | **P5-8 运营加固**：Legacy 路径使用计数与指标埋点（退场量化依据） | PRD 收口 + 代码 | 1–2 天 |
| P2 | **规格覆盖率台账**：为 P2/P3/P4/P5/P6 各生成"章节 → PRD → AC → 测试文件"映射表（可脚本化生成初稿） | `docs/research/*-coverage-matrix.md` | 2–3 天 |
| P2 | **回滚与修复演练**：以 dev 为靶场，演练一次"账本冲销 + 对账修复 + 争议收敛"闭环，记录到 `docs/operations/` | 演练报告 | 0.5 天 |
| P3 | **provider 扩展**：申请 Adyen/PayPal sandbox 凭据后续做 §68 | PRD + 适配器 | 待凭据 |

---

## 6. 未覆盖项（明确声明，避免过度解读）

1. 未做**逐 AC 复算**：本报告核查"工件/测试/证据/部署"，未逐条重放历史 AC（P4/P6/P7 的 AC 数量级为数十条/线）。
2. 未做**逐章节规格覆盖率证明**：P2=108、P3=122、P4=130、P6=151、P7=149 章节与实现的三级映射缺失（见建议 P2-①）。
3. 未审计**前端/Storefront 侧**的 P2-P6 相关 UI（storefront checkout 迁移 PRD 仍 approved）。
4. 未核验**历史数据一致性**（如 legacy 回填的正确性），仅核验其代码与测试存在。
5. 未覆盖**旁线 PRD**（catalog 产品评论、邮件自动化、多市场架构升级 V1.0 等）的实现状态。

---

## 7. 附录：证据索引

- PRD 索引：`docs/prd/README.md`（113 行状态表）
- 源规格：`豆包梳理业务需求/{P0任务,P2…P7}.md`
- 代表工件：`backend/pallastrade_gems/pallastrade_core/app/{models,services}/pallastrade/{commerce_transaction,stock_reservation,financial_fact,financial_ledger_entry,refund,dispute}.rb`、`services/pallastrade/{transactions,refunds,disputes,reconciliations,financial_ledger}/`
- 迁移：`backend/db/migrate/`（232 个）
- 全量验证：`EVD-20260913071415-e7c36f0977`（1661 examples / 0 failures / 6 pending）
- 流水线与部署：commit `81aaf582` 四件套 CI 全绿；`/opt/pallastrade/.pull-deploy-state-dev = 81aaf582`
- 治理任务：`TASK-20260913083052-54a7e245`（本审计）/ gate `GATE-2026-09-13T08-30-58`
