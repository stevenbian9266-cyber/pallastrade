# REQ-20260809-oss-cache-control

## 需求
OSS 图片对象加 `Cache-Control: public, max-age=31536000, immutable`，优化浏览器缓存（实测当前为空）。

## 背景
- OSS 图片响应头 Cache-Control 为空 → 浏览器缓存不充分，重复访问回源
- 前后台图片都从 OSS 拉取，均受益

## 方案
1. `config/storage.yml` aliyun service 加 `upload: { cache_control: "public, max-age=31536000, immutable" }`（新对象自动带头，已验证 S3 service `upload_options` → `put(**, upload_options)` 支持）
2. 存量对象批量补头：AWS `copy_object` + `metadata_directive: REPLACE`（脚本遍历 dev/prod bucket 图片对象）
3. 验证 `curl -I` 返回 Cache-Control

## Skill 咨询证据表
| Skill | 关键结论 |
|---|---|
| pallastrade-deployment | ActiveStorage S3 service 配置 upload 选项（config/storage.yml） |
| pallastrade-customization | 存储配置属 config 级，无需 decorator |
| pallastrade-prd | 一句话需求 → PRD → gate → 测试 → 知识同步闭环 |

## 验证
- 新上传对象 curl -I 带 Cache-Control
- 存量对象批量后抽样验证
- dev 页面图片回归 200

## 跨层搜索
- backend：storage.yml（aliyun service）、S3 service 源码（upload_options → put 支持 cache_control ✅）
- storefront/admin/api：无图片缓存头逻辑，复用
- 结论：仅 storage.yml 配置 + 一次性补头脚本，无重复实现
