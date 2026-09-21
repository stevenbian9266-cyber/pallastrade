# PRD-20260921-checkout-place-order-正名与显式化-bff-prepare-place-order-前台-prepareorder-p

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-21 |
| 来源 | Place Order 正名与显式化：BFF prepare → place-order + 前台 prepareOrder → placeOrder（保留薄别名） |
| 分类 | checkout（关键词命中 1，自动判定） |
| 关联 Skill | pallastrade-storefront、pallastrade-checkout |
| 关联 REQ | REQ-20260921-place-order-rename.md |
| 关联 PRD | N/A（`harness prd new` 查重未阻止新建） |
| 需求类型 | 优化迭代（**正名与显式化**，非新功能） |
| 影响层 | ☐ App ☐ Core ☐ API ☐ Admin ☑ Storefront ☐ Platform |
| 风险等级 | critical（`harness risk check` 输出） |
| 关联设计文档 | `docs/design/payment-convergence-stripe-only.md` §3.0（下单编排总则）+ §12（切片 8 展开）+ §11 决策 6/7/8 + §11.1 硬约束 C-5 |

---

## 0. 摘要（TL;DR）

- **一句话结论**：把 BFF 端点 `POST /api/checkout/prepare` 正名为 `POST /api/checkout/place-order`、前台函数 `prepareOrder()` 正名为 `placeOrder()`，`prepare` 保留为**薄别名**。**行为完全等价** —— 两段语义（先建单再付款）今天已实现，本次只是**把名字改成它实际在做的事**。
- **交付物清单**：① 新增 `app/api/checkout/place-order/route.ts`（由 `prepare` 搬移）；② `prepare` 路由改为转发的薄别名；③ `UnifiedCheckout.tsx` 函数改名 + 注释术语统一；④ `lib/checkout/server.ts` 类型改名（保留旧名 alias）；⑤ 测试与文档同步。
- **不做的事（Out of Scope）**：❌ 不改建单/支付链路（零行为变更，硬约束 **C-5**）；❌ 不改 Store API `carts/:id/submit`（本任务**零后端改动**）；❌ 不删 `prepare`（保留过渡期，删除时点见 §12 Q-1）；❌ 不改顾客可见文案与交互。
- **前置依赖**：设计文档 §11 决策 6/7/8 已于 2026-09-21 确认（“12 项全按建议”）。

## 0. 摘要（TL;DR）

- **一句话结论**：<读完这一行就知道要交付什么>
- **交付物清单**：<逐项列出可验收的产出>
- **不做的事（Out of Scope）**：<明确排除，防止范围蔓延>
- **前置依赖**：<必须先完成/先确认的事项；无则写「无」>

## 1. 背景与目标

### 1.1 现象 / 现状（含证据）

| # | 现象 | 证据（命令输出 / SQL / 代码位置 / 截图路径） |
|---|---|---|
| 1 | 一个在做「**下单**」的端点叫「**准备**」 | `storefront/src/app/api/checkout/prepare/route.ts` 头注释**自认**：「做两件事，且**只做**这两件：1. `carts.update`（保存 email / 地址 / 物流 / 账单语义） 2. `carts.submit`（生成 `or_` 订单 + successor cart）」；并明确「**不**创建 `PaymentSession`、**不**启动 `Transaction`」 |
| 2 | 一个在做「**下单**」的函数叫 `prepareOrder()` | `components/checkout/UnifiedCheckout.tsx` 约 L1060；其 JSDoc 写「**第一段 Prepare**：保存填写内容并提交订单」 |
| 3 | 两段语义与顺序强制**已经实现**，并非待建能力 | 同文件 `handlePayNow`：`const prepared = await prepareOrder(); if (!prepared) return;` → 建单失败**永不**进入付款 |
| 4 | 测试已锁定该顺序（改名前即成立） | `components/checkout/__tests__/UnifiedCheckout.test.tsx` 断言 `prepare` 被调用（`cart_id` + `checkout`）且 `start` 携 `order_id: "or_123"` |
| 5 | `prepare` 同时承担「保存表单」与「建单」，边界在**契约上不可见** | 路由响应仅返回 `{ order_id, order, quote }`，调用方无法从名字看出这是「下单」还是「预检」 |

### 1.2 根因

