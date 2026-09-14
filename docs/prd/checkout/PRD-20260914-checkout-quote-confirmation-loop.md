# PRD-20260914-checkout-quote-confirmation-loop

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-14 |
| 来源 | 用户指令「同时做1和2」→ ② PRD-3（research `RESEARCH-20260913` §9.1 P0-d / §11 PRD-3 行，用户确认项：无） |
| 分类 | checkout |
| 关联 Skill | pallastrade-storefront / pallastrade-api-v3 |
| 关联 REQ | REQ-20260914-checkout-quote-confirmation-loop.md |
| 关联 PRD | 取代 `PRD-20260913-checkout-txn-error-routing` 中 `quote_changed`/`checkout_version_conflict` 的 `or_` 跳转分支（其余分支不变） |
| 需求类型 | 优化迭代（闭环既有后端机制） |

> 用户确认依据：「同时做1和2」（2026-09-14）—— 2 即本 PRD。

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **缺口（research §9.1 第 2 条已核实）**：后端已具备报价确认机制 —— `Transactions::Start`（quote 过期自动 Refresh；商业事实变化 → `quote_changed` 带 `order_id`）与 `PaymentSessions::Start#ensure_fresh_quote`（`expected_version` ↔ `order.checkout_version`、`expected_price_version` ↔ `order.price_version`，不匹配 → `checkout_version_conflict` **并返回 compact 最新 quote**）。但 **storefront 从未发送 `expected_*`**（BFF `transactions.create` 只传 `payment_method_id`/`external_data`）→ 闭环未合上。
- **现行为（PRD-1 已上线）**：`quote_changed` / `checkout_version_conflict` → 跳 `or_?notice=quote_changed` 横幅重新确认。用户看不到"到底变了什么"，且多一次跳转。
- **目标**：把 `cart_` 页的报价确认做成**页内闭环** —— Pay Now 携带客户端所见版本；冲突时在页内展示逐步差异（Shipping / Promotion / Amount due 旧→新）并要求重新点击；**绝不自动扣款**。
- **成功指标**：① Pay Now 载荷含 `expected_checkout_version`/`expected_price_version`（有快照时）；② 冲突时 **零跳转**、页内出现差异块、`fetch` 不重试；③ 五语言键齐备；④ 其他错误码分流行为零回归。

## 2. 用户故事 / 场景

- 作为**顾客**，我希望报价变化时当场看到“什么变了、变成多少”，再决定是否继续付款。
- 作为**运营**，我希望系统绝不因为报价变化而自动扣款。
- 场景：① 首次点击（无快照）→ 正常建单并进入支付；② 有快照且未漂移 → 正常；③ 快照已过期（促销到期/地址/Locale 变化）→ 409 → **页内差异块** + 再次点击（带新版本）成功；④ 服务端未返回 quote（降级）→ 页内通用提示“报价已更新，请重试”，不崩溃、不自动重试；⑤ 无 `order_id` 的错误 → 保持既有 toast 行为。

## 3. 功能需求（FR）

- **FR-001**：BFF `/api/checkout/start` 接受可选 `expected_checkout_version`（number）/ `expected_price_version`（string），并透传给 `orders.transactions.create`（SDK 类型已具备）。
- **FR-002**：BFF 成功响应新增 `quote`（`checkout_version`、`price_version` + Shipping / Promotion / Amount due 的 raw + `display_*`），供前端存快照（Money 契约：raw 判逻辑 / display 渲染）。
- **FR-003**：当 `transactions.create` 抛 `quote_changed` / `checkout_version_conflict` 时，BFF 在错误响应附带**当前** `quote`（读取 `orders.checkout.get(orderId)`；读取失败则省略该字段，不得因此改变错误码）。
- **FR-004**：UI 以 cart id 为键将 `quote` 存于 `sessionStorage`（解析失败/无快照即忽略，不阻断支付）；Pay Now 时携带快照中的 `expected_*`。
- **FR-005**：`quote_changed` / `checkout_version_conflict` → **不跳转**（不再 `router.replace('/checkout/or_...')`）：在页内渲染 `checkout-quote-diff`（行：Shipping / Promotion / Amount due，旧→新）+ 标题/正文/CTA 文案；并用服务端返回的最新 quote 覆盖快照。
- **FR-006**：降级路径 —— 无快照差异可比或服务端未回传 quote 时，仍为页内提示 + 要求重新点击（不自动重试、不自动扣款）。
- **FR-007**：i18n —— 五语言（de/en/es/fr/pl）新增 `checkout.quoteChangedTitle` / `quoteChangedBody` / `quoteConfirmAgain` / `quoteRowShipping` / `quoteRowPromotion` / `quoteRowAmountDue`（名称以实施为准，均需守护测试）。
- **FR-008**：知识同步 —— `pallastrade-storefront` Skill 的 Checkout 错误分流段改为“页内报价确认”（取代 `or_` 跳转描述）；`harness/scenarios/scenarios.json` 的 GS-111 对应 mustDo/mustNotDo 同步修改（**必须**：避免 Skill 与代码不一致）。
- **FR-009**（范围外）：`or_` 页自身的 `?notice=quote_changed` 横幅保留（其他入口进入时的兜底）；后端服务与 API 契约不改（仅消费既有能力）。

## 4. 非功能需求（NFR）

