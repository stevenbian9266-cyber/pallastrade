# REQ-20260916-d15-risk-lists

> 任务：**D15 切片1 风控名单与订单风险评估**（业务方案 §78-D15 / §72.2 底座 / §72.3 / §74.1）
> 关联 PRD：`docs/prd/payments/PRD-20260916-payments-d15-risk-lists.md`
> 关联 Task：`TASK-20260916070359-2ef8542e` / Gate：`GATE-2026-09-16T07-04-11`

---

## Step 0：跨层搜索（强制）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | risk / fraud / denylist | 仅生成物（builds CSS、serializer 类型） | ❌ 未满足 |
| App — views/decorators | `backend/app/` | risk | 无命中 | ❌ 未满足 |
| Core Gem — models | `pallastrade_core/app/models/` | `considered_risky` / `is_risky?` | `order.rb:1160 is_risky? = !payments.risky.empty?`、`order.rb:1206 considered_risky!`、`order.rb:1203 consider_risk` | ⚠️ 部分（支付响应驱动，非可配置名单） |
| Core Gem — services | `pallastrade_core/app/services/` | risk / approve | `orders/approve.rb`（写 `OrderApproval` + 清 `considered_risky` + `order.approved`） | ⚠️ 部分（有人工审批闭环，无评估） |
| Core Gem — subscribers | `pallastrade_core/app/subscribers/` + `lib/pallastrade/core/engine.rb` | subscriber 注册 | `PallasTrade.subscribers.concat [...]`（14 个既有订阅者，含 disputes/financial_ledger） | ✅ 复用注册范式 |
| Core Gem — events | `publishable.rb` / `carts/submit.rb` | `order.submitted` | `services/pallastrade/carts/submit.rb:280` 发布 `order.submitted` | ✅ 复用接线点 |
| API Gem — controllers/serializers | `pallastrade_api/app/` | risk | `admin/order_serializer.rb`（暴露 `considered_risky`），无风控端点 | ✅ 无需变更 |
| Admin Gem — controllers/views | `pallastrade_admin/app/` | risk | `orders/_risk_analysis.html.erb`（只读 AVS/CVV）、`orders_controller.rb:234 @order_events = %w{approve cancel resume}` | ⚠️ 部分（缺名单工作台 + 决策卡） |
| Storefront | `storefront/src/` | risk / 3ds | 零命中 | ✅ 无需变更 |
| Platform | `platform/packages/` | risk | 零命中 | ✅ 无需变更 |

### 搜索结论

- **已有可复用**：①`Order#consider_risk`（标记）与 `Orders::Approve`（复核动作）→ 本切片只**新增一个标记来源**，不新增动作；②`order.submitted` 事件 + `PallasTrade.subscribers` 注册表 → 接线零侵入；③D13b `Reconciliations::Payouts::ImportCSV` 的 CSV 范式（`::CSV` + `ImportCSV` 常量命名 + 错误收集）→ 批量导入直接照搬。
- **需新建**：Core 2 表（`pallastrade_payment_risk_lists` / `pallastrade_payment_risk_assessments`）+ 2 模型 + 4 服务（`Risk::Lists::{ImportCSV,Export,Upsert}`、`Risk::Assess`）+ 1 订阅者；Admin 1 工作台 + 1 订单页卡片 + i18n/导航/权限。
- **零改动**：API v3、Storefront、Platform（无契约变更）。

---

## Step 1：Skill 文件咨询（强制，真实结论）

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树优先级 2 = 事件 + 订阅者（副作用）；本次接线选**订阅者**而非 `after_save`（AP-004），配置走 `PallasTrade::Config` 而非硬编码 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 只读/运营页范式：`BaseController` + `model_class` + `admin_tables` 注册 + `filter_by` 同源口径 + 导航 position + 双语 locale；`ResourceController#update` 成功返回 **302**（spec 需 `location_after_save` 打桩） |
| `ai/skills/pallastrade-payments/SKILL.md` | ✅ 已读 | 风控域与「资金语义动作」纪律：本切片**零资金副作用**（不写 funds/Journal/退款）、不调 provider；金额与状态一律不动 |
| `ai/skills/pallastrade-data-model/SKILL.md` | ✅ 已读 | 新表规范：`store_id` + 唯一键（幂等）+ 查询索引 + jsonb 快照；迁移**只新增不回填**；前缀 id 用于对外 |
| `ai/skills/pallastrade-events-webhooks/SKILL.md` | ✅ 已读 | 事件 payload 用前缀 id；订阅者异常**不阻断**主流程（rescue + 日志）；幂等语义由订阅者负责 |
| `ai/skills/pallastrade-security/SKILL.md` | ✅ 已读 | 敏感数据（邮箱/IP/卡指纹）→ 脱敏展示 + 审计不落明文 + 权限门（`can :manage`）；批量导入要防注入/超大文件 |
| `ai/skills/pallastrade-testing/SKILL.md` | ✅ 已读 | 验证器注册进 `harness.config.mjs`；用例须环境无关（随机 code、`find_by || create`）；断言用结果而非实现 |
| `ai/skills/pallastrade-i18n/SKILL.md` | ✅ 已读 | 新键同时补 gem `en.yml` 与宿主 `zh-CN`；改 locale 后必须 `YAML.load_file` 校验 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ⬜ 本次不涉及 | 零 API 端点变更（不新增/不改 v3 契约） |
| `ai/skills/pallastrade-storefront/SKILL.md` | ⬜ 本次不涉及 | 零前台改动 |

