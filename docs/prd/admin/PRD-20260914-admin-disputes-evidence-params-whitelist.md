# PRD-20260914-admin-disputes-evidence-params-whitelist

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | 用户在 Backend CI 排查后要求「修掉这条 Brakeman 告警」（`params[:evidence].permit!`） |
| 分类 | admin |
| 关联 Skill | pallastrade-security / pallastrade-admin |
| 关联 REQ | REQ-20260914-admin-disputes-evidence-params-whitelist.md |
| 关联 PRD | N/A（查重未命中） |
| 需求类型 | 安全修复（Brakeman Mass Assignment） |

> 背景：`Backend CI` 自 2026-09-13 起持续红，失败步骤为 `bundle exec brakeman --no-pager -q`（exit 3），唯一告警 = `pallastrade_gems/pallastrade_admin/app/controllers/pallastrade/admin/disputes_ops_controller.rb:341  params[:evidence].permit!`（Mass Assignment, Medium）。RSpec 步骤本身是通过的。

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **现象**：Backend CI 因 Brakeman 告警持续失败；告警点 `disputes_ops_controller.rb:341` 使用 `permit!`（任意键 + 静默标白，Mass Assignment Medium）。
- **关键事实（已核实）**：`evidence_payload` 仅用于两处（`precheck` 零写校验、`approve_draft` 签核记录）的「参数 → 纯 Hash」转换；**键的合法性已在服务层强制** —— `EvidenceCatalog#validate` 对目录外键返回 `unknown_evidence_key:<key>`，文件/文本类型与长度也逐项校验；风险更高的 `submit_evidence` 路径已用 `to_unsafe_h`。
- **目标**：消除该告警（与 `pallastrade-security` Skill 的「禁止 `permit!`」一致），**不改变**现有行为与降级语义。
- **成功指标**：`bundle exec brakeman --no-pager -q` → **Security Warnings: 0**；`disputes_ops_*` 请求 spec 全绿；CI `Backend CI` 恢复全绿。

## 2. 用户故事 / 场景

- 作为**安全/平台维护者**，我希望静态扫描零告警，以免真实风险淹没在长期红页里。
- 作为**运营**，我希望争议页的草稿预检（precheck）与签核（approve_draft）行为不变。
- 场景：① 目录内键（如 `customer_name`）→ 正常预检；② 目录外键（如 `totally_unknown`）→ 仍由服务层报 `unknown_evidence_key`；③ 空载荷 → `evidence_empty`；④ 文件类字段 → 保留上传对象交给服务层校验。

## 3. 功能需求（FR）

- **FR-001**：`DisputesOpsController#evidence_payload` 不再使用 `permit!`，改为显式「参数 → 纯 Hash」转换（`to_unsafe_h`）并剔除框架保留键（`controller`/`action`/`authenticity_token`/`utf8`/`id`）。
- **FR-002**：保留 `submit_evidence` 现有 `to_unsafe_h` 路径，使两条路径参数处理方式一致。
- **FR-003**：**不改**服务层校验语义（`EvidenceCatalog#validate` 仍是权威白名单：`unknown_evidence_key:*` / 类型 / 长度）。
- **FR-004**（范围外）：`params_normalizer.rb:24` 与 `prepare_nested_attributes.rb:96` 另有两处 `permit!` 未被 Brakeman 告警，本次**不动**（避免超范围；如后续告警再评估）。

## 4. 非功能需求（NFR）

- **行为等价**：仅参数提取方式变化，不改变落到服务层的键/值集合（除框架保留键）。
- **可审计**：不引入新依赖、不改 API/路由/视图；变更点单一文件单方法，附 `# PALLAS-CUSTOM:` 说明依据。
- **回归可检测**：既有 `disputes_ops_*` 请求 spec 覆盖未知键、空载荷等边界，直接复用。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001：`bundle exec brakeman --no-pager -q` 输出 `Security Warnings: 0` / `No warnings found`。
- **AC-002** ← FR-001/003：`disputes_ops_evidence_ops_spec.rb` 全绿（含目录外键 `totally_unknown` 仍被阻断、空载荷 `evidence_empty`）。
- **AC-003** ← FR-001：`disputes_ops_actions_spec.rb` 全绿（危险动作确认链路不变）。
- **AC-004** ← FR-001：控制器无 `permit!` 残留（grep 验证）。
- **AC-005** ← 目标：CI `Backend CI` 在推送后转绿（安全扫描步骤不再 exit 3）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | disputes / params | 无争议控制台实现 | — |
| Core | `pallastrade_core/app/` | EvidenceCatalog / PreSubmitCheck | `disputes/evidence_catalog.rb#validate`（权威白名单 + 类型/长度校验）、`pre_submit_check.rb`、`submit_evidence.rb` | 是（本次不动，作为基线） |
| API | `pallastrade_api/app/` | `permit!` | `concerns/pallastrade/api/v3/params_normalizer.rb:24`（另一处 `permit!`，**未被 Brakeman 告警**） | 否（范围外） |
| Admin | `pallastrade_admin/app/` | permits / evidence | `disputes_ops_controller.rb` L337-342（**本次改动点**）、L184-186（`submit_evidence` 已用 `to_unsafe_h`） | **是** |
| Storefront | `storefront/src/` | — | 无 | — |
| Platform | `platform/packages/` | — | 无 | — |

**结论**：单点、单方法修复；服务层校验语义不变；无重复实现。

## 7. 技术影响

- **修改**：`pallastrade_admin/app/controllers/pallastrade/admin/disputes_ops_controller.rb`（`evidence_payload`）
- **数据库 / 接口 / SDK / 前端**：无变更
- **影响面**：仅 admin 争议控制台的草稿预检与签核参数提取

## 8. 测试计划

- **复用（不新增）**：`spec/requests/pallastrade/admin/disputes_ops_evidence_ops_spec.rb`、`disputes_ops_actions_spec.rb`（AC-002/003）
- **新增验证**：Brakeman 本地运行（AC-001）+ grep 无 `permit!`（AC-004）+ 推送后 CI 观察（AC-005）
- **AC 映射**：AC-001→brakeman；AC-002/003→上述 spec；AC-004→grep；AC-005→CI

## 9. 文档同步清单（知识同步门）

| 知识资产 | 结论 |
|---|---|
| API 文档 / SDK 类型 | ✅ 不适用（未改接口契约） |
| `pallastrade-security` Skill | ✅ 已读并作为修复依据引用；Skill 自身无需更新（其「禁止 `permit!`」条款已覆盖本场景） |
| `pallastrade-prd` Skill / `AGENTS.md` / `copilot-instructions.md` | ✅ 已评估无需更新（流程与规范无变化） |
| 场景库 / `scenarios.json` | ✅ 已评估无需更新（未新增机制/范式） |
| 本 PRD 状态 + `docs/prd/README.md` 索引 | ✅ 已更新（`done` + 索引行） |
| `harness sync-check --ack` | ✅ 已确认（知识环 6/4） |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 实施：`evidence_payload` 去 `permit!`（to_unsafe_h + 剔除框架保留键）；本地 Brakeman `Security Warnings: 0`；争议 spec 19 例全绿 | AI |
