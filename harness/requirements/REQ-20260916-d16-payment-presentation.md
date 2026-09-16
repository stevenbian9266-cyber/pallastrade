# REQ-20260916-d16-payment-presentation

> 任务：`TASK-20260915165504-3efcd8a6` · PRD：`docs/prd/payments/PRD-20260916-payments-d16-payment-method-presentation.md`
> 需求原文：用户 2026-09-16「继续」（承接 D12 后按 §78 顺序推进 D16；本批取**切片1**）

## Step 0：6 层跨层搜索（实查结论）

| 层 | 关键词 | 结论 |
|---|---|---|
| App | `display_name` / `payment_options` | 无命中 |
| Core | 同上 | `PaymentMethod#payment_options` / `#available_payment_options` / `#effective_payment_options` / `#default_payment_option`（**已含 `display_name`**）/ `#payment_option_for` → 数据齐备，缺契约投影 |
| API | `payment_method_payload` | `store/checkout/checkout_serializer.rb#payment_method_payload` + `v3/payment_method_serializer.rb`（cart/order 通道）→ 两个承载点 |
| Admin | `display_name` | `payment_methods_controller` 写 `options[kind][display_name]`；`payments_helper` 后台侧已回落 → **零改动** |
| Storefront | `method.name` | `OrderPaymentContent` / `UnifiedCheckout` / `PaymentCheckoutModal` 三处行渲染 |
| Platform | 生成类型 | `sdk/src/types/generated/PaymentMethod.ts` 等随契约再生成 |

**防重复判定**：不新增模型/字段（`display_name` 早在 D1 落在 `metadata['options']`），只做投影与渲染；不改 Start 语义与行基数。

## Step 1：Skill 咨询证据表

| Skill | 结论（约束） |
|---|---|
| `pallastrade-customization` | 决策树优先级 8；本批改 core/api gem 文件 + storefront 组件，均按 `# PALLAS-CUSTOM:` 注释 |
| `pallastrade-payments` | 支付域：支付方式 payload 已含 D10 `client_config`、D8 `kind/frontend_kind`；本批只加展示元数据，**不得**改变 `session_required/source_required` 语义 |
| `pallastrade-api-v3` | Store API 契约：additive；改 serializer 后必须 `scripts/ci/contracts.sh` 再生成 + `generated:check` 零漂移 |
| `pallastrade-storefront` | 客户端组件不直连 API；行渲染只用传入 props；i18n 键用现有 `checkout.*` 命名空间，不新增文案（显示名来自服务端） |
| `pallastrade-typescript-sdk` | 生成类型勿手改；消费面用生成的 `PaymentMethod` 类型 |
| `pallastrade-testing` | 后端 spec 走 `rails_helper`；前端 vitest 在 `storefront` 目录内跑 |

## Step 2：设计要点

1. **单一读模型**：core 提供 `effective_payment_option`（选项化 → `effective_payment_options.first`；未选项化 → `default_payment_option`）+ `option_display_name` / `option_description` / `option_identifier(kind)`；两个 serializer 都调它，**禁止各写回落**。
2. **option_id 形态**：`"#{prefixed_id}:#{kind}"`（稳定、可读、与既有 `id` 同源）。
3. **零回归**：既有键集只增不减；行基数不变；Start 调用参数不变（本切片不做 per-option 行）。
4. **前台渲染**：`display_name ?? name`（缺失回落），其余逻辑不动。

## Step 3：切片

- **切片1（本批）**：契约扩展（4 字段）+ 前台渲染 + specs。
- **切片2（未做，留待后续）**：per-option 行（Express 行拆分 / 入口维度列表）+ `saved_sources` + badges/hint/installments；本地化支付矩阵（EU/BR）依赖 provider 侧开通。

## 实施记录（收口时补全）

- **改动清单**：
  - core：`pallastrade_gems/pallastrade_core/app/models/pallastrade/payment_method.rb`（`effective_payment_option` / `option_display_name` / `option_identifier(kind = nil)`）；
  - api：`pallastrade_api/app/serializers/pallastrade/api/v3/payment_method_serializer.rb`、`.../store/checkout/checkout_serializer.rb`（typelize + 三字段）；
  - 契约：`backend/app/javascript/types/serializers/*`、`backend/packages/{sdk,admin-sdk}/src/types/generated/*`、`backend/public/api-docs/{store,admin}.yaml`、`platform/docs/api-reference/*`、`platform/packages/sdk/{src/types/generated,dist}/*`（`contracts.sh` 再生成）；
  - 前台：`storefront/src/components/checkout/{OrderPaymentContent,PaymentCheckoutModal,UnifiedCheckout}.tsx`；
  - 测试：`backend/spec/models/pallastrade/d16_payment_option_presentation_spec.rb`（新增 5 例）、`backend/spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb`（键集更新 + AC-001/002 新用例）、`storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`（AC-005 新用例）。
- **验证器**：`harness verify d16-payment-presentation-rspec`（4 文件，后端 27 examples / 0 failures）+ `harness verify storefront-test`（全量 vitest 绿）；
  `harness generated:check` 零漂移。
- **决策与偏差**：
  1. `option_id` 采用 `"#{prefixed_id}:#{kind}"`（非 §76.1 草案的 `popt_`）——入口层无独立前缀 id，与后台 line item 的 `prefixed_id:kind` 同源；
  2. **不做** `description`（入口级）/ `icon` / `badges` / `hint` / `installments` / `saved_sources`：入口 metadata 无数据来源，先扩 metadata 再扩契约；
  3. 行基数不变（每 provider 一行）；per-option 行、Express 拆分、已存卡、EU/BR 矩阵 → 切片2；
  4. Start 调用参数不变（`option_kind` 透传留待与 D8 门禁一并处理）。
- **状态**：done（2026-09-16）。
