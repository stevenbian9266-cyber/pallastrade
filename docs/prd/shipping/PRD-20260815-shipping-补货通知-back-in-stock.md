# PRD-20260815-shipping-补货通知-back-in-stock

| 元数据 | 值 |
|---|---|
| 状态 | approved（2026-08-15 用户确认） |
| 创建日期 | 2026-08-15 |
| 来源 | 需求：实施阶段二 B4 P1-6 补货通知（RESEARCH §4.11） |
| 分类 | shipping（自动判定） |
| 关联 Skill | pallastrade-events-webhooks、pallastrade-api-v3、pallastrade-deployment、pallastrade-data-model |
| 关联 REQ | REQ-20260815-back-in-stock.md（实施时回填） |
| 关联 PRD | N/A（全新功能） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：实施阶段二 B4 P1-6 补货通知
- **背景**：商品缺货时客户流失；到货后没有通知机制，无法挽回缺货期间的转化。Shopify 有 Back-in-stock 能力。
- **目标**：客户在缺货商品页留下邮箱，商品补货后自动收到通知邮件。
- **成功指标**：缺货商品页可订阅；补货（`product.back_in_stock` 事件）后订阅者收到邮件并标记已通知。

## 2. 用户故事 / 场景

- 作为访客，我希望在缺货商品页输入邮箱订阅"到货通知"，以便补货时第一时间知道。
- 作为店主，我希望补货时订阅者自动收到邮件，以便挽回缺货流失的转化。
- 场景：缺货商品页订阅（正常）；已订阅再提交（幂等/去重）；补货触发（事件）；取消订阅（可选）。

## 3. 功能需求（FR）

- FR-001：`BackInStockSubscription` 模型（`variant`、`email`、`status[active/notified]`、`store` 作用域、唯一约束 variant+email）
- FR-002：Store API 创建订阅（`POST /api/v3/store/products/:id/back_in_stock_subscriptions`，body 含 email；校验邮箱/缺货状态）
- FR-003：订阅 `product.back_in_stock` 事件（新增 Subscriber，事件已由 StockMovement::CustomEvents 发布）→ 扫描该产品 variants 的 active 订阅 → 发邮件 + 标记 notified
- FR-004：通知邮件用 **Resend** 发送（`ENV['RESEND_API_KEY']` 配置，密钥不进代码/不提交；无 key 时降级为日志，不阻断库存）
- FR-005：前台商品缺货时显示"Notify me when back in stock"邮箱输入框（登录客户自动带邮箱），提交走 Store API
- FR-006：Admin 查看订阅列表（`/admin/back_in_stock_subscriptions`，简单 index）

## 4. 非功能需求（NFR）

- **密钥安全**：Resend API key 只放服务器 `.env`（`RESEND_API_KEY`），不硬编码、不提交仓库；`scan-secrets` 前置校验
- 事件触发幂等：`notified` 标记 + 唯一约束防重复邮件
- 邮件发送失败不阻断库存流程（降级 + Sidekiq 重试）
- 多语言：邮件模板走 `with_store_locale`

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：可创建订阅；重复 (variant, email) 幂等；store 作用域隔离
- AC-002 ← FR-002：POST 订阅返回成功；非法邮箱/缺货校验失败
- AC-003 ← FR-003：`product.back_in_stock` 事件触发后订阅者收到邮件（测试用 test 发送）且 status→notified；无 key 时降级不崩
- AC-004 ← FR-004：邮件通过 Resend HTTP API 发送（mock 验证请求）
- AC-005 ← FR-005：缺货商品页渲染订阅表单（含在 storefront）
- AC-006 ← FR-006：`/admin/back_in_stock_subscriptions` 渲染订阅列表

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足 |
|---|---|---|---|---|
| App | `backend/app/` | back_in_stock | 无 | 否 |
| Core | `pallastrade_gems/pallastrade_core/app/` | back_in_stock/subscriber | `stock_movement/custom_events.rb`（`product.back_in_stock` 事件已发布）；`subscribers/`（先例）；`base_mailer.rb`；无 BackInStock 模型 | 触发机制已有，模型/订阅/邮件需新建 |
| API | `pallastrade_gems/pallastrade_api/app/` | back_in_stock | 无 | 需新建 store 端点 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | back_in_stock | 无 | 需新建订阅列表 |
| Storefront | `storefront/src/` | back_in_stock/notify | 无 | 需新建缺货订阅组件 |
| Platform | `platform/packages/` | back_in_stock | 无 | SDK 可选（后续） |

**结论**：`product.back_in_stock` 事件已存在（复用）；需新建模型 + Subscriber + Store API + Admin index + Storefront 组件 + Resend 邮件发送。

## 7. 技术影响

- 涉及文件：
  - 迁移（core + backend）：`pallastrade_back_in_stock_subscriptions`（variant_id, email, status, store_id, timestamps + 唯一索引）
  - `core/app/models/pallastrade/back_in_stock_subscription.rb`
  - `core/app/subscribers/pallastrade/back_in_stock_subscriber.rb`（订阅 product.back_in_stock）
  - `core/app/mailers/pallastrade/back_in_stock_mailer.rb` + Resend 发送 service
  - `core/lib/pallastrade/core/dependencies.rb`（注册 serializer/service 等）
  - `api/.../store/back_in_stock_subscriptions_controller.rb`（或挂 products 下）
  - `admin/.../back_in_stock_subscriptions_controller.rb` + views + tables + navigation + locale
  - storefront 商品页组件 + SDK 调用（fetch → 需确认 SDK 或直接 fetch——按 AP-002 用 SDK，若无则加 SDK 方法）
  - `.env.example`：+ `RESEND_API_KEY`（占位）
- 数据库：新表 1 张
- 接口：Store API 新增 1 端点

## 8. 测试计划

- model spec：唯一约束/作用域/状态转换
- store API spec：创建/幂等/校验
- subscriber spec：事件 → 邮件发送 + notified（mock Resend）
- admin UI spec：订阅列表渲染
- storefront：组件测试（缺货显示/提交）

## 9. 文档同步清单

- `ai/skills/pallastrade-events-webhooks/SKILL.md`：+ back_in_stock 订阅者示例
- `ai/skills/pallastrade-api-v3/SKILL.md`：+ store 订阅端点
- `ai/skills/pallastrade-deployment/SKILL.md`：+ RESEND_API_KEY 环境变量说明
- `backend/public/api-docs/store.yaml`：+ 订阅端点
- `harness/scenarios/scenarios.json`：+ 新场景（改 skill 触发 doc-impact）
- `.env.example`：+ RESEND_API_KEY

## 10. 变更记录

- 2026-08-15：创建 PRD（reviewing），待用户确认
