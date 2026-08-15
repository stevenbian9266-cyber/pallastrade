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
| done | PRD-20260815-catalog-redirect-页面展示商品-url-变更清单并引导创建重定向 | catalog | 2026-08-15 | REQ-20260815-redirects-url-change-list |
| done | PRD-20260815-other-redirect-增加标题与描述字段 | other | 2026-08-15 | REQ-20260815-redirect-title-description |
| reviewing | PRD-20260815-shipping-补货通知-back-in-stock | shipping | 2026-08-15 | （实施时回填） |

## 使用流程（摘要，详见 `ai/skills/pallastrade-prd/SKILL.md`）

1. 用户一句话需求 → AI 查重 + 分类 + 生成 PRD（draft）
2. 用户确认 → approved
3. `harness gate` → 生成 REQ → 实施 → 测试
4. 验证 → done → 知识同步门（更新本索引）
