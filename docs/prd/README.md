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
| done | PRD-20260808-admin-去掉管理后台左侧菜单的升级逻辑-community-edition-升级提示 | admin | 2026-08-08 | REQ-20260808-remove-enterprise-notice |
| done | PRD-20260808-admin-ai-tools-page-optimization | admin | 2026-08-08 | REQ-20260808-ai-tools-page-optimization |
| done | PRD-20260808-api-实施-ai-tools-模块优化-p0-locale修复-添加provider-p1-预设可见-引导-p2-api文档- | api | 2026-08-08 | REQ-20260808-ai-tools-optimization |
| done | PRD-20260808-harness-l4-promotion | harness | 2026-08-08 | REQ-20260808-harness-l4-promotion |
| done | PRD-20260809-infra-aliyun-dev-prod-deploy | infra | 2026-08-09 | REQ-20260809-infra-aliyun-dev-prod-deploy |
| reviewing | PRD-20260809-infra-oss-storage | infra | 2026-08-09 | （实施时回填） |
| reviewing | PRD-20260809-infra-oss-cache-control | infra | 2026-08-09 | （实施时回填） |

## 使用流程（摘要，详见 `ai/skills/pallastrade-prd/SKILL.md`）

1. 用户一句话需求 → AI 查重 + 分类 + 生成 PRD（draft）
2. 用户确认 → approved
3. `harness gate` → 生成 REQ → 实施 → 测试
4. 验证 → done → 知识同步门（更新本索引）
