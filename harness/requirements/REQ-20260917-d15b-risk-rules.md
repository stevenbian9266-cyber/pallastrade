# REQ-20260917-d15b-risk-rules

## 元数据

| 项 | 值 |
|---|---|
| 关联 PRD | `docs/prd/payments/PRD-20260917-payments-d15b-risk-rules.md` |
| 任务 ID | `TASK-20260916164406-13399878` |
| Gate | `GATE-2026-09-16T16-44-20` |
| 任务类型 | 新功能（扩展既有引擎：版本化 + 灰度 + 回滚） |
| 风险等级 | standard（requiredEvidence = test + review + knowledge） |
| 允许改动范围 | `backend/**`、`docs/prd/**`、`harness/**`、`ai/skills/**`、`harness.config.mjs` |
| 一句话需求 | 支付风控规则引擎版本化/灰度/回滚（D15 切片2，业务方案 §72.2） |

## Step 0：跨层搜索（所有任务强制执行）

| 层 | 搜索路径 | 搜索关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App – models/controllers | `backend/app/` | risk / blacklist / rule | 无 | ❌ 宿主零风控代码 |
| App – views/decorators | `backend/app/` | risk / blacklist | 无 | ❌ |
| Core Gem – models | `pallastrade_core/app/models/` | risk / rule / version | `payment_risk_list.rb`、`payment_risk_assessment.rb`（D15 切片1） | ⚠️ 只有名单与留痕，**无规则/版本模型** |
| Core Gem – services | `pallastrade_core/app/services/` | risk / rule / preflight | `risk/assess.rb`、`risk/lists/{upsert,export}.rb`、`checkout/preflight.rb` | ⚠️ 只有名单评估入口；**无规则层/版本/灰度** |
| Core Gem – lib | `pallastrade_core/lib/` | risk / rule / rollout / canary | `lib/pallastrade/risk.rb`、`lib/pallastrade/risk/{blacklist_rule,order_frequency_rule}.rb` | ⚠️ **规则引擎已存在**（P8，代码注册式）但无版本/灰度/回滚 → **扩展它** |
| API Gem – controllers | `pallastrade_api/app/controllers/` | risk / preflight | 仅 `order_serializer.rb` 的 `considered_risky` | ✅ 无端点 → 零契约变更 |
| Admin Gem – controllers/views | `pallastrade_admin/app/` | risk | `risk_lists_controller.rb`、`orders/_risk_analysis.html.erb` | ⚠️ 有名单工作台；**无规则/版本页面** |
| Storefront | `storefront/src/` | risk / blacklist / preflight | 无 | ❌ 不涉前台 |
| Platform | `platform/packages/` | risk / blacklist / preflight | 无 | ❌ 不涉 SDK/CLI/Dashboard |

### 搜索结论

- **规则引擎已存在**（`PallasTrade::Risk`，`lib/pallastrade/risk.rb`，P8 2026-08-28）：进程内 `rules` 数组 + `Risk.evaluate` 首个命中 → `{ code:, message: }`，唯一调用点 `Checkout::Preflight`（flag 门控，默认关闭）。**本切片扩展它，不新建第二套引擎**。
- **评估入口已存在**（D15 切片1 `Risk::Assess`）：名单 → 决策 → 留痕（`PaymentRiskAssessment`），由 `Risk::OrderSubmittedSubscriber` 在 `order.submitted` 触发。规则结果并入同一决策与留痕，**不新建入口**。
- **留痕表可扩展**：`signals`/`metadata` 均为 jsonb → 版本/灰度/命中信息**零迁移**写入。
- **BIN 无列、设备指纹无采集** → 不提供对应条件键（不猜）。
- 需要新建：2 表（规则集 + 版本）、4 服务（Condition / Schema / Evaluate / Versioning）、1 后台页（`/admin/risk_rules`）、2 事件。