---

## 需求标题

风控名单（可运营 + 可批量导入 + 到期 + 审计）与**名单驱动的订单风险评估**（决策留痕 + 复用既有 `considered_risky` / `Orders::Approve` 复核闭环），为 D15 后续切片（规则引擎版本/回滚、3DS 下发、复核队列）打地基。

## 任务类型

新功能（D15 切片1）

## 设计要点（实施依据）

1. **表名遵循 §74.1 规划**：`pallastrade_payment_risk_lists`（`UNIQUE(list_type, subject_type, value_hash)`）；决策留痕表 `pallastrade_payment_risk_assessments`（切片专属，列见 PRD FR-005）。
2. **归一化唯一口径** `PaymentRiskList.normalize_value`（邮箱小写/去空白、BIN 去分隔符、国家大写）→ `value_hash = SHA256("#{list_type}:#{subject_type}:#{normalized}")`；幂等靠唯一键 + `upsert`。
3. **到期即失效**：`active` scope = `status='active' AND (expires_at IS NULL OR expires_at > now)`；撤销靠 `status='revoked'`（不物理删，保留审计）。
4. **决策默认保守**：`PallasTrade::Config[:risk_denylist_action]` 默认 `review`（**不误伤**：不会自动阻断真实订单）；`allow`/`review`/`block` 三值白名单化。
5. **接线零侵入**：订阅 `order.submitted` → `Risk::Assess` → 非 allow 时 `order.consider_risk`；订阅者内部 rescue（**绝不**让风控异常阻断下单）。
6. **店铺隔离**：评估只取 `store_id IS NULL OR store_id = order.store_id`；工作台只写本店/全局行（与 D14b 同纪律）。
7. **脱敏**：页面/审计只显脱敏值；CSV 导出保留原值（权限 + 审计）。
8. **复用 CSV 范式**：`Risk::Lists::ImportCSV` 照搬 D13b（`::CSV` 显式命名空间、`ImportCSV` 常量名、逐行错误收集、分批 upsert）。

## 切片拆分

- 切片 1（本批）：名单台账 + 批量导入/导出 + 维护/撤销 + 名单驱动评估留痕 + 订阅者接线 + 后台工作台/订单页决策卡。
- 切片 2：规则引擎（条件/动作/priority/版本/灰度/回滚）→ 满足「规则可回滚」锚点。
- 切片 3：3DS/SCA 策略（`always`/`risk_based`/`off` + 豁免）与 provider 下发 → 满足「高风险订单只给 redirect+3DS」锚点。
- 切片 4：复核队列（SLA 倒计时 + 通过并捕获 / 拒绝并释放 / 请求补充材料 + 与交易排障台互跳）。

## 实施记录（收口时补全）

- **改动清单（2026-09-16 收口）**：
  - 迁移 `backend/db/migrate/20260916220000_create_pallastrade_payment_risk_lists.rb`（两表 + 唯一键 + 索引，只建表不回填）。
  - Core：`models/pallastrade/payment_risk_list.rb`、`payment_risk_assessment.rb`（新）、
    `services/pallastrade/risk/assess.rb`、`risk/lists/{upsert,import_csv,export}.rb`（新）、
    `subscribers/pallastrade/risk/order_submitted_subscriber.rb`（新）+ `lib/pallastrade/core/engine.rb`（注册订阅者）、
    `lib/pallastrade/core/configuration.rb`（`preference :risk_denylist_action`，默认 `review`）、
    `models/pallastrade/order.rb`（`has_many :risk_assessments`）、
    `permission_sets/configuration_management.rb`（`can :manage, PallasTrade::PaymentRiskList`）。
  - Admin：`risk_lists_controller.rb` + `views/…/risk_lists/{index.html.erb,_order_assessment_card.html.erb}`（新）、
    `config/routes.rb`、`initializers/pallastrade_admin_navigation.rb`（position 59）、
    `initializers/pallastrade_admin_partials.rb`（`order_page_body` 注入订单页风控卡）、
    gem `config/locales/en.yml` + 宿主 `backend/config/locales/admin_risk_lists.zh-CN.yml`。
  - 验证器：`harness.config.mjs` 注册 `d15-risk-lists-rspec`（5 份新 spec + 导航一致性回归）、`AGENTS.md` §6 行、场景库 **GS-153**。
  - API / Storefront / Platform：**零改动**。
- **验证器用例数**：`d15-risk-lists-rspec` = **43 examples, 0 failures**。
- **决策与偏差**：
  1. 名单导航放在 **Orders** 域（与 D13/D14 的全部支付运营页一致），而非新建顶级项。
  2. `subject_type` 支持 8 类，但本切片**评估只自动解析** 4 类订单本地可得主体（email/ip/customer/country）；其余靠人工维护，接线留切片3。
  3. BIN 脱敏采用「只露头部 4 位」（首尾各留 4 位会让 8 位 BIN 全露）。
  4. 留痕幂等从「每秒一行」细化为「**同决策 + 同命中集复用窗口 5 分钟**，决策变化/窗口之外新增」（避免重复投递丢行、也避免审计丢历史）。
  5. 测试文件从 PRD 初版的 6 份收敛为 5 份（维护/导入/导出合并为一份），已回写 PRD §8。
