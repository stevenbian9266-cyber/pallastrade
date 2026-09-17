# PallasTrade PRD 文档库

> 一句话需求 → 详细 PRD → harness 门禁实施 → 测试验收 → 知识同步。本目录为 PRD 统一存放处。

## 目录结构

```
docs/prd/
├── README.md            # 本索引（AI 每次变更后自动更新）
├── _TEMPLATE.md         # PRD 文档模板（必用）
├── catalog/             # 商品 / 类目 / 搜索
├── checkout/            # 购物车 / 结算 / 订单
├── payments/            # 支付 / 退款
├── promotions/          # 促销 / 优惠券
├── pricing/             # 价格 / 多币种
├── shipping/            # 物流 / 库存 / 履约
├── admin/               # 管理后台
├── storefront/          # 商城前端
├── api/                 # 接口 / API 规范
├── platform/            # SDK / CLI / 平台能力
├── security/            # 安全
├── i18n/                # 多语言
├── harness/             # 工程机制
├── infra/               # 部署 / 基础设施
└── other/               # 其他
```

## 命名规则

```
PRD-{YYYYMMDD}-{category}-{slug}.md
例：PRD-20260808-catalog-bulk-import.md
```

分类由 `harness/policies/prd-categories.json` 关键词规则自动判定，AI 可语义微调。

## PRD 列表

