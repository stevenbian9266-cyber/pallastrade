# PRD-20260916-payments-d15-risk-lists

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D15 切片1 风控名单与订单风险评估 —— 名单（批量导入/到期/审计）+ 名单驱动的决策留痕 + 复用既有复核闭环（业务方案 §78-D15 / §72.2 底座 / §72.3 / §74.1 表名规划） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-admin`、`pallastrade-data-model`、`pallastrade-events-webhooks`、`pallastrade-security`、`pallastrade-testing` |
| 关联 PRD | `PRD-20260916-payments-d13b-payout-ledger`（CSV 批量导入范式）、`PRD-20260911-payments-dsp-p7-1`（事件/订阅者接线范式）、`PRD-20260915-payments-d8`（店铺作用域与策略门控范式） |
| 需求类型 | 新功能（风控域从零到一：名单 + 决策留痕底座） |

## 1. 背景与目标

业务方案 §72 定义「风控与 3DS/SCA」，D15 验收锚点三条：**高风险订单只给 redirect+3DS**、**规则可回滚**、**名单可批量导入**。

现状（6 层搜索结论见 §6）：
- **有**：`Order#considered_risky`（布尔 + 索引，`Order#is_risky?` = `!payments.risky.empty?` 的**支付响应驱动**启发式）、`Orders::Approve`（写 `OrderApproval` + 清标记 + `order.approved` 事件）、后台订单页 `_risk_analysis`（只读 AVS/CVV 展示）。
- **缺**：**可配置的名单**（人工维护 + 批量导入 + 到期 + 审计）、**名单驱动的决策与留痕**（命中什么、何时、按什么规则）、**规则版本**（切片2）、**3DS/SCA 策略与 provider 下发**（切片3）、**复核队列 SLA 与动作**（切片4）。

本切片（D15 切片1）目标：把「风控」从**被动展示**变成**可运营的名单 + 可追溯的决策**，并把判断结果接回**既有复核闭环**（`considered_risky` → `Orders::Approve`），为后续切片（规则引擎版本/回滚、3DS 下发、复核队列）打好**唯一口径**的地基。

**铁律**：本切片**零资金副作用**（不改 Payment/Refund/Journal/Order 金额与状态、不调 provider、不做 3DS 下发、不阻断结账），只写**名单**与**决策留痕**，以及按既有契约标记 `considered_risky`。

## 2. 用户故事 / 场景

- **风控运营**：拿到一份欺诈名单（邮箱/BIN/IP/卡指纹），粘贴 CSV 一次导入 → 后续这些主体下单时自动落「高风险」决策并可复核，不再靠人肉搜索。
- **风控运营**：某条名单误伤（如误判的邮箱）→ 在后台**撤销**该条，或加一条 `allowlist` 白名单让它短路放行。
- **合规/审计**：某订单为何被标记？→ 订单页看到**决策留痕**（命中哪条名单、主体类型、值、决策、时间）。
- **风控运营**：某条名单有期限（如临时封禁 7 天）→ 到期**自动失效**（不硬删，保留历史）。

## 3. 功能需求（FR）

- **FR-001　名单台账** —— 新表 `pallastrade_payment_risk_lists`（§74.1 规划表名）：
  `list_type`（`denylist` / `allowlist`）、`subject_type`（`card_fingerprint` / `bin` / `email` / `ip` / `device` / `customer` / `address` / `country`）、`value`（原文，受限长度）、`value_hash`（归一化 SHA256，**唯一键 `(list_type, subject_type, value_hash)`** 负责幂等）、`expires_at`（可空 = 永不过期）、`status`（`active` / `revoked`）、`reason`、`added_by_id` / `added_by_type`、`store_id`（**可空 = 全局名单**；非空 = 店铺名单）、`metadata`（jsonb）、时间戳。
  归一化**唯一口径**（`PallasTrade::PaymentRiskList.normalize_value`）：邮箱小写、IP/BIN/卡指纹去空格与分隔符、国家大写；`active` scope = `status = 'active'` 且（`expires_at IS NULL OR expires_at > now`）。
