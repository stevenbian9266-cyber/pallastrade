# PRD-20260909-payments-admin-api-v3-只读端点-payment_combinations-index-show-refunds-sh

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-09-09 |
| 来源 | Admin API v3 只读端点：payment_combinations index/show + refunds show + 孤儿扫描（REV-P6-8l） |
| 分类 | payments（自动判定） |
| 关联 Skill | pallastrade-api-v3 / pallastrade-payments / pallastrade-customization |
| 关联 REQ | REQ-20260909-rev-p6-8l-admin-api-v3-readonly.md（实施时建） |
| 关联 PRD | REV-P6-8g（边界「Admin API 组合只读端点 → 后续」）、8h（边界「Admin API v3 端点/SDK → 后续」）；8a/8f（refund v3 既有） |
| 需求类型 | 优化迭代（8g/8h 边界落地：v3 API 化，feature gate） |

> 源：`豆包…/P6` §63 REV-P6-8（Admin 展示清单——现仅在 Rails Admin HTML 可见，外部系统/未来 dashboard
> 无 JSON API 可达）。**本包 = Admin API v3 只读端点化**：把 8a/8g/8h 已在 Rails Admin 实现的组合/退款/
> 孤儿配对只读信息暴露为 `/api/v3/admin` 端点。**SDK 现实**：platform 无 admin SDK 包（`@pallastrade/sdk`
> 仅 Store API，`generate-zod` 只消费 store types；AGENTS.md 所列 admin-sdk 未建）→ 新建 admin TS 客户端
> 属独立工程（边界记录，本包不做）。

## 1. 背景与目标
8g（PaymentCombination Rails Admin 可视化）、8a（Refund Admin Ops）、8h（孤儿只读金额 + Payments Ops）后，
组合/退款/孤儿的**只读信息只在 Rails Admin HTML 页面**；v3 admin 目前仅有 `orders/:id/refunds index+create`
（无 show）、`payment_combinations/:id/cancel`（动作）。外部系统 / 未来 dashboard（依赖 JSON API + typed
client，AP-002 禁裸 fetch）无法读取。目标：
1. **payment_combinations index/show**（8g 数据面 API 化，含 split 成员/组合 payment/txn 关联）；
2. **refunds show**（补全 refund 详情读取——8a serializer 字段已在，只缺端点）；
3. **孤儿配对只读端点**（8d/8h 在线 OrphanPairing 的 API 化，含金额降级语义）；
4. admin.yaml（curated paths + 生成 schemas）+ `platform/docs/api-reference/admin.yaml` 副本同步，
   `generated:check` 过。
成功指标：四端点 store 作用域 + prefixed ids + `{data}`/`{data:[],meta}`；权限复用（order_management read）；
零写/零 provider mutation（孤儿端点沿用 8d/8h 只读不变式）；全量绿。

## 2. 用户故事 / 场景
- 作为 dashboard/集成方，我希望经 `GET /api/v3/admin/payment_combinations` 拉组合列表（状态/金额/成员数），
  以便在非 Rails Admin 界面展示组合资金概览。
- 作为运营，我希望 `GET .../payment_combinations/:id` 看到该组合成员 split captured/refunded/credit_allowed +
  组合 payment + txn 关联（镜像 8g show），以便程序化对账。
- 作为运营，我希望 `GET .../orders/:id/refunds/:refund_id` 看到单笔退款 state/时间戳/last_error/
  payment_split/target_order，以便排查（8a UI 等价数据 API 化）。
- 作为财务，我希望 `GET .../payments/:id/orphan_pairing` 在线查看该支付与 provider 的孤儿退款配对
  （含金额；无能力/无 session 降级不 500），以便审计。
- 边界/异常：跨 store 不可见（store 作用域）；非法 id 404 / 无权限 403；孤儿端点 provider 异常降级。

## 3. 功能需求（FR）
- FR-R68L-101（组合列表）：`GET /api/v3/admin/payment_combinations`——`current_store.payment_combinations`
  Ransack 过滤（status 等）+ 分页（`{data, meta{count,current_page,total_pages}}`）；serializer 返回
  `id(pcom_)` + attributes{status, amount, currency, member_count, refunded_total, created_at}。
- FR-R68L-102（组合详情）：`GET /api/v3/admin/payment_combinations/:id`（`find_by_prefix_id!` + store 作用域）——
  attributes 含 101 + members（`payment_splits`：order prefixed id/order_number/captured/refunded/
  credit_allowed）+ 组合 payments（state/credit_allowed）+ commerce_transaction（id/state 摘要）；`expand=`
  控制嵌套（既有 v3 惯例）；无整型 PK。
- FR-R68L-103（退款详情）：`GET /api/v3/admin/orders/:order_id/refunds/:id`——store 作用域 + `find_by_prefix_id!`；
  serializer 复用 admin_refund_serializer（state/metadata/last_error_code/message/attempt/5 时间戳/
  payment_split_id/target_order_id 等 8a 字段）；补 v3 show（现 only index/create）。
- FR-R68L-104（孤儿配对只读）：`GET /api/v3/admin/payments/:id/orphan_pairing`——`Refunds::OrphanPairing.call`
  （payment + 组合 fallback session；`implements_financial_details?` 能力/锚点判定同 ReconcilePayment）→
  `{data:{status: matched|needs_attention|not_applicable|unsupported|unavailable, reasons[],
  orphans:[{provider_id, amount, currency}], matched:[{provider_id, refund_id}], local_unmatched:[…]}}`；
  单条 orphan 金额失败降级（amount nil + ORPHAN_AMOUNT_UNAVAILABLE，8h 语义）；**零写/零 provider mutation**。
