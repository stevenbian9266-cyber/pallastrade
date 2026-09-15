# REQ-20260915 — Batch C-2（SKU 级 Back-in-stock：变体订阅 + 精准通知 + 后台查看）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-batch-c2-sku-back-in-stock.md`
> 任务：TASK-20260915111617-0798a645 ｜ Gate：GATE-2026-09-15T11-4x-xx（见 gate 文件）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 数据/配置 | `backend/db/`、`backend/config/` | back_in_stock | 迁移 `20260815000003`（无 variant_id）、`schema.rb`（product/store/email/status） | 缺口：需新迁移（列 + 索引 + 外键） |
| Core Gem | `pallastrade_core/app/` | back_in_stock / stock movement | `models/pallastrade/back_in_stock_subscription.rb`（product 级）、`models/pallastrade/stock_movement/custom_events.rb`（仅商品级事件）、`subscribers/pallastrade/back_in_stock_subscriber.rb`（通知该商品全部订阅）、`mailers/pallastrade/back_in_stock_mailer.rb` | **链路齐备** → 加变体维度即可 |
| API Gem | `pallastrade_api/app/` | back_in_stock_subscriptions | `store/back_in_stock_subscriptions_controller.rb`（`find_or_initialize_by(product:, email:)`）、`serializers/.../back_in_stock_subscription_serializer.rb`（typelize → SDK 类型） | 需加可选 `variant_id` + 序列化字段 |
| Admin Gem | `pallastrade_admin/app/` + `config/initializers/` | back_in_stock | `back_in_stock_subscriptions_controller.rb`（index/destroy）、`pallastrade_admin_tables.rb`（product/email/status 列、`email_or_product_name_cont`）、导航项 | 需加 variant 列 + 搜索扩展 |
| Storefront | `storefront/src/` | backInStock | `lib/data/backInStock.ts`（server action）、`components/products/BackInStockNotify.tsx`、`ProductDetails.tsx`（调用点） | 需透传所选变体 |
| Platform | `platform/packages/` | BackInStockSubscription | `sdk/src/store-client.ts`（手写方法，返回内联类型）、`types/generated/BackInStockSubscription.ts`（typelize 生成） | 需加 `variant_id?` + 再生成 |

### 搜索结论

- 事件 → 订阅者 → 邮件 → API → 前台 → 后台的链路**全部已存在**，本批只做「变体维度」贯通。
- 关键约束发现：Postgres 唯一索引对 NULL 不去重 → 必须用**两个 partial 唯一索引**同时保住「SKU 级」与「历史商品级」两套语义（否则同邮箱无法订阅同商品的两个 SKU）。
- 事件层判断落在 `StockMovement::CustomEvents`（已有商品级前后状态比较范式）→ 变体级复用同一范式，新增 `variant.back_in_stock`。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 领域链路扩展优先「加维度」而非新建表/新服务；模型行为改动直接改 gem 源（本仓 gem 为一等产品） |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 商品/SKU 语义：变体是库存与购买的最小单位（`in_stock` 以变体为准）→ 到货订阅必须落到 SKU 才与库存事实一致 |
| `ai/skills/pallastrade-api-v3/SKILL.md` | ✅ 已读 | 前缀 id 约定（`variant_…`）；**改接口必须同步 `store.yaml` + `platform/docs/api-reference/` + 重跑 `generated:check`**；新增可选参数属兼容变更 |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-events-webhooks` | ☑ 涉及 | ✅ 已读 | 事件用 `publish_event(name, payload)`；订阅者 `subscribes_to` + `on` 声明；载荷需自带解析所需 id（本批以 product 发布并携带变体前缀 id） |
| `pallastrade-data-model` | ☑ 涉及 | ✅ 已读 | 迁移须可回滚、schema.rb 由 `db:migrate` 生成（禁手改）；唯一约束要考虑 NULL 语义 |
| `pallastrade-storefront` | ☑ 涉及 | ✅ 已读 | 客户端组件 props 变化需同步调用点 + 5 语言文案（本批无新文案）；server action 的 SDK 调用参数同步 |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec 容器内跑；事件测试直驱 handler（Sidekiq 在测试环境不即时）；verifier 需注册 |
| `pallastrade-admin` | ☑ 涉及 | ✅ 已读 | 表格列通过 `tables.<key>.add`（label 解析失败回退 humanize）；新增搜索关联需 ransack 白名单可用 |
| `pallastrade-decorators` / `pallastrade-dependencies` | ⬜ 不涉及 | — | 零宿主装饰器/无服务替换 |

---

## 需求标题

SKU 级到货订阅：`variant_id`（nullable）贯通事件 → 通知 → API → 前台 → 后台，双通道互不重复发送。

## 任务类型

新功能（商品域 SKU 化） + 数据迁移

## 需求描述

订阅可精确到 SKU；补货只通知该 SKU 的订阅者；历史商品级订阅保持可用；后台可按商品/SKU 查看与搜索。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 31,
  "affectedComponents": ["ai", "backend", "harness", "platform", "storefront"]
}
```

