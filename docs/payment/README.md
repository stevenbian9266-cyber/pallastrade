# Payment 领域文档（P0 系列）

> P0-6（2026-09-03）「显式化」文档族：冻结术语与合同、说明流程/Webhook/标识符/安全。
> 与代码事实一致；冲突以 `AGENTS.md`/PRD 与本文档内标注的「唯一权威」为准。

## 文档索引

| 文档 | 内容 |
|---|---|
| [payment-flow.md](./payment-flow.md) | Canonical（Order 域）与 Legacy（Cart 域）支付流、幂等、三路收敛、Trace 字段 |
| [provider-contract.md](./provider-contract.md) | Gateway 抽象合同（冻结）、当前/未来 Provider、术语规范 |
| [webhook.md](./webhook.md) | Webhook 链路：验签 → Event Store/Dedup/Retry/Replay |
| [payment-identifiers.md](./payment-identifiers.md) | 标识符体系与排障关联链（order→session→payment→PSP→webhook） |
| [security.md](./security.md) | 敏感凭据安全：加密/掩码/日志纪律/轮换 |
| [P0-5_SECRET_ENCRYPTION_SPIKE.md](./P0-5_SECRET_ENCRYPTION_SPIKE.md) | Secret 加密迁移决策与 runbook |
| [P0_BEFORE_REFACTOR_TEST_BASELINE.md](./P0_BEFORE_REFACTOR_TEST_BASELINE.md) | P0-0 回归安全网基线 |

## 术语规范（FR-061）

| 术语 | 含义 | 对应代码 |
|---|---|---|
| **Gateway Configuration** | 一个可配置的支付方式实例（密钥/开关/展示位） | `PallasTrade::PaymentMethod`（STI，含 `PallasTrade::PaymentMethod::Check` 等） |
| **Gateway / Provider adapter** | 对接 PSP 的抽象实现 | `PallasTrade::Gateway`（如 Stripe = `PallasTradeStripe::Gateway`）；远期 `PallasTradeAdyen::Gateway` |
| **TenderType**（架构文档） | 收单载体 | CARD / APPLE_PAY / GOOGLE_PAY —— **不映射为 Rails Model** |
| **PaymentProvider**（未来） | PSP 标识 | STRIPE / ADYEN —— **本期不建 ProviderRegistry/Router** |
| **Standard / Canonical Flow** | Order 域支付（P1+） | `/api/v3/store/orders/:id/payment_sessions` → `PaymentSessions::Start`（P0-7 声明为 canonical） |
| **Legacy / Cart Flow** | Cart 域支付（Express 等） | `/api/v3/store/carts/:id/payment_sessions`（P0-7 声明 compatibility-only） |

⚠️ `PaymentMethod` 是最易错配的术语：它在代码里是「Gateway 配置」而不是 PSP；不要与 TenderType/PaymentProvider 混用。禁止为此重命名现有 Rails Model。
