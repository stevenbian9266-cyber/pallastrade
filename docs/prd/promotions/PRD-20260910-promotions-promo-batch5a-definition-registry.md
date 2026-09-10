# PRD-20260910-promotions-promo-batch5a-definition-registry

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-10 |
| 来源 | `promotion模块架构-任务拆解.md` 批次 5 → Phase 7（PR-P7-1..3）；架构 §3 Definition Registry；评审修正点「Definition 增量化 + 消除双描述漂移」 |
| 分类 | promotions |
| 关联 Skill | pallastrade-promotions、pallastrade-api-v3、pallastrade-admin、pallastrade-customization、pallastrade-testing |
| 关联 REQ | REQ-20260910-promo-batch5a-definition-registry.md（实施时回填） |
| 关联 PRD | batch1（invariants）、batch2（投影）、batch4a/4b（快照与分摊） |
| 需求类型 | 优化迭代（治理收敛：单一事实源 + 校验，**不改业务语义**） |

> **原则**：**收敛读取面，不重写注册机制**。现有注册入口 `PallasTrade.promotions.rules << X` / `.actions = [...]`
> 保持不变（扩展与第三方 gem 继续用它们）；本批次新增的是一个**只读聚合注册表**与**完整性校验**，
> 消除「Rails Admin partial / API preference_schema / calculator 兼容表 / 允许属性表」四处各写一份的漂移。

---

## 1. 背景与目标

### 1.1 现状（PR-P7-1 盘点，2026-09-10 实测）

| 事实来源 | 位置 | 说明 |
|---|---|---|
| Rule 允许集 | `Rails.application.config.pallastrade.promotions.rules`（`engine.rb:211` concat 13 个） | `PallasTrade.promotions.rules` |
| Action 允许集 | 同上 `.actions = [...]`（`engine.rb:242` 4 个） | `PallasTrade.promotions.actions` |
| Calculator 兼容 | `PallasTrade.calculators.promotion_actions_create_adjustments` / `..._create_item_adjustments`（`engine.rb:197/205`） | 由 `CalculatedAdjustments#calculators` 按父类名推导 |
| 允许属性 | 各 STI 子类的 `self.additional_permitted_attributes`（如 `Rules::Taxon → [category_ids: []]`） | API `SubclassedResource` 合并进 `params.permit` |
| API 类型发现 | `PreferenceSchema#registered_subclasses`（`preference_schema.rb:176`）路由到上表两个数组；`/types` 端点输出 `{ type, label, description, preference_schema }` | `subclasses_with_preference_schema` |
| Rails Admin 表单 | `promotion_rules/forms/_<api_type>.erb`、`promotion_actions/forms/_<key>.erb`（共 13 + 5 个 partial） | 命名 = `api_type`（`taxon → category`、`user → customer`） |
| 文案 | `pallastrade.promotion_rule_types.<api_type>.{name,description}`（`en.yml:1294`） | `human_name` 有 `default: api_type.titleize` 兜底 |

### 1.2 问题

1. **四处各写一份**：新增一个 rule/action 要在 4 个地方各自登记（registry 数组 / calculator 桶 / partial / locale），漏一处不会报错——API 能建、后台渲染炸；或后台能配、API 拒绝。
2. **双描述漂移**：Rails Admin partial 与 API `preference_schema` 各自描述"可配置字段"，无一致性校验（PR-P7-2 要治）。
3. **无显式 key→类→能力 映射**：`api_type` 分散在各类上（含两个改名覆盖：`category`/`customer`），没有可查询的单一对象。
4. **无校验**：没有任务/测试能回答"注册表当前是否自洽"。

### 1.3 目标

- 新增 `PallasTrade::Promotions::DefinitionRegistry`（**只读聚合**）：一处回答 key / 类 / kind / calculator 兼容 / 允许属性 / admin partial / locale key。
- **API 与 Rails Admin 的 type discovery 同一来源**：`PreferenceSchema` 与 Admin 控制器/helper 改读 registry。
- 提供**完整性校验**（`validate!` + rake 任务 + spec），把"漏登记"变成可发现错误而不是线上故障。
- 零业务语义变化：除 discovery 读取路径外不改 eligibility/金额/表单行为。

---

## 2. 功能需求（FR）