| 状态 | PRD | 分类 | 日期 | 关联 REQ |
|---|---|---|---|---|
| done | PRD-20260914-checkout-quote-confirmation-loop | checkout | 2026-09-14 | REQ-20260914-checkout-quote-confirmation-loop.md |
| done | PRD-20260914-admin-disputes-evidence-params-whitelist | admin | 2026-09-14 | REQ-20260914-admin-disputes-evidence-params-whitelist.md |
| done | PRD-20260914-shipping-category-name-i18n-fallback | shipping | 2026-09-14 | REQ-20260914-shipping-category-name-i18n-fallback.md |
| done | PRD-20260913-checkout-billing-mode | checkout | 2026-09-13 | REQ-20260913-checkout-billing-mode.md |
| done | PRD-20260913-checkout-txn-error-routing | checkout | 2026-09-13 | REQ-20260913-checkout-error-routing-and-money-contract.md |
| done | PRD-20260913-checkout-money-contract | checkout | 2026-09-13 | REQ-20260913-checkout-error-routing-and-money-contract.md |
| done | PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics | payments | 2026-09-13 | REQ-20260913-dsp-p7-9-partial-and-multi-dispute-semantics.md |
| done | PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission | payments | 2026-09-13 | REQ-20260913-dsp-p7-8-dispute-dangerous-actions.md |
| done | PRD-20260913-payments-dsp-p7-7-admin-disputes-console | payments | 2026-09-13 | REQ-20260913-dsp-p7-7-admin-disputes-console.md |
| done | PRD-20260912-payments-dsp-p7-6-dispute-recovery | payments | 2026-09-12 | REQ-20260912-dsp-p7-6-dispute-recovery.md |
| done | PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep | payments | 2026-09-12 | REQ-20260912-dsp-p7-5-dispute-deadline-sweep.md |
| done | PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot | payments | 2026-09-12 | REQ-20260912-dsp-p7-4-dispute-evidence-snapshot.md |
| done | PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile | payments | 2026-09-12 | REQ-20260912-dsp-p7-3-dispute-posting-and-reconcile.md |
| done | PRD-20260911-payments-dsp-p7-2-dispute-fact-resolution | payments | 2026-09-11 | REQ-20260911-dsp-p7-2-dispute-fact-resolution.md |
| done | PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion | payments | 2026-09-11 | REQ-20260911-dsp-p7-1-dispute-model-and-event-ingestion.md |
| done | PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze | payments | 2026-09-11 | REQ-20260911-dsp-p7-0-dispute-semantic-audit.md |
| done | PRD-20260911-promotions-promo-batch6-pr-p9-cleanup | promotions | 2026-09-11 | REQ-20260911-promo-batch6-pr-p9-cleanup.md |
| done | PRD-20260911-promotions-promo-batch5b-permission-single-source | promotions | 2026-09-11 | REQ-20260911-promo-batch5b-permission-single-source.md |
| done | PRD-20260910-promotions-promo-batch5a-definition-registry | promotions | 2026-09-10 | REQ-20260910-promo-batch5a-definition-registry.md |
| done | PRD-20260910-promotions-promo-batch4b-refund-allocation | promotions | 2026-09-10 | REQ-20260910-promo-batch4b-refund-allocation.md |
| done | PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot | promotions | 2026-09-10 | REQ-20260910-promo-batch4a-orderpromotion-snapshot.md |
| done | PRD-20260910-promotions-promo-batch3c-redemption-readonly | promotions | 2026-09-10 | REQ-20260910-promo-batch3c-redemption-readonly.md |
| done | PRD-20260910-promotions-promo-batch3b-redemption-hardening | promotions | 2026-09-10 | REQ-20260910-promo-batch3b-redemption-hardening.md |
| done | PRD-20260910-promotions-promo-batch3a-redemption-ledger | promotions | 2026-09-10 | REQ-20260910-promo-batch3a-redemption-ledger.md |
| done | PRD-20260909-promotions-promo-batch2-discount-projection-unified | promotions | 2026-09-09 | REQ-20260910-promo-batch2-discount-projection-unified.md |
| done | PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness | promotions | 2026-09-09 | REQ-20260909-promo-batch1-invariants-and-code-uniqueness.md |
| done | PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine | payments | 2026-09-09 | REQ-20260909-rev-p6-8j-ordercancellation-state-machine.md |
| done | PRD-20260909-payments-孤儿退款补记-backfill-refunds-backfillproviderrefund-rake-dry-run- | payments | 2026-09-09 | REQ-20260909-rev-p6-8m-orphan-refund-backfill.md |
| done | PRD-20260909-payments-admin-api-v3-只读端点-payment_combinations-index-show-refunds-sh | payments | 2026-09-09 | REQ-20260909-rev-p6-8l-admin-api-v3-readonly.md |
| done | PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling | payments | 2026-09-08 | REQ-20260908-rev-p6-8i-recover-auto-scheduling.md |
| done | PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops | payments | 2026-09-08 | REQ-20260908-rev-p6-8h-orphan-amounts-payment-ops.md |
| done | PRD-20260908-payments-rev-p6-8g-combination-visibility-rails-admin | payments | 2026-09-08 | REQ-20260908-rev-p6-8g-combination-visibility.md |
| done | PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration | payments | 2026-09-08 | REQ-20260908-rev-p6-8f-combination-level-cancel.md |
| done | PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain | payments | 2026-09-08 | REQ-20260908-rev-p6-8e-reverse-commerce-recover.md |
| done | PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing | payments | 2026-09-08 | REQ-20260908-rev-p6-8d-provider-orphan-refund-pairing.md |
| done | PRD-20260908-payments-rev-p6-8c-reimbursement-async-chain-durable-requested-executejob | payments | 2026-09-08 | REQ-20260908-rev-p6-8c-reimbursement-async-chain.md |
| done | PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry-人工裁决与确定性重试-危险操作 | payments | 2026-09-08 | REQ-20260908-rev-p6-8b-refund-manual-review-retry.md |
| done | PRD-20260908-payments-rev-p6-8a-refund-admin-ops-可见性-退款状态列表-详情-rails-admin | payments | 2026-09-08 | REQ-20260908-rev-p6-8a-refund-admin-ops-visibility.md |
| done | PRD-20260908-storefront-小屏下个人中心入口可见与移动菜单search弹出搜索框 | storefront | 2026-09-08 | REQ-20260908-storefront-mobile-account-and-menu-search.md |
| done | PRD-20260908-checkout-商城前台-order-模块-订单列表排序按订单创建时间由近到远排序 | checkout | 2026-09-08 | REQ-20260908-store-order-list-created-at-desc.md |
| done | PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting | payments | 2026-09-08 | REQ-20260908-rev-p6-7-financial-convergence.md |
| done | PRD-20260908-payments-rev-p6-6-refund-reverse-recovery-recover-recoverjob-recovers | payments | 2026-09-08 | REQ-20260908-rev-p6-6-refund-reverse-recovery.md |
| done | PRD-20260907-shipping-rev-p6-5-return-restock-decision-exactly-once-restock-accept | shipping | 2026-09-07 | REQ-20260907-rev-p6-5-return-restock-exactly-once.md |
| done | PRD-20260907-payments-rev-p6-4-cancellation-orchestration-取消业务决策上收-unpaid-void-pai | payments | 2026-09-07 | REQ-20260907-rev-p6-4-cancellation-orchestration.md |
| done | PRD-20260907-payments-rev-p6-3-partial-combination-refund-allocation-组合退款-ownershi | payments | 2026-09-07 | REQ-20260907-rev-p6-3-partial-combination-refund-allocation.md |
| done | PRD-20260906-payments-rev-p6-2-refund-execution-orchestration-refunds-request-asyn | payments | 2026-09-06 | REQ-20260906-rev-p6-2-refund-execution.md |
| done | PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation-退款-durable-生命周期 | payments | 2026-09-06 | REQ-20260906-rev-p6-1-durable-refund-lifecycle.md |
| done | PRD-20260906-admin-core-p5-8-operational-hardening-legacy-路径使用计数-运营指标埋点 | admin | 2026-09-06 | REQ-20260906-cp5-8-operational-hardening.md |
| done | PRD-20260906-payments-fin-p4-8-repair-legacy-operations | payments | 2026-09-06 | REQ-20260906-fin-p4-8.md |
| done | PRD-20260906-payments-fin-p4-7-transaction-reconciliation | payments | 2026-09-06 | REQ-20260906-fin-p4-7.md |
| done | PRD-20260906-payments-fin-p4-6-source-reconciliation | payments | 2026-09-06 | REQ-20260906-fin-p4-6.md |
| done | PRD-20260906-payments-fin-p4-5-stripe-provider-financial-facts | payments | 2026-09-06 | REQ-20260906-fin-p4-5.md |
| done | PRD-20260906-payments-fin-p4-4-allocation-integrity | payments | 2026-09-06 | REQ-20260906-fin-p4-4.md |
| done | PRD-20260906-payments-fin-p4-3-payment-refund-posting | payments | 2026-09-06 | REQ-20260906-fin-p4-3.md |
| done | PRD-20260905-payments-fin-p4-2-immutable-financial-journal | payments | 2026-09-05 | REQ-20260906-fin-p4-2.md |
| done | PRD-20260905-payments-fin-p4-1-支付资金账本-commercetransaction-级-immutable-financial-jo | payments | 2026-09-05 | REQ-20260906-fin-p4-1.md |
| done | PRD-20260905-shipping-库存事务集成与预留生命周期-p3-stockreservation-接入-commercetransaction-res | shipping | 2026-09-05 | （实施时回填） |
| done | PRD-20260905-checkout-paymentcombination-txn-化-组合交易收敛到-transactions-finalize-recov | checkout | 2026-09-05 | REQ-20260905-paymentcombination-txn.md |
| done | PRD-20260905-checkout-txn-p2-6-轮3-storefront-transaction-first-迁移-checkout-start-b | checkout | 2026-09-05 | REQ-20260905-txn-p2-6-storefront-transaction-first.md |
| done | PRD-20260905-payments-txn-p2-6-contract-snapshot | payments | 2026-09-05 | REQ-20260905-txn-p2-6-contract-snapshot.md |
| done | PRD-20260905-other-txn-p2-closure-report-and-store-serializer | other | 2026-09-05 | REQ-20260905-txn-p2-closure.md |
| done | PRD-20260905-payments-txn-p2-7-operational-hardening-backend-slice | payments | 2026-09-05 | REQ-20260905-txn-p2-7.md |
| done | PRD-20260904-payments-txn-p2-5-unified-finalization-transactions-finalize-onpaymentsuccess | payments | 2026-09-04 | REQ-20260904-txn-p2-5.md |
| done | PRD-20260904-payments-txn-p2-4-recovery-engine-recovery-required-权威状态解析-recover | payments | 2026-09-04 | REQ-20260904-txn-p2-4.md |
| done | PRD-20260904-payments-txn-p2-3-payment-fact-resolver-provider-只读状态契约-资金事实判定 | payments | 2026-09-04 | REQ-20260904-txn-p2-3.md |
| done | PRD-20260904-api-txn-p2-2-transactions-start-resume-事务启动幂等-quote-consent-sess | api | 2026-09-04 | REQ-20260904-txn-p2-2.md |
| done | PRD-20260904-checkout-txn-p2-1-commercetransaction-core-transactions-transaction_o | checkout | 2026-09-04 | REQ-20260904-txn-p2-1.md |
| done | PRD-20260902-payments-payment-p0-foundation-hardening-paymentsession-payment-正式关联- | payments | 2026-09-02 | REQ-20260902-payment-p0.md |
| done | PRD-20260831-harness-实施-harness-token-优化-宿主侧 | harness | 2026-08-31 | REQ-20260831-harness-token-optimization-host.md |
| done | PRD-20260830-checkout-下单链路规范化统一化-场景a-b统一下单页-场景c收银台弹窗-参考阿里国际站 | checkout | 2026-08-30 | REQ-20260901-positive-checkout-payment-flow-hardening.md |
| done | PRD-20260830-other-修复-skill-权威路径 | other | 2026-08-30 | REQ-20260830-fix-skill-authority-paths.md |
| done | PRD-20260829-checkout-订单模块-单笔走现有checkout-多笔走组合支付新流程-收货信息独立填写 | checkout | 2026-08-29 | REQ-20260830-order-module-single-combined-payment.md |
| done | PRD-20260829-checkout-订单流程标准电商改造-购物车与订单分表-订单确认-提交订单-checkout纯支付-自有化去上游品牌化 | checkout | 2026-08-29 | REQ-20260830-order-flow-standard-ecommerce-p1.md |
| done | PRD-20260828-checkout-p8-前置校验-库存-风控-订单服务增强-flag-灰度 | checkout | 2026-08-28 | REQ-20260828-order-lifecycle-p8.md |
| done | PRD-20260828-checkout-p7-逆向链路售后父子单化-flag-灰度 | checkout | 2026-08-28 | REQ-20260828-order-lifecycle-p7.md |
| done | PRD-20260828-admin-p6-admin-手动拆单-父子树-ui-flag-灰度 | admin | 2026-08-28 | REQ-20260828-order-lifecycle-p6.md |
| done | PRD-20260827-checkout-实施-p5-checkout-集成-自动拆单-合并支付收银台-buy-now-flag-灰度 | checkout | 2026-08-27 | REQ-20260827-order-lifecycle-p5.md |
| done | PRD-20260827-payments-实施-p4-合并支付载体-paymentcombination-服务层-webhook-幂等完成 | payments | 2026-08-27 | REQ-20260827-order-lifecycle-p4.md |
| done | PRD-20260827-payments-实施-p3-父子单金额与支付状态派生-combined_total-payment-shipment_state-聚合 | payments | 2026-08-27 | REQ-20260827-order-lifecycle-p3.md |
| done | PRD-20260826-checkout-实施-p2-统一拆单引擎-orders-splitter-策略分组-调整分摊-幂等 | checkout | 2026-08-26 | REQ-20260826-order-lifecycle-p2.md |
| done | PRD-20260826-payments-实施-p1-数据模型与语义方法-父子单-parent_id-paymentcombination-paymentspli | payments | 2026-08-26 | REQ-20260826-order-lifecycle-p1.md |
| done | PRD-20260818-catalog-p0-4-产品评论 | catalog | 2026-08-18 | （实施时回填） |
| done | PRD-20260818-other-p0-3-邮件自动化-弃单恢复 | other | 2026-08-18 | （实施时回填） |
| done | PRD-20260817-other-移除根-package-json-无用的-glob-弃用依赖 | other | 2026-08-17 | （实施时回填） |
| done | PRD-20260817-admin-新建店铺表单-货币语言选择器与邮箱预设 | admin | 2026-08-17 | （实施时回填） |
| done | PRD-20260817-admin-多店铺管理-店铺列表-新建-切换 | admin | 2026-08-17 | （实施时回填） |
| done | PRD-20260817-admin-菜单配置收敛-结构代码化-可视化只读展示-权限配置依据 | admin | 2026-08-17 | （实施时回填） |
| done | PRD-20260816-admin-后台可视化菜单配置模块-角色权限体系-菜单-数据-功能权限 | admin | 2026-08-16 | （实施时回填） |
| done | PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局 | admin | 2026-08-16 | REQ-20260816-admin-nav-architecture |
| done | PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 | admin | 2026-08-16 | REQ-20260816-admin-nav-consistency |
| done | PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑 | admin | 2026-08-13 | （实施时回填） |
| done | PRD-20260808-admin-去掉管理后台左侧菜单的升级逻辑-community-edition-升级提示 | admin | 2026-08-08 | REQ-20260808-remove-enterprise-notice |
| done | PRD-20260808-admin-ai-tools-page-optimization | admin | 2026-08-08 | REQ-20260808-ai-tools-page-optimization |
| done | PRD-20260808-api-实施-ai-tools-模块优化-p0-locale修复-添加provider-p1-预设可见-引导-p2-api文档- | api | 2026-08-08 | REQ-20260808-ai-tools-optimization |
| done | PRD-20260808-harness-l4-promotion | harness | 2026-08-08 | REQ-20260808-harness-l4-promotion |
| done | PRD-20260809-infra-aliyun-dev-prod-deploy | infra | 2026-08-09 | REQ-20260809-infra-aliyun-dev-prod-deploy |
| done | PRD-20260809-infra-oss-storage | infra | 2026-08-09 | REQ-20260809-oss-storage |
| merged | PRD-20260809-infra-oss-cache-control | infra | 2026-08-09 | REQ-20260809-oss-cache-control |
| done | PRD-20260809-harness-prd-dedupe-update | harness | 2026-08-09 | REQ-20260809-harness-prd-dedupe-update |
| done | PRD-20260809-storefront-brand-assets | storefront | 2026-08-09 | （实施时回填） |
| done | PRD-20260809-catalog-创建兔狲品牌图片资源套件 | catalog | 2026-08-09 | REQ-20260810-pallas-cat-brand-assets |
| done | PRD-20260810-storefront-商城前台接入tawk-to作为客服工具 | storefront | 2026-08-10 | REQ-20260810-tawk-to-widget |
| done | PRD-20260810-storefront-对商城前台进行重新规划 | storefront | 2026-08-10 | REQ-20260810-storefront-redesign |
| done | PRD-20260812-storefront-商城前台注册面板接入-turnstile-真人验证 | storefront | 2026-08-12 | REQ-20260812-turnstile-verification |
| done | PRD-20260812-storefront-商城前台新增cookie功能 | storefront | 2026-08-12 | REQ-20260812-storefront-cookie-consent |
| done | PRD-20260813-storefront-裁剪-admin-storefront-页面-vercel-集成-ui-并优化已连接-origins-展示 | storefront | 2026-08-13 | REQ-20260814-trim-admin-storefront-vercel |
| ⛔废弃 | PRD-20260814-admin-管理后台统一配置中心-集中管理关键参数与-secret-env-从模块取数 | admin | 2026-08-14 | REQ-20260814-admin-config-center |
| done | PRD-20260814-catalog-seo-深度增强-商品-分类级元数据-json-ld-301-重定向 | catalog | 2026-08-14 | REQ-20260815-seo-301-redirects |
| done | PRD-20260814-catalog-图片-cdn-动态变换-resize-format-webp-响应式图片 | catalog | 2026-08-14 | REQ-20260815-image-cdn-transform |
| done | PRD-20260815-storefront-redirects-管理页面增加功能说明文案 | storefront | 2026-08-15 | REQ-20260815-redirects-intro-copy |
| done | PRD-20260816-other-新增cms博客 | other | 2026-08-16 | REQ-20260816-cms-blog |
| done | PRD-20260815-catalog-redirect-页面展示商品-url-变更清单并引导创建重定向 | catalog | 2026-08-15 | REQ-20260815-redirects-url-change-list |
| done | PRD-20260815-other-redirect-增加标题与描述字段 | other | 2026-08-15 | REQ-20260815-redirect-title-description |
| done | PRD-20260815-shipping-补货通知-back-in-stock | shipping | 2026-08-15 | 订阅→补货事件→Resend 邮件 delivered 验证通过 |
| done | PRD-20260815-catalog-邮件管理整合-email-一级菜单-配置-模板-记录-分类-回复开关 | catalog | 2026-08-15 | REQ-20260815-email-management-integration |
| done | PRD-20260829-payments-升级-stripe-支付从-payment-intents-迁移到-checkout-sessions-api-ui_m | payments | 2026-08-29 | （实施时回填） |
| done | PRD-20260831-payments-stripe-自绘卡支付表单-paymentintent-模式 | payments | 2026-08-31 | REQ-20260831-stripe-自绘卡支付表单.md |