- **FR-002　批量导入（锚点：名单可批量导入）** —— `Risk::Lists::ImportCSV.call(store:, csv_text:, actor:)`：
  列：**必填** `list_type,subject_type,value`；**可选** `expires_at`（ISO8601 或 `YYYY-MM-DD`）、`reason`。
  语义：逐行**幂等 upsert**（命中原有行 → 更新 `expires_at`/`reason` 并复活为 `active`，不产生第二行）；非法行**不中断**，进 `errors[]`（行号 + 原因）；返回 `{ created:, updated:, skipped:, errors: [] }`；写审计 `risk_list_imported`（含计数，不含明细值）。
  范式**复用** D13b `Reconciliations::Payouts::ImportCSV`（`::CSV` 显式命名空间、`ImportCSV` 常量名、错误收集结构）。
- **FR-003　导出** —— `Risk::Lists::Export.call(store:, filters:)` → CSV（列与导入同构，可**再导入**=往返一致），仅导出筛选后的行；导出写审计 `risk_list_exported`（计数）。
- **FR-004　手工维护** —— `Risk::Lists::Upsert.call(...)`（新增/续期/撤销）+ 审计 `risk_list_entry_changed`（before/after 快照）；撤销 = `status: revoked`（**保留历史**，不物理删除）。
- **FR-005　评估（决策留痕）** —— 新表 `pallastrade_payment_risk_assessments`：
  `order_id`（可空）、`store_id`、`decision`（`allow` / `review` / `block`）、`matched_entry_ids`（jsonb）、`signals`（jsonb：命中的主体类型 + 脱敏值摘要 + 是否白名单短路）、`evaluated_at`、`metadata`。
  服务 `Risk::Assess.call(order:)`：先算 `allowlist`（命中 → `allow` **短路**，denylist 不再评估）→ 再算 `denylist`（命中 → 决策取 `PallasTrade::Config[:risk_denylist_action]`，默认 `review`；只有该配置显式为 `block` 时才是 `block`）→ 写 assessment（**每次评估一条**，幂等键 `(order_id, evaluated_at 秒级)` 防重复订阅投递）。
  `order` 无主体可用（无邮箱/IP/支付）→ `allow`（**不猜**）+ `signals['insufficient_subject'] = true`。
- **FR-006　接线（复用既有复核闭环）** —— 订阅 `order.submitted`（`Carts::Submit` 发布）→ `Risk::Assess`；`decision != 'allow'` → `order.consider_risk`（**复用**既有 `considered_risky!`，发布 `order.updated`）。
  订阅者在 `pallastrade_core/lib/pallastrade/core/engine.rb` 的 `PallasTrade.subscribers.concat` 注册（与既有 14 个订阅者一致）。
  **不阻断**：本切片不阻止下单、不改支付意图、不触发 3DS（留给切片2/3）。
- **FR-007　后台名单工作台** —— `/admin/risk_lists`（Payments 或 Developers 域，见 §7）：列表（筛选 `list_type` / `subject_type` / `status` / `expired` / 店铺）+ 计数（与筛选**同源 scope**）+ 新增/编辑（`reason`、`expires_at`）+ 撤销（confirm）+ 批量导入（粘贴或上传 CSV）+ 导出（CSV，带筛选条件）；
  权限 `can :manage, PallasTrade::PaymentRiskList`（默认 admin 角色可见）；动作写 `AuditLog`；i18n（gem `en.yml` + 宿主 `zh-CN`）。
