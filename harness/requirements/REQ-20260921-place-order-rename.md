# REQ-20260921-place-order-rename（Place Order 正名与显式化）

> **关联 PRD**：`docs/prd/checkout/PRD-20260921-checkout-place-order-正名与显式化-bff-prepare-place-order-前台-prepareorder-p.md`（状态 **approved**，2026-09-21 用户「确认」）
> **关联设计文档**：`docs/design/payment-convergence-stripe-only.md` §3.0 + §12（切片 8 展开）+ §11 决策 6/7/8 + §11.1 硬约束 **C-5**
> **任务**：`TASK-20260921005741-b8111f83` · Gate `GATE-2026-09-21T00-57-48`

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | place_order / prepare | 无 | ❌ 无（不在范围） |
| App — views/decorators | `backend/app/` | — | 无 | ❌ 无 |
| Core Gem — models | `pallastrade_gems/pallastrade_core/app/models/` | submitted_at / state | `pallastrade/order.rb`（`state=pending` + `submitted_at`） | ✅ 已具备，**不改** |
| Core Gem — services | `.../pallastrade_core/app/services/` | build_order / submit / convert! | **`carts/submit.rb`（真正的下单实现）** | ✅ 已具备，**不改** |
| API Gem — controllers | `.../pallastrade_api/app/controllers/` | carts#submit | `v3/store/carts_controller.rb#submit`（行锁 + converted replay 幂等） | ✅ 已具备，**不改** |
| Admin Gem — controllers | `.../pallastrade_admin/app/controllers/` | — | 无 | ❌ 无（不涉及） |
| Admin Gem — views | `.../pallastrade_admin/app/views/` | — | 无 | ❌ 无 |
| Storefront | `storefront/src/` | prepare / prepareOrder / CheckoutPrepareBody | `app/api/checkout/prepare/route.ts`（注释自认「做两件事」）、`components/checkout/UnifiedCheckout.tsx#prepareOrder`、`lib/checkout/server.ts#CheckoutPrepareBody`、`__tests__/UnifiedCheckout.test.tsx` | ✅ **已实现** —— 仅缺**正名** |
| Platform | `platform/packages/` | — | 无 | ❌ 无（BFF 是 Next 内部契约） |

### 搜索结论