| done | PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview | checkout | 2026-09-03 | REQ-20260903-chk-p1-1a.md |
| done | PRD-20260903-checkout-chk-p1-1-order-checkout-application-layer-checkoutview | checkout | 2026-09-03 | REQ-20260903-chk-p1-{1b,2,3,4,4b,4c,5}.md · REQ-20260904-chk-p1-4c4.md |
| done | PRD-20260904-r1-contract-generation-infra | api | 2026-09-04 | REQ-20260904-r1-contract-generation.md |
| done | PRD-20260905-other-txn-p2-6-sdk-consumption | other | 2026-09-05 | REQ-20260905-txn-p2-6-sdk-consumption.md |
| done | PRD-20260831-infra-部署脚本固化与容错-deploy-sf-固化-pull-deploy-磁盘预检与-flock-超时-deploy-rea | infra | 2026-08-31 | REQ-20260831-部署脚本固化与容错.md |
| merged | PRD-20260828-other-p7-逆向链路售后父子单化-flag-灰度 | other | 2026-08-28 | （与 checkout-p7 同需求：历史副本，正式以 checkout 侧为准） |
| done | PRD-20260913-harness-prd-状态一致性检查器-readme-索引-文件头状态自动同步-引擎口径归一-ci-lefthook-漂移即失败 | harness | 2026-09-13 | （实施时回填） |
| done | PRD-20260913-payments-争议本地运营增强与-stripe-深化-规格-68-边界-c-证据素材库-提交前校验-证据版本回执-审批复核-运营报表- | payments | 2026-09-13 | （实施时回填） |
| done | PRD-20260914-checkout-cart-discount-codes-canonical | checkout | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-other-prefixedid-ownership-validation | other | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-other-paymentsource-prefix-disambiguation | other | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-checkout-placeholder-controls-governance | checkout | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-checkout-cart-gift-cards-canonical | checkout | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-checkout-cart-store-credits-canonical | checkout | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-checkout-checkout-收尾收敛-b1-checkoutview-扩展-credits-capabilities-availa | checkout | 2026-09-14 | （实施时回填） |
| done | PRD-20260914-checkout-checkout-收尾收敛-b2-购物车页店铺余额入口与订单摘要三合一 | checkout | 2026-09-14 | （实施时回填） |
| done | PRD-20260915-checkout-checkout-收尾收敛-b3-库存错误四态与履约结果页-recovery-语义-shipment-groups | checkout | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti | checkout | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-checkout-checkout-收尾收敛-b5-legacy-端点治理-usage-metric-收口与零新增调用守护 | checkout | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-admin-管理后台-ui-b6-1-品牌色-token-语义-token-与密度变量基础层 | admin | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-checkout-单页两段语义-prepare-产出-order-权威报价-页内报价确认 | checkout | 2026-09-15 | PRD-20260915-checkout-单页两段语义 |

