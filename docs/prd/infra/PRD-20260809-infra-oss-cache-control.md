# PRD-20260809-infra-oss-cache-control

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-09 |
| 来源 | 需求：OSS 图片加 Cache-Control（提升浏览器缓存性能） |
| 分类 | infra（部署 / 基础设施 / 性能优化） |
| 关联 Skill | pallastrade-deployment |
| 关联 REQ | （实施时回填） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求原文**：OSS 图片加 Cache-Control
- **背景**：实测 OSS 图片对象响应头 `Cache-Control` 为空 → 浏览器/客户端缓存不充分，重复访问反复回源，浪费带宽 + 增加延迟。前后台（后台 `representations/redirect`、前台 `_next/image` 回源）都从 OSS 拉图，均受影响
- **目标**：OSS 图片对象带 `Cache-Control: public, max-age=31536000, immutable`，浏览器强缓存
- **成功指标**：图片响应头含 Cache-Control；二次访问走浏览器缓存（无网络请求）

## 2. 用户故事 / 场景

- 作为访客：第二次访问商城，图片从浏览器缓存加载（秒开）
- 作为管理员：后台图片重复查看不重复下载
- 场景：新上传图片（自动带头）；存量图片（批量补头）

## 3. 功能需求（FR）

- FR-001：`config/storage.yml` aliyun service 上传配置加 `upload: { cache_control: "public, max-age=31536000, immutable" }`（新对象自动带头）
- FR-002：存量对象批量设置 Cache-Control（AWS `copy_object` + `metadata_directive: REPLACE`，脚本遍历 dev/prod bucket 图片对象）
- FR-003：验证：`curl -I` 图片对象返回 Cache-Control 头

## 4. 非功能需求（NFR）

- 安全：图片对象公共读，immutable 缓存安全（对象 key 不可变）
- 性能：减少重复回源
- 兼容：不改变对象内容/URL；变体对象同样受益

## 5. 验收标准（AC）

- AC-001 ← FR-001：storage.yml 含 cache_control 上传配置；新上传图片带 Cache-Control
- AC-002 ← FR-002：存量对象批量执行后，抽样对象 `curl -I` 返回 `Cache-Control: public, max-age=31536000, immutable`
- AC-003 ← FR-003：dev 商城页面图片二次访问命中浏览器缓存

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | cache_control | 无 | 不适用 |
| Core | `pallastrade_gems/pallastrade_core/app/` | active_storage | 无上传头配置 | 不适用 |
| API | `pallastrade_gems/pallastrade_api/app/` | 图片 URL | media_serializer（URL 生成） | 复用 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | 上传 | uppy active_storage | 复用 |
| Storefront | `storefront/src/` | next/image | next.config（minimumCacheTTL 300） | 不受影响 |
| Platform | `platform/packages/` | 图片 | 无 | 不适用 |

**结论**：缓存头在 OSS 对象层（service 上传配置），无应用代码重复。需验证 ActiveStorage S3 service `upload` 配置支持 cache_control。

## 7. 技术影响

- 修改：`config/storage.yml`（aliyun service 加 upload 配置）
- 新增：一次性批量补头脚本（lib/tasks/ 或 ossutil）
- 依赖：aws-sdk-s3（已有）
- 影响面：仅 OSS 对象响应头，URL/内容不变

## 8. 测试计划

- 新上传对象：curl -I 验证 Cache-Control
- 存量对象：批量执行后抽样验证
- 回归：dev 页面图片 200

## 9. 文档同步清单（知识同步门）

- [x] `docs/prd/README.md` 索引
- [x] PRD 状态更新
- [x] 服务器部署说明（如涉及）

**知识评估结论**（sync-check）：`config/storage.yml` 变更不在 doc-impact 同步矩阵（Skill/README/Agent 等），pallastrade-deployment skill 的 ActiveStorage 配置章节已涵盖通用 S3 upload 选项，无需更新。

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-09 | 0.1 | 初稿 | AI |
| 2026-08-09 | 0.2 | 实施完成：storage.yml upload cache_control + 存量 747 对象批量补头（ossutil set-meta -r --update -f）+ 验证 200 | AI |