## Step 1：Skill 文件咨询（新功能 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级：**领域能力优先落框架（本仓直接改 gem）**，页面加导航用 `PallasTrade.admin.navigation.sidebar.add`，副作用用 Events/Subscriber —— 本切片因此把引擎放 `pallastrade_core`、留痕沿用既有 subscriber 路径 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 「新增/删除子项必须同步 `navigation_consistency_spec.rb` 的子项数组断言」；新增可授权资源须在 `pallastrade_permission_registry.rb` 登记；只读页四件套（控制器/表格/导航/权限），写路径 `location_after_save` 需覆写 |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | 「下单风控规则（P8）：`PallasTrade::Risk.rules << MyRule`，`#call(order:, user:, store:)` → `{ code:, message: }`，错误统一 `{code:,message:}` 不泄露内部细节」→ 本切片保持该契约不变，规则引擎的输出只并入决策与留痕 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | D15 切片1 表约定：`store_id` 可空 = 全局（非空 = 店铺）、幂等靠唯一键、状态用 `status` 而非删除、jsonb 扩展字段 —— 新两表沿用同一口径（含 partial unique 处理 NULL 不去重） |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-events-webhooks` | ☑ | ✅ 已读 | 事件 payload **无 PII**、发布失败不阻断业务、禁止在业务事务内发布（用 `after_commit`）；D15 切片1 订阅者需兼容 `payload['id'] / ['order_id'] / dig('payload','order_id')` 三形态 |
| `pallastrade-checkout` | ☑ | ✅ 已读 | 「前置校验：`Checkout::Preflight` 在 `Carts::Complete` 支付处理前评估 Risk，命中返回业务失败；flag `checkout_preflight_enabled` **默认关闭**」→ 本切片**不改其启用条件与阻断行为** |
| `pallastrade-testing` | ☑ | ✅ 已读 | 模型/控制器 spec 约定（`render_views`、工厂优先、`build` 优于 `create`）；控制器 spec 必须渲染视图（本切片后台页断言依赖它） |
| `pallastrade-prd` | ☑ | ✅ 已读 | PRD 工作流：查重 > 0.3 阻止新建 → 回写原 PRD；确属新切片才 `--force`；`prd-status-sync --check` 必须一致 |
| `pallastrade-api-v3` | ☐ | — | 不适用：零 API 变更 |
| `pallastrade-storefront` | ☐ | — | 不适用：零前台变更 |

## 目标

1. 规则（条件 + 动作 + 优先级）落库，运营可在后台维护，无需发版。
2. 每次变更生成**不可变版本**；**回滚** = 以历史版本内容生成新版本并生效，全程可审计（验收锚点「规则可回滚」）。
3. **灰度**：金丝雀版本按订单维度**确定性分桶**的流量百分比生效，桶值可复算、可审计。
4. **可解释**：留痕记录规则集/版本/是否金丝雀/桶/命中规则/命中条件；缺失主体不猜。
5. **零风险**：零 provider、零资金副作用；不改变下单是否被阻断的既有行为。

## 非目标

- `force_3ds` 动作与 provider 下发（切片3），本切片动作词汇 = allow / review / block。
- 不改 `Checkout::Preflight` 的启用条件与阻断行为；不改 P8 代码规则（`Risk.rules`）语义。
- 不做 BIN / 设备指纹条件；不做 IP 地理/网段判定；不做可视化规则构建器（JSON + 服务端强校验 + 预览）。
- 不做规则执行性能工程（规则数 ≤ 50/版本，评估 O(规则数)）。

## 交付物清单