- 根因链：**命名与语义脱节**（非功能缺陷）。`prepare`/`prepareOrder` 的名称暗示「预检/准备」，但实现是「`carts.update` + `carts.submit` → 建正式 Order（`state=pending` + `submitted_at`）」。`storefront/src/app/api/checkout/prepare/route.ts`（端点命名）→ `components/checkout/UnifiedCheckout.tsx#prepareOrder`（函数命名）→ `lib/checkout/server.ts#CheckoutPrepareBody`（类型命名）三处一致地错名，导致：
  1. 新人读代码时会把 `prepare` 当作「预检请求」而**低估其副作用**（它**会建单**）；
  2. 设计讨论中反复出现「要不要加 Place Order」的误解（本次即如此）——“它已经在做这件事，只是名字不叫这个”；
  3. 文档、代码、测试三处的术语无法与本仓设计文档 `docs/design/payment-convergence-stripe-only.md` §3.0 的「Place Order → Payment」对齐。

### 1.3 目标与成功指标

- **目标**：让**端点名 / 函数名 / 类型名**与实际语义（下单）一致，并与设计文档 §3.0 的术语对齐；**零行为变更**。
- **成功指标**（可量化、可复测）：

| 指标 | 现状 | 目标 | 复测方式 |
|---|---|---|---|
| BFF 端点名与语义一致 | `prepare` | `place-order`（`prepare` 仅作转发别名） | `rg -n "checkout/(prepare|place-order)" storefront/src` |
| 前台函数名与语义一致 | `prepareOrder()` | `placeOrder()` | `rg -n "prepareOrder|placeOrder\(" storefront/src` |
| 已提交测试是否仍全绿 | 52 passed | 仍 52+ passed（重命名不改行为） | `npx vitest run …/UnifiedCheckout.test.tsx` |
| 顾客可见交互变化 | — | **0**（硬约束 C-5） | 既有 AC（零跳转 / 一次点击 / 只建一次单）回归 |

### 1.4 非目标（明确不做）

| 不做 | 理由 | 若属后续需求，指向 |
|---|---|---|
| 改**建单/支付**任何行为（含“把 `carts.update` 拆出去”） | 硬约束 **C-5**：本次只改名字与文档，不改控制流 | 若确需拆分，另立 PRD |
| 改 **Store API**（`POST /api/v3/store/carts/:id/submit`） | 它已完整满足需求（行锁 + converted replay 幂等）；本任务**零后端改动** | — |
| **删除** `prepare` 别名 | 需给未升级调用方（含缓存中的旧客户端 bundle）一个过渡期 | §12 Q-1（定删除时点） |
| 改顾客可见文案 / 按钮 / 跳转 | 硬约束 **C-5** | — |
| 顺带做「支付失败以外的分支也给订单入口」 | 属切片 9 的 Q-2 遗留，不在本任务 | 切片 9 PRD §12 Q-2 |

## 2. 用户故事 / 场景

| # | 角色 | 场景 | 期望 | 类型 | 优先级 |
|---|---|---|---|---|---|
| S-1 | 顾客 | 点「确认并支付」（金额未变） | 行为与改名前**完全一致**（一次点击走完建单 + 支付） | 正常 | P0 |
| S-2 | 开发者 | 读 BFF 路由目录 | 看到 `place-order`，一眼知道它**会建单** | 正常 | P0 |
| S-3 | 已缓存的旧前端 bundle | 仍向 `POST /api/checkout/prepare` 发请求 | 仍正常工作（薄别名转发，返回形状不变） | 边界 | P0 |
| S-4 | 开发者 | 搜 `prepareOrder` | 除别名转发层外**零命中** | 边界 | P1 |
| S-5 | 顾客 | 建单失败（缺货 / 无价 / 缺邮箱） | 仍在结账页页内提示、零扣款、**不**进入付款 | 异常 | P0 |
| S-6 | 调用方 | 向 `place-order` 发送形状不合法的 body | 返回 **400 `invalid_request`**（与旧端点同码，不得变成 500） | 异常 | P1 |

> 要求：「类型」列至少各出现一次 **边界** 与 **异常**。

## 3. 功能需求（FR）

| FR | 描述（可验收） | 优先级 | 落点（文件 / 层） |
|---|---|---|---|
| FR-001 | 新增 `POST /api/checkout/place-order`，**行为与旧 `prepare` 逐一等价**（`carts.update` + `carts.submit` → `{ order_id, order, quote }`；切换 `cart_`→`or_` cookie；**不**建 Session/Transaction） | P0 | Storefront · 新增 `app/api/checkout/place-order/route.ts` |
| FR-002 | `POST /api/checkout/prepare` 保留为**薄别名**，转发到同一实现，**响应形状与状态码零变化** | P0 | Storefront · `app/api/checkout/prepare/route.ts` |
| FR-003 | 前台函数 `prepareOrder()` → `placeOrder()`；调用点与注释术语同步 | P0 | Storefront · `components/checkout/UnifiedCheckout.tsx` |
| FR-004 | 类型 `CheckoutPrepareBody` → `CheckoutPlaceOrderBody`，**保留旧名 alias** 以免外部引用断裂 | P1 | Storefront · `lib/checkout/server.ts` |
| FR-005 | 术语统一：把两处 skill / 设计文档里描述该端点的地方改用 `place-order`（写明 `prepare` 为别名） | P1 | 知识资产 · `ai/skills/pallastrade-storefront/SKILL.md`、`ai/skills/pallastrade-checkout/SKILL.md`、设计文档 §3.0.4 | |

## 4. 非功能需求（NFR）

| 维度 | 要求 | 验证方式 |
|---|---|---|
| 性能 | 不得引入额外跳转/双重请求 —— 别名应是**同一处理函数**（不是 HTTP 内部转发） | 代码审查 + 现有「一次点击只发一次 prepare」断言 |
| 安全 | 别名**不得**绕过任何既有守卫（`sameOrigin` 403、`invalid_request` 400）—— 两路径必须共用同一守卫链 | 请求 spec：对两条路径分别发跨源/残缺 body，断言同码 |
| 兼容 | 旧路径在一个过渡期内**完全可用**（响应形状、状态码、cookie 行为一致） | 双路径对比测试（AC-005） |
| 可维护性 | 端点同名双路由时，**实现只允许存在一份**（别名不得复制粘贴） | 代码审查：别名文件不得包含业务逻辑 |
| 可观测性 | 不适用（纯重命名，无新事件 / 无新指标；不新增日志以免噪音） | — |

> 不涉及的维度写「不适用」+ 理由，**不得整行留空**。

## 5. 验收标准（AC，与测试一一映射）

| AC | ← FR | 判定条件（可执行） | 测试落点（文件） | 状态 |
|---|---|---|---|---|
| AC-001 | FR-001 | `place-order` 能成功建单并返回 `{ order_id, order, quote }`（换端点点名后旧断言仍成立） | `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | ☐ |
| AC-002 | FR-001 | 金额未变时**一次点击**走完 place-order → start（保持既有 AC 不回退） | 同上 | ☐ |
| AC-003 | FR-003 | 全仓 `rg -n "prepareOrder" storefront/src` 不再出现在 `UnifiedCheckout`（只剩 alias 转发层或零命中） | 代码审查 + 本 PRD §1.3 复测命令 | ☐ |
| AC-004 | FR-004 | `CheckoutPlaceOrderBody` 可用；旧名 `CheckoutPrepareBody` 仍可导入（alias 保留） | `storefront/src/lib/checkout/__tests__/types.test-d.ts`（若仓内无 type 测试，则以 `tsc --noEmit` 不报错为准） | ☐ |
| AC-005 | FR-002 | 同一 body 分别 POST 到 `prepare` 与 `place-order` → **响应体形状与状态码一致** | `storefront/src/app/api/checkout/place-order/__tests__/route.test.ts`（新增） | ☐ |
| AC-006 | FR-002 | 两条路径的 `sameOrigin` 守卫均生效：跨源请求 → **403 `invalid_checkout_origin`** | 同上 | ☐ |
| AC-007 | FR-002 | 残缺 body → **400 `invalid_request`**（不得变 500） | 同上 | ☐ |
| AC-008 | FR-003 | 建单失败仍**页内提示、零跳转、不进入付款**（回退保护） | `UnifiedCheckout.test.tsx`（既有用例回归，断言不破） | ☐ |

**手工验收**（无法自动化时填写；须写明操作步骤与期望观察结果）：

| # | 步骤 | 期望结果 | 证据形式 |
|---|---|---|---|
| 1 | 启动前台 → `/cart` 加商品 → `/checkout` 填邮箱地址 → 点支付 | 订单创建并可支付；Network 面板显示请求打到 `place-order` | 浏览器截图 / Network 面板截图 |
| 2 | 将前台改为直调旧 `prepare`（临时） | 行为与 `place-order` 一致（别名生效） | Network 对比截图 |

> 不允许用「人工检查一下」充当 AC；每条 AC 必须有测试落点或明确的手工证据形式。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | place_order / prepare / submit | 无 | ❌ 无（不在本任务范围） |
| Core | `pallastrade_gems/pallastrade_core/app/` | build_order / convert! | `services/pallastrade/carts/submit.rb`（**真正的下单实现**） | ✅ 已具备 —— **不改** |
| API | `pallastrade_gems/pallastrade_api/app/` | carts#submit | `v3/store/carts_controller.rb#submit` | ✅ 已具备 —— **不改** |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | — | 无 | ❌ 无（不涉及） |
| Storefront | `storefront/src/` | prepare / prepareOrder / CheckoutPrepareBody | `app/api/checkout/prepare/route.ts`、`components/checkout/UnifiedCheckout.tsx`、`lib/checkout/server.ts`、`components/checkout/__tests__/UnifiedCheckout.test.tsx` | ✅ **已实现** —— 仅缺**正名** |
| Platform | `platform/packages/` | — | 无 | ❌ 无（BFF 为 Next 内部契约，SDK 不需变） |

### 6.1 防重复判定

- **已有能力**：（Core）`Carts::Submit` 是**唯一**下单实现；（Storefront）两段语义与「先建单再付款」的**顺序强制**均已在 `handlePayNow` 中实现并有测试锁定。
- **需要新建**：仅 **命名层** —— 新路由文件 + 别名转发 + 函数/类型改名 + 文档术语。
- **结论**：**不是重复建设** —— 本任务**不新增任何能力**，只把已有能力改成名副其实的名字。**行为等价**是本任务的第一约束（C-5）。

### 6.2 AP-SEARCH 反模式自检

| 反模式 | 本次是否触犯 | 说明 |
|---|---|---|
| AP-SEARCH-1 提前停止（找到第一个就收工） | ✅ 未触犯 | 找到 BFF 路由后仍继续搜到 `Carts::Submit` / `carts#submit` / 测试断言，确认「下单真的已存在」而不是“长得像” |
| AP-SEARCH-2 名称不匹配（改用领域概念再搜一次） | ✅ 未触犯 | 按**领域概念**（建单 / place order / submit / 提交订单）而非只搜 `prepare` —— 否则会漏掉 `Carts::Submit` |
| AP-SEARCH-3 层间假设（每层独立验证，不连推） | ✅ 未触犯 | 未从「core 有 Submit」推定「BFF 也调了它」，而是**实际读完** `prepare/route.ts` 的执行体确认 `carts.update` + `carts.submit` |

## 7. 技术影响

### 7.1 变更面（文件级）

| 文件 | 动作（新增 / 修改 / 删除） | 说明 |
|---|---|---|
| `storefront/src/app/api/checkout/place-order/route.ts` | **新增** | 由 `prepare/route.ts` 内容**搬移**（实现只允许存在一份）；头注释改「第一段：Place Order」 |
| `storefront/src/app/api/checkout/prepare/route.ts` | 修改（改薄） | 保留为**薄别名**：仅转发到同一处理函数，**不得**含业务逻辑 |
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | 修改 | `prepareOrder` → `placeOrder`；注释术语同步；**控制流不变** |
| `storefront/src/lib/checkout/server.ts` | 修改 | `CheckoutPrepareBody` → `CheckoutPlaceOrderBody`（保留旧名 alias） |
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | 修改 | 端点字符串与函数名同步（断言不得弱化） |
| `storefront/src/app/api/checkout/place-order/__tests__/route.test.ts` | **新增** | AC-005 / AC-006 / AC-007（双路径等价 + 守卫） |
| `ai/skills/pallastrade-storefront/SKILL.md`、`ai/skills/pallastrade-checkout/SKILL.md` | 修改 | 术语统一（`place-order` 为主，`prepare` 标注为别名） |
| `docs/design/payment-convergence-stripe-only.md` §3.0.4 | 修改 | 端点表回填实施结果 |

### 7.2 契约影响

| 契约 | 是否变化 | 说明 | 同步动作 |
|---|---|---|---|
| OpenAPI（`store.yaml` / `admin.yaml`） | ❌ **不变** | `/api/checkout/*` 是 **Next.js BFF**，不入 OpenAPI | 需跑 `generated:check` 确认 |
| SDK 类型 | ❌ **不变** | 不新增/修改 SDK 方法 | 无需 |
| 数据库 schema / migration | ❌ **不变** | 零 migration | 无需 |
| 事件 | ❌ **不变** | 硬约束 **C-7**：不新增订单类事件 | 无需 |
| 后台导航 | ❌ **不变** | 不涉及后台 | 仍需跑 `nav_validate` |
| **BFF 内部契约** | ⚠️ **新增一条路径**（旧路径保留） | 属**向后兼容的加法**；两者行为必须逐一等价 | AC-005 锁定 |

### 7.3 依赖与前置

- 仅依赖既有代码；无新依赖、无外部服务、无环境变量、**无后端改动**。
- 跨需求前置：设计文档 §11 决策 6–8 已确认（已完成）。

### 7.4 影响面（`harness affected` 输出）

> 本 PRD 尚未实施；下列为立项时的**基线**输出（工作树含并行会话改动），仅说明工具链可用。**实施完成后必须重跑并回填真实影响面**。

```
$ harness affected --base origin/dev
{
  "filesChanged": 9,
  "affectedComponents": ["backend", "harness"],
  "errors": [],
  "estimatedTests": 36
}
```

> 注：`backend` 与 `harness` 的命中来自**并行会话**的未提交改动，与本 PRD 无关 —— 本 PRD 的改动面**全在 `storefront/`**（§7.1）。

## 8. 测试计划

### 8.1 新增 / 更新测试

| 文件 | 动作 | 覆盖 AC |
|---|---|---|
| `storefront/src/app/api/checkout/place-order/__tests__/route.test.ts` | 新增 | AC-005 / AC-006 / AC-007 |
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | 更新 | AC-001 / AC-002 / AC-008（既有断言不得弱化，只换端点字符串） |

### 8.2 AC ↔ 测试映射

- 标记规则：测试文件内须写 **完整 PRD-ID + AC-x 同一行**（如 `// PRD-20260921-checkout-place-order-… AC-001`）。
- 收尾复核：`harness prd verify --id PRD-20260921-checkout-place-order-正名与显式化-bff-prepare-place-order-前台-prepareorder-p`

### 8.3 验证器（`harness verify <name>`）

| 验证器 | 用途 | 耗时 |
|---|---|---|
| `harness verify storefront-test` | 前台组件与路由测试（AC-001/002/005/006/007/008） | ≤ 15 min |
| `pnpm --filter pallastrade-storefront typecheck` | AC-004（类型 alias 不报错）；**注：仓内已有既有类型错误，本任务需保证不新增** | ≤ 3 min |
| `pallastrade:admin:nav_validate` | 回归（本次不改后台） | ≤ 1 min |

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引
- [ ] 关联设计文档（`docs/design/*.md`）回填

**结论**：
- API 文档 / SDK 类型 / DB schema / 事件 / 后台导航：**已评估，无需更新**（零契约变更，见 §7.2）。
- Skill 文档：**需更新** `ai/skills/pallastrade-storefront/SKILL.md` 与 `ai/skills/pallastrade-checkout/SKILL.md`（术语统一为 `place-order`，`prepare` 标注为**薄别名**）→ 一旦改 skill 则 `harness/scenarios/scenarios.json` 随之**需更新**。
- 本 PRD 状态 + `docs/prd/README.md` 索引：**收尾时更新**（五处同时核对）。
- 关联设计文档：**需回填** `docs/design/payment-convergence-stripe-only.md` §3.0.4（端点表加实施结果）与 §12.1（交付清单勾选）。

## 10. 风险与回滚

| # | 风险 | 概率 | 影响 | 缓解 | 回滚 |
|---|---|---|---|---|---|
| R-1 | **漏改引用**：BFF 路径是字符串字面量（测试 / 组件 / 注释），可能出现「旧断言配新端点」或反之 | 中 | 中 | 全仓 `rg -n "checkout/prepare"` 一次清；AC-005 双路径对比测试兼当兼容网 | 保留别名 → 即使漏改也不会立即断；`git revert` |
| R-2 | **行为漂移**：搬移实现时“顺手改了点什么” | 低 | **高** | 硬约束 **C-5**；实现**只能存在一份**，别名不得携带业务逻辑；既有 52 例测试不回退 | `git revert` 单提交 |
| R-3 | **别名长期残留**成为第二真相源 | 中 | 中 | §12 Q-1 定删除时点；别名文件不得含业务逻辑（NFR 可维护性） | 删别名文件 |
| R-4 | 搬移时**丢失守卫**（`sameOrigin` 403 / `invalid_request` 400） | 低 | **高** | AC-006 / AC-007 直接锁两路径的守卫行为 | `git revert` |
| R-5 | 缓存中的旧 bundle 打旧路径 → 若别名没写对则**回归故障** | 低 | 中 | S-3 场景 + AC-005 覆盖 | 别名已保留，风险极低 |

**回滚方式**：
1. 代码：`git revert <本 PRD 实施提交>`（新增路由 + 别名 + 改名 同一提交回退，无残留）。
2. 数据：**零数据变更**（不改 schema、不写业务数据），无需数据恢复。
3. 紧急处置：若 `place-order` 出问题，可**临时**把前台调用点指回 `prepare`（别名仍在），无需回滚提交。

## 11. 决策记录（ADR 简版）

| # | 决策 | 备选方案 | 选择理由 | 日期 |
|---|---|---|---|---|
| D-1 | **正名**（而非新造流程） | A) 新写一个 place-order 域；B) 只改名 | 两段语义**今天已实现**（`prepareOrder` → `start(order_id)` + 测试锁定）—— 重写只会制造并行实现（§6.1） | 2026-09-21 |
| D-2 | `prepare` 保留为**薄别名** | A) 直接删；B) 保留别名 | 旧路径可能存在于已缓存的客户端 bundle；删了就是硬切。用户已拍板（决策 6） | 2026-09-21 |
| D-3 | 实现**只能存在一份**（别名转发，不复制） | A) 两份；B) 一份 | 两份 = 第二个真相源，必漂移（NFR 可维护性 + R-3） | 2026-09-21 |
| D-4 | **不改控制流**（C-5） | A) 顺手拆分 `carts.update`；B) 纯改名 | 用户拍板「顾客仍是一次点击、按钮文案与交互不变」（决策 7） | 2026-09-21 |
| D-5 | **不新增** `order.placed` 事件（C-7） | A) 新增；B) 不加 | `order.submitted` 已是建单提交后的语义等价事实源 | 2026-09-21 |
| D-6 | Body 类型改名但**保留旧名 alias** | A) 硬改；B) alias | 降低外部引用断裂面（AC-004）；alias 无运行时成本 | 2026-09-21 |

> 与用户拍板相关的决策**必须**记录用户原话或明确指令。

## 12. 开放问题

| # | 问题 | 影响 | 状态（open / resolved） | 结论 |
|---|---|---|---|---|
| Q-1 | `prepare` 别名的**删除时点** | 影响 R-3 与知识资产残留 | **open** | 建议：切片 7（知识同步）后观察一个发版周期，无旧路径流量再删；删除时同步改 skill 与设计文档 |
| Q-2 | 是否把 `lib/checkout/server.ts` 的 `CheckoutView` / 相关导出也一并改名 | 影响改动面 | **resolved** | **不改** —— 与本任务语义无关，保持改动面单一（只改 `CheckoutPrepareBody`） |

> 开工前所有 `open` 必须清零，或转为 §10 的风险项。**Q-1 不阻塞开工**（别名保留是本次决策）。

## 13. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-21 | 1.0 | **实施完成**：5 条 FR 全部落地。新增 `place-order/route.ts`（实现搬移）+ `prepare/route.ts` 改为一行薄别名（`export { POST } from "../place-order/route"`）+ `prepareOrder()`→`placeOrder()`（含状态 `preparedOrder`→`placedOrder`）+ `CheckoutPlaceBody` 改名保留旧名 alias + 术语同步。验证：路由测试 **5 passed**（含别名引用同一性 / 守卫 403 / 400 / 双路径响应相等）、组件回归 **52 passed 零回退**、改名残留实测 **0**、`eval-ai --scenarios` **206/206**。零后端改动 / 零 schema / 零用户可见变化（C-5） | AI |
| 2026-09-21 | 0.1 | 初稿（`harness prd new` 创建骨架 → 按 14 节模板完整扩充：摘要 / 现象+证据 5 条 / 根因 / 非目标 / 场景含边界与异常 / FR 5 条 / NFR 逐维度 / AC 8 条带测试落点 / AP-SEARCH 自检 / 契约影响 / 测试与验证器 / 同步清单 / 风险 R-1..R-5 / 决策 D-1..D-6 / 开放问题 Q-1..Q-2） | AI |
