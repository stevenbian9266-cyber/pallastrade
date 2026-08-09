# PRD-20260809-infra-oss-storage

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-09 |
| 来源 | 需求：dev/prod 图片通过阿里云 OSS 统一维护（存 OSS + 预留自定义域名/CDN） |
| 分类 | infra（部署 / 基础设施） |
| 关联 Skill | pallastrade-deployment |
| 关联 REQ | REQ-20260809-oss-storage.md |
| 需求类型 | 新功能（基础设施） |

## 1. 背景与目标

- **一句话需求原文**：dev/prod 环境的图片通过 OSS 维护起来（公共读 + CDN，敏感附件私有签名）
- **背景**：
  - 当前图片用 Rails Active Storage **本地 Disk**（backend 容器内 `storage/`），服务器 40G 磁盘已用 ~87%，图片是主要占用
  - 容器重建/迁移会丢图；prod/dev 数据不隔离；图片流量全走 backend（nginx→backend），占用服务器带宽
  - 服务器为 2C/3.5G 小规格（ECS `ecs.c7.large`，杭州 cn-hangzhou-j），资源紧张
- **目标**：
  - Active Storage 切换阿里云 OSS（S3 兼容，virtual-hosted-style）
  - prod/dev 双 bucket 隔离（`pallastrade-prod` / `pallastrade-dev`，已创建）
  - 预留 `CDN_HOST`（img.pallastrade.cn / img.dev.pallastrade.cn）切换位，域名绑定后一行 env 切换直连 OSS
- **成功指标**：
  - 服务器 backend 容器内 `storage/` 不再增长；磁盘压力解除
  - 图片 URL 在未绑定自定义域名期间走 backend 反代（302→OSS），绑定后直连 `img.*.pallastrade.cn`
  - 现有 ~869 blobs 迁移后图片全部可访问

## 2. 用户故事 / 场景

- 作为管理员：上传商品图 → 存储到 OSS，不占服务器磁盘
- 作为访客：打开商城 → 图片正常显示（未绑定域名时经 backend 302→OSS；绑定后直连 img 域名/CDN）
- 作为开发者：本地开发仍用 local 存储，不受影响
- 场景：正常上传/显示；迁移期间服务不中断；OSS 凭据失效时回滚 local

## 3. 功能需求（FR）

- FR-001：`config/storage.yml` 新增 `aliyun` service（S3 兼容 + endpoint + `force_path_style: false`（virtual-hosted-style，OSS 要求），bucket/region 走 env）
- FR-002：`config/environments/production.rb` 选择逻辑加 OSS 分支（优先级 OSS > AWS > Cloudflare > local）
- FR-003：`.env.prod` / `.env.dev`（服务器，不入库）配置 `OSS_ACCESS_KEY_ID/SECRET/ENDPOINT/REGION/BUCKET` + 内网 endpoint `oss-cn-hangzhou-internal.aliyuncs.com`
- FR-004：存量 blobs 迁移脚本（本地 Disk → OSS，逐 blob 上传，支持重试），迁移后验证可读
- FR-005：预留 `CDN_HOST`（`PallasTrade.cdn_host` 已支持），代码不强制；绑定 img 域名后设 env 即切直连 OSS
- FR-006：storefront `next.config.ts` `images.remotePatterns` 预加 `img.pallastrade.cn` / `img.dev.pallastrade.cn`（防切域名后 400）
- FR-007：dev/prod 双 bucket 隔离；本地开发保持 `local` 不受影响

## 4. 非功能需求（NFR）

- 安全：AccessKey 只写服务器 env / GitHub Secrets，**不入库**（git 只追踪 `.env.*.example`）
- 性能：同地域内网 endpoint（免费 + 快）；绑定域名后走 CDN 缓存
- 兼容：Active Storage `signed_id` 不变，URL 路径结构不变；storefront 无逻辑改动
- 可维护：凭据失效可回滚 local；迁移双写过渡

## 5. 验收标准（AC）

- AC-001 ← FR-001/002：`storage.yml` + `production.rb` 支持 OSS 分支，`OSS_*` env 存在时 active_storage.service = aliyun
- AC-002 ← FR-003：服务器 `.env.prod/.env.dev` 含 OSS 配置；git 无凭据泄露（`git ls-files` 仅 example）
- AC-003 ← FR-004：迁移后 OSS 中对象数与 DB blobs 数一致（~869）；随机抽查图片 200
- AC-004 ← FR-005/006：`remotePatterns` 已含 img 域名；未设 CDN_HOST 时图片走 backend 反代 200
- AC-005 ← FR-007：prod/dev 各指向各自 bucket；本地 storefront 图片仍正常

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | active_storage/图片 | 无（存储配置在 config/） | 不适用 |
| Core | `pallastrade_gems/pallastrade_core/app/` | cdn_host、rails_blob_url | `core/lib/pallastrade/core.rb`（cdn_host 配置）、`core/config/routes.rb`（cdn_host 用于 URL host） | ✅ 已有 CDN_HOST 支持 |
| API | `pallastrade_gems/pallastrade_api/app/` | rails_blob_url | `api/app/serializers/.../media_serializer.rb`（host 解析含 cdn_host） | ✅ 无需改 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | active_storage 上传 | admin 上传组件（uppy active_storage） | ✅ 复用 |
| Storefront | `storefront/src/` | next/image、remotePatterns | `storefront/next.config.ts`（已有 pallastrade.cn 等）、`components/ui/product-image.tsx` | 需加 img 域名 |
| Platform | `platform/packages/` | 图片 URL | 无图片处理 | 不适用 |

