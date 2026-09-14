# PRD-20260914-other-prefixedid-ownership-validation

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | research `RESEARCH-20260913-checkout-plan-review-and-decision` §9.1 **P0-f**（`PrefixedId` 前缀归属校验，防串单）—— 用户指令「继续」授权实施 |
| 分类 | other |
| 关联 Skill | pallastrade-data-model（§Prefixed IDs）/ pallastrade-api-v3（§Prefixed IDs） |
| 关联 REQ | harness/requirements/REQ-20260914-prefixedid-ownership-validation.md |
| 关联 PRD | 与 PRD-20260914-checkout-cart-discount-codes-canonical 同期（同属 §9.1 P0 队列收尾）；无重复 PRD |
| 需求类型 | 修复（跨实体 id 串单防护） |

## 1. 背景与目标

- **实测事实（代码级，2026-09-14）**：`pallastrade_core/app/models/concerns/pallastrade/prefixed_id.rb`
  - `PrefixedId.decode_prefixed_id`（L73）把 `"prefix_xxxx"` 拆开后**丢弃前缀**，只返回 Sqids 解出的整数 PK；
  - `find_by_prefix_id!`（L135）/`find_by_prefix_id`（L143）直接用该整数 `find(id)`，**不校验前缀归属**。
- **后果（跨实体 id 串单）**：`Product.find_by_prefix_id!("or_#{同一 PK 的 sqid}")` 会把**订单 id 解析成商品**（只要该整数在商品表存在）；反之 `variant_`、`cart_`、`prod_` 等互相之间同理。而 API 契约明确规定「资源类型由前缀隐含（无 `type` 字段）」——前缀是类型标识，跨前缀解析即契约违背。
- **目标**：`has_prefix_id` 声明的前缀成为**归属约束**：跨前缀 id 一律不解析（bang → `RecordNotFound` / 404；非 bang → `nil` / 过滤返回空集，不 500）。
- **成功指标**：新增前缀归属规格全绿；后端全量回归不破坏任何既有合法解析路径；API 契约（§Prefixed IDs）与实现一致。

## 2. 用户故事 / 场景

- 作为**平台方**，我希望把 A 类资源的 id 传给 B 类资源端点时得到 404/空集，而不是"恰好命中同 PK 的另一个资源"，避免越权读取/错改。
- 场景：① 自有前缀正常解析（回归）；② 外来前缀 bang 抛错、非 bang 返回 nil；③ 过滤参数使用外来前缀 → 空集（不 500）；④ `Order.find_by_param` 不再解析外来前缀；⑤ `Order.find_by_param` 对自有 `or_` 与 legacy order number/id 仍正常；⑥ 前缀登记唯一性守护（新重复前缀会失败）。

## 3. 功能需求（FR）

- **FR-001**（解析层）：`PrefixedId` 新增 `split` / `decode_with_prefix` / `prefix_of`，`decode_prefixed_id` 语义保持不变（通用解析路径如 `ParamsNormalizer`、导出、搜索提供者不受影响）。
- **FR-002**（归属校验）：`find_by_prefix_id!` / `find_by_prefix_id` 通过 `decode_owned_prefixed_id!` 校验前缀 == 本类 `_prefix_id_prefix`；不匹配 → `ActiveRecord::RecordNotFound`（bang）/ `nil`（非 bang）。
- **FR-003**（Order 参数解析）：`Order.find_by_param` 的解码分支只接受自有 `or_` 前缀，外来前缀继续走 number/整数回退（→ `nil` 或 `RecordNotFound`），不串单。
- **FR-004**（唯一性守护）：新增规格扫描所有模型声明的 `has_prefix_id`，把**当前已知重复**固定为 `ps`（`PaymentSession` / `PaymentSource`），任何新增重复前缀都会让规格失败。
- **FR-005**（知识同步）：`pallastrade-data-model` / `pallastrade-api-v3` Skill 记录"前缀 = 归属约束"与 `ps` 残留；research §9.1 P0-f 标记完成；场景库新增条目。
- **FR-006**（范围外）：重命名 `ps`（对已发布 API 是破坏性变更，另立 PRD 评估）；`decode_prefixed_id` 的泛用调用点逐一收敛（保持通用语义）。

## 4. 非功能需求（NFR）

