# REQ-20260913-dsp-p7-9-partial-and-multi-dispute-semantics

| 元数据 | 值 |
|---|---|
| 关联 PRD | `docs/prd/payments/PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics.md` |
| 任务 | `TASK-20260913061444-ad0ddbce`（critical） |
| Gate | `GATE-2026-09-13T06-17-33` |
| 用户批准 | 2026-09-13 明确回复「实施」（边界 C：partial / 同一支付多 dispute / 争议费用 / provider 能力矩阵） |
| 源计划 | `豆包梳理业务需求/P7 — Dispute & Chargeback Orchestration.md` §68（边界 C 收窄）+ §71（不做清单）+ RV-D10（Unsupported Provider）+ P7-0 §9 开放项 O1/O2/O3 |

---

## Step 0 — 跨层搜索结果（6 层，2026-09-13 实测）

关键词：`dispute` / `chargeback` / `partial` / `fee_amount` / `DISPUTE_FEE` / `capabilit*` / `fact_posting_key`

| 层 | 路径 | 找到的文件 | 结论 |
|---|---|---|---|
| App | `backend/app/` | `config/initializers/pallastrade_admin_*.rb`、`config/locales/admin_nav.zh-CN.yml` | 无 dispute 领域代码；宿主层仅补双语 keys |
| Core | `pallastrade_gems/pallastrade_core/app/` | `models/pallastrade/{dispute,financial_ledger_entry,financial_fact,payment_method}.rb`；`services/pallastrade/disputes/*`；`services/pallastrade/{financial_ledger/post_dispute,end}` | **主战场**；`fact_posting_key` dispute 分支已就绪（P7-3），但 `fee_amount` 零写入、无 fee 类型、无 `partial?`、无 payment 级聚合、无能力矩阵 |
| API | `pallastrade_gems/pallastrade_api/app/` | 无命中 | 不动 API v3 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | `controllers/.../disputes_ops_controller.rb`；`views/.../disputes_ops/{index,show}.html.erb`；`config/routes.rb` | 控制台已存在（P7-7/P7-8）；本片只加只读卡片 + 能力降级 |
| Storefront | `storefront/src/` | 无命中 | 不涉及 |
| Platform | `platform/packages/` | 无命中 | 无 SDK 变更 |

**防重复判定**：六层无重复实现；需新建 4 处（fee 闭环 / partial 语义 / payment 聚合 / 能力矩阵）。

## Step 1 — Skill 咨询证据表（真实结论）

| Skill | 是否必读 | 结论引用 |
|---|---|---|
| `pallastrade-customization` | ✅ 必读 | 决策树第 8 级（直接改 gem 视图/模型，标 `# PALLAS-CUSTOM:`）；危险操作三件套沿用既有 `Ability` + `Audit.record` |
| `pallastrade-data-model` | ✅ 必读 | §Disputes：一个 payment 可携带 **1:N** 争议与部分金额；`attention_reason` 只补不覆盖；§Immutable Financial Journal：账行 append-only、`ImmutableError`、posting 输入 = `FinancialFact` |
| `pallastrade-payments` | ✅ 必读 | §P7-3：**期望账行 = funds 时间戳集合**（不是「当前最强事实」）；`effective_at` 无 fallback；非 dispute 事实 key **逐字节不变**；§P7-4：capability 用**类级**判定；§P7-8：写契约 + 证据目录 + 铁律（零资金副作用） |
| `pallastrade-admin` | ✅ 按需（控制台） | 后台页面五件套 + 表格注册 + 双语硬门（`nav_validate`）；危险区不渲染不可用表单 |
| `pallastrade-testing` | ✅ 按需 | 服务/job spec 约定；request spec 权限拒绝断言 302 |
| `pallastrade-security` | ➖ 评估后不更新 | 本片不新增权限项，沿用 `can?(:read/:update, PallasTrade::Dispute)` |
| `pallastrade-events-webhooks` | ✅ 按需 | 事件目录需追加 fee 事实事件（若有新事件） |

## 交付清单（对应 PRD FR）

| FR | 交付物 |
|---|---|
| FR-P79-01 | `Dispute#partial?`（只读派生） |
| FR-P79-02 | 金额来源唯一性断言（fixture + grep 级负向断言） |
| FR-P79-03 | Stripe `fetch_dispute_details` 扩展 `balance_transaction_details` + `fee_amount` / `fee_currency` |
| FR-P79-04 | fee **首次观测写入**（空→非空，重放不覆盖） |
| FR-P79-05 | `DISPUTE_FEE` 事实/账行类型 + `PostDispute` fee 分支（**永不冲销**） |
| FR-P79-06 | `ReconcileDispute` fee 期望 + `fee_missing` / `fee_unexpected` 分类 |
| FR-P79-07 | `Disputes::PaymentDisputeSummary`（只读聚合，零写） |
| FR-P79-08 | `PaymentMethod#dispute_capabilities`（基类 `UNSUPPORTED`）+ Stripe 矩阵 + 控制台降级 |

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| fee 类型扩展触碰跨域常量（`FACT_TYPES` / `ENTRY_TYPES`） | 追加式扩展；非 dispute key 逐字节不变（回归断言）；同步 payments / data-model Skill + GS-101 |
| provider 未返回 fee（旧事件 / 无 BT） | `nil` 不猜、不写死 $15；对账 `fee_missing` |
| partial 无法用 Stripe test helper 构造 | fixture 驱动 + PRD/Skill 标注「provider 侧未实测」 |
| 聚合/能力服务异常 | 控制台逐项 rescue → `unavailable`，页面绝不 500 |
| critical 任务无恢复计划不可完成 | 完成后即建 `REC-*` 手动恢复计划 |

## 不做（§71 + PRD 边界）

自动抗辩 / AI 生成证据 / 自动退款 / 自动补货 / Adyen-PayPal 适配 / 改 `Dispute` 状态机 / 绕过 webhook 的资金写入。
