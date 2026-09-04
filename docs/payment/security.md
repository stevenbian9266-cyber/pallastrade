# Payment Security（支付安全基线）

> P0-5/P0-6：敏感凭据与敏感操作的统一纪律。NFR-004 落地说明。

## 1. 凭据分级

| 凭据 | 级别 | 处理 |
|---|---|---|
| Stripe `secret_key`（`sk_`） | Secret | **加密存储**（P0-5 方案 A：AR Encryption `encrypts :preferences`）；不回显、不入日志 |
| Stripe Webhook signing secret（`whsec_`） | Secret | 同上（gateway preferences / WebhookEndpoint.secret_key 均已 `encrypts`） |
| Adyen/PayPal 等未来 credential | Secret | 进入同一 Gateway `encrypts :preferences` 覆盖 |
| Stripe `publishable_key`（`pk_`） | Public | 明文配置即可（FR-050 明示） |

## 2. 加密与迁移（P0-5）

- `PallasTrade::Gateway` 的 `preferences` 列 AR-encrypted（条件启用：`ACTIVE_RECORD_ENCRYPTION_*` 存在才生效）。
- `support_unencrypted_data=true`：历史明文行 dual-read，backfill 后新写全加密。
- 运维：`rake pallastrade:payments:encrypt_preferences` + `verify_encrypted_preferences`；dump 抽查 `sk_/whsec_` 为 0。
- 回滚非 destructive（见 [P0-5_SECRET_ENCRYPTION_SPIKE.md](./P0-5_SECRET_ENCRYPTION_SPIKE.md) §10.4）。

## 3. 输出纪律（NFR-004）

- **不回显**：Admin GET 只返回 masked value（`Masking.serialize` / `serialized_preferences`）。
- **不覆盖**：masked 值再提交不覆盖真实 Secret（`SubclassedResource` masked? 守卫）。
- **不入日志**：任何 secret 值禁止进入 Rails.logger / 异常 message / 审计 `before/after`（审计前需脱敏）。
- **不落明文**：DB 新写入不留明文 secret。

## 4. 敏感操作审计（P0-6，FR-064）

`PallasTrade::AuditLog` + `PallasTrade::Audit.record`：

- 覆盖动作：`webhook_replay`（已接）、Refund、Manual repair/retry、`gateway_credential_change`（接线见报告开放项）。
- 字段：actor_type/actor_id/actor_label + action + resource_type/resource_id(+prefixed) + request_id + before/after + occurred_at。
- 审计写失败不影响主流程（rescue → Rails.error）。

## 5. 轮换（FR-054）

历史 DB dump/backup 可能含明文 → **建议轮换** Stripe secret + webhook signing secret（双活切流验证后撤销）。publishable key 不需轮换。

## 6. 禁止事项

- 往源码写真实 secret（hooks 拦截 `sk_live_/whsec_` 等）。
- 前端获得 provider 内部错误细节（错误映射走 `Payments::ErrorCodes` 安全文案）。