**结论**：后端 CDN_HOST/媒体 URL 机制已具备；只需 storage.yml + production.rb + env + 迁移 + storefront remotePatterns。无重复实现。

## 7. 技术影响

- 新增：`config/storage.yml` aliyun service；迁移脚本 `lib/tasks/`（或一次性 runner）
- 修改：`config/environments/production.rb`；`.env.prod/.env.dev`（服务器）；`storefront/next.config.ts`
- 依赖：`aws-sdk-s3`（已有 ✅）
- 影响面：backend 存储层、部署配置、storefront 图片白名单

## 8. 测试计划

- 连通性：AWS SDK 读写删测试（已验证 PUT/GET/DELETE OK ✅）
- 迁移验证：blobs 数对比 + 图片 URL 抽样 200
- 回归：本地 storefront 图片显示、服务器 dev/prod 图片显示
- 映射：AC-001~005 → 部署验证（无新增单测文件，属基础设施变更）

## 8.5 自定义域名与证书配置（2026-08-09 实施完成）

### 域名解析（阿里云云解析 DNS）
- `img.pallastrade.cn` → CNAME → `pallastrade-prod.oss-cn-hangzhou.aliyuncs.com`
- `img.dev.pallastrade.cn` → CNAME → `pallastrade-dev.oss-cn-hangzhou.aliyuncs.com`
- 主机记录：`img`（prod）、`img.dev`（dev 四级域名，前缀要填完整）

### OSS 自定义域名绑定（双 bucket）
- `pallastrade-prod` ⇄ `img.pallastrade.cn`（Enabled）
- `pallastrade-dev` ⇄ `img.dev.pallastrade.cn`（Enabled）
- ⚠️ 踩坑：`img.pallastrade.cn` 曾被误绑到 dev bucket，已用 ossutil `bucket-cname --method delete/put` 修正到 prod

### HTTPS 免费证书（Let's Encrypt，非阿里云）
- 服务器 certbot **DNS-01** 签发（img 域名解析到 OSS，HTTP-01 不可行，必须 DNS-01；需要人工在阿里云云解析加 `_acme-challenge.*` TXT 记录）
- 单证书 SAN：`img.pallastrade.cn` + `img.dev.pallastrade.cn`，2026-11-07 到期，certbot 自动续期；**续期后需重新上传证书到 OSS**（手动步骤）
- 上传：`ossutil bucket-cname --method put --item certificate oss://<bucket> cert.xml`
- ⚠️ 踩坑：证书 XML 必须带 `<Force>true</Force>` 强制覆盖 OSS 默认证书，否则 HTTPS 仍显示 `cn-hangzhou.oss.aliyuncs.com` 默认证书
- RAM 子账号需 `AliyunYundunCertFullAccess`（上传证书实际调用 `yundun-cert:CreateSSLCertificate`）

### CDN_HOST 决策（暂不启用）
- `cdn_image_url` 生成 `https://{CDN_HOST}/rails/active_storage/...` 路径
- img 域名是 OSS CNAME（仅对象路径，无 `active_storage` 路由）→ 直接设 CDN_HOST 会 404 破坏图片
- 当前图片走 backend 反代（全 HTTPS），**不设置 CDN_HOST**
- 将来配阿里云 CDN（能处理 active_storage 路径回源 OSS）后再设 `CDN_HOST=img.*.pallastrade.cn`，一行 env 切换

### 当前图片链路（全 HTTPS）
```
storefront → dev.pallastrade.cn/rails/active_storage/... → 302 → OSS bucket 域名(HTTPS) → 200
```

## 9. 文档同步清单（知识同步门）

- [ ] `ai/skills/pallastrade-deployment/SKILL.md`（OSS 配置/环境变量）
- [x] `docs/prd/README.md` 索引
- [x] PRD 状态更新（reviewing → approved → done）
- [x] 服务器部署 README/notes（如 `deploy/` 说明）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿（含 OSS 方案调研 + 凭据验证结果） | AI |
| 2026-08-09 | 0.2 | 实施完成：aliyun service + public URL、迁移 741 blobs、nginx dev active_storage 端口修复（3100→3102）、公网图片 200 | AI |
| 2026-08-09 | 0.3 | 自定义域名/证书：DNS CNAME、双 bucket 绑定修正、Let's Encrypt DNS-01 签发、OSS 证书上传（Force 经验）、CDN_HOST 决策（暂不启用） | AI |
