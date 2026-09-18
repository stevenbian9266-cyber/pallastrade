# REQ-20260918-d7-payment-section-express

关联 PRD：`docs/prd/payments/PRD-20260918-payments-d7-payment-section-express.md`
任务：`TASK-20260918070835-ad430a64`（critical）
用户确认：**2026-09-18 用户以「实施」明确确认**（承接上一轮「需要我开这一批吗」的提议：D7 支付区收尾 —— 入口级支付列表 + 钱包快付 + 三页共用支付区）。

## 1. 问题与根因（一句话）

后台已能配多入口（D1），但投影把 provider 折叠成「一个生效入口」（`effective_payment_option = effective_payment_options.first`），前台又无 `frontend_kind` 分派、钱包组件只在购物车抽屉 —— 三处叠加导致 **checkout 页看不到 Apple Pay / Google Pay，且关掉前一个入口才轮换显示下一个**。

## 2. 文件计划

**修改（Core / API）**
- `backend/pallastrade_gems/pallastrade_core/app/models/pallastrade/payment_method.rb`（入口级投影辅助：`payment_option_entries` / `option_group`）
- `backend/pallastrade_gems/pallastrade_core/app/services/pallastrade/order_checkout/view.rb`（`available_payment_methods` 输出 provider + entries）
- `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/payment_method_serializer.rb`（provider 级 `group`/`position`）
- `backend/pallastrade_gems/pallastrade_api/app/serializers/pallastrade/api/v3/store/checkout/checkout_serializer.rb`（`entries[]`）
- `backend/pallastrade_gems/pallastrade_api/app/controllers/pallastrade/api/v3/store/{carts,orders}/payment_sessions_controller.rb`（`option_kind` 透传）

**新增（Storefront）**
- `storefront/src/components/checkout/PaymentSection.tsx`（三页共用支付区）
- `storefront/src/components/checkout/WalletPaymentButtons.tsx`（订单页钱包按钮：PI 会话 + ExpressCheckoutElement）
- 对应 `__tests__`

**修改（Storefront）**
- `storefront/src/components/checkout/UnifiedCheckout.tsx`、`OrderPaymentContent.tsx`（接入 PaymentSection + 移动吸底 Pay 条）
- `storefront/src/lib/data/*`（会话创建带 `option_kind`）

**契约**
- `backend/public/api-docs/store.yaml` + `platform/docs/api-reference/store.yaml` + SDK 生成类型（`bash scripts/ci/contracts.sh`）

**Harness / 文档**
- `harness.config.mjs`（verifier `d7-payment-section-rspec`）、`AGENTS.md` §6、`harness/scenarios/scenarios.json`、4 个 Skill、`docs/prd/README.md`

## 3. Skill 咨询表（gate `read-skill-*` 强制，须真实结论）

| Skill | 读到的关键约束 | 本切片的遵循方式 |
|---|---|---|
| `pallastrade-customization` | 决策树：能扩既有读模型就不新建域；后台/前台优先扩展点 | **不建入口表**，复用 `metadata['options']` 与既有读模型；只加投影与渲染 |
| `pallastrade-payments` | 入口身份 = `effective_payment_option['kind']`；`Resolver` 是唯一求值点；`Start(option_kind:)` 已做入口级校验 | 入口集合**必须**来自 `Resolver.available_options`；投影只做「翻译」不重算 |
| `pallastrade-checkout` | 「看得到、付不了」是红线；隐藏=不出现由服务端决定 | 前台零筛选；`option_kind` 全链路透传，拒绝即 422 且不建会话 |
| `pallastrade-storefront` | **不得**在客户端按 `kind/frontend_kind` 自行隐藏入口；AP-001/002/006 | 只按服务端已过滤的结果渲染；不写内联样式、不用裸 fetch |
| `pallastrade-api-v3` | 契约 additive + `generated:check` 零漂移；prefixed id | `entries[]` 为新增字段；`option_id` 用既有 `"pm_x:kind"` |
| `pallastrade-security` | 下发面只带 publishable 级凭据；不得下发 secret | 钱包按钮复用 `client_config`（D10），不新增下发字段 |
| `pallastrade-testing` | 夹具不得依赖默认店铺 market 状态；查询数断言口径 | 入口投影 spec 用显式 metadata 夹具；投影为纯内存展开（无额外查询） |

## 4. 验收与证据计划

- **verifier**：`d7-payment-section-rspec`（后端 4 文件 + D1/D8/D15c/D16 回归）+ 前端 `storefront-test` → `evidence run --type test`
- **AC ↔ 测试映射**：PRD §5 的 AC-001..010 逐条在规格内以 `# PRD-20260918-payments-d7-payment-section-express AC-0xx` 同行标注
- **dev 冒烟**：Stripe 测试入口三入口（card/apple_pay/google_pay）→ 断言投影 `entries[]` 三项且顺序正确；or_ 页渲染钱包按钮（服务端 `option_kind` 校验通过）；停用 card 后 `card` 项消失而其余仍在（**证明不再「轮换显示」**）
- **知识同步**：`sync-check --id PRD-…` → 逐项 `knowledge assess` → `--ack`
- **恢复计划**：critical 任务必需（`harness recovery create`）

## 5. 风险与回滚

| 风险 | 等级 | 缓解 |
|---|---|---|
| 契约 additive 撞旧断言 | 中 | 同步 `checkout_serializer_spec` 等键集断言（属正当修改） |
| 钱包确认受 provider/域名限制（Apple Pay 需域关联） | 中 | 钱包不可用时**只隐藏按钮**、其余入口照常；不做降级猜测 |
| 入口展开引入 N+1 | 低 | 纯内存展开 + 查询数断言 |
| 与并行会话的共享文件冲突 | 中 | 提交用显式 pathspec；共享文件（AGENTS/scenarios/config/Skill）提交前核对差异仅含本批 |
| 前台无 `entries[]` 的旧响应 | 低 | 回落「一 provider 一行」（AC-010） |

**回滚**：`git revert <本批提交>`；零迁移 → 无数据回滚。
