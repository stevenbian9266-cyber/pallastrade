# REQ-20260910-promo-batch5a-definition-registry

| 项 | 值 |
|---|---|
| 需求 | Promotion 批次 5a —— PromotionDefinitionRegistry 收敛（PR-P7-1..3） |
| 类型 | 优化迭代（治理收敛） |
| 关联 PRD | `docs/prd/promotions/PRD-20260910-promotions-promo-batch5a-definition-registry.md` |
| 关联任务 | TASK-20260910135024-0c256fd0 |
| Gate | GATE-2026-09-10T13-50-41 |
| 分支 | dev |

---

## Step 0 — 跨层搜索（6 层，2026-09-10 实测）

| 层 | 搜索路径 | 关键词 | 结果 | 是否已满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | promotions.rules / api_type / 表单 partial | 无宿主实现 | 不涉及 |
| Core | `backend/pallastrade_gems/pallastrade_core/app/` | `api_type` / `additional_permitted_attributes` / `preference_schema` / `calculators` | `models/pallastrade/promotion_rule.rb`、`promotion_action.rb`、`promotion/rules/{taxon,user}.rb`（api_type 改名 category/customer）、`concerns/preference_schema.rb`（`registered_subclasses` 176-196 / `subclasses_with_preference_schema` / `find_by_api_type`）、`concerns/calculated_adjustments.rb`（calculator 桶读取） | ⚠️ 无统一注册表 → 本批次新增（只读聚合） |
| Core 配置 | `pallastrade_core/lib/pallastrade/core/engine.rb` | `promotions.rules` / `promotions.actions` / calculators | `:211` rules concat（13）、`:242` actions（4）、`:197/205` calculator 桶；`initializer 'PallasTrade.promo.environment'` 建立空数组 | ✅ 保留为权威数组（只读聚合，不改注册机制） |
| API | `backend/pallastrade_gems/pallastrade_api/app/` | `types` / `SubclassedResource` | `admin/promotion_rules_controller.rb`、`admin/promotion_actions_controller.rb`（`subclassed_via -> { PallasTrade.promotions.rules }`、`#types`）、`concerns/.../subclassed_resource.rb`（合并 `additional_permitted_attributes`） | ⚠️ 发现来源需切 registry（FR-002） |
| Admin | `backend/pallastrade_gems/pallastrade_admin/app/` | `allowed_rule_types` / forms partial / helper | `controllers/.../promotion_rules_controller.rb`、`promotion_actions_controller.rb`、`helpers/promotion_{rules,actions}_helper.rb`、`views/.../promotion_{rules,actions}/forms/_*.erb`（13 + 5） | ⚠️ 同上 + partial 路径由 registry 提供 |
| Storefront | `storefront/src/` | promotions / types | 无消费点 | 不涉及 |
| Platform | `platform/packages/` | types | 无相关类型（端点结构未变） | 不涉及 |

**结论**：4 处事实来源（注册数组 / calculator 桶 / admin partial / locale）分散，无一致性校验；本批次新增只读聚合注册表 + 校验任务，并把 API 与 Rails Admin 的 type discovery 收敛到同一来源。

---

## Step 1 — Skill 咨询证据

| Skill | 读取 | 关键结论 |
|---|---|---|
| `pallastrade-customization` | ✅ | 决策树第 8 级（直接改 gem）适用于 gem 内部收敛；不改业务语义 → 无需 decorator/generator |
| `pallastrade-promotions` | ✅ | 文档已写死「注册 `PallasTrade.promotions.rules <<` + 后台 partial `_<key>.erb` + locale `promotion_rule_types.<key>`」三步手工清单（§Custom Rule 121-125、261 行）——正是漂移来源；本批次把该清单变成可校验对象 |
| `pallastrade-prd` | ✅ | R8 流程：PRD 详细化（FR/规则/AC/测试映射/知识同步）→ approved → gate → 实施 → `prd verify` |
| `pallastrade-api-v3` | ✅ | `/types` 输出 `{ type, label, description, preference_schema }`；响应结构不变 → 无需重生成契约（实施后 `schemas:check` 确认） |
| `pallastrade-admin` | ✅ | 后台规则/动作 picker 读 `allowed_*_types` + partial 名 = `api_type` |
| `pallastrade-testing` | ✅ | service/rake/request 三层测试组织方式；回归用既有 promotions spec 集 |

---

## Step 2 — 实施范围（写前确认）

- 新增：`definition_registry.rb`（registry + Entry）、`definitions:validate` 任务类 + rake 入口、4 个 spec 文件。
- 修改：`preference_schema.rb`（`registered_subclasses` 走 registry）、Admin 规则/动作控制器与 helper、Skill ×4、`scenarios.json`、PRD 索引。
- 不改：注册数组内容与顺序、`api_type` 值、calculator 桶内容、eligibility/金额逻辑、Admin 表单字段、API `/types` 响应结构。

## 用户确认记录

| 时间 | 用户输入 | 授权范围 |
|---|---|---|
| 2026-09-10 | 「继续」（承接 AI 预先声明的批次 5a = PR-P7-1..3 Definition Registry 收敛） | 实施批次 5a（沿用 batch3a/3b/3c/4a/4b 同一模式） |
