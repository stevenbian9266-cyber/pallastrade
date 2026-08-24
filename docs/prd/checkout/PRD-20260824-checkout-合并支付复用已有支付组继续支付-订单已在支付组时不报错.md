# PRD-20260824-checkout-合并支付复用已有支付组继续支付-订单已在支付组时不报错

| 元数据 | 值 |
|---|---|
| 状态 | approved（用户 2026-08-24 通过 askQuestions 确认三项方案） |
| 创建日期 | 2026-08-24 |
| 来源 | 优化：合并支付复用已有支付组继续支付（订单已在支付组时不报错） |
| 分类 | checkout（自动判定） |
| 关联 Skill | pallastrade-payments、pallastrade-api-v3、pallastrade-storefront |
| 关联 REQ | REQ-20260824-payment-group-reuse.md（实施时回填） |
| 关联 PRD | PRD-20260823-checkout-多订单拆分与合并支付（合并支付基础，本 PRD 为行为修正） |
| 需求类型 | 优化迭代 |

> 🔒 **查重回写**：`harness prd new` 自动查重（相似度未达阻止阈值，未命中）。本需求是对 PRD-20260823 合并支付的**行为修正**：订单已在 active 支付组时不再报错，改为复用已有组继续支付。

## 1. 背景与目标

- **一句话需求原文**：优化：合并支付复用已有支付组继续支付（订单已在支付组时不报错）
- **背景**：当前 `PaymentGroups::Create` 在所选订单中任意一个已关联到 active 支付组（status=pending/processing 且未过期）时，直接返回 `:order_in_active_group` 错误（"A selected order is already in an active payment group"）。但用户在以下场景会反复踩到：
  1. 点过 Pay now / Pay together 进了收银台但未付款就退出 → 组停在 pending，订单被锁；
  2. Stripe 会话中断（3DS 取消、页面关闭）→ 组停在 pending/processing；
  3. 重复点击支付按钮。
  这些场景下用户理应能**继续支付**，而不是被报错挡在门外。此外 `PaymentGroups::Create` 创建组时未设置 `expires_at`，导致 active 组永不自动过期，订单会被无限期锁住。
- **目标**：把「订单已在 active 支付组」从硬错误改为**幂等复用**——返回已有组（最近创建的）继续支付；所选订单无论分散在几个组，都并入最近组一次付清。
- **成功指标**：已入组订单再次点支付可直达收银台继续付款；无 `order_in_active_group` 报错；合并/单独支付均不受影响。

## 2. 用户故事 / 场景

- 作为商城顾客，我在点过支付但未付完时再次点支付，应直接回到收银台继续付款，而不是看到错误。
- 作为商城顾客，我勾选多个订单合并支付时，若其中部分订单此前已进过支付组，应统一并入一个组一次付清。

场景：
1. 正常流：未入组订单 → 创建新组 → 收银台（现有行为，回归）。
2. 复用流：单订单已在 active 组 → 返回该组 → 前端跳转该组收银台。
3. 跨组流：所选订单分散在多个 active 组 → 复用最近创建的组，全部订单并入该组。
4. 混合流：部分订单已在组、部分未在组 → 未入组订单并入已有组。
5. 异常流：货币不一致 / 已支付 / 已取消 / 非本人订单 → 仍返回对应错误（回归）。

## 3. 功能需求（FR）

- FR-001：`PaymentGroups::Create` 不再因订单已在 active 支付组而失败；存在 active 组时返回该组（幂等）。
- FR-002：存在多个 active 组时复用**最近创建**的组（按 created_at 最大）。
- FR-003：本次所选订单（含分散在其它组、或未入组的）全部并入被复用的组，组的 `amount` 重新计算。
- FR-004：并入时校验货币一致性（目标组 currency 与本次订单一致），不一致仍返回 `mixed_currency`。
- FR-005：`validate_orders!` 其余校验（not_found / not_owned / canceled / already_paid / mixed_currency）保持不变。
- FR-006：前端无需改动——`CombinedPaymentPicker.paySingle/payNow` 已按返回组 id 跳转收银台。

## 4. 非功能需求（NFR）