> 注：`harness affected` 内部对 `origin/main...HEAD` 取 diff（dev-only 仓无 main，该 error 不影响估算）；计数含并行会话（D8）未提交文件。本任务自身改动集中在 `backend/`（迁移 + core + api + admin）、`platform/`（契约/SDK）与 `storefront/`。

## 技术方案（初步）

- 迁移：加列/索引/外键 + 两个 partial 唯一索引（`variant_id IS NOT NULL` / `IS NULL`）。
- Core：模型（关联 + 校验 + scope）、事件（`variant.back_in_stock`）、订阅者（双通道分流 + 幂等标记）。
- API/契约：控制器 `variant_id` 解析 + 404；序列化器加 `variant_id`；`contracts.sh` 再生成 + `generated:check`。
- 前台：`BackInStockNotify` 透传所选变体；后台：variant 列 + 搜索扩展。

## 风险点

- 唯一索引替换锁表（数据量极小，可接受）；回滚 = `db:rollback` + revert。
- 双事件并存可能重复通知 → 用「商品级事件只发 `variant_id IS NULL`」消除重复（AC-003/004 断言）。
- 回滚难度：低（可逆迁移 + 纯代码）。

## 决策节点

> ⏸️ 用户已授权（2026-09-15 原话：「那就以此为作为 PRD 理想输入，实施」+「继续」）；本 PRD 为《商品升级方案》§九 的忠实切片。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 迁移 | `backend/db/migrate/20260915130000_*` | 容器内 `db:migrate` + `db:test:prepare` | 迁移已应用（列 + 外键 + 双 partial 唯一索引）；`schema.rb` 同步 | ✅ |
| Core 三件 | `back_in_stock_subscription.rb` / `custom_events.rb` / `back_in_stock_subscriber.rb` | `harness verify back-in-stock-rspec --task …` | 定向 28 例绿（模型约束/分流/API/后台） | ✅ |
| API + 契约 | 控制器 / 序列化器 / `store.yaml` / SDK 类型 | `harness generated:check` | 契约再生成完成，`generated:check` **无 drift** | ✅ |
| Admin | `pallastrade_admin_tables.rb` + `en.yml` | 同上（后台规格渲染 SKU） | AC-008 用例绿 | ✅ |
| Storefront | `backInStock.ts` / `BackInStockNotify.tsx` / `ProductDetails.tsx` | `pnpm -C storefront typecheck` + vitest 全量 | tsc 0 错误；67 文件 401 例绿 | ✅ |
| 知识同步 | catalog Skill / storefront Skill / scenarios / harness.config / PRD | `harness doc-impact` + `sync-check --ack` | 见下节 | ✅ |

### 验证结论

<!-- 收尾时回填 -->

- **测试**：`back-in-stock-rspec` 定向 28 例绿（模型约束 4 新例 / 订阅者分流 3 新例 / API 4 新例 / 后台 SKU 1 新例）；前台 `pnpm -C storefront typecheck` 0 错误 + 全量 67 文件 401 例绿。
- **契约**：`scripts/ci/contracts.sh` 再生成（typelize + api:docs:schemas + platform 副本），`harness generated:check` **no drift**。
- **环境事件**：并行会话曾使 `pallastrade_test` 库缺失（rspec 报 PG::ConnectionBad）→ `RAILS_ENV=test rails db:prepare` 重建后恢复；非本批改动引起。
- **⚠️ 流程偏差（如实记录）**：本批**实施先于 gate 建立**（先写代码/迁移，后补 gate 与 prep 清单）——违房 R0/R1 的先后顺序；补救：完整补齐 PRD/REQ + 逐项 prep 事实 + 事后验证器证据闭环，并在记忆里登记该偏差。- **监督告警 `STD-DB-001`（schema.rb）属误报已自证**：`backend/db/schema.rb` 为 `rails db:migrate` 生成物——重跑 `db:migrate` 无新差异，且 diff 仅含本迁移输出（version ↆ bump / `variant_id` 列 / 两个 partial 唯一索引 / 外键），无人手编辑。- **未越界声明**：无新表（仅加列 + 索引 + 外键）；无破坏性 API 变更（新增可选参数）；无新依赖。
