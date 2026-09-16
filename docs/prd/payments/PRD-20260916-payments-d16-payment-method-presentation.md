# PRD-20260916-payments-d16-payment-method-presentation

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-16 |
| 来源 | 需求：D16 切片1 —— 前台消费面：支付方式「入口级展示元数据」+ 方法行渲染（业务方案 §78-D16 / §76.1） |
| 分类 | payments |
| 关联 Skill | `pallastrade-payments`、`pallastrade-api-v3`、`pallastrade-storefront`、`pallastrade-typescript-sdk` |
| 关联 REQ | `harness/requirements/REQ-20260916-d16-payment-presentation.md` |
| 关联 PRD | `PRD-20260915-admin-管理后台支付配置选项化…`（D1：入口模型 + 门店显示名）；`PRD-20260915-payments-d8-…`（入口范围）；`PRD-20260915-payments-d10-client-config.md`（client_config 同 payload） |
| 需求类型 | 新功能 |

## 1. 背景与目标

- **一句话需求原文**：D16 前台消费面（§76.1「`available_payment_methods[]` 字段扩展（additive）」）：`option_id` / `method_key` / `display_name` / `description` … + 支付方法行含图标/文案。
- **背景（代码事实）**：
  - 后台自 D1 起支持「入口（PaymentOption）过渡形态」：`metadata['options']` 中每个入口可配 `active` / `display_name`（门店显示名）/ `position` / `frontend_kind` / `rule_set`，后台列表按入口渲染（`payments_helper` 已做 `display_name` 回落）。
  - 但**前台契约只回默认入口**：`CheckoutSerializer#payment_method_payload` 与 store `PaymentMethodSerializer` 只给 `kind` / `frontend_kind`（= 默认入口）与 `name`，运营在后台改的**入口显示名到不了前台** —— 前台行仍显示 provider 名（如「Stripe」而非「信用卡 / Apple Pay」）。
  - 契约缺少 `option_id`（稳定行键）与 `method_key`（入口维度），§76.1 要求的消费面无法按入口维度渲染。
- **目标**：以 **additive** 方式把入口级展示元数据下发前台，让支付方法行显示运营配置的名称/描述；不改行基数、不改 Start 语义（零回归）。
- **成功指标**：① 后台把 Stripe 的 card 入口显示名设为「信用卡」后，前台支付方式行显示「信用卡」；② 未配置显示名时回落 provider 名（零回归）；③ `generated:check` 零漂移。

## 2. 用户故事 / 场景

- 作为**运营**，我希望后台配置的入口显示名前台即时可见，以便用业务语言描述支付方式。
- 作为**买家**，我希望支付方式列表用我能懂的名称描述。
- 场景：① 配了显示名 → 前台显示该名；② 未配 → 回落 provider 名（`name`）；③ 老客户端忽略新字段；④ 多入口 provider（card + apple_pay）仍只回默认入口行为不变（本切片**不改行基数**）。

## 3. 功能需求（FR）

- **FR-001**：支付方式 payload（checkout `payment.available_payment_methods[]` + store `PaymentMethodSerializer` 用于 cart/order）**additive** 新增：
  - `option_id`：稳定行键 = `"#{prefixed_id}:#{method_key}"`；
  - `method_key`：入口 kind（与既有 `kind` 同值；命名对齐 §76.1）；
  - `display_name`：入口显示名（option `display_name` → provider `name` 回落）；
  - `description`：入口描述（option `description` → provider `description` 回落，可空）。
- **FR-002**：解析走**单一入口**：由 `PaymentMethod#default_payment_option`（未选项化）或生效入口（选项化）统一提供，避免两处各写一套回落逻辑。
- **FR-003**：既有字段（`id` / `name` / `type` / `session_required` / `source_required` / `kind` / `frontend_kind` / `client_config`）语义不变；**行基数不变**（每个 payment method 一行）。
- **FR-004**：前台方法行渲染 `display_name`（缺失回落 `name`）；不改 Start 调用参数（本切片不引入 `option_kind` 透传）。
- **FR-005**：契约再生成（`scripts/ci/contracts.sh`）→ `store.yaml`（backend + platform 副本）+ SDK/zod 类型；`generated:check` 零漂移。

## 4. 非功能需求（NFR）

- **兼容**：additive；老客户端忽略。
- **性能**：全部取自已加载对象的 metadata，零额外查询。
- **安全**：不含凭据（`client_config` 已有独立 D10 口径）。

## 5. 验收标准（AC，与测试一一映射）

- **AC-001** ← FR-001/002：选项化 provider 配了 `display_name` → payload `display_name` = 配置值，`method_key`/`option_id` 正确。
- **AC-002** ← FR-002：未配 `display_name`（或未选项化）→ 回落 provider `name`；`description` 同口径。
- **AC-003** ← FR-003：既有键集合不丢失（含 `client_config`），行基数 = payment method 数。
- **AC-004** ← FR-005：store `PaymentMethodSerializer`（cart/order 通道）同样带新字段。
- **AC-005** ← FR-004：前台方法行渲染 `display_name`，缺失时渲染 `name`（vitest）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | `display_name` / `payment_options` | 无命中 | ❌ |
| Core | `pallastrade_core/app/` | 同上 | `payment_method.rb`：`payment_options` / `available_payment_options` / `effective_payment_options` / `default_payment_option`（已含 `display_name`）/ `payment_option_for` | ⚠️ 部分（数据齐备，缺契约投影） |
| API | `pallastrade_api/app/` | `payment_method_payload` | `store/checkout/checkout_serializer.rb` + `v3/payment_method_serializer.rb` | ⚠️ 承载点，需扩字段 |
| Admin | `pallastrade_admin/app/` | `display_name` | `payment_methods_controller`（写 `options[kind][display_name]`）+ `payments_helper`（后台侧回落） | ✅ 已满足（零改动） |
| Storefront | `storefront/src/` | `method.name` | `OrderPaymentContent` / `UnifiedCheckout` / `PaymentCheckoutModal` 的行渲染 | ⚠️ 需改渲染 |
| Platform | `platform/packages/` | `PaymentMethod` 生成类型 | `sdk/src/types/generated/PaymentMethod.ts` 等 | ⚠️ 随契约再生成 |