- **兼容**：合法路径零行为变化（自有前缀、legacy number/id、slug 解析）；错误口径与既有 API 约定一致（资源 404 / 过滤空集）。
- **性能**：仅一次字符串 split + 常量比较，无额外查询。
- **可观测**：`RecordNotFound` 消息包含前缀与期望前缀，便于排查。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-002：自有前缀 `find_by_prefix_id!` 正常返回记录（回归）。
- **AC-002** ← FR-002：外来前缀 → bang 抛 `RecordNotFound`，非 bang 返回 `nil`（且断言解码整数确实指向该记录 PK，证明修复前会串单）。
- **AC-003** ← FR-002：外来前缀过滤查询返回空集，不抛 500。
- **AC-004** ← FR-003：`Order.find_by_param(prod_…)` 返回 nil（不再解析为订单）。
- **AC-005** ← FR-003：`Order.find_by_param(or_…)` 与 legacy `order.number` 仍解析成功（回归）。
- **AC-006** ← FR-004：前缀唯一性守护规格通过（已知重复仅 `ps`）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `find_by_prefix_id` | `controllers/pallastrade/admin/ai_controller.rb:205` | 受益方（自动获得归属校验） |
| Core | `pallastrade_core/app/` | `has_prefix_id` / `decode_prefixed_id` | `concerns/pallastrade/prefixed_id.rb`（**修复点**：decode 丢弃前缀 / find_by_prefix_id! 无校验）、115 个模型声明前缀、`finders/orders/find_complete.rb`（自带 decode） | **本次改动点** |
| API | `pallastrade_api/app/` | `find_by_prefix_id!` | 98 处（`cart_resolvable`、`order_resolvable`、admin resource controllers…） | 受益方（404 取代串单） |
| Admin | `pallastrade_admin/app/` | `find_by_prefix_id` | 40 处（`order_concern`、`addresses`、`api_keys`、`disputes_ops`…） | 受益方 |
| Storefront | `storefront/src/` | prefixed / `prod_` | 仅透传 id（无解析逻辑） | 无需改动 |
| Platform | `platform/packages/` | prefixed | 仅 SDK 集成测试脚本消费 `prefixed_id` | 无需改动；SDK 类型不变 |

**结论**：修复集中在 Core concern（+ Order 参数解析），API/Admin 全为受益方；**必须跑后端全量回归**（行为面横跨 138 处调用点）。

## 7. 技术影响

- **修改**：`pallastrade_core/app/models/concerns/pallastrade/prefixed_id.rb`、`pallastrade_core/app/models/pallastrade/order.rb`（`find_by_param`）
- **新增**：`backend/spec/models/pallastrade/prefixed_id_spec.rb`
- **数据库**：无迁移
- **接口**：错误口径不变（404 / 空集），无 schema 变化；`ps` 前缀歧义为**已知残留**（记录于 Skill/PRD）

## 8. 测试计划

- **新增**：`backend/spec/models/pallastrade/prefixed_id_spec.rb`（AC-001..006；含唯一性守护扫描）
- **验证器**：`backend-rspec`（全量，行为面横跨 API/Admin/Core）
- **AC 映射**：见 §5（测试内以 `PRD-20260914-other-prefixedid-ownership-validation AC-xxx` 注释关联）

## 9. 文档同步清单（知识同步门）—— 结论

| 资产 | 状态 | 结论 |
|---|---|---|
| `ai/skills/pallastrade-data-model/SKILL.md` §Prefixed IDs | ✅ 已更新 | 前缀 = 归属约束；跨前缀 → 404/nil/空集；`ps` 已知重复 |
| `ai/skills/pallastrade-api-v3/SKILL.md` §Prefixed IDs | ✅ 已更新 | 契约显式化：前缀即类型，跨前缀 id 不解析 |
| `harness/scenarios/scenarios.json` | ✅ 已更新 | 新增 GS-115（归属校验 + 唯一性守护） |
| `docs/research/RESEARCH-20260913…` §9.1 / §12 | ✅ 已更新 | P0-f 标记完成；§12 两项运行时验证标记闭环 |
| OpenAPI ×2 | ✅ 已评估，无需更新 | 端点路径/参数未变；错误仍为 404/空集（既有约定） |
| SDK / platform 包 | ✅ 已评估，无需更新 | 无类型变化 |
| 反模式库 / 任务规则 | ✅ 已评估，无需更新 | 未引入禁止模式；反而消除一类越权解析 |
| 本 PRD 状态 + README 索引 | ✅ 已更新 | `done`；`prd-status-sync --check` 校验 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 1.0 | 实施：`decode_with_prefix` 暴露前缀；`find_by_prefix_id(!)` 归属校验；`Order.find_by_param` 限自有前缀；新增规格（含唯一性守护 pin `ps`）；Skill×2 + GS-115 + research §9.1/§12 同步 | AI |