- FR-R68L-105（serializer 注册 + 文档）：api dependencies 增 `admin_payment_combination_serializer`
  （`PallasTrade.api`）；admin.yaml paths curated + `rake api:docs:schemas` 生成 schema → 
  `platform/docs/api-reference/admin.yaml` 副本同步 + `generated:check`。
- 边界（记录不实施）：新建 admin TS SDK/typed client（当前无此包，独立工程）；孤儿全店扫描列表端点
  （N×provider 在线不可行——保持 rake `refunds:orphans`）；组合/退款写动作（既有 create/cancel 通道）。

## 4. 非功能需求（NFR）
零写/零 provider mutation（孤儿端点只读；provider I/O 仍避 DB 锁——8d 只读不变式）；store 作用域 +
prefixed ids + 无整型 PK（AGENTS §4）；N+1 用 ar_lazy_preload/includes；权限 order_management read
（PaymentCombination/PaymentSplit 8g 已授；Refund read 沿用）；serializer as_json JSON-safe。

## 5. 验收标准（AC）
| AC | 条件 | FR |
|---|---|---|
| AC-R68L-01 | GET /admin/payment_combinations → {data[], meta}，store 隔离；status 过滤生效；含 member_count/refunded_total | 101 |
| AC-R68L-02 | GET /admin/payment_combinations/:id（pcom_）→ {data} 含 members splits（captured/refunded/credit_allowed）+ payments + txn 摘要；404 跨 store/不存在 | 102 |
| AC-R68L-03 | GET /admin/orders/:oid/refunds/:rid → {data} refund 详情（state/时间戳/last_error/payment_split/target_order）；404 跨 store | 103 |
| AC-R68L-04 | GET /admin/payments/:pid/orphan_pairing → 只读配对结构（matched/needs_attention/orphans 含金额）；bogus 无能力 → unsupported 降级不 500；无 session legacy → unavailable | 104 |
| AC-R68L-05 | 权限：无 order_management/read → 403；admin.yaml + api-reference 同步 + generated:check；零写断言（孤儿端点后无 Refund/无 provider 调用变化） | 105 |
| AC-R68L-06 | 回归：8a/8f/8g/8h 相关组绿；全量 backend-rspec ×2 + quick check + doc-impact | — |

## 6. 跨层搜索记录（6 层）
| 层 | 路径 | 找到 | 满足 |
|---|---|---|---|
| App | backend/app | 无 override | — |
| Core | core/app | PaymentCombination/PaymentSplit/Refund/OrphanPairing/OrphanPairingResult（8d/8h）；CommerceTransaction | 数据面有 |
| API | api/app | admin orders/refunds index+create（无 show）；payment_combinations cancel；serializer 注册表 admin_refund/admin_payment（无 admin_payment_combination） | 部分（缺口=只读端点） |
| Admin | admin/app | 8a/8g/8h Rails Admin 只读页（数据面参考） | 供镜像 |
| Storefront | storefront/src | 无 admin | — |
| Platform | platform/packages | sdk 仅 store（types/generated Refund/PaymentCombination 为 store schema）；**无 admin-sdk** | 边界（不新建） |

**结论**：core 数据面与 serializer 字段齐备；缺 admin v3 只读 controller/routes + admin_payment_combination_serializer +
yaml paths + api-reference 同步；SDK 无 admin 包 → 不做客户端。

## 7. 技术影响
- api：routes（admin：payment_combinations +index/show；orders/refunds +show；payments member orphan_pairing）；
  新/改 controller（payment_combinations_controller index/show、orders/refunds_controller show、
  orders/payments_controller 或 payments_controller member orphan_pairing）；serializer 新
  admin_payment_combination_serializer + dependencies 注册。
- docs：admin.yaml（curated paths + schemas 生成）+ platform/docs/api-reference/admin.yaml 副本 +
  admin-api/ 页面。
- specs：request specs（index/show/orphan 结构 + 权限 + 404 + 降级）；回归 8a/8f/8g/8h 组。
- 无 migration / 无 sidekiq / 无 UI / 无 store SDK。

## 8. 测试计划
新增：admin request specs——payment_combinations（index 分页/过滤/show 结构/404）、refunds show、
payments orphan_pairing（bogus unsupported、孤儿 fixture 金额、local_unmatched、降级）；controller/serializer
单元。更新：无（8g nav spec 不动）。AC-R68L-01~06 映射至上述 request specs。

## 9. 文档同步清单（知识同步门）
- [ ] API 文档：admin.yaml + api-reference/admin.yaml 副本（`generated:check`）；api-v3 skill 端点节。
- [ ] payments skill（8l 节）；scenarios GS-079。
- [ ] README（docs/prd/README 加 8l 行——新 PRD）。
- [ ] 本 PRD 状态更新 + 变更记录。

## 10. 变更记录
| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-09-09 | 0.1 | 初稿（8g/8h 边界落地：admin v3 只读端点化；SDK 现状记录不新建） | AI |
| 2026-09-09 | 1.0 | done：实施完成（需求 commit bbf6bc6）——payment_combinations index/show + refunds show + payments show/orphan_pairing + Admin::PaymentCombinationSerializer + admin.yaml(5 paths)/api-reference + generated:check；request spec 5 绿+回归 21 绿+全量 ×2 绿+quick 干净；GS-079；payments/api-v3 skill 8l 节 | AI |

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |
