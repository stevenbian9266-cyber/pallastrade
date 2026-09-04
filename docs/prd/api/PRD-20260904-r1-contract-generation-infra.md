# PRD-20260904-r1-contract-generation-infra

> 一句话需求：实施 R1 基建——rswag/typelizer 可运行化（消除 SDK/yaml 手写漂移）。用户确认方案 A（Schema 全自动生成 + Paths 维持校验），Docker 执行。

## 1. 背景

P1 系列因契约生成管线不可运行，长期手写同步 SDK 类型与 `backend/public/api-docs/{store,admin}.yaml`，产生漂移风险与 Psych 损坏史。调研确认：

- `generated:check` 现状**空转**：`harness.config.mjs → generatedCheck.checks` 两命令均 `|| echo SKIP`（SDK Types 脚本不存在、CLI spec 未配置）。
- Typelizer 已可运行（host app context）：`rake typelizer:generate` 产出 `backend/packages/{sdk,admin-sdk}/src/types/generated`；`generated:check` 曾报 no drift 实为未运行。
- `pallastrade_api` 提供可复用 `OpenAPI::SchemaHelper`（`all_schemas`/`admin_schemas`：common + Typelizer schemas + x-typelizer 标记 + 数组/枚举补丁）与 `PathSorter`（canonical paths 排序）。
- yaml 中 62/66 个 schema 带 `x-typelizer: true` → 曾由管线生成；现全手维护（store 92 ops / admin 240 ops / 178 schemas）。
- rswag 全量重建不可行（gem 无 spec/dummy、host bundle 无 rswag-specs、~332 ops 需数周）→ 排除方案 B。

## 2. 方案（A：Schema 全自动 + Paths 维持校验）

```
serializers (typelize hints) ──Typelizer──▶ backend/packages/{sdk,admin-sdk}/src/types/generated   (SDK 类型)
                                       └─▶ SchemaHelper 生成集 ──api:docs:schemas:generate──▶ store/admin.yaml
                                                                        components.schemas 仅 typelizer 拥有项
paths/info/tags（手维护，字节不变）◀── $ref 完整性校验（api:docs:validate）──▶ 端点正确性
```

交付（详见 `REQ-20260904-r1-contract-generation`）：

- R1-A1：宿主 rake `api:docs:schemas:generate|check`（合并保留算法 + 幂等）+ `api:docs:validate`（$ref/解析）。
- R1-A2：SDK 类型接入：`api:docs:generate|check` 串联 `typelizer:generate`。
- R1-A3：编排 `scripts/ci/contracts.sh`（docker exec + platform 副本同步）。
- R1-A4：`generated:check` 真实接线（docker-gated，CI-safe SKIP）。
- R1-A5：一次规范化提交（yaml schema 段）+ 幂等 0 diff 验证 + platform api-v3-docs-check 通过。

## 3. AC（与测试映射）

- AC-101 ← R1-A1：`api:docs:schemas:generate` 后 `api:docs:schemas:check` exit 0（幂等）；两次运行产物一致。
- AC-102 ← R1-A1：仅 x-typelizer 拥有项被改写/增删；手维护 schema（无标记）与 paths/info 字节不变（git diff 校验）。
- AC-103 ← R1-A1：`api:docs:validate` 通过（Psych 解析 + 全部 `#/components/schemas/X` $ref 有目标）。
- AC-104 ← R1-A2：`rake typelizer:generate`（docker, ENABLE_TYPELIZER=1）幂等 0 diff。
- AC-105 ← R1-A4：`harness generated:check`（容器在场）真实运行 SDK Types + OpenAPI Schemas 两项且 0 drift；容器缺席时 SKIP 不报错。
- AC-106 ← 回归：platform `api-v3-docs-check` 通过；storefront typecheck 0；既有请求 spec 不受影响。

## 4. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-04 | 0.1 | 初稿（方案 A + Docker；调研结论：generated:check 空转、typelizer 可运行、rswag 全量不可行） | AI |
| 2026-09-04 | 0.2 | 实施完成：宿主 rake api:docs:{schemas,schemas:check,validate,generate,check}（components.schemas Typelizer 拥有项自动重写 + paths $ref 硬校验 + 幂等）；Symbol→String/iso8601 归一；修复手维护悬空 ref（Error→ErrorResponse、AdminPost→Post）；typelizer 生成类型归一 + zod 派生同步 + platform 副本同步；generated:check 接入 contracts.sh（docker-gated）；docs/contracts/README + skills changelog | AI |
