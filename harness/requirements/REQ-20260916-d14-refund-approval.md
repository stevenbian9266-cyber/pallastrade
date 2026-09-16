# REQ-20260916-d14-refund-approval

- **关联 PRD**：`docs/prd/payments/PRD-20260916-payments-d14-refund-approval.md`（业务方案 §78-D14 / §71.1）
- **任务**：`TASK-20260916035551-700c32de` ｜ **Gate**：`GATE-2026-09-16T03-56-25`
- **恢复计划**：`REC-f459fcb73079f4`（manual-only）
- **风险**：critical（资金相关：退款审批门 + 幂等键）

## 6 层跨层搜索结果（gate 强制）

| 层 | 路径 | 关键词 | 结果 |
|---|---|---|---|
| App（宿主） | `backend/app/` | `refund_policy` / `approval` | 零命中（无宿主侧退款策略/审批代码） |
| Core | `pallastrade_core/app/` | `refund` / `approval` / `threshold` | `Refunds::{Request,Execute,Recover,ManualRetry,MarkManualReview}`、`Refund`（状态机 + 累计额度校验 + `provider_idempotency_key` 唯一）、`Orders::Cancel`（系统编排退款）→ **生命周期已有，审批策略缺** |
| API | `pallastrade_api/app/` | `refunds` | `api/v3/admin/orders/refunds_controller.rb`（人工创建入口，直接 enqueue ExecuteJob）、`admin/refund_serializer.rb` → **需接入策略门 + 契约字段** |
| Admin | `pallastrade_admin/app/` | `refund` | `refunds_controller`、`refunds_ops_controller`（只读 + retry/mark_review）、`refund_reasons_controller` → **需审批工作台 + 策略卡** |
| Storefront | `storefront/src/` | `refund` | 仅 email 模板引用 → **无需变更** |
| Platform | `platform/packages/` | `refund` | `sdk/src/types/generated/Refund.ts`（typelizer 生成物）→ **仅生成物再生成** |

**跨层结论**：审批门放在 Core 的新服务（`Refunds::Submit`）＋ Admin 工作台，API 控制器改调新入口；**不把策略门放进 `Refunds::Request`**（编排/网关退款必须保持无人值守）。

## Skill Consultation Evidence Table（gate 强制，真实结论）

| Skill | 结论 |
|---|---|
| `pallastrade-payments` | 退款唯一写入口 = `Refunds::Request`（durable → ExecuteJob）；`Refunds::Execute` 幂等只对 `requested` claim；**本批新增的门必须在 Request 之上，不能改 Execute 语义**；审计动作命名沿用 `refund_*` 前缀风格 |
| `pallastrade-security` | 敏感动作三件套（权限 + 二次确认 + 审计）；「不能自批」属职责分离（SoD）约束，必须在**服务层**强制（页面隐藏只是 UX）；CSV/表单不回显敏感数据 |
| `pallastrade-admin` | 财务 ops 页范式（BaseController + 筛选 + `safe_value` 降级 + `audit_actor`）；新增导航项必须同步 `navigation_consistency_spec.rb`；`data: { turbo_method: :post }` 而非 `method:` |
| `pallastrade-data-model` | 新表带 `store_id` + 状态枚举常量 + 索引（`(store_id, status)`）；新列可空 + partial unique index 避免破坏既有行；只建表不回填 |
| `pallastrade-api-v3` | Admin API 契约只增不改；serializer 属性变更后跑 `scripts/ci/contracts.sh`（typelizer + OpenAPI + platform 副本）并 `generated:check`；prefixed id 不得暴露整数主键 |
| `pallastrade-testing` | 验证器登记（`d14-refund-approval-rspec`）；覆盖：策略归一矩阵、自动/待批分支、幂等并发、自批拒绝、终态幂等、权限、零副作用、既有编排回归 |

## 设计要点（实施依据）

