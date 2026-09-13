# REQ-20260913-dsp-p7-7-admin-disputes-console

> 关联 PRD：`docs/prd/payments/PRD-20260913-payments-dsp-p7-7-admin-disputes-console.md`
> 任务：`TASK-20260913011222-7251b398` ｜ Gate：`GATE-2026-09-13T01-12-31`（feature，branch `dev`）

---

## Step 0：跨层搜索（强制执行）

关键词：`dispute` / `chargeback` / `ops` / `admin` / `for_store` / `ransack` / `tables.register` / `navigation`

| 层 | 搜索路径 | 找到的文件 | 是否满足需求？ |
|---|---|---|---|
| App | `backend/app/`、`backend/config/` | 无 dispute admin 代码（`grep dispute` 在 admin 侧 0 命中）；`backend/config/initializers/pallastrade_permission_registry.rb`（资源注册表，**无 `:disputes`**）、`backend/config/locales/admin_nav.zh-CN.yml`（zh 文案） | ⚠️ 需注册 capability + 补 zh-CN 文案 |
| Core Gem | `pallastrade_core/app/` | `models/pallastrade/dispute.rb`（**无 `for_store`、无 ransack 白名单**）、`permission_sets/{order_management,order_display,super_user}.rb`（**均无 Dispute 规则**）、`models/pallastrade/ability.rb` | ⚠️ 需补 `for_store` + ransack 白名单 + 权限集只读规则 |
| Admin Gem | `pallastrade_admin/app/`、`config/` | `controllers/.../{payments_ops,refunds_ops}_controller.rb`（范式）、`config/routes.rb:321-341`（ops 路由段）、`config/initializers/pallastrade_admin_navigation.rb:80-113`（Orders 组，position 5/10/20/30/40/45/48）、`config/initializers/pallastrade_admin_tables.rb`、`config/locales/en.yml:482-483`、`app/views/.../{payments,refunds}_ops/*` | ❌ 无 dispute 页面 → 本切片**新增**（范式可复制：控制器/视图/表格注册/导航/路由） |
| API Gem | `pallastrade_api/app/` | 无命中（无 dispute 端点） | ❌ 本切片不加 API（Console 仅 Admin HTML） |
| Storefront | `storefront/src/` | 无命中 | ❌ 不适用 |
| Platform | `platform/packages/` | 无命中 | ❌ 无 SDK 变更 |

### 搜索结论（含 5 个模型/接线缺口，侦察确认）

1. **`PallasTrade::Dispute` 缺 3 项能力**：无 `for_store`（→ `ResourceController` 的 `model_class.try(:for_store, current_store)` 回退全表 = **跨店泄露风险**）、
   无 `whitelisted_ransackable_attributes`（→ 列表过滤静默失效）、无任何授权规则（→ 除超管外角色访问被拒）。
2. **Admin 侧缺 4 类接线**：路由 / 导航 / 表格注册 / 双语文案 —— 均按 `RefundsOpsController`（REV-P6-8a/8b）与 `PaymentsOpsController`（REV-P6-8h）范式新增。
3. **防重复判定（AP-SEARCH-1/2/3）**：不新建事实/裁决/对账/证据/收敛逻辑（全部复用 P7-1..6 服务：
   `ResolveFact` / `Recover`（`apply:` 可控）/ `BuildEvidenceSnapshot` / `ReconcileDispute`）；不新建导航顶级项（挂既有 Orders 组）；
   不新建权限体系（走既有 registry + permission sets）。
4. **零 schema 变更**：`store_id` 列已存在；P7-4 证据快照为 transient（不落库），无新表。

