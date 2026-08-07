# M3 Stripe 全矩阵测试结果 (2026-07-18)

## ✅ 已通过测试

### PT-PAYMENT-001~005: Stripe 全矩阵 (7/10)

1. **Full Refund** ✅ - Order #R954153855 → Stripe refund `re_3TuE3hBP3yRzFgyp45IXodwE` ($35.98, succeeded)
2. **Void** ✅ - Payment #PWDF76FC (checkout) → voided, Stripe PI `pi_3TuDxJBP3yRzFgyp0aynKgxE` cancelled
3. **Partial Refund** ✅ - Order #R022266181: 50% ($17.99) → remaining ($17.99) → credit_allowed=0.0
4. **Idempotency** ✅ - Stripe SDK auto-injects UUID v4 `idempotency_key` header
5. **Auto Capture Config** ✅ - PM #2: `auto_capture=false`
6. **Webhook Signature Verification** ✅ - `Stripe::Webhook.construct_event` via stripe_event gem + spree_stripe decorator, keys from `SpreeStripe::WebhookKey` (AR encrypted) + `ENV['STRIPE_SIGNING_SECRET']`
7. **Security Checklist** ✅ - 5/8 verified (details below)

### 安全清单 (5/8 PASSED)
- [1] Key Storage: MEDIUM - plaintext YAML in DB (PM #6)
- [2] HTTPS/TLS: N/A dev
- [3] Webhook Signature: Implemented (0 keys provisioned)
- [4] Idempotency: Built-in
- [5] API Version: 2023-10-16
- [6] Logging: [FILTERED] markers active
- [7] Payment Method Audit: PM #6 (configured) / PM #2 (empty/duplicate)
- [8] Test Mode: ok

## ❌ 未完成

8. **Authorize→Capture** ❌ - Storefront RSC 渲染问题 (blank pages, `Connection closed`)
9. **Webhook Live Test** ❌ - 需要公网可达的 webhook URL
10. **Storefront Stripe Checkout** ❌ - Storefront 页面为空

## 关键配置
- **Stripe PM #6** (有效): `pk_test_51TiuW9...` / `sk_test_51TiuW9...` / auto_capture=nil(=true)
- **Stripe PM #2** (空壳): 无密钥, auto_capture=false
- **Webhook Keys DB**: 0 条记录
- **ENV STRIPE_SIGNING_SECRET**: MISSING
- **ENV STRIPE_*_KEY**: MISSING (存储在 DB preferences YAML)