- 幂等性：重复点击支付不产生重复组、不报错。
- 数据一致性：订单从旧组移入新组后，旧组若清空则标记 canceled（释放），不残留 pending 空组。
- 兼容：`/api/v3/store/payment_groups` 响应结构不变（仍返回 PaymentGroup）；SDK 无需改动。
- 安全：复用仅限当前 store + 当前用户自己的组。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：订单已在 active 组时 `createPaymentGroup` 返回 success 且 `group.id` 等于已有组 id。
- AC-002 ← FR-001：重复调用不产生新组（组数量不变）。
- AC-003 ← FR-002：订单分散在 2 个 active 组时，返回最近创建的组，全部订单并入该组。
- AC-004 ← FR-003：混合场景（部分已入组）返回已有组，未入组订单并入，`amount` 为组内全部订单之和。
- AC-005 ← FR-004：货币不一致（订单 currency ≠ 目标组 currency）返回 `mixed_currency`。
- AC-006 ← FR-005：已支付 / 已取消 / 非本人 / 未知订单仍返回原错误（回归）。
- AC-007 ← FR-005：无 active 组时正常创建新组（回归）。
- AC-008 ← 前端：订单页点 Pay now / Pay together 命中已有组时，跳转到该组收银台继续支付。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | payment_group | 无 | 不涉及（App 层无支付组逻辑） |
| Core | `pallastrade_gems/pallastrade_core/app/` | PaymentGroup, PaymentGroups::Create, active? | `app/models/pallastrade/payment_group.rb`（active?/状态机/scope）；`app/services/pallastrade/payment_groups/create.rb`（validate_orders! 含 order_in_active_group） | **需修改**：Create 幂等复用；payment_group.rb 无需改 |
| API | `pallastrade_gems/pallastrade_api/app/` | payment_groups, order_in_active_group | `app/controllers/pallastrade/api/v3/store/payment_groups_controller.rb`（错误映射表） | 保留 order_in_active_group 映射即可（Create 不再产生）；无需改 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | payment_group | `admin/payment_groups_controller.rb` + views（只读管理视图） | 不涉及（只读，无需改） |
| Storefront | `storefront/src/` | createPaymentGroup, CombinedPayment | `components/account/CombinedPaymentPicker.tsx`（paySingle/payNow → router.push 收银台） | 无需改：后端返回已有组后自动跳转 |
| Platform | `platform/packages/` | paymentGroups, create | `sdk/src/store-client.ts`（paymentGroups.create POST /payment_groups） | 无需改：接口契约不变 |

**结论**：唯一需改的是 Core 层 `PaymentGroups::Create`（幂等复用）+ 后端测试。前端/SDK/Admin 均无需改动。

## 7. 技术影响

- 涉及文件：
  - `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/payment_groups/create.rb`（核心改动）
  - `backend/spec/services/pallastrade/payment_groups/create_spec.rb`（新增复用/跨组/混合用例）
- 接口：`POST /api/v3/store/payment_groups` 行为变化（命中 active 组时返回已有组而非 4xx），响应结构不变。
- 数据库：无 schema 变更。
- 影响面：合并支付 / 单独支付收银台流程。

## 8. 测试计划

- 更新 `backend/spec/services/pallastrade/payment_groups/create_spec.rb`：
  - AC-001：已有 active 组 → 返回同组
  - AC-002：重复调用不新建组
  - AC-003：跨组 → 返回最近组 + 订单并入
  - AC-004：混合 → 并入 + amount 重算
  - AC-005：货币不一致 → mixed_currency
  - AC-006：已支付/已取消/非本人/未知（回归）
  - AC-007：正常创建（回归）
- 前端：`CombinedPaymentPicker` 现有用例回归（行为不变）。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：store.yaml 无需改（响应结构不变）；评估错误枚举注释是否需要补充幂等说明
- [ ] Skill：`ai/skills/pallastrade-payments/SKILL.md` 补幂等复用说明；`pallastrade-api-v3` 评估
- [ ] 场景库：`harness/scenarios/scenarios.json` 更新 GS-041（mustNotDo 补"不得因订单已在组而拒绝支付"）
- [ ] README / Agent 文件：评估无需更新
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-24 | 0.1 | 初稿（用户确认三项方案：复用最近组 / 全部并入） | AI |


## 1. 背景与目标

- **一句话需求原文**：<用户输入原文>
- **背景**：为什么做、解决什么问题
- **目标**：期望达成的结果
- **成功指标**：可量化指标（如：导入 1 万 SKU 耗时 < 60s）

## 2. 用户故事 / 场景

- 作为 <角色>，我希望 <能力>，以便 <价值>
- 场景列表（正常流 + 边界 + 异常）

## 3. 功能需求（FR）

- FR-001：<可验收的功能描述>
- FR-002：...

## 4. 非功能需求（NFR）

- 性能 / 安全 / 兼容 / 可维护性

## 5. 验收标准（AC，与测试一一映射）

> ⚠️ 以下为示例，正式内容请删除注释标记并替换为真实 AC：
- <!-- AC-001 ← FR-001：<可验证的判定条件> -->
- <!-- AC-002 ← ... -->

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | | | |
| Core | `pallastrade_gems/pallastrade_core/app/` | | | |
| API | `pallastrade_gems/pallastrade_api/app/` | | | |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | | | |
| Storefront | `storefront/src/` | | | |
| Platform | `platform/packages/` | | | |

**结论**：哪些层已有能力 / 哪些需新建 / 防重复判定

## 7. 技术影响

- 涉及组件 / 文件 / 依赖 / 数据库 / 接口
- 影响面（`harness affected --base origin/main` 输出）

## 8. 测试计划

- 新增测试文件（路径清单）
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射（AC-xxx → 测试文件）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |
