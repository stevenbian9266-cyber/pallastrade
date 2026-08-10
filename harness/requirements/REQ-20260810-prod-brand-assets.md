# REQ-20260810-prod-brand-assets

## 需求
完成 prod 品牌资产部署待办：prod storefront 镜像（品牌资产+seo.ts）+ attach prod mailer_logo。

## 背景
- dev 品牌资产部署已完成（PRD-20260809-storefront-brand-assets，done）
- prod 栈停止，待办：prod storefront 镜像更新 + prod backend store mailer_logo attach

## 方案
1. 本地构建 prod storefront 镜像（build args：PALLASTRADE_API_URL=https://pallastrade.cn + prod key pk_aRyDJMXg8si8Ni8xtC1366nu）
2. docker save → scp → 服务器 load
3. 单栈切换（dev down → prod up）→ 部署 prod storefront + attach prod mailer_logo → 验证
4. 提交品牌资源套件文件（catalog PRD / REQ / tests / brand-assets 源目录）

## Skill 咨询证据表
| Skill | 关键结论 |
|---|---|
| pallastrade-storefront | 品牌资产部署沿用（prod 镜像同法） |
| docs/standards/logo.md | 各使用位置要求 |
| pallastrade-deployment | 单栈策略、镜像传输 |

## 验证
- prod 页面 200 + 品牌 logo/favicon/og 200
- prod store mailer_logo attached
- 单栈切换后服务器稳定

## 跨层搜索
- 复用 PRD-20260809-storefront-brand-assets 部署路径（dev 已验证）
- 无重复实现