**结论**：数据（入口显示名）已在 core 齐备，本切片只做「投影 + 渲染」，不新增模型、不改后台、不改 Start。

## 7. 技术影响（实施口径）

- **Core**：`payment_method.rb` 增 `effective_payment_option`（生效入口读模型：选项化 → `effective_payment_options.first`，否则 `default_payment_option`）+ `option_display_name` / `option_identifier(kind = nil)`（`"#{prefixed_id}:#{kind}"`）。
  *实施修正*：草案里的 `effective_display_option` / `option_description` / `option_id_for` 合并为上述三个方法；**入口级 `description` 不做**——入口 metadata 没有该键，`description` 维持 provider 语义（详见 §11）。
- **API**：store `CheckoutSerializer`（`payment.available_payment_methods[]`）+ store `PaymentMethodSerializer` 的 payload/typelize 加 `option_id` / `method_key` / `display_name`。
- **Storefront**：三处方法行渲染 `display_name ?? name`。
- **契约**：再生成（typelize 类型 + SDK generated types + `{store,admin}.yaml` + platform 副本）；无迁移。

## 8. 测试计划

| 层 | 文件 | 覆盖 |
|---|---|---|
| 后端 | `backend/spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb`（追加用例） | AC-001/002/003 |
| 后端 | `backend/spec/models/pallastrade/d16_payment_option_presentation_spec.rb` | AC-001/002（模型读模型） |
| 前端 | `storefront/src/components/checkout/__tests__/OrderPaymentContent.test.tsx`（追加用例） | AC-005 |

## 9. 收口清单

- [x] 本 PRD（approved → 实施后 done）
- [x] REQ：`harness/requirements/REQ-20260916-d16-payment-presentation.md`
- [x] gate + prep 清理
- [x] 用户确认：用户 2026-09-16「继续」（承接 D12 后按 §78 顺序推进 D16）
- [x] 知识同步：`pallastrade-payments`（D16 小节）/ `pallastrade-api-v3`（契约表）/ `pallastrade-storefront`（方法行渲染）Skill + AGENTS §6 verifier 行 + 场景库 GS-140 + 业务方案 §76.1 回写
- [x] 验证：`harness verify d16-payment-presentation-rspec`（后端）+ `harness verify storefront-test`（前端）
- [x] 契约：`generated:check` 零漂移

## 10. 变更记录

| 版本 | 日期 | 变更 |
|---|---|---|
| 0.1 | 2026-09-16 | 初版（切片1：入口级展示元数据 + 方法行渲染） |
| 1.0 | 2026-09-16 | 实施完成（后端读模型 + 契约三字段 + 前台三处渲染 + 前后端测试）；状态 approved → done |

## 11. 实施记录

| 项 | 事实 |
|---|---|
| 后端读模型 | `PaymentMethod#effective_payment_option` / `#option_display_name` / `#option_identifier(kind = nil)` |
| 契约字段 | `option_id`（`prefixed_id:kind`）/ `method_key`（入口 `kind` → `default_option_kind`）/ `display_name`（入口 `display_name` → `name`） |
| 下发面 | store `CheckoutSerializer.payment.available_payment_methods[]`、store `PaymentMethodSerializer`（cart / order / shopping_cart） |
| 前台渲染 | `OrderPaymentContent.tsx` / `PaymentCheckoutModal.tsx` / `UnifiedCheckout.tsx`（`name="payment-method"` 块）→ `display_name ?? name` |
| 测试 | 后端 27 examples / 0 failures（含新增模型 5 例 + checkout serializer 新用例）；前端 `OrderPaymentContent.test.tsx` 21 例（新增 display_name 渲染 + 无 display_name 回落） |

**决策与偏差（均已记入知识资产）**：

1. **`option_id` 不用 `popt_` 前缀**：入口层当前没有独立前缀 id，本切片取 `"#{payment_method.prefixed_id}:#{kind}"`，与后台 line item 的 `prefixed_id:kind` 同源（前后台对得上同一条入口）。
2. **不做 `icon` / `badges` / `hint` / `installments` / `saved_sources`**：入口 metadata 只存 `active` / `display_name` / `position` / `kind` / `rule_set`，这些字段**没有数据来源**；先扩 metadata 契约再下发，避免序列化器臆造字段。
3. **不做入口级 `description`**：同上（provider 级 `description` 语义不变，保持老客户端兼容）。
4. **行基数不变**：每 provider 一行；按入口拆行（card / apple_pay 各一行）与 Express 行拆分、已存卡管理、EU/BR 本地化矩阵均属**后续切片**。
5. **不改 Start 调用参数**：本切片纯展示读模型，`option_kind` 透传（入口级门禁强化）留待后续切片与 D8 求值口径一并处理。