- **FR-008　订单页决策留痕** —— 订单详情「风控」区（注入 `orders_header_partials` 风格或既有风控卡片旁）展示**最近一次**评估：决策徽章 + 命中项（主体类型 + 脱敏值）+ 时间 + 命中名单类型的说明；无评估 → 不渲染（避免噪音）。
- **FR-009　店铺作用域硬边界** —— 评估只用「全局名单 + 该店铺名单」（`store_id IS NULL OR store_id = ?`）；**绝不**把 A 店名单套到 B 店（与 D14b 同纪律）；名单工作台只增删本店/全局行（无跨店写）。
- **FR-010　零资金副作用** —— 全链路不写 Payment / Refund / FinancialLedgerEntry / 订单金额与状态 / 库存，不调 provider；用例以负向断言钉死（对齐 §71/§70 批次纪律）。

## 4. 非功能需求（NFR）

- **安全**：名单值是**敏感运营数据**（邮箱/IP/卡指纹）→ 列表与详情**脱敏展示**（邮箱 `a***@b.com`、IP 保留前两段、卡指纹只显前后 4 位）；CSV 导出**保留原值**但要求权限 + 写审计；`AuditLog` 不落明文（只落 `value_hash` 前缀 + 类型）。
- **性能**：评估是**有界查询**（`subject_type IN (...)` + 值集合 `IN`，走 `(list_type, subject_type, value_hash)` 唯一索引）；单订单评估 ≤ 2 次查询（allowlist / denylist）；导入批量 `upsert_all` 分批（默认 500/批）。
- **兼容**：既有 `Order#is_risky?`（支付响应驱动）与 `Orders::Approve` **语义不变**；本切片只是**多一个**标记来源（`consider_risk` 幂等，重复标记无副作用）。
- **范围纪律（本切片不做）**：规则引擎（条件/动作/priority/灰度/版本回滚）→ 切片2；3DS/SCA 策略与 provider（Stripe Radar / Adyen）下发 → 切片3；复核队列（SLA 倒计时 / 通过并捕获 / 拒绝并释放 / 请求补充材料）→ 切片4；名单的自动同步（provider 名单 API 拉取）→ 不在计划内。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：名单归一化与唯一性矩阵（邮箱大小写/空白、BIN 去分隔符、国家大写）；重复导入**不产生第二行**；`active` scope 排除 `revoked` 与**已过期**行。
- **AC-002** ← FR-002：CSV 批量导入 —— 必填列缺失/值非法 → 逐行进 `errors[]` 且**不中断**；同一文件重复导入 → `created: 0`（幂等）；续期（同一 value 新 `expires_at`）→ `updated` 且行数不变；审计写入。
- **AC-003** ← FR-003：导出 CSV 与导入列同构（**往返一致**：导出 → 再导入 → 零新增/零错误）；导出仅含筛选结果。
- **AC-004** ← FR-004：新增/续期/撤销各写审计（before/after）；撤销后行仍存在（`revoked`）且不再命中评估。
- **AC-005** ← FR-005：评估决策矩阵 —— allowlist 命中 → `allow` 且**短路**（denylist 命中也不改）；denylist 命中 → 默认 `review`、配置 `block` 时 `block`（非法配置回落 `review`）；无命中 → `allow`；主体不足 → `allow` + `insufficient_subject`；撤销/过期条目不再命中。
  **留痕幂等**：重复投递（5 分钟窗口内**同决策 + 同命中集**）复用已有行；命中集/决策变化或窗口之外**新增一行**（审计不丢）；兼底唯一键 `(order_id, evaluated_at)`。