- **FR-001 Registry（PR-P7-1）**：新增 `PallasTrade::Promotions::DefinitionRegistry`
  - `DefinitionRegistry.for(:rule | :action)`、`.rule_types` / `.action_types` / `.all_entries`；
  - `#fetch(key_or_type)`（api_type 或全类名）、`#find_by_api_type(shorthand)`、`#kind_for(type)`；
  - `#calculators_for(type)`、`#allowed_attributes_for(type)`、`#admin_partial_for(key)`、`#locale_key_for(key)`；
  - `Entry` 值对象字段：`key`、`type`、`kind`、`klass`、`label`、`description`、`calculators`、`allowed_attributes`、`admin_partial`、`locale_key`、`calculator_required?`；
  - **注册入口不变**：仍读 `PallasTrade.promotions.rules/.actions`（数组内容即权威），registry 只读聚合 + 缓存（进程内 memoize，测试可 `.reset!`）。
- **FR-002 双面 discovery 收敛（PR-P7-2）**
  - `PallasTrade::PreferenceSchema#registered_subclasses` 改为经 registry 解析（`PromotionRule` → rule 集、`PromotionAction` → action 集；其它父类保持原逻辑：`providers` / 空集）；
  - Rails Admin `PromotionRulesController#allowed_rule_types`、`PromotionActionsController` 的等价方法、`promotion_rules_helper` / `promotion_actions_helper` 改读 registry；
  - Admin 表单 partial 路径由 `Entry#admin_partial` 决定（新类漏 partial 时 `validate!` 报 error，而不是运行时报 `MissingTemplate`）。
- **FR-003 完整性校验（PR-P7-3）**：`DefinitionRegistry#validate!` 返回 `[{ level: :error|:warning, code:, message:, key: }]`：
  | code | level | 判定 |
  |---|---|---|
  | `duplicate_api_type` | error | 同一 kind 内 `api_type` 重复 |
  | `invalid_sti_parent` | error | 类未继承 `PromotionRule`/`PromotionAction` |
  | `missing_admin_partial` | error | `promotion_rules/forms/_<key>.erb`（或 actions 目录）不存在 |
  | `missing_calculator` | error | 需要 calculator 的 action（`CreateAdjustment` / `CreateItemAdjustments`）在其 calculator 桶中为空 |
  | `invalid_allowed_attributes` | error | `additional_permitted_attributes` 非数组 |
  | `missing_locale` | warning | `promotion_rule_types.<key>.name` 缺失（有 titleize 兜底） |
  | `unregistered_class` | warning | 已存在的 STI 子类未注册（后台不可选，历史数据仍可读） |
- **FR-004 校验任务（PR-P7-3）**：`PallasTrade::Tasks::PromoDefinitionRegistryValidator` + rake `pallastrade:promotions:definitions:validate`
  - 默认打印按 kind 分组的分级报告 + 汇总（`rules=13 actions=4 errors=0 warnings=n`）；
  - `STRICT=1` 时存在 error → 非零退出（CI/lefthook 可用）；
  - 支持注入 registry（spec 用假注册表验证缺口分类）。
- **FR-005 文档同步**：`pallastrade-promotions`（Definition Registry 节）、`pallastrade-api-v3`（`/types` 来源说明）、`pallastrade-admin`（表单 partial 由 registry 决定）、`pallastrade-customization`（新增 rule/action 的正确登记方式 + 校验命令）、GS-088、PRD 索引。

---

## 3. 业务规则与边界

| # | 规则 | 说明 |
|---|---|---|
| R1 | 只读聚合 | registry 不改变 `PallasTrade.promotions.*` 数组内容与顺序（顺序仍是后台 picker 顺序）；需要排序时只影响 `Entry` 列表输出（按 label） |
| R2 | 兼容旧读取 | `PallasTrade.promotions.rules` 直接读取仍然有效（第三方/扩展不改） |
| R3 | 缓存 | `Entry` 与校验结果进程内 memoize；提供 `DefinitionRegistry.reset!` 供测试与 `to_prepare` 使用 |
| R4 | 不碰业务 | 不改 eligibility / calculator 计算 / `preferences` 语义 / 表单字段 |
| R5 | 空集安全 | 数组为空（未初始化环境）时 registry 返回空集，`validate!` 不抛异常 |
| R6 | 校验分级 | 缺 partial / 缺 calculator / 重复 key / 非法属性 = error（阻断 STRICT）；缺 locale / 未注册类 = warning |
| R7 | admin partial 命名 | `api_type` 决定 partial 名（`category` / `customer` 等改名型以 `api_type` 为准） |
| R8 | 新旧一致性 | `PreferenceSchema` 的发现结果在收敛前后**逐字段一致**（回归断言：`/types` 输出与 batch3c 前一致） |

