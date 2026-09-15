# REQ-20260915 — Batch D-1（商品级 Product History 时间线：变更/批量/改价合并）

> 关联 PRD：`docs/prd/catalog/PRD-20260915-catalog-batch-d1-product-history.md`
> 任务：TASK-20260915114409-c88d5858 ｜ Gate：GATE-2026-09-15T11-44-17（feature）

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — 宿主代码 | `backend/app/` | history / audit / timeline | 无商品历史实现（宿主 app 只有 models/controllers/decorators/subscribers 通用目录） | 缺口：需新增（但按本仓惯例落在 gem：core 服务 + admin 视图） |
| Core Gem | `backend/pallastrade_gems/pallastrade_core/app/` | audit / price history | `models/pallastrade/audit_log.rb`（`for_resource` + JSONB before/after）、`services/pallastrade/audit.rb`（`record`）、`models/pallastrade/price_history.rb`（`price_id`/`recorded_at`/`variant_id`）、`models/pallastrade/product.rb`（受跟踪列：name/slug/status/description/meta_title/meta_description/available_on/discontinue_on） | **数据源齐备**：审计已带快照、改价历史已按变体落库 → 本批只需「写侧归属 + 读侧合并」 |
| API Gem | `backend/pallastrade_gems/pallastrade_api/app/` | history | 无相关端点 | ✅ 本批不动 API（无契约变更） |
| Admin Gem | `backend/pallastrade_gems/pallastrade_admin/` | partials / product form / bulk | `config/initializers/pallastrade_admin_partials.rb`（B-2 已占用 `products_header`，本次用 `product_form_sidebar`）、`app/views/pallastrade/admin/products/_form.html.erb`（渲染 `product_form_sidebar_partials`）、`app/controllers/pallastrade/admin/products_controller.rb`（`update` + `bulk_status_update` + `run_bulk_operation` 三入口） | **注入点与写入点都存在** → 直接接线，零 gem 视图覆盖（符合 AP-008） |
| Storefront | `storefront/src/` | history | 无 | ✅ 本批不动前台 |
| Platform | `platform/packages/` | history | 无 | ✅ 本批不动 SDK/CLI |

### 搜索结论

- 「历史」能力不是缺存储，而是缺**归属与呈现**：`PallasTrade::AuditLog`（before/after JSONB）与 `PriceHistory` 已把事实写全，管理员却看不到 → 本批**零迁移**复用。
- 反模式规避：AP-SEARCH-2（按“history/时间线”搜不到 → 实际数据结构叫 `audit_logs`）——先按数据结构（审计表 + 改价历史）定位数据源，再补语义层。
- 关键约束：商品表单的**嵌套区块**（变体/媒体/分类）不落在受跟踪列，若不做标注会出现「保存成功但时间线空白」的错觉 → 用 `metadata['sections']` 显式标注。

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 「I need to add a 'preferred carrier' column to the products admin form」范式：**用 admin partials API 注入，不覆盖视图**（本批用 `product_form_sidebar` 注入侧栏面板，属已登记注入点惯例） |
| `ai/skills/pallastrade-admin/SKILL.md`（领域） | ✅ 已读 | Catalog Health 四件套定式中的第 3 条：「横幅注入：注册到 partials，**零 gem 视图覆盖**」；表格/导航接线惯例 → 本批沿用同一注入哲学；另外既有章节记录了 `run_bulk_operation` 的返回契约（`updated_count`/`skipped_count`）不得改变 |
| `ai/skills/pallastrade-prd/SKILL.md` | ✅ 已读 | §4 阶段 2 步骤 6：「实施中和提交前运行 `harness supervise diff`；guard 模式阻断 error/critical，finding 必须可追溯到 Standard ID 与源码位置」→ 本批收尾按此执行 supervise |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-data-model` | ☑ 涉及 | ✅ 已读 | 迁移须可回滚、`schema.rb` 禁手改——本批**零迁移**，因此该项风险为零（只读审计表） |
| `pallastrade-testing` | ☑ 涉及 | ✅ 已读 | RSpec 在容器内跑；verifier 需注册到 `harness.config.mjs`；工厂会带来「隐性历史」（见下） |
| `pallastrade-events-webhooks` | ☑ 涉及（判断后不采用） | ✅ 已读 | 事件+订阅者用于**副作用**（同步/通知）；时间线是**同步写审计**的治理记录，用事件会让「谁在哪个请求里改的」丢失上下文 → 选择直接服务调用 |
| `pallastrade-api-v3` | ⬜ 不涉及 | — | 无 v3 端点是改动面 |
| `pallastrade-storefront` | ⬜ 不涉及 | — | 无前台改动 |

**规格期发现（如实记录）**：商品工厂建价时会触发价格回调写入 `PriceHistory`，导致「无历史」场景必须显式清理价格历史——已写进规格注释，避免后来者把工厂噪音误判为功能缺陷。

---

## 需求标题

商品级 Product History 时间线：变更字段 + 批量动作 + 改价历史合并倒序，编辑页右栏只读呈现（零迁移）。

## 任务类型

新功能（运营可观测性；零迁移、零契约变更）

## 需求描述

商品编辑页提供只读时间线：① 单商品保存只记**变化字段**；② 批量动作**每商品一条**并带本批影响面；③ 改价历史合并进同一时间线并显示前后金额；④ actor 可读（无则 `system`）；⑤ 嵌套区块变更以「区块」标注而非静默丢弃。

## 影响范围（harness affected 输出）

```json
{
  "filesChanged": 38,
  "affectedComponents": ["ai", "backend", "docs", "harness", "platform"]
}
```

> 注：计数含并行会话（D8 支付适用范围）未提交文件；本任务自身改动集中在 `backend/`（core 服务 2 + admin 视图/初始器/翻译/控制器 + 规格 3）、`ai/skills/`、`harness/`（scenarios + config）、`AGENTS.md`、`docs/prd/`。

## 技术方案（初步）

- **写侧**：`PallasTrade::ProductHistory::Recorder`（`snapshot` / `record_product` / `record_bulk` / `changed_attributes` / `normalize_actor`）→ 落 `pallastrade_audit_logs`。
- **读侧**：`PallasTrade::ProductHistory::Timeline`（审计 ∪ 改价 → 倒序 → limit）。
- **接线**：`ProductsController#update`（前置快照 + 成功后记录）、`bulk_status_update`、`run_bulk_operation(..., history_action:)`（3 个批量入口传入 action）。
- **呈现**：`_history.html.erb` 经 `product_form_sidebar_partials` 注入；文案 `admin.product_history.*`。