---

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树第 8 级（框架自研产品线：直接改 Gem 并标 `# PALLAS-CUSTOM:`）；行为型副作用走 Subscriber（非 `after_save`，AP-004）；本切片属 Admin 展现层，不引入回调 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | ①§Adding a new admin resource：控制器 + 视图 + **表格注册** + **导航注册** + 路由 五件套；②§Customizing the sidebar：新增页面**只声明导航项**，不改导航代码（`orders.add` 支持 `label/url/position/active/if`）；③面包屑由导航自动推导 → 新页面三要素自检（标题 / 面包屑 / 图标）；④String label 需 en+zh 双语（`nav_validate` 硬门槛） |
| `ai/skills/harness-prd/SKILL.md` | ✅ 已读 | 阶段 2 要求 `supervise plan` + gate preparation 清理；阶段 3/4 证据四类与知识同步门；PRD 未 done 不得关 gate |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-payments` | ✅ | ✅ 已读 | Skill 明文约定（§Admin Ops）：「Show 页 `page_actions` 按钮仅 eligible + `can?(:update)` 显示，危险操作 `turbo_confirm`；i18n 双语。模板 = `TransactionsController#recover`」；P7-6 动作语义（`Recover(fetch:, apply:)` 幂等 / `BuildEvidenceSnapshot` transient 不落库 / `ReconcileDispute` 零 provider I/O）；危险操作（接受争议/提交证据）归 P7-8 |
| `pallastrade-i18n` | ✅ | ✅ 已读 | `PallasTrade.t('key')` 自动加 `pallastrade.` 前缀；新增键需 gem `admin/config/locales/en.yml` + 宿主 `admin_nav.zh-CN.yml` **成对**；**改 gem en.yml 后必须 normalize**（monorepo 约定） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 「Test behavior, not implementation」「Real factories, not stubs（外部 HTTP/Stripe 才打桩）」→ 请求 spec 断言 HTTP 状态 + 页面内容 + DB 事实；负向断言优于注释 |

---

## 需求标题

DSP-P7-7：争议**管理后台控制台**（Disputes Ops）—— 只读检视（源计划 §66 的 18 项）+ 5 个安全动作
（刷新 provider 状态 / 收敛预览 / 收敛执行 / 生成证据快照 / 标记人工复核）；**不含**接受争议与提交证据。

## 任务类型

新功能（Admin 页面 + 5 个动作；0 migration、0 API）。

## 需求描述

新增 `Admin::DisputesOpsController`（Orders → Disputes，store 作用域）+ 列表表格注册 + 详情页全字段下钻 + 5 个幂等安全动作
（唯一写路径 = `Recover` 收敛与 `Mark Manual Review`，均不触碰资金实体）；补齐模型的 `for_store` / ransack 白名单与权限接线。范围与 AC 见 PRD §3/§5。

**范围外**：`Accept Dispute` / `Submit Evidence`（危险操作，归 P7-8）、任何退款/重扣/provider 写调用、API 端点、证据提交、账行改写。

## 已确认的产品决策（2026-09-13）

| # | 决策 | 取值 |
|---|---|---|
| 1 | 动作集合 | **包含** `dry_run`（收敛预览，零写）；共 5 个动作（源计划 §67 四个 + dry_run） |
| 2 | `recover` 执行 | **允许真实执行**（带 `turbo_confirm` + 幂等 + 铁律负向断言） |
| 3 | 运营角色可见性 | `OrderManagement` / `OrderDisplay` **补 Dispute 只读规则**（运营开箱可见） |

## 验证方案（AC ↔ 命令）

| AC | 命令/证据 |
|---|---|
| AC-P77-01..04、11、14 | `docker exec pallastrade-web-1 bash -lc "cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/disputes_ops_spec.rb"` |
| AC-P77-05..10、12 | `... rspec spec/requests/pallastrade/admin/disputes_ops_actions_spec.rb` |
| AC-P77-13 | `... rspec spec/requests/pallastrade/admin/navigation_consistency_spec.rb` + `node scripts/nav-validate-static.mjs` |
| AC-P77-15 | `... rspec spec/models/pallastrade/dispute_spec.rb` |
| AC-P77-16 | 注册 verifier `backend-rspec`（全量）+ `harness generated:check` + `doc-impact` |

## 用户确认

| 项 | 状态 |
|---|---|
| PRD 已呈现 | ✅ 2026-09-13 已呈现（范围 + 6 层搜索发现的 5 个缺口 + 3 个决策点） |
| 用户确认 | ✅ **已确认**（2026-09-13 问答工具：包含 dry_run / 允许真实执行 recover / 补只读规则） |