- **AC-006** ← FR-006：`order.submitted` → 命中时订单被标记 `considered_risky`（复用既有字段）+ 审计/事件契约不变；未命中订单**零改动**；全链路**不阻断**（订单状态与支付意图不变）。
- **AC-007** ← FR-009：跨店隔离 —— A 店名单不命中 B 店订单；评估查询只取「全局 + 本店」。
- **AC-008** ← FR-007：后台工作台 —— 计数与筛选同源、导入/导出/撤销动作可用、无权限用户被拒；i18n 键齐备（en + zh-CN）。
- **AC-009** ← FR-008：订单页风控卡渲染最近评估（决策 + 脱敏命中项）；无评估不渲染；**不回显明文**（脱敏断言）。
- **AC-010** ← FR-010：零资金副作用（Payment/Refund/FinancialLedgerEntry/Order 金额与状态/库存行数与金额不变、无 provider 调用）。
- **AC-011** ← §74.1：表名/列名与规划一致（`pallastrade_payment_risk_lists` 唯一键 `(list_type, subject_type, value_hash)`）+ `PallasTrade::Config[:risk_denylist_action]` 默认 `review`（**保守默认**：不误伤真实订单）+ 属性白名单（`permitted_attributes`）不误开。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `risk` / `fraud` / `denylist` | 仅生成物（`assets/builds/**`、serializer 类型）| ❌ 未满足（宿主无风控代码） |
| Core | `pallastrade_gems/pallastrade_core/app/` | `risk` / `considered_risky` / `3ds` / `sca` | `Order#considered_risky` + `#is_risky?`（`payments.risky` 驱动）+ `#consider_risk`、`Orders::Approve`（写 `OrderApproval` + 清标记）、`order.submitted` 事件（`Carts::Submit`）、订阅者注册表（`lib/pallastrade/core/engine.rb` → `PallasTrade.subscribers.concat`） | ⚠️ 部分（有**支付响应驱动**的标记与人工审批闭环；**缺名单/决策留痕**） |
| API | `pallastrade_api/app/` | `risk` | `admin/order_serializer` 暴露 `considered_risky`；无风控端点 | ✅ 本切片无需变更（零契约） |
| Admin | `pallastrade_admin/app/` | `risk` | `orders/_risk_analysis.html.erb`（只读 AVS/CVV）、`orders_controller`（`@order_events = %w{approve cancel resume}`）、`_badges.css` | ⚠️ 部分（有只读展示，**缺名单工作台与决策卡**） |
| Storefront | `storefront/src/` | `risk` / `3ds` | 零命中 | ✅ 无需变更 |
| Platform | `platform/packages/` | `risk` | 零命中 | ✅ 无需变更 |

**结论**：承载点 = **Core**（2 表 + 2 模型 + 3 服务 + 1 订阅者）+ **Admin**（1 工作台 + 订单页决策卡）；API / Storefront / Platform **零改动**。
**复用而非重写**：CSV 导入/导出复用 D13b `ImportCSV` 范式；标记复用 `Order#consider_risk`；复核动作复用 `Orders::Approve`（本切片不新增动作）；订阅者注册复用 engine 注册表。

## 7. 技术影响

- **Core**：迁移（`pallastrade_payment_risk_lists` + `pallastrade_payment_risk_assessments`，只新增表不回填）；模型 `PaymentRiskList` / `PaymentRiskAssessment`；服务 `Risk::Lists::{ImportCSV,Export,Upsert}` + `Risk::Assess`；订阅者 `Risk::OrderSubmittedSubscriber` 注册进 `PallasTrade.subscribers`。
- **Admin**：`/admin/risk_lists`（index / new / create / update / revoke / import / export）+ 导航（**Payments** 域，position 见实现）+ 权限 + 订单页决策卡 + i18n（gem `en.yml` + 宿主 `zh-CN`）。
- **数据库**：只新增表/索引，不回填、不改既有列。
- **契约**：**零 API v3 变更**（`generated:check` 应无漂移）。
- **测试**：归一化/唯一性、导入导出往返、维护与审计、决策矩阵与留痕幂等、订阅者接线与不阻断、跨店隔离、后台工作台与权限、订单页脱敏、零资金副作用。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 模型 | `backend/spec/models/pallastrade/d15_payment_risk_list_spec.rb` | AC-001/007/009/011 |
| 服务（维护 + 导入导出） | `backend/spec/services/pallastrade/risk/d15_upsert_import_export_spec.rb` | AC-002/003/004 |
| 服务（评估） | `backend/spec/services/pallastrade/risk/d15_assess_spec.rb` | AC-005/007/010 |
| 订阅者 | `backend/spec/subscribers/pallastrade/risk/d15_order_submitted_spec.rb` | AC-006 |
| 后台 | `backend/spec/requests/pallastrade/admin/d15_risk_lists_spec.rb` | AC-008/009 |
| 回归 | `backend/spec/requests/pallastrade/admin/navigation_consistency_spec.rb` | 导航子项完整列表（新增 `:risk_lists`） |

