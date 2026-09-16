# REQ-20260916-d3-product-merge

| 项 | 值 |
|---|---|
| 关联 PRD | `docs/prd/catalog/PRD-20260916-catalog-d3-product-merge.md`（approved） |
| 任务类型 | 新功能（feature gate，含用户追加的撤销能力） |
| Harness Task | `TASK-20260916075301-c137a044`（risk: quick，工具判定） |
| Gate | `GATE-2026-09-16T07-53-12` |
| 分支 | `dev @ 87aad365` |

## Step 0：跨层搜索（强制执行）

| 层 | 搜索路径 | 关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App | `backend/app/` | `merge_product` / `product_merge` / `consolidat` | 无 | ❌ |
| Core — 模型 | `pallastrade_core/app/models/` | `merge` / `def merge` | `order_merger.rb`（**订单**合并，异域）；`product.rb` 的 `variants/reviews/media/classifications/promotions` 关联齐备 + `acts_as_paranoid` | ❌ 需新建服务 |
| Core — 服务 | `pallastrade_core/app/services/` | `merge` / `DuplicateCandidates` | `products/duplicate_candidates.rb`（D-2 检测，注释明确「合并属 D-3」） | ❌ |
| API | `pallastrade_api/app/` | `merge` / `consolidat` | 仅 `Hash#merge`（如 `reviews_controller` 的 `serializer_params.merge`） | ❌ 无端点（本批零 API 变更） |
| Admin | `pallastrade_admin/app/` | `merge` / `duplicate_products` | `duplicate_products_controller.rb`（检测工作台 = 本批入口落点） | ⚠️ 有入口无动作 |
| Storefront | `storefront/src/` | `merge` | 仅 `tailwind-merge` | ❌ |
| Platform | `platform/packages/**/src` | `merge` | 仅通用 JSON merge 注释 | ❌ |
| 可复用能力 | `Redirect` / `Product` | — | `PallasTrade::Redirect`（store 作用域 + `from_path` 唯一 + `active`）= 301 通道；`acts_as_paranoid` = 软删通道 | ✅ 复用，零新中间件 |

**结论**：合并能力 6 层零命中 → 新建 **1 张台账表 + 3 个服务（preview / merge / undo_merge）+ 1 个后台动作 + 1 个确认页**；
零公开契约变更（不新增 API 端点、不动 store.yaml）。

## Step 1：Skill 文件咨询（强制执行）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树「Settings → Configuration → Events → Dependencies → Admin/Ransack APIs → **Generators (resource or model)** → Decorators → Extensions」；AGENTS §1 明确 `pallastrade_gems/` 是团队产品、可直接改 gem（升级=merge）→ 采用「gem 内新增服务 + 迁移」 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | 「表格：`pallastrade_admin_tables.rb` 里 `tables.register(:<key>, …)` + 逐列 `.add`；视图只写 `render_table`」→ 合并入口挂在既有 Duplicate Detection 控制器/视图上（`duplicate_products_controller.rb`），不新建列表页 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | line 280-285：「商品层**没有任何防重约束**……后台 `Products → Duplicate Products` 按三类信号给候选分组（**只读，合并仍属 D-3**）」→ 本批正是该章的收尾；D-2 信号口径**冻结不改** |

**按需 Skill（本次涉及）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-data-model` | ✅ | ✅ 已读 | ① 新表必须选**全局唯一前缀**（`prefixed_id_spec.rb` 守护）→ 本批用 `pmg`；② **partial unique** 是既有惯例（`pallastrade_stock_reservations` 的 `WHERE state='reserved'`）→ 台账用 `WHERE undone_at IS NULL` 表达「同一 absorbed 只有一条未撤销合并」；③ 新迁移只增表/列，禁止改历史迁移 |
| `pallastrade-security` | ✅ | ✅ 已读 | 跨店隔离是硬边界（一切经 `current_store`）；**不可逆动作必须有权限门 + 审计**；错误语义不混用（403 权限 / 404 不可见 / 422 业务冲突） |
| `pallastrade-testing` | ✅ | ✅ 已读 | 栈为 **RSpec + Factory Bot**；新增用例必须进注册验证器（`harness.config.mjs`）→ 注册 `d3-product-merge-rspec` |
| `pallastrade-events-webhooks` | ✅ | ✅ 已读 | 合并**不发领域事件**（无外部同步语义）；避免为审计单独引入订阅者（Audit 直接写） |
| `pallastrade-api-v3` | ✅ | ✅ 已读 | 本批**零 API 变更** → 无需改 `store.yaml`/SDK；确认 `generated:check` 应保持无漂移 |

## 需求标题

**D-3 商品合并（切片 1）**：把重复商品合并进主商品 —— 预检影响面（零写入）、单事务迁移可迁移引用、
旧 URL 301、被合并商品软删留痕、**台账 + 一键撤销**，且**历史交易零改写**。

## 范围

**做**：`pallastrade_product_merges` 台账表；`Products::MergePreview` / `Products::Merge` / `Products::UndoMerge`
三个服务；后台 Duplicate Detection 组内「合并到…」+ 确认页（预检结果）+ 执行报告 + 撤销入口；审计（`product_merged` / `product_merge_undone`）。

**不做**：批量合并、跨店合并、改写历史交易与快照、合并库存数量、自动选择 survivor、改 D-2 信号口径。

## 关键不变量（AC 守护）

| 不变量 | 断言方式 |
|---|---|
| 历史交易零改写 | `line_items`/`orders`/`payments`/`commerce_transactions` 合并前后**全表校验和相等**（合并与撤销各一遍） |
| 迁移守恒 | 迁移数 + 跳过数 = 原数 |
| 冲突不静默 | `sku_conflict` / `review_conflict` 列入报告且对象仍属原商品 |
| 预检零写入 | 预检前后全表校验和相等 |
| 撤销逐项还原 | 台账 `moved` 清单逐条断言归属回到 absorbed |
| 撤销前置校验 | 阻塞项存在 → 拒绝且零写入（不做部分撤销） |
| 幂等 | 重复合并 → `already_merged`；重复撤销 → `already_undone` |

## 实施计划（文件级）

1. `backend/db/migrate/20260916230000_create_pallastrade_product_merges.rb`（新表 + partial unique + 索引；`reviews` 无变更）
2. `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/product_merge.rb`（`has_prefix_id :pmg`；`moved` jsonb；`undone_at`）
3. `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/products/merge_preview.rb`
4. `.../products/merge.rb`（单事务迁移 + redirect upsert + 软删 + 台账 + 审计）
5. `.../products/undo_merge.rb`（按台账反迁移 + 恢复 + redirect 停用 + 标记 undone + 审计）
6. `pallastrade_admin`：`duplicate_products_controller` 新增 `merge_preview` / `merge` / `undo_merge`（`data: { turbo_method: }` 约定）+ 确认页视图 + locale
7. specs：`merge_preview_spec.rb` / `merge_spec.rb` / `undo_merge_spec.rb` / admin request spec
8. 知识同步：catalog / admin / data-model Skill + GS-153 + AGENTS §6 + verifier 注册 + PRD done
