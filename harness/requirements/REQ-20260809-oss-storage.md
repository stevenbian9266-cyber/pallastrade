# REQ-20260809-oss-storage

## 需求
dev/prod 图片通过阿里云 OSS 维护（Active Storage 切换 OSS，双 bucket 隔离，预留 CDN_HOST 直连切换）。

## 背景
- 图片当前存 backend 容器本地 Disk（`service=:local`），服务器 40G 磁盘 ~87% 占用
- 容器重建丢图、prod/dev 不隔离、图片流量走 backend
- OSS 双 bucket（`pallastrade-prod`/`pallastrade-dev`，杭州 cn-hangzhou）已创建，AccessKey 已验证读写可用

## 方案
1. `config/storage.yml` 新增 `aliyun` service（S3 兼容，virtual-hosted-style，endpoint/bucket/region 走 env）
2. `config/environments/production.rb` 选择逻辑加 OSS 分支（OSS > AWS > Cloudflare > local）
3. 服务器 `.env.prod/.env.dev` 配置 `OSS_*`（内网 endpoint，凭据不入库）
4. 存量 blobs 迁移脚本（Disk → OSS）
5. storefront `next.config.ts` remotePatterns 预加 `img.pallastrade.cn`/`img.dev.pallastrade.cn`
6. `CDN_HOST` 预留（代码已支持，绑定域名后设 env 即切直连）

## Skill 咨询证据表
| Skill | 关键结论 |
|---|---|
| pallastrade-deployment | ActiveStorage 后端经 storage.yml + env 自动检测；OSS 无内置集成 → 走 S3 兼容自定义 service |
| pallastrade-customization | 存储配置属 config 级（Settings→Config），无需 decorator/subscriber |
| pallastrade-prd | 一句话需求 → PRD → gate → 测试 → 知识同步闭环 |

## 验证
- OSS 读写删连通性（已测 PUT/GET/DELETE OK ✅）
- 迁移后 blobs 数与 OSS 对象一致，图片抽样 200
- 本地 storefront 图片回归、服务器 dev 图片显示
- git 无凭据泄露（仅 example 入库）

## 跨层搜索
- backend：`config/storage.yml`（amazon/cloudflare 已有）、`production.rb`（service 选择）、`Gemfile`（aws-sdk-s3 ✅）、`pallastrade_core`（cdn_host 支持 ✅）
- storefront：`next.config.ts`（remotePatterns 已有 pallastrade.cn）
- platform/admin：无图片存储逻辑，复用
- 结论：仅需新增 aliyun service + OSS 分支 + env + 迁移脚本 + remotePatterns，无重复实现