验证器：`d15-risk-lists-rspec`（注册于 `harness.config.mjs`）。

## 9. 收口清单

- [x] 本 PRD（approved → 实施后 done）
- [x] REQ：`harness/requirements/REQ-20260916-d15-risk-lists.md`（含 Skill Consultation Evidence Table）
- [x] gate + prep 清理（critical：恢复计划随 gate 记录）
- [x] 用户确认：用户 2026-09-16「继续」（承接 §78 D15 批次）
- [x] 知识同步：`pallastrade-payments` / `pallastrade-admin` / `pallastrade-data-model` / `pallastrade-events-webhooks` Skill + AGENTS §6 verifier 行 + 场景库 GS-153 + 业务方案 §72 回写
- [x] 契约：无需 `generated:check`（零 API 契约变更）；仍跑一次确认无漂移

### 9.1 实施记录（2026-09-16）

| 项 | 结果 |
|---|---|
| 迁移 | `20260916220000_create_pallastrade_payment_risk_lists.rb`（两表 + 唯一键 + 索引；**只建表不回填**） |
| Core | `PaymentRiskList`（归一化/唯一键/生效率/脱敏）/ `PaymentRiskAssessment`（决策留痕）/ `Risk::Assess`（决策矩阵 + 复用窗口）/ `Risk::Lists::{Upsert,ImportCSV,Export}` / `Risk::OrderSubmittedSubscriber`（注册进 `PallasTrade.subscribers`）/ `Order#risk_assessments` 关联 + `configuration.rb` 新增 `risk_denylist_action` 偏好（默认 `review`） |
| Admin | `/admin/risk_lists` 工作台（筛选/计数同源 + 新增续期 + 撤销 + 导入 + 导出）/ 导航 position 59 / 权限 `can :manage, PallasTrade::PaymentRiskList` / 订单页风控卡（`order_page_body` 注入点）/ gem `en.yml` + 宿主机 `zh-CN` |
| API / Storefront / Platform | **零改动**（无契约变更） |
| 测试 | `harness verify d15-risk-lists-rspec` = **43 examples, 0 failures**（含导航一致性回归） |
| 实测语义 | 归一化幂等（大小写/分隔符不产生第二行）；白名单优先（denylist也命中仍 allow）；denylist 默认 `review`、配置 `block` 才是 `block`；撤销/过期不再命中；重复投递复用留痕，决策变化新增 |
| 修过的坑 | ①`PallasTrade::Config[:x]` 对**未声明**的键会 NoMethodError → 新配置必须先在 `core/lib/pallastrade/core/configuration.rb` 里 `preference` 声明；②后台控制器需自己定义 `audit_actor`（不在 BaseController）；③注入的 partial 文件名必须带 `_` 前缀；④订单页 request spec 需固定 `current_store` + 用 `prefixed_id`；⑤BIN 用「只露头部」而非「首尾各留 4」（8 位 BIN 会全露） |

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片1：名单台账/批量导入导出/维护审计 + 名单驱动决策留痕 + 复用既有复核闭环；规则引擎/3DS 下发/复核队列留切片2/3/4） |
| 0.2 | 2026-09-16 | 实施完成（43 examples 全绿）+ 知识同步 + §9.1 实施记录；AC-005 留痕幂等口径细化为「复用窗口 + 决策变化新增」；测试文件按实际落地收敛为 5 份 + 导航回归 |