---

## 4. 验收标准（AC，与测试一一映射）

| AC | 对应 | 判定条件 | 映射测试 |
|---|---|---|---|
| AC-001 | FR-001/R1 | 默认注册表 = 13 rules + 4 actions；每条 `Entry` 的 `key`/`type`/`kind`/`klass` 正确；`category`/`customer` 改名映射保留（`Taxon.api_type == 'category'`） | `backend/spec/services/pallastrade/promotions/definition_registry_spec.rb` |
| AC-002 | FR-001 | `calculators_for` 与 `PallasTrade.calculators.promotion_actions_create_adjustments/_create_item_adjustments` 完全一致；`allowed_attributes_for` 与 `klass.additional_permitted_attributes` 一致（含 `category_ids`/`customer_ids`） | 同上 |
| AC-003 | FR-001 | `fetch` 支持 api_type 与全类名；`find_by_api_type('category')` → `Rules::Taxon`；未注册 shorthand → nil；`kind_for` 正确 | 同上 |
| AC-004 | FR-003/R6 | `validate!` 对当前默认集合返回 **0 error**（warning 允许）；每条 issue 带 `level/code/key/message` | 同上 |
| AC-005 | FR-003/R6 | 合成缺口被正确分类：重复 api_type → `duplicate_api_type`；缺 partial → `missing_admin_partial`；空 calculator 桶 → `missing_calculator`；非数组属性 → `invalid_allowed_attributes`；缺 locale → `missing_locale`(warning) | 同上（用测试态 registry 注入） |
| AC-006 | FR-004 | 校验任务输出分组报告与汇总；`STRICT=1` + 注入 error → 非零退出；默认（0 error）→ 0 退出 | `backend/spec/lib/pallastrade/tasks/promo_definition_registry_validator_spec.rb` |
| AC-007 | FR-002/R8 | Admin API `GET /api/v3/admin/promotion_rules/types` 与 `promotion_actions/types` 的 `type` 集合 == registry 的 `rule_types/action_types`（同一来源）；`PreferenceSchema.registered_subclasses` 对 `PromotionRule`/`PromotionAction` 返回 registry 结果；其它父类（`PaymentMethod.providers`）行为不变 | `backend/spec/requests/api/v3/admin/promotion_types_registry_spec.rb` + `spec/models/concerns/preference_schema_registry_spec.rb` |
| AC-008 | FR-005 | 回归：promotions 相关 spec 全绿（batch1/2/3a/3b/3c/4a/4b）；Skill ×4 更新 + GS-088 + `prd verify` 全 AC 覆盖 + `doc-impact` 无缺失 | 回归命令 + `harness prd verify` / `doc-impact` |

---

## 5. 跨层搜索记录（6 层，2026-09-10 实测）

| 层 | 路径 | 关键词 | 找到 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | promotions.rules / api_type | 无宿主实现 | 不涉及 |
| Core — models | `pallastrade_core/app/models/` | api_type / additional_permitted_attributes / preference_schema | `promotion_rule.rb`（`key`、`human_name`）、`promotion_action.rb`、`rules/{taxon,user}.rb`（api_type 改名）、`concerns/preference_schema.rb`（`registered_subclasses`/`subclasses_with_preference_schema`/`find_by_api_type`）、`concerns/calculated_adjustments.rb`（calculator 桶） | ⚠️ 需新增只读聚合（本批次核心） |
| Core — engine/config | `pallastrade_core/lib/pallastrade/core/engine.rb` | promotions.rules/actions、calculators | `engine.rb:211`（13 rules）、`:242`（4 actions）、`:197/205`（calculator 桶） | ✅ 权威数组保留（R2） |
| API | `pallastrade_api/app/controllers/**/admin/` | types / SubclassedResource | `promotion_rules_controller#types`、`promotion_actions_controller#types`、`concerns/admin/subclassed_resource.rb`（`subclassed_via -> { PallasTrade.promotions.rules }`） | ⚠️ 需切到 registry（FR-002） |
| Admin | `pallastrade_admin/app/{controllers,views,helpers}` | allowed_rule_types / forms partial | `promotion_rules_controller#allowed_rule_types`、`promotion_actions_controller`、`views/.../promotion_{rules,actions}/forms/_*.erb`（13+5）、helpers 过滤 existing | ⚠️ 需切到 registry（FR-002） |
| Storefront | `storefront/src/` | — | 无消费点 | 不涉及 |
| Platform | `platform/packages/` | types | 无相关类型（本批次无端点变更） | 不涉及 |

