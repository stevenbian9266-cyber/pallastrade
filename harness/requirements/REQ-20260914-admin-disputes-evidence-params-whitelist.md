# REQ-20260914-admin-disputes-evidence-params-whitelist — 争议证据载荷去 permit!（Brakeman 告警消除）

> 关联 PRD：`docs/prd/admin/PRD-20260914-admin-disputes-evidence-params-whitelist.md`（done）
> 来源：用户指令「同时做1和2」→ ① 修掉 Backend CI 的 Brakeman 告警（2026-09-14）
> Task：`TASK-20260914014133-3ebe20ff`；Gate：`GATE-2026-09-14T01-41-40`（security，critical 风险）
> 产出：admin 争议控制台 `evidence_payload` 参数处理去除 `permit!`

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 结果 |
|---|---|---|
| App | `backend/app/` | 无争议控制台实现 |
| Core | `pallastrade_core/app/` | `disputes/evidence_catalog.rb#validate`（**权威白名单**：`unknown_evidence_key:*` + 类型/长度）、`pre_submit_check.rb`、`submit_evidence.rb` | 
| API | `pallastrade_api/app/` | `params_normalizer.rb:24` 另有一处 `permit!`（**未被 Brakeman 告警**，本次范围外） |
| Admin | `pallastrade_admin/app/` | `disputes_ops_controller.rb` L337-342 `raw.permit!.to_h`（**告警点 / 本次改动**）、L184-186 `submit_evidence` 已用 `to_unsafe_h` |
| Storefront | `storefront/src/` | 无 |
| Platform | `platform/packages/` | 无 |

**结论**：告警点单方法；服务层已有强校验，本次仅改参数提取方式，语义不变。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-security` | ✅ 已读（L40-54 Strong Parameters / L79-83 Mass assignment） | 「始终白名单参数，**禁止** `params.permit!` 或把用户输入 splat 进 mass assignment」；Mass assignment 的防线就是 `permit`（勿用 `attr_readonly` 替代） |

## 实施结果（2026-09-14）

| 项 | 结果 |
|---|---|
| FR-001 去 `permit!` | ✅ `to_unsafe_h.except('controller','action','authenticity_token','utf8','id')`，附 `# PALLAS-CUSTOM:` 依据注释 |
| FR-002 路径一致 | ✅ 与 `submit_evidence` 同用 `to_unsafe_h` |
| FR-003 服务层语义不变 | ✅ `EvidenceCatalog#validate` 未改（未知键仍报 `unknown_evidence_key:*`） |
| FR-004 范围外 | ✅ 另两处 `permit!` 本次不动（无告警） |

## 验证与证据（2026-09-14）

| 证据 | 结果 |
|---|---|
| Brakeman（复刻 CI：`bundle exec brakeman --no-pager -q`） | ✅ **Security Warnings: 0**（修复前 1） |
| `disputes_ops_evidence_ops_spec.rb` + `disputes_ops_actions_spec.rb` | ✅ 19 examples, 0 failures |
| Controller 无 `permit!` | ✅（见 PRD AC-004） |
| CI Backend CI 转绿 | ⏳ 推送后观察 |

## 后续任务

| # | 内容 |
|---|---|
| 1 | 如需，评估 `params_normalizer.rb` / `prepare_nested_attributes.rb` 两处 `permit!`（当前无告警，属技术债） |