- **已有能力**：下单实现在 Core/API 层**早已存在且完整**；前台的两段语义与「先建单再付款」的**顺序强制**也已实现并有测试锁定。
- **需要新建**：仅 **命名层**（新路由文件 + 别名转发 + 函数/类型改名 + 文档术语）。
- **防重复判定**：**不是重复建设** —— 本任务**不新增任何能力**，只把已有能力改成名副其实的名字。**行为等价是第一约束**（硬约束 C-5）。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 本次**不走**自定义决策树第 1–7 级（不改 core/gem、不加 decorator/extension）；属对既有**前台文件与 BFF 路由**的就地改名，无升级合并面 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 本任务**不触碰后台**（`/admin/orders` 列表口径属切片 9 已完成）；「面包屑由导航配置自动推导」在此不适用 |
| `ai/skills/pallastrade-storefront/SKILL.md` | ✅ 已读 | 原文已写明两段语义：「先 Prepare（= BFF `carts.update` + `carts.submit`，返回 `{ order_id, order, quote }`，**不建** PaymentSession/Transaction）→ 再 Start（只做 Pay）」；且 P1-a 段明确「**一次点击**」「**绝不自动扣款**」。本任务只改**名字**，AC 以**不回退既有口径**为准 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-checkout` | ✅ 涉及 | ✅ 已读 | 已读 §"Guest checkout vs logged-in" 与两段语义段；本次**不改**任何 checkout 行为，只在两个 skill 里把端点术语统一为 `place-order` |
| `pallastrade-api-v3` | ❌ 不涉及 | ✅ 已读 | **零 API 变更**（`/api/checkout/*` 是 Next BFF，不入 OpenAPI） |
| `pallastrade-decorators` | ❌ 不涉及 | — | 不改 core 类结构 |
| `pallastrade-dependencies` | ❌ 不涉及 | — | 不替换核心服务 |
| `pallastrade-events-webhooks` | ❌ 不涉及 | ✅ 已读 | 硬约束 **C-7**：不新增订单类事件（`order.submitted` 已是建单提交后的等价事实源） |
| `pallastrade-testing` | ✅ 涉及 | ✅ 已读 | 前台 Vitest 位于 `storefront/src/**/__tests__/*.test.tsx`；每条 AC 必须落测试并标注完整 PRD-ID + AC-x |
| `pallastrade-i18n` | ❌ 不涉及 | ✅ 已读 | **本任务不新增任何用户可见文案**（纯重命名，顾客可见交互零变化 —— C-5） |

---

## 需求标题

Place Order 正名与显式化：BFF `prepare` → `place-order` + 前台 `prepareOrder` → `placeOrder`（保留薄别名）

## 任务类型

功能优化（重构 / 正名，**非新功能**）

## 需求描述

用户与 AI 在设计讨论中反复困惑「要不要在下单环节加一个 place order」。取证后发现：**它已经在做这件事，只是名字不叫这个**。BFF 端点 `POST /api/checkout/prepare` 的实际行为是 `carts.update`（保存）+ `carts.submit`（**建正式订单**），前台函数 `prepareOrder()` 同理 —— 命名暗示「预检」，实际是「下单」。

本需求把这些名字改成名副其实的，并与设计文档 `docs/design/payment-convergence-stripe-only.md` §3.0 的「Place Order → Payment」术语对齐。**零行为变更。**

## 影响范围（harness affected 输出）

```json
{ "filesChanged": 9, "affectedComponents": ["backend", "harness"], "errors": [], "estimatedTests": 36 }
```

> 注：`backend` / `harness` 的命中来自**并行会话**的未提交改动，与本任务无关 —— 本任务改动面**全在 `storefront/`**。

## 技术方案（初步）

- **FR-001**：新增 `app/api/checkout/place-order/route.ts`，由 `prepare/route.ts` **搬移**（实现只允许存在一份）。
- **FR-002**：`prepare/route.ts` 改为**薄别名**（仅转发到同一处理函数，**不得含业务逻辑**）。
- **FR-003**：`UnifiedCheckout.tsx` 的 `prepareOrder()` → `placeOrder()`；调用点与注释同步；**控制流不变**。
- **FR-004**：`lib/checkout/server.ts` 的 `CheckoutPrepareBody` → `CheckoutPlaceOrderBody`，**保留旧名 alias**。
- **FR-005**：术语统一到两个 skill 与设计文档 §3.0.4。

## 风险点

| 风险 | 缓解 | 回滚难度 |
|---|---|---|
| **行为漂移**（搬移时顺手改了别的）| 硬约束 **C-5**；实现只存在一份；既有 52 例测试不回退 | 低（单提交 revert） |
| **丢失守卫**（`sameOrigin` 403 / `invalid_request` 400） | AC-006 / AC-007 直接锁两条路径的守卫行为 | 低 |
| **漏改引用**（BFF 路径是字符串字面量） | 全仓 `rg -n "checkout/prepare"` 一次清；AC-005 双路径对比测试兼作兼容网 | 低（别名兜底） |
| **别名长期残留**成第二真相源 | §12 Q-1 定删除时点；别名不得携带业务逻辑 | 低 |

> 最高风险：R-2（行为漂移，影响高、概率低）。**本任务零数据变更**，故回滚 = `git revert`，无数据恢复动作。

## 决策节点

⏸️ **用户已于 2026-09-21 回复「确认」** → PRD 置 `approved`，进入实施。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Storefront BFF 路由 | `app/api/checkout/place-order/route.ts`（新增）+ `prepare/route.ts`（薄别名） | `npx vitest run .../place-order/__tests__/route.test.ts` | **5 tests passed**（AC-001/005/006/007） | ✅ |
| Storefront 组件 | `components/checkout/UnifiedCheckout.tsx` | `npx vitest run .../UnifiedCheckout.test.tsx`（52 例不回退） | **52 tests passed**（零回退，AC-002/008） | ✅ |
| 类型 alias | `lib/checkout/server.ts` | `npx tsc --noEmit`（不得**新增**错误） | 未单跑 typecheck：本次只**新增**一个 interface + 一个 type alias，**未删改**任何既有类型；改名脚本实测无残留（`prepareOrder`/`preparedOrder`/`/api/checkout/prepare` 均为 0） | ⚠️ 降级（理由如上） |
| 知识资产 | 两个 skill + 设计文档 §3.0.4 | `harness doc-impact` | storefront skill 已更新（2 处）；checkout skill 无命中（引用的是前端路由而非 BFF 端点）；设计文档 §3.0.4 已回填；scenarios 新增 GS-205 | ✅ |
| 后台导航（回归） | 不变 | `pallastrade:admin:nav_validate` | 本任务不改后台，未单跑；上一轮同分支已跑 nav:validate OK — 0 warning(s) | ⚠️ 降级（理由如上） |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

**本节不适用：本任务不改动任何 admin 页面**（纯前台重命名）。

### 验证结论

5 条 FR 全部落地并验证：新增路由测试 5 例通过（含**别名引用同一性** `expect(preparePOST).toBe(placeOrderPOST)`、守卫 403/400、双路径响应逐字段相等）；组件回归 **52 例零回退**；改名残留实测 **0**；`eval-ai --scenarios` **206/206**。

**两处降级已标注理由**：① 未单跑 `tsc --noEmit`（本次只新增类型未删改既有类型，且该命令在本仓**已有既有错误**，单跑无法区分增量）；② 未重跑 nav_validate（本任务零后台改动）。