| # | 类型 | 内容 | 状态 |
|---|---|---|---|
| 1 | 迁移 | `backend/db/migrate/20260917010000_create_pallastrade_risk_rule_sets_and_versions.rb`（2 表 + 3 唯一索引（2 个 partial）+ 普通索引） | 已实施 |
| 2 | 模型 | `pallastrade_core/app/models/pallastrade/risk_rule_set.rb`、`risk_rule_version.rb`（版本不可变守卫 + 作用域/筛选 scope） | 已实施 |
| 3 | 服务 | `.../app/services/pallastrade/risk/rules/{condition,schema,evaluate,versioning}.rb` | 已实施 |
| 4 | 修改 | `.../app/services/pallastrade/risk/assess.rb`（合并规则决策 + 留痕 signals/metadata） | 已实施 |
| 5 | 后台 | `.../pallastrade_admin/app/controllers/pallastrade/admin/risk_rules_controller.rb` + `views/pallastrade/admin/risk_rules/{index,show,preview}.html.erb` | 已实施（无独立 helper，展示口径写在控制器） |
| 6 | 修改 | 导航（Orders position 59.5）、`routes.rb`、`configuration_management.rb`（`manage RiskRuleSet`/`RiskRuleVersion`）、gem `en.yml` | 已实施（另登记 PermissionRegistry `:risk_rules`） |
| 7 | i18n | `backend/config/locales/admin_risk_rules.zh-CN.yml`（与 gem 键集一致） | 已实施（109/109） |
| 8 | 工厂 | `.../testing_support/factories/risk_rule_factory.rb` | 已实施 |
| 9 | 测试 | PRD §8 的 6 个新 spec + 导航一致性回归 + 3 个既有 spec 回归 | 已实施（108 例 0 失败） |
| 10 | Harness | verifier `d15b-risk-rules-rspec`、`AGENTS.md` §6 行、新 GS 场景 | 已实施（GS-166） |
| 11 | 文档 | 5 个 Skill + 业务方案 §72.2/§78-D15 回写 + PRD `done` | 已实施 |

## 验证策略

- **主验证**：注册 verifier `d15b-risk-rules-rspec`（6 个新 spec + 3 个既有回归 + 导航），`harness verify` 采 test 证据。
- **锚点证据**：AC-010「回滚生成新版本且源版本不可变」+ AC-015「零副作用与兼容（P8/D15 切片1 行为不变）」。
- **确定性证据**：AC-006/AC-016「同订单同桶（跨 now 调用）」「percent=0/100 边界」。
- **契约**：`harness generated:check`（预期零漂移）。
- **dev 冒烟**：建规则集 → 发布 → 灰度 50%（同一订单多次评估桶恒定）→ 命中/未命中与 skip 原因 → 回滚（新版本 + 源版本内容不变）→ 订单留痕含版本/桶 → 零副作用（订单/支付/账本计数全等）→ HTTP 与路由可达 → 事务回滚无残留。

## 实施记录

| 项 | 结果 |
|---|---|
| 迁移 | `20260917010000` 已应用（2 表 + 3 唯一索引（2 partial）+ 4 普通索引；`schema.rb` +37 行） |
| 服务/模型 | 已落地（`RiskRuleSet`/`RiskRuleVersion` + `Rules::{Condition,Schema,Evaluate,Versioning}` + `Assess` 合并） |
| 后台 | `/admin/risk_rules`（Orders position 59.5）+ 9 条路由（index/show/create/preview/create_version/publish/canary/rollback/toggle） |
| i18n | gem `en.yml` 109 键 + host `zh-CN` 109 键（键集一致） |
| 测试 | verifier `d15b-risk-rules-rspec`：**108 examples, 0 failures**（6 新 spec 60 例 + 导航 + preflight/d15_assess/d15_risk_lists 回归） |
| 跨层搜索结论保持 | Host App / API v3 / storefront / platform 均无命中 → 本切片**零契约变更**（`generated:check` 零漂移） |
| 设计变更（相对 REQ 初稿） | ① 新增 `create`（建规则集容器）与 `preview`（订单试算）两个动作（初稿只列了 show/版本/灰度）；② 展示口径写在控制器（不另建 helper）；③ 额外登记 `PermissionRegistry :risk_rules`（便于 DB 角色矩阵可见） |
| 遗留 | `force_3ds` 与 provider 下发（切片3）；可视化规则构建器；BIN/设备指纹条件不可得 |
