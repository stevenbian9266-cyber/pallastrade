# PRD-20260914-other-paymentsource-prefix-disambiguation

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | PRD-20260914-other-prefixedid-ownership-validation（P0-f）**§3 FR-006 范围外残留**：`ps` 前缀被 `PaymentSession` 与 `PaymentSource` 共用 → 前缀不再唯一，归属校验在该对上失效；用户指令「自主决定」授权实施 |
| 分类 | other |
| 关联 Skill | pallastrade-api-v3（§Prefixed IDs）/ pallastrade-data-model / pallastrade-payments |
| 关联 PRD | PRD-20260914-other-prefixedid-ownership-validation（前置，消除跨实体串单）；无重复 PRD |
| 需求类型 | 修复（前缀唯一性 / 契约收敛） |

## 1. 背景与目标

- **事实（代码级实测）**：`PaymentSession` 与 `PaymentSource` 均声明 `has_prefix_id :ps` → 二者 prefixed id 形态完全无法区分。
- **影响面**：
  1. `PaymentSessionReservationSubscriber#find_session` 按 `id.start_with?('ps_')` 判定「这是 PaymentSession」→ 传入 PaymentSource id 时会去查同 PK 的会话（跨资源串单）；
  2. API 同时对外发出 `ps_…`：`payment_setup_session_serializer#payment_source_id`（PaymentSource）与 payment execution / payment session 的 `ps_…`（PaymentSession）→ 调用方无法区分，P0-f 的「前缀 = 类型」契约在该对上失效；
  3. 前缀唯一性守卫规格只能把 `ps` 记为「已知重复」（技术债显性化）。
- **非破坏性确认（本次侦察）**：全仓客户端（storefront `src/`、platform `packages/` 生成类型与 SDK）对 `ps_` 的引用**全部指向 PaymentSession**；`PaymentSource` 的 id 无任何客户端按 `ps_` 解析依赖 → 改名风险低。
- **目标**：`PaymentSource` 改用唯一前缀 `src_`；`PaymentSession` 保持 `ps_`（storefront/SDK 已依赖）；前缀唯一性守卫规格期望**零重复**。

## 2. 用户故事 / 场景

- 作为**调用方**，我拿到 `src_…`/`ps_…` 就能确定资源类型，不必猜；把 A 的 id 传给 B 的端点会被拒绝（而不是命中的同 PK 的另一资源）。
- 场景：① 两资源前缀不同；② 互不解析（含解码证明：同 payload 换旧前缀会命中同 PK）；③ 唯一性守卫零重复；④ 支付链路回归绿。

## 3. 功能需求（FR）

- **FR-001**：`PallasTrade::PaymentSource` 的 `has_prefix_id` 由 `:ps` 改为 `:src`（含 PALLAS-CUSTOM 溯源注释）；`PaymentSession` 不变。
- **FR-002**：前缀归属校验（P0-f）自动覆盖该对资源：`PaymentSession.find_by_prefix_id('src_…')` → nil/404，反之亦然。
- **FR-003**：唯一性守卫规格由「期望重复 = ['ps']」改为「期望零重复」，任何新增重复声明都会失败。
- **FR-004**：知识同步：`pallastrade-api-v3` / `pallastrade-data-model` Skill 的「ps 残留」结论更新为已消除；场景库 GS-115 措辞同步；P0-f PRD 的 FR-006 标注已由本 PRD 收口。
- **FR-005**（范围外）：历史数据中若曾把 `ps_…`（PaymentSource 语义）落库/落外发 webhook，需按需回填 —— 侦察确认本仓无持久化的 prefixed 字符串（DB 存整数 `payment_source_id`），故不回填。

## 4. 非功能需求（NFR）

- **兼容**：`PaymentSession` 的 `ps_` 不变（客户依赖）；`payment_source_id` 在 API 为纯字符串类型，客户端已按不透明字符串处理。
- **无迁移**：前缀为运行时计算（无 DB 列），无数据迁移。
- **可验证**：互不解析与唯一性均由规格守护。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-003：唯一性守卫规格期望零重复（含 `ps` 已消除）。
- **AC-002** ← FR-001：`PaymentSource._prefix_id_prefix == 'src'` 且 `PaymentSession._prefix_id_prefix == 'ps'`。
- **AC-003** ← FR-002：两资源互不解析（并断言同 payload 换旧 `ps_` 前缀会解码出同 PK，证明旧行为会串单）。
- **AC-004** ← FR-002：API 序列化层对外发出 `src_…`（`PaymentSetupSession` 的 `payment_source_id`）。

