# M4 外部品牌化结果 (2026-07-18)

## ✅ 通过 (6/8)

1. **Store DB Settings** ✅ — name=PallasTrade, mail_from=no-reply@pallastrade.local, support=support@pallastrade.local
2. **Storefront Branding** ✅ — package.json → pallastrade-storefront, .env.example → PallasTrade, store.ts fallback → PallasTrade
3. **Admin UI** ✅ — 页面标题 "Dashboard - Pallastrade", 页脚 "PallasTrade Community Edition", 登录页 0 个 "Spree" 文本
4. **API Responses** ✅ — JSON 无品牌标识，store name 来自 DB
5. **Mailer** ✅ — ActionMailer default from: "PallasTrade <no-reply@pallastrade.local>"
6. **Source Files** ✅ — 3 文件已修改

## ⏳ M5 待处理 (2/8)

7. **Docker Service Names** ⏳ — spree-web-1/spree-worker-1/spree-postgres-1 等来自 ghcr.io/spree/spree 预编译镜像
8. **ENV Variable Prefixes** ⏳ — SPREE_PORT/SPREE_API_URL/SPREE_PUBLISHABLE_KEY → M5 代码协调修改

## 已修改文件
- d:\pallastrade\storefront\.env.example (NEXT_PUBLIC_STORE_NAME + DESCRIPTION)
- d:\pallastrade\storefront\package.json (name → pallastrade-storefront)
- Spree::Store.default (mail_from_address, customer_support_email)
- ActionMailer::Base.default(from:)

## 当前 Docker 容器
- pallastrade-storefront (已品牌化)
- spree-web-1, spree-worker-1, spree-postgres-1, spree-redis-1, spree-meilisearch-1, spree-mailpit-1 (M5 处理)