1. **策略门位置**：`Refunds::Submit`（人工入口）→ `Refunds::Request(enqueue: policy.auto? ? true : false)`；编排/网关仍直连 `Request`。
2. **策略存储**：`Store#private_metadata['refund_policy']`（jsonb，无新表）；读入口 `Refunds::Policy.for(store)`（值对象：`enabled?` / `auto_approve_limit` / `currency` / `requires_approval?(amount, currency)`）。
3. **默认安全方向**：未配置 = 不启用（零行为变化）；配置非法 = 不启用 + reason；启用但阈值缺失 = 全部需审批。
4. **双人复核**：`approver_id` 必填且 ≠ `requester_id`；仅 `pending` 可决策；批准 → enqueue ExecuteJob；拒绝 → `cancel_request!`（容量释放，复用既有事件）。
5. **幂等键**：`refunds.request_key`（nullable，partial unique index）+ `Refund` 侧 `find_by(request_key:)` 前置查 + `RecordNotUnique` 兜底。
6. **零资金副作用**：本批服务不调 provider、不改金额；仅 durable refund 行 + approval 行 + 审计。
7. **契约**：Admin API refunds 控制器改调 `Submit`；`Admin::RefundSerializer` 增 `approval_status`（可空字符串）。

## 切片拆分

- 切片 1（本批）：策略阈值 + 双人复核 + 幂等请求键 + 审批工作台 + API 契约字段。
- 后续：切片 2（§71.2 争议期限 T-3/T-1 分档提醒 + 超期处理）、切片 3（§71.3 拒付率看板 + 卡组织阈值预警 + 下钻）。

## 实施记录（收口时补全）

| 项 | 内容 |
|---|---|
| 改动清单 | **Core**：`db/migrate/20260916190000_create_pallastrade_refund_approvals.rb`；`app/models/pallastrade/refund_approval.rb`；`refund.rb`（`has_one :approval`、`request_key`）；`app/services/pallastrade/refunds/{policy,submit}.rb` + `refunds/approvals/{approve,reject}.rb` + `request.rb`（`request_key:` / `enqueue: false` 透传）。**Admin**：`refund_approvals_controller.rb` + `views/…/refund_approvals/index.html.erb` + `routes.rb` + `pallastrade_admin_navigation.rb` + `permission_sets/configuration_management.rb` + `locales/en.yml` + 宿主 `config/locales/admin_refund_approvals.zh-CN.yml`。**API**：`api/v3/admin/orders/refunds_controller.rb`（接 `Submit` + `request_key`）+ `admin/refund_serializer.rb`（`approval_status`）+ 生成物（admin-sdk `Refund.ts`、`api-docs/admin.yaml`、`platform/docs/api-reference/admin.yaml`）。**测试**：6 个 spec 文件 + 导航一致性断言扩展 |
| 验证器 | `harness.config.mjs` 登记 `d14-refund-approval-rspec`；实测 **64 examples, 0 failures** |
| 用例分布 | 模型（状态/唯一/作用域/SoD helper）、策略（归一化矩阵：未配置 / 非法值 / 缺阈值 / 币种不匹配）、提交（未启用=今天行为 / ≤阈值自动+审计 / >阈值待批 / 币种范围 / request_key 幂等 / 零副作用）、决策（第二人批准入队 / 自批自拒被拒 / 重复批准幂等 / 拒绝必填原因 + 取消 + 审计 / 零副作用）、后台（筛选/计数/策略卡保存/动作/权限/本人行无动作）、API（策略门 + `approval_status` 契约字段） |
| 偏差 | ① 策略门位置 = 人工入口 `Submit`（不改 `Request` 内核）；② 策略存 `Store#private_metadata['refund_policy']`（无新表）；③ `Approve` 直接入队（离散动作，无外层事务） |
| 修复 | 移除 `Refund` 重复的 `has_one :approval`；拒绝路径校验顺序（原因必填优先于状态检查，与 spec 对齐） |