> 回归（`p0-payment-rspec` / `backend-rspec` 全绿）与知识同步属于**验证证据**（见 §9 与任务证据），不单列为 AC；`prd verify` 只对 AC-001..004 计测试覆盖。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | payment_source | `models/pallastrade/user.rb:4`（UserPaymentSource concern） | 无前缀假设（不受影响） |
| Core | `pallastrade_core/app/` | `has_prefix_id` / `ps_` | `models/pallastrade/payment_source.rb`（**修复点**）、`subscribers/.../payment_session_reservation_subscriber.rb:44`（按 `ps_` 判会话 → 串单隐患） | **本次改动点** |
| API | `pallastrade_api/app/` | payment_source | `serializers/.../payment_setup_session_serializer.rb`（`payment_source_id` → prefixed_id）、`payment_serializer.rb`（source）、`payment_source_serializer.rb` | 受益方（发出 `src_…`） |
| Admin | `pallastrade_admin/app/` | payment_source | `payments_controller.rb`（`payment_source_class`）、`payments/*.erb`（表单 `payment_source[...]` 参数前缀） | 与 id 前缀无关 |
| Storefront | `storefront/src/` | `ps_` / payment_source | 34 处 `ps_` **全部是 PaymentSession** 语义（payment execution / session） | 无需改动 |
| Platform | `platform/packages/` | `ps_` / payment_source | SDK 示例与类型（`payment_source_id: string \| null`；`session.id` 期望 `/^ps_/` = PaymentSession） | 无需改动（类型不变） |

**结论**：改名仅影响 PaymentSource 对外 id 形态，客户端零依赖 → 低风险；同时消除订阅者按前缀判类型的串单隐患。

## 7. 技术影响

- **修改**：`pallastrade_core/app/models/pallastrade/payment_source.rb`、`backend/spec/models/pallastrade/prefixed_id_spec.rb`、`ai/skills/pallastrade-api-v3/SKILL.md`、`ai/skills/pallastrade-data-model/SKILL.md`、`harness/scenarios/scenarios.json`、`docs/prd/other/PRD-20260914-other-prefixedid-ownership-validation.md`
- **数据库**：无迁移
- **接口**：`payment_source_id` / `payment.source.id` 形态 `ps_…` → `src_…`（字符串类型不变）

## 8. 测试计划

- **更新**：`backend/spec/models/pallastrade/prefixed_id_spec.rb`（AC-001/002/003）
- **回归**：`p0-payment-rspec`（注册验证器：支付会话/Webhook/金额权威等）+ `backend-rspec`（全量）
- **AC 映射**：见 §5（测试内以 `PRD-20260914-other-paymentsource-prefix-disambiguation AC-xxx` 注释关联）

## 9. 文档同步清单（知识同步门）—— 结论

| 资产 | 状态 | 结论 |
|---|---|---|
| `ai/skills/pallastrade-api-v3/SKILL.md` §Prefixed IDs | ✅ 已更新 | 「`ps` 残留」改为：PaymentSource → `src_`（2026-09-14 消除），前缀与资源 1:1 |
| `ai/skills/pallastrade-data-model/SKILL.md` §Prefixed IDs | ✅ 已更新 | 唯一性表述更新为「已零重复，规格守卫」 |
| `harness/scenarios/scenarios.json` GS-115 | ✅ 已更新 | 唯一性条款改为「零重复」，并记录 `ps` 冲突已消除 |
| `docs/prd/other/PRD-20260914-other-prefixedid-ownership-validation.md` | ✅ 已更新 | FR-006 残留项标注由本 PRD 收口；变更记录追加 |
| OpenAPI ×2 | ✅ 已评估，无需更新 | 字段类型为 string，无前缀枚举/示例（`payment_source_id` 未在文档中给示例值） |
| SDK / platform 包 | ✅ 已评估，无需更新 | `payment_source_id: string \| null` 类型不变；SDK 集成测试仅断言 PaymentSession 的 `ps_` |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新 | 未引入禁止模式 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 实施：PaymentSource 前缀 `ps` → `src`（+ 溯源注释）；唯一性守卫改为零重复；新增互不解析规格；api-v3/data-model Skill + GS-115 + P0-f PRD 同步 | AI |