## 使用流程（摘要，详见 `ai/skills/pallastrade-prd/SKILL.md`）

1. 用户一句话需求 → AI 查重 + 分类 + 生成 PRD（draft）
2. 用户确认 → approved
3. `harness gate` → 生成 REQ → 实施 → 测试
4. 验证 → done → 知识同步门（更新本索引）
| done | PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 | admin | 2026-09-15 | N/A |
| done | PRD-20260915-catalog-pdp-state-correctness | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-admin-bulk-operations-2 | admin | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 | payments | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-admin-catalog-health-v1 | admin | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-catalog-batch-c1-discovery | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-catalog-batch-c2-sku-back-in-stock | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-catalog-batch-d1-product-history | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-catalog-batch-d2-duplicate-detection | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-payments-d9-支付凭据与环境 | payments | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-payments-d10-client-config | payments | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-catalog-batch-e1-ai-copilot | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-payments-d12-webhook-governance | payments | 2026-09-15 | （实施时回填） |
| done | PRD-20260915-catalog-batch-e2-ai-translate-missing | catalog | 2026-09-15 | （实施时回填） |
| done | PRD-20260916-payments-d16-payment-method-presentation | payments | 2026-09-16 | 后端读模型 + 契约三字段 + 前台方法行渲染；`d16-payment-presentation-rspec` + `storefront-test` 绿 |
| done | PRD-20260916-payments-d13-reconciliation-cases | payments | 2026-09-16 | 实施：案例队列（2 表）+ SyncCases（幂等/自动销案/签名取代）+ sweeper 接入 + 后台工作台（指派/备注/关单/CSV）；`d13-reconciliation-cases-rspec` |
| done | PRD-20260916-payments-d11-circuit-breaker-health | payments | 2026-09-16 | 实施：熔断状态机 + 健康指标 + 判定/恢复 + 每小时巡检 + Resolver 同源门禁 + 后台「熔断与健康」卡（原因必填/粘性/审计）；`d11-circuit-breaker-rspec` |
| done | PRD-20260916-catalog-batch-e3-ai-fix-suggestion | catalog | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-catalog-batch-f1-reviews | catalog | 2026-09-16 | 实施：评分分布 + 分页 Load more + 图片评论（≤3 张/直传/未审核不外泄）+ 后台图片列；`reviews-f1-rspec`（后端 31 例）+ `storefront-test`（14 例）绿 |
| done | PRD-20260916-catalog-batch-f2-stock-shipping | catalog | 2026-09-16 | 实施：库存分桶（与 in_stock? 同源、不下发数字）+ 配送估算读模型/端点 + PDP 徽章与配送区块 + 卡片徽章；`f2-stock-shipping-rspec` + 前台 30 例绿 |
| done | PRD-20260916-catalog-batch-f3-review-bulk-moderation | catalog | 2026-09-16 | 实施：评论审核批量通过/拒绝（逐条状态机 + 逐条鉴权 + 四计数报告 + 50 条上限，复用 B-1 模态，零契约变更）；`f3-review-bulk-rspec` 10 例绿 |
| done | PRD-20260916-catalog-batch-f4-review-sorting | catalog | 2026-09-16 | 实施：评论排序（`?sort=` 白名单 + 稳定 tie-break + `meta.sort` + PDP 下拉切换重置首屏 + 5 语言）；后端 10 例 + 前台 30 例绿，`generated:check` 无漂移 |
| done | PRD-20260916-payments-d13b-payout-ledger | payments | 2026-09-16 | 实施：结算台账（2 表）+ CSV 导入（幂等/错误收集）+ 匹配锚点/容差 + 差异行进队列（自动销案）+ 后台台账页（筛选/汇总/详情/导入/重匹配）；`d13b-payouts-rspec`（52 例）绿 |
| done | PRD-20260916-payments-d14-refund-approval | payments | 2026-09-16 | 实施：退款策略阈值（≤ 自动 / > 需第二人批准）+ 幂等请求键 + 审批工作台（不能自批）+ Admin API 策略门与 `approval_status` 契约字段；`d14-refund-approval-rspec`（64 例）绿；期限提醒与拒付率看板留切片2/3 |
| done | PRD-20260916-payments-d14b-dispute-deadlines | payments | 2026-09-16 | 实施（切片2）：T-3/T-1 分档幂等告警（台账唯一键 + 跳档补齐）+ 超期策略化自动 lost（默认关闭 + 单轮上限 + 审计）+ 后台分档看板/列/提醒历史；`d14b-dispute-deadlines-rspec`（41 例，含 DSP-P7-5 回归）绿；零资金副作用；拒付率看板留切片3 |
| done | PRD-20260916-catalog-batch-f5-helpful-vote | catalog | 2026-09-16 | 实施：评论 Helpful Vote（§十 **最后一项**）——新表 `pallastrade_review_votes`（一人一票唯一索引）+ `helpful_votes_count` 计数器 + 2 个投票端点 + 读模型（计数公开 / 本人状态仅登录）+ `most_helpful` 排序 + 前台按钮与登录引导 + 后台 Helpful 列；后端 29 例 + 前台 6 例绿，`f5-helpful-vote-rspec` |
| done | PRD-20260916-payments-d15-risk-lists | payments | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-catalog-d3-product-merge | catalog | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-payments-d13c-fee-cost-report | payments | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-payments-d13d-fx-snapshot | payments | 2026-09-16 | （实施时回填） |
| approved | PRD-20260916-shipping-catalog-observability-scope | shipping | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-catalog-ai-acceptance-audit | catalog | 2026-09-16 |  实施：AI 采纳审计——`AI::Run` 增采纳状态 + `RecordAcceptance` 服务 + `POST /admin/ai/acceptances`（跨店/非法/幂等/改判均有覆盖）+ Runs 列表展示状态；`run_acceptance_spec` / `ai_acceptances_spec` / `ai_assist_edited_source_spec` 绿 |
| done | PRD-20260916-payments-d14c-dispute-rate-board | payments | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-catalog-operations-report | catalog | 2026-09-16 | （实施时回填） |
| done | PRD-20260916-catalog-health-trend-snapshot | catalog | 2026-09-16 | （实施时回填） |
| done | PRD-20260917-catalog-health-coverage-ratios | catalog | 2026-09-17 | （实施时回填） |
| done | PRD-20260917-payments-d15b-risk-rules | payments | 2026-09-17 | （实施时回填） |
| done | PRD-20260917-catalog-ai-edited-before-save | catalog | 2026-09-17 | 实施：“采纳后修改”审计（补方案 §16 最后一项指标）——`accept()` 先写入再快照、提交前比**值**而非“是否碰过”、每次决策只上报一次、上报失败静默不阻断保存；`ai_edited_before_save_spec` + `ai_assist_edited_source_spec` 绿（17/17 AC） |
| done | PRD-20260917-checkout-d15-切片3-3ds-sca-支付认证策略与-provider-下发-高风险订单只给-redirect-3ds | checkout | 2026-09-17 | 实施（D15 切片3）：门店 3DS/SCA 策略（always/risk_based/off + 豁免，两路径归一化）→ 订单级认证需求判定（唯一入口、只读、请求内缓存）→ 规则动作 `force_3ds`（严重度 `allow<review<force_3ds<block`）→ 入口闸门（高风险只给能认证的入口，与 `Start` 同源、建会话前 422）→ 已声明能力才下发（Stripe `request_three_d_secure='any'`）；契约 additive `requires_authentication` + SDK 类型同步；`d15c-three-d-secure-rspec`（181 例，含 D8/D11/D16/切片1·2 回归）绿；零迁移、零资金副作用 |
| done | PRD-20260917-catalog-json-ld-phase2 | catalog | 2026-09-17 | 实施：JSON-LD 第二阶段 **4/4 字段** —— `seller` + `priceValidUntil`（实际命中价目表的 `ends_at`，新增 `Price.price_list_ends_at`）+ `shippingDetails`（复用 PDP 已有运费估算）+ **结构化** `hasMerchantReturnPolicy`（退货条款存 `pallastrade_policies.preferences`，后台 Policies 页编辑，随现有 `policies#show` 下发，零新端点）；四字段缺数据一律**不输出**；后端 22 例 + 前台 23 例绿，`generated:check` 无漂移 |
| done | PRD-20260917-catalog-product-events | catalog | 2026-09-17 | REQ-20260917-catalog-product-events |
| done | PRD-20260917-catalog-bulk-media | catalog | 2026-09-17 | REQ-20260917-catalog-bulk-media |
| done | PRD-20260917-catalog-health-score | catalog | 2026-09-17 | 实施：Catalog Health **可解释健康分** —— 覆盖率从 2 维扩到 **7 维**（`DENOMINATORS` 一处定义五套分母：内容=未归档商品、库存=active、草稿=draft、翻译=商品×语言槽位、URL=变更总数）+ 新增 `CatalogHealth::Score`（**等权**、只对可计算维度加权、分母为 0 或计数报错 → 排除且**不按 0/1 计入**、全不可计算则总分为 `nil`）；工作台总分卡 + 逐维分子/分母/权重/未计入原因；`admin-catalog-health-rspec` 已纳入覆盖率与健康分 spec（92 例绿） |
| done | PRD-20260917-payments-d2-交易排障台-manual_review-审核动作-通过并捕获-拒绝并释放 | payments | 2026-09-17 | 实施（D2）：`manual_review` 唯一人工出口 —— `Transactions::Review`（capture：要求 pending 授权 → provider 捕获 → 新增边 `approve_after_review` → **既有** `Finalize` → completed；release：void 授权 + `Orders::Cancel`（`refund_payments: false` **零退款**）→ 新增边 `release_after_review` → canceled）+ `(transaction, decision)` 审计键幂等（`already_applied`）+ 原因必填 + 不猜拒绝（`no_pending_authorization` / `paid_payment_present` 不改状态）+ 后台复核卡/复核历史/双语键；**人工专用**（job/sweeper/subscriber 零调用点，spec 断言）；零迁移、零契约变更；`d2-manual-review-rspec` 110 例绿 |
| done | PRD-20260917-payments-d3-risk-dashboard-threshold-alerts | payments | 2026-09-17 | 实施（D3）：5 水位只读看板 + 阈值告警 —— `Risk::Dashboard{Policy,Report,Threshold,Alert}`（risky 单占比 / 3DS 挑战率 / **拒付率委派 D14c 不重算** / 退款率 / 审核队列时长含已处理 P90；**不可判定不猜**：分母 0 或报表降级 → `nil` + 结构化 `reason`，绝不回落 0）+ 阈值策略归一化（`warning < critical` 强制、非法不落库、坏载荷 fail-safe 读、双档齐备才算已配置）+ 五态判定（`unconfigured` 不判定）+ 留痕幂等且**同日不降档** + `DashboardAlertSweeperJob`（每小时、逐店隔离）+ 后台 `/admin/payment_risk`（5 卡/策略/告警历史/立即评估）+ 双语键 + GS-177；零迁移、零契约、零资金副作用；`d3-risk-dashboard-rspec` 144 例绿 |