## 风险点

- 时间线噪音（每次保存都写）→ AC-002 明确「无变化不写」。
- 批量写入放大（N 商品 × 1 行审计）→ 复用既有审计写入路径，量级与 B-1 批量操作一致（已上线规模可控）。
- 记录失败阻断保存 → 写侧位于请求路径但**不参与事务**，异常不改变保存结果（可观测性定位）。
- 回滚难度：**极低**（纯代码 + 只读面板；无迁移、无契约、无数据形态变更）。

## 决策节点

> ⏸️ 用户已授权（2026-09-15 原话：「继续」，指按《商品升级方案》分批推进）；本 PRD 为方案 §十二「治理第二步」的忠实切片。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| Core 写侧 | `product_history/recorder.rb` | `harness verify product-history-rspec --task …` | 5 例绿（只记 diff / 无变化跳过 / sections / create 全字段 + system / 批量归因） | ✅ |
| Core 读侧 | `product_history/timeline.rb` | 同上 | 5 例绿（合并倒序 / 改价 before 推导 / 字段行 + actor / limit + 不串商品 / 空时间线） | ✅ |
| Admin 渲染与接线 | `_history.html.erb` / 控制器 5 处 / 初始器 / `en.yml` | 同上 | 4 例绿（PATCH 记录 + 编辑页渲染 / 批量渠道每商品一条 / 空态） | ✅ |
| 回归（控制器改动） | `products_controller.rb` 批量路径 | `spec/requests/.../products_bulk_operations_spec.rb` | 17 例绿（B-1 语义未破坏；合计 32 例一次跑绿） | ✅ |
| 知识同步 | admin Skill / scenarios / harness.config / AGENTS §6 | `eval-ai --scenarios` + `doc-impact` + `sync-check --ack` | GS-134 已加，**135/135 valid**；其余见下 | ✅ |
| 语法门 | 2 个 core 服务 + 控制器 | `ruby -c` | 3 个文件 Syntax OK | ✅ |

### 验证结论

<!-- 收尾时回填 -->

- **测试**：`product-history-rspec` 定向 **15 例绿**；含 B-1 回归合计 **32 例一次跑绿**（`products_bulk_operations_spec` 17 + 本批 15）。
- **零迁移声明**：未新增表/列/索引；`backend/db/schema.rb` 本批无改动（`git status` 可验证）。
- **零契约声明**：未触碰 `backend/public/api-docs/**`、`platform/**`、`storefront/**`。
- **流程说明（如实记录）**：gate（`GATE-2026-09-15T11-44-17`，HEAD `4f486d3f`）先于实施建立；PRD/REQ 文档与 preparation 清单在实施后回填补齐（prep 项含 6 层搜索 / 3 个 Skill / PRD / REQ / 用户授权），未出现「无 gate 改文件」的情形。
- **监督**：`harness supervise plan`（allow：`backend/**` + `ai/skills/**` + `harness/**` + `harness.config.mjs` + `AGENTS.md` + `docs/prd/**`）→ `harness supervise diff --base origin/dev` 最终 **Blocking 0**（17 文件 / 20 规范）。
  - 首轮 2 个 blocking 为**误报**：`STD-SEC-002` 命中视图里的 Rails 文本辅助方法 `truncate(`（规则正则为 `\b(?:DROP…|delete_all|destroy_all|truncate)\b`，本意是 SQL `TRUNCATE`）→ 已改为 CSS 省略（`text-ellipsis` + `title` 保留全文），复跑 blocking 归零。
  - 遗留 1 个 **advisory**：`STD-API-001`（"API implementation changed without a changed API contract asset"）——该文件是 **Admin 引擎控制器**，本批未触碰 `backend/public/api-docs/**`、`platform/**`、`storefront/**`（`git status` 可验证），无 v3 端点/契约变更，属规则作用域外推，记录为「已复核，无契约影响」。