---

## 6. 技术影响

- **新增**：`pallastrade_core/app/services/pallastrade/promotions/definition_registry.rb`（registry + Entry + Validator 结果）；`lib/tasks/promotions.rake` 增 `definitions:validate` 任务类与 rake 入口；3 个 spec。
- **修改**：`concerns/preference_schema.rb`（`registered_subclasses` 走 registry）、`pallastrade_admin` 规则/动作控制器与 helpers（读 registry + partial 路径）、Skill ×4、`scenarios.json`。
- **不改**：注册数组本身、`api_type` 定义、calculator 桶内容、eligibility/金额、Admin 表单字段与既有 partial 内容、API `/types` 响应结构。

---

## 7. 测试计划

| 文件 | 类型 | 覆盖 AC |
|---|---|---|
| `backend/spec/services/pallastrade/promotions/definition_registry_spec.rb`（新） | service | AC-001/002/003/004/005 |
| `backend/spec/lib/pallastrade/tasks/promo_definition_registry_validator_spec.rb`（新） | rake/task | AC-006 |
| `backend/spec/models/concerns/preference_schema_registry_spec.rb`（新） | concern | AC-007 |
| `backend/spec/requests/api/v3/admin/promotion_types_registry_spec.rb`（新） | request | AC-007 |
| promotions 相关既有 spec（batch1/2/3a/3b/3c/4a/4b） | 回归 | AC-008 |

---

## 8. 文档同步清单（知识同步门）

- [x] `ai/skills/pallastrade-promotions/SKILL.md`：Definition Registry 节（Entry 字段 + 校验命令 + 新增 rule/action 的 4 步登记）。
- [x] `ai/skills/pallastrade-api-v3/SKILL.md`：`/types` 数据来源 = registry。
- [x] `ai/skills/pallastrade-admin/SKILL.md`：后台规则/动作表单 partial 由 registry 解析。
- [x] `ai/skills/pallastrade-customization/SKILL.md`：自定义 rule/action 的登记清单 + `definitions:validate`。
- [x] `harness/scenarios/scenarios.json`：GS-088。
- [x] `docs/prd/README.md` + 本 PRD 状态。
- [x] 接口契约：**响应结构未变**（`/types` 字段不变）→ 不重生成（实施后以 `schemas:check` 确认）。

---

## 9. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-10 | 0.1 | 初稿：PR-P7-1 现状盘点（4 处事实来源）+ 收敛方案（只读聚合 + 校验） | AI |
| 2026-09-10 | 1.0 | 用户「继续」授权实施批次 5a；FR/AC（AC-001..008）与测试映射锁定 | AI || 2026-09-10 | 1.1 | 实施完成：registry + 双面 discovery 收敛 + 校验任务 + 5 个 spec；另发现并修复工作树被外部回退（20 文件恢复至 HEAD，见 §10） | AI |

## 10. 实施记录与工作树事故

**实施落点**

