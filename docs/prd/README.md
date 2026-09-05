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
| approved | PRD-20260905-checkout-txn-p2-6-轮3-storefront-transaction-first-迁移-checkout-start-b | checkout | 2026-09-05 | REQ-20260905-txn-p2-6-storefront-transaction-first.md |
| approved | PRD-20260905-payments-txn-p2-6-contract-snapshot | payments | 2026-09-05 | REQ-20260905-txn-p2-6-contract-snapshot.md |
| approved | PRD-20260905-other-txn-p2-closure-report-and-store-serializer | other | 2026-09-05 | REQ-20260905-txn-p2-closure.md |
| approved | PRD-20260905-payments-txn-p2-7-operational-hardening-backend-slice | payments | 2026-09-05 | REQ-20260905-txn-p2-7.md |
| approved | PRD-20260904-payments-txn-p2-5-unified-finalization-transactions-finalize-onpaymentsuccess | payments | 2026-09-04 | REQ-20260904-txn-p2-5.md |
| approved | PRD-20260904-payments-txn-p2-4-recovery-engine-recovery-required-权威状态解析-recover | payments | 2026-09-04 | REQ-20260904-txn-p2-4.md |
| approved | PRD-20260904-payments-txn-p2-3-payment-fact-resolver-provider-只读状态契约-资金事实判定 | payments | 2026-09-04 | REQ-20260904-txn-p2-3.md |
| approved | PRD-20260904-api-txn-p2-2-transactions-start-resume-事务启动幂等-quote-consent-sess | api | 2026-09-04 | REQ-20260904-txn-p2-2.md |
| approved | PRD-20260904-checkout-txn-p2-1-commercetransaction-core-transactions-transaction_o | checkout | 2026-09-04 | REQ-20260904-txn-p2-1.md |
| done | PRD-20260902-payments-payment-p0-foundation-hardening-paymentsession-payment-正式关联- | payments | 2026-09-02 | REQ-20260902-payment-p0.md |
| done | PRD-20260831-harness-实施-harness-token-优化-宿主侧 | harness | 2026-08-31 | REQ-20260831-harness-token-optimization-host.md |
| approved | PRD-20260830-checkout-下单链路规范化统一化-场景a-b统一下单页-场景c收银台弹窗-参考阿里国际站 | checkout | 2026-08-30 | REQ-20260901-positive-checkout-payment-flow-hardening.md |
| done | PRD-20260830-other-修复-skill-权威路径 | other | 2026-08-30 | REQ-20260830-fix-skill-authority-paths.md |
| approved | PRD-20260829-checkout-订单模块-单笔走现有checkout-多笔走组合支付新流程-收货信息独立填写 | checkout | 2026-08-29 | REQ-20260830-order-module-single-combined-payment.md |
| approved | PRD-20260829-checkout-订单流程标准电商改造-购物车与订单分表-订单确认-提交订单-checkout纯支付-自有化去spree化 | checkout | 2026-08-29 | REQ-20260830-order-flow-standard-ecommerce-p1.md |
| done | PRD-20260828-checkout-p8-前置校验-库存-风控-订单服务增强-flag-灰度 | checkout | 2026-08-28 | REQ-20260828-order-lifecycle-p8.md |
| done | PRD-20260828-checkout-p7-逆向链路售后父子单化-flag-灰度 | checkout | 2026-08-28 | REQ-20260828-order-lifecycle-p7.md |
| done | PRD-20260828-admin-p6-admin-手动拆单-父子树-ui-flag-灰度 | admin | 2026-08-28 | REQ-20260828-order-lifecycle-p6.md |
| done | PRD-20260827-checkout-实施-p5-checkout-集成-自动拆单-合并支付收银台-buy-now-flag-灰度 | checkout | 2026-08-27 | REQ-20260827-order-lifecycle-p5.md |
| done | PRD-20260827-payments-实施-p4-合并支付载体-paymentcombination-服务层-webhook-幂等完成 | payments | 2026-08-27 | REQ-20260827-order-lifecycle-p4.md |
| done | PRD-20260827-payments-实施-p3-父子单金额与支付状态派生-combined_total-payment-shipment_state-聚合 | payments | 2026-08-27 | REQ-20260827-order-lifecycle-p3.md |
| done | PRD-20260826-checkout-实施-p2-统一拆单引擎-orders-splitter-策略分组-调整分摊-幂等 | checkout | 2026-08-26 | REQ-20260826-order-lifecycle-p2.md |
| done | PRD-20260826-payments-实施-p1-数据模型与语义方法-父子单-parent_id-paymentcombination-paymentspli | payments | 2026-08-26 | REQ-20260826-order-lifecycle-p1.md |
| draft | PRD-20260818-catalog-p0-4-产品评论 | catalog | 2026-08-18 | （实施时回填） |
| draft | PRD-20260818-other-p0-3-邮件自动化-弃单恢复 | other | 2026-08-18 | （实施时回填） |
| approved | PRD-20260817-other-移除根-package-json-无用的-glob-弃用依赖 | other | 2026-08-17 | （实施时回填） |
| approved | PRD-20260817-admin-新建店铺表单-货币语言选择器与邮箱预设 | admin | 2026-08-17 | （实施时回填） |
| draft | PRD-20260817-admin-多店铺管理-店铺列表-新建-切换 | admin | 2026-08-17 | （实施时回填） |
| draft | PRD-20260817-admin-菜单配置收敛-结构代码化-可视化只读展示-权限配置依据 | admin | 2026-08-17 | （实施时回填） |
| reviewing | PRD-20260816-admin-后台可视化菜单配置模块-角色权限体系-菜单-数据-功能权限 | admin | 2026-08-16 | （实施时回填） |
| approved | PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局 | admin | 2026-08-16 | REQ-20260816-admin-nav-architecture |
| done | PRD-20260816-admin-管理后台导航一致性-主区按-email-模式-设置区按-settings-模式统一 | admin | 2026-08-16 | REQ-20260816-admin-nav-consistency |
| draft | PRD-20260813-admin-移除管理后台-integrations-菜单及相关逻辑 | admin | 2026-08-13 | （实施时回填） |
| done | PRD-20260808-admin-去掉管理后台左侧菜单的升级逻辑-community-edition-升级提示 | admin | 2026-08-08 | REQ-20260808-remove-enterprise-notice |
| done | PRD-20260808-admin-ai-tools-page-optimization | admin | 2026-08-08 | REQ-20260808-ai-tools-page-optimization |
| done | PRD-20260808-api-实施-ai-tools-模块优化-p0-locale修复-添加provider-p1-预设可见-引导-p2-api文档- | api | 2026-08-08 | REQ-20260808-ai-tools-optimization |
| done | PRD-20260808-harness-l4-promotion | harness | 2026-08-08 | REQ-20260808-harness-l4-promotion |
| done | PRD-20260809-infra-aliyun-dev-prod-deploy | infra | 2026-08-09 | REQ-20260809-infra-aliyun-dev-prod-deploy |
| done | PRD-20260809-infra-oss-storage | infra | 2026-08-09 | REQ-20260809-oss-storage |
| merged | PRD-20260809-infra-oss-cache-control | infra | 2026-08-09 | REQ-20260809-oss-cache-control |
| done | PRD-20260809-harness-prd-dedupe-update | harness | 2026-08-09 | REQ-20260809-harness-prd-dedupe-update |
| reviewing | PRD-20260809-storefront-brand-assets | storefront | 2026-08-09 | （实施时回填） |
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
| approved | PRD-20260829-payments-升级-stripe-支付从-payment-intents-迁移到-checkout-sessions-api-ui_m | payments | 2026-08-29 | （实施时回填） |
| implementing | PRD-20260831-payments-stripe-自绘卡支付表单-paymentintent-模式 | payments | 2026-08-31 | REQ-20260831-stripe-自绘卡支付表单.md |

| done | PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview | checkout | 2026-09-03 | REQ-20260903-chk-p1-1a.md |
| done | PRD-20260903-checkout-chk-p1-1-order-checkout-application-layer-checkoutview（1B/2/3/4/4B/4C/4C4/5 实施收口） | checkout | 2026-09-03 | REQ-20260903-chk-p1-{1b,2,3,4,4b,4c,5}.md · REQ-20260904-chk-p1-4c4.md |
| done | PRD-20260904-r1-contract-generation-infra | api | 2026-09-04 | REQ-20260904-r1-contract-generation.md |
## 使用流程（摘要，详见 `ai/skills/pallastrade-prd/SKILL.md`）

1. 用户一句话需求 → AI 查重 + 分类 + 生成 PRD（draft）
2. 用户确认 → approved
3. `harness gate` → 生成 REQ → 实施 → 测试
4. 验证 → done → 知识同步门（更新本索引）