- **红线**：任何路径**不得自动扣款、不得自动重试支付**（冲突后必须由用户再次点击）。
- **降级安全**：快照缺失/损坏、quote 缺失 → 宁可少一层校验，也不能阻断支付或报错崩溃。
- **存储**：仅 `sessionStorage`（无 PII、无跨会话残留）；键含 cart id，购物车切换即失效。
- **Money 契约**：差异判断用 raw 字段；展示一律 `display_*`（不得 `parseFloat(display_*)`）。
- **可测试**：分支均由 Vitest 覆盖（不依赖真网络）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-004：有快照时 Pay Now 载荷含 `expected_checkout_version`/`expected_price_version`（Vitest）。
- **AC-002** ← FR-001：无快照时载荷不含 `expected_*` 且不报错（Vitest）。
- **AC-003** ← FR-005：模拟 409 `quote_changed` → 页内出现 `checkout-quote-diff`，且 `router.replace` **未被调用**（Vitest）。
- **AC-004** ← FR-005：差异块展示 Shipping / Promotion / Amount due 三行旧→新（Vitest）。
- **AC-005** ← FR-006：409 但无 quote → 页内提示且 `fetch` 不再被调用（不自动重试，Vitest）。
- **AC-006** ← FR-003：BFF 错误响应含 `quote`（路由层单测/集成断言）。
- **AC-007** ← FR-007：五语言键齐备（i18n 守护测试扩展）。
- **AC-008** ← 回归：库存/恢复/不可支付/未就绪/未知码分支行为不变（既有用例全绿）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | quote / expected | 无宿主层实现 | — |
| Core | `pallastrade_core/app/` | expected_* / quote_changed | `transactions/start.rb`（L32/L73/L109-119：`expected_price_version`、`quote_changed_error`）、`payment_sessions/start.rb`（L90-146：`ensure_fresh_quote` → `checkout_version_conflict` + 返回 compact 最新 quote） | 是（后端能力已具备，本次仅消费） |
| API | `pallastrade_api/app/` | 错误信封 | `error_handler.rb`（错误码汇集）；无契约变更 | 否 |
| Admin | `pallastrade_admin/app/` | — | 无 | — |
| Storefront | `storefront/src/` | expected_* / quote_changed | `app/api/checkout/start/route.ts`（POST：carts.update→submit→transactions.create，**未传 expected_***，L128-186）、`components/checkout/UnifiedCheckout.tsx`（handlePayNow：`quote_changed`/`checkout_version_conflict` → `router.replace(or_?notice=...)`，L655-670）、`messages/*.json` ×5 | **本次改动点** |
| Platform | `platform/packages/sdk/` | expected_* | `src/types/index.ts` L93-94（`expected_checkout_version?: number` / `expected_price_version?: string` 已存在） | 是（类型已就绪，无需改） |

**结论**：后端与 SDK 已就绪，缺口在 storefront BFF + UI；无重复实现。

## 7. 技术影响

- **修改**：`storefront/src/app/api/checkout/start/route.ts`（接受/透传 `expected_*`；成功与冲突响应附 `quote`）、`storefront/src/components/checkout/UnifiedCheckout.tsx`（快照存取 + 载荷 + 页内差异块 + 分支改写）、`storefront/messages/{de,en,es,fr,pl}.json`
- **知识**：`ai/skills/pallastrade-storefront/SKILL.md`（Checkout 错误分流段改写）、`harness/scenarios/scenarios.json`（GS-111 同步）
- **测试**：`storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx`、`storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（+ 必要时新增 BFF 断言）
- **数据库 / 后端 / API 契约 / SDK**：**不变**

## 8. 测试计划

- **更新**：`UnifiedCheckout.test.tsx`（AC-001/002/003/004/005/008）、`checkout-i18n-keys.test.ts`（AC-007）
- **新增（如既有测试无法覆盖 BFF 响应形状）**：`storefront/src/app/api/checkout/__tests__/` 下的路由断言（AC-006）
- **验证器**：`chk-p1-4b-storefront` / `chk-p1-4c-storefront` / `storefront-test`；另跑 `pnpm check`（biome）+ `pnpm typecheck`（CI 红线教训）
- **AC 映射**：见 §5 逐条标注（测试文件内以 `PRD-20260914-checkout-quote-confirmation-loop AC-xxx` 注释关联）

## 9. 文档同步清单（知识同步门）

## 9. 文档同步清单（知识同步门）

| 知识资产 | 结论 |
|---|---|
| API 文档 / SDK | ✅ 不适用（BFF 内部接口；SDK 类型已具备） |
| `pallastrade-storefront` Skill | ⏳ 待更新（Checkout 错误分流段：`or_` 跳转 → 页内报价确认） |
| `harness/scenarios/scenarios.json` | ✅ 已更新（GS-111 mustDo 改为页内确认 + 携带 expected 快照） |
| FR-008 知识同步的验收 | 由 `sync-check --ack` + 本次 PRD/索引回填证据覆盖（不单列为 AC） |
| `pallastrade-prd` Skill / `AGENTS.md` / `copilot-instructions.md` | ⏳ 评估（预计无需更新） |
| 本 PRD 状态 + `docs/prd/README.md` 索引 | ⏳ 完成时回填 |
| `harness sync-check --ack` | ⏳ 完成时执行 |

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-14 | 0.1 | 初稿：侦察确认后端/SDK 已就绪，缺口在 BFF+UI；定下页内确认取代 `or_` 跳转；待实施 | AI |
| 2026-09-14 | 1.0 | 实施完成：新增 `lib/checkout-quote.ts`（快照/差异，sessionStorage）；BFF 透传 `expected_*` 并在成功/冲突响应回传 `quote`；`UnifiedCheckout` 页内 `checkout-quote-diff`（零跳转、零自动重试）；五语言 ×6 键；Skill + GS-111 同步。测试：定向 33 例全绿（含取代旧 or_ 断言）、biome 0 error、typecheck exit 0。偏差说明：AC-006（BFF 回传 quote）由客户端契约用例（模拟信封）+ BFF 代码审阅覆盖，未单独新建路由测试。 | AI |