| 文件 | 变更 |
|---|---|
| `pallastrade_core/app/services/pallastrade/promotions/definition_registry.rb`（新） | `DefinitionRegistry` + `Entry` + `Kind` + `Validator`（7 类校验码） |
| `pallastrade_core/app/models/concerns/pallastrade/preference_schema.rb` | `registered_subclasses` 走 registry（PromotionRule/Action），其它父类不变 |
| `pallastrade_api/.../concerns/.../subclassed_resource.rb` | `resolve_subclass` 兼容完整类名（仅注册表内匹配，不做 constantize） |
| `pallastrade_api/.../admin/promotion_{rules,actions}_controller.rb` | `subclassed_via` 改读 registry |
| `pallastrade_admin/.../promotion_{rules,actions}_controller.rb` + helpers | allowlist / picker 条目 / 表单 partial 改读 registry |
| `pallastrade_admin/.../promotion_{rules,actions}/{new,edit}.html.erb` | 选择器用 `entry.label/description`（修复 Taxon→taxon / User→user 文案缺失）；partial 走 helper |
| `pallastrade_core/lib/tasks/promotions.rake` | 新增 `pallastrade:promotions:definitions`（`STRICT=1` 出错非零退出）+ `Tasks::PromoDefinitionRegistryValidator` |
| spec ×5 | registry（AC-001..005）、rake（AC-006）、PreferenceSchema（AC-007）、Admin API（AC-007）、Rails Admin 选择器（AC-007） |

**工作树事故（2026-09-10 21:46 左右，非本批次改动）**：约 20 个已提交文件在工作树中被回退到旧版本（batch3a/3b/3c/4a/4b 的接线：`order.rb` 关联、`engine.rb` subscriber 注册、admin navigation/tables/locales/routes、api routes/dependencies、`admin.yaml`、`scenarios.json`、`sidekiq_schedule.rb`、pricing SKILL 等）。期间 promotions 回归失败全部由此引起（`order.promotion_redemptions` NoMethodError）。经用户确认后，已将这些文件 `git checkout HEAD` 恢复（用户确认存在并行会话在同一仓库操作，后续提交前需复核工作树）。→ 教训：**每批次开始前先 `git status --porcelain` 对比预期改动集，发现异常先报告**。

## 11. 知识同步评估（sync-check 逐项结论）

`harness sync-check --id PRD-20260910-promotions-promo-batch5a-definition-registry` 命中的资产逐项结论：

| 触发组 | 资产 | 结论 | 依据 |
|---|---|---|---|
| Model / DB 变更 | 领域 Skill（promotions） | ✅ updated | `pallastrade-promotions/SKILL.md` 新增 Definition Registry 节 + 校验命令 |
| Model / DB 变更 | pallastrade-data-model Skill | ➖ reviewed-no-change | 本批次无模型/表/关联变更 |
| Model / DB 变更 | 测试 | ✅ updated | 新增 5 个 spec（registry / rake / PreferenceSchema / Admin API / Rails Admin） |
| Model / DB 变更 | 场景库 | ✅ updated | `harness/scenarios/scenarios.json` 新增 GS-088 |
| API 端点变更 | `backend/public/api-docs/{store,admin}.yaml` | ➖ reviewed-no-change | `/types` 响应结构与路径未变；`generated:check` 无漂移 |
| API 端点变更 | pallastrade-api-v3 Skill | ✅ updated | 新增「促销定义发现单源化」节（registry 来源 + 类名兜底 + 422 语义） |
| API 端点变更 | SDK 类型(generated:check) | ➖ reviewed-no-change | 未新增/修改 serializer 字段；`generated:check` 通过 |
| API 端点变更 | 场景库 | ✅ updated | 同上（GS-088） |
| UI 组件 / 页面 | pallastrade-storefront Skill / 组件测试 | ➖ reviewed-no-change | 变更仅在 Rails Admin（gem 内 ERB），不涉及 storefront |
| 事件 / 订阅者 | pallastrade-events-webhooks Skill | ➖ reviewed-no-change | 无订阅者/事件变更 |
| 包 / SDK 能力 | pallastrade-typescript-sdk Skill / platform/packages/README.md / 根 README | ➖ reviewed-no-change | 无平台包变更（命中来自并行批次的 SDK 类型文件） |
| Skill / PRD 机制 | pallastrade-prd Skill | ➖ reviewed-no-change | PRD 流程本身未变 |
| Skill / PRD 机制 | AGENTS.md / copilot-instructions.md | ➖ reviewed-no-change | 规则未变（§0.1 文件表无需新增条目） |
| Skill / PRD 机制 | scenarios.json | ✅ updated | GS-088（同场景库行） |

> 说明：sync-check 的 diff 基线为 `origin/dev`，会一并列出此前批次（3a..4b）的文件；那些资产已在各自批次评估过，本表只对本批次实际改动负责。