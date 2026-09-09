# REQ-20260909-promo-batch1-invariants-and-code-uniqueness

> 关联 PRD：`docs/prd/promotions/PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness.md`（approved，2026-09-10 用户"认可"）
> 任务：TASK-20260909162014-44426624 ｜ Gate：GATE-2026-09-09T16-20-24 ｜ 分支 dev

---

## Step 0：跨层搜索结论（2026-09-09 会话已核实）

| 层 | 关键词 | 结论 |
|---|---|---|
| backend/app | promotion/decorator | 仅生成 TS serializers 类型；无宿主促销业务代码 → 无需宿主改动 |
| core gem models | promotion/discount_total/promo_total/adjuster/coupon | **主改动区**：`Promotion`(validations/with_coupon_code)、`order_updater.rb`(三档聚合公式，已核实口径)、`adjustable/adjuster/promotion.rb`(best-per-adjustable/tie-break)、`order_promotion.rb`(#amount 未过滤 eligible=已记录偏差)、`adjustment.rb`(eligible/promotion scopes) |
| api gem | promotions/coupon | 本批次无 API 载荷变化（仅内部校验/lookup） |
| admin gem | promotions views | 不改 UI（唯一约束错误由通用错误渲染呈现）；导航文件不改 |
| storefront | coupon/discount | 不改（lookup 行为对合法数据不变） |
| platform | promotion/coupon types | 无 API 变化，SDK/OpenAPI 无需再生 |

**结论**：能力均在 core；本批次 = core 模型/校验/迁移 + backend/spec 契约测试。无重复实现；宿主无自定义需同步。

## Step 1：Skill 咨询证据表（Gate 强制）

| Skill | 状态 | 关键结论引用 |
|---|---|---|
| `pallastrade-promotions`（领域） | ✅ 已读 | 促销=Rule/Action/Calculator；单码小写/大小写不敏感匹配；multi_codes 每码一次性；`usage_limit` 与 `credits_count`；择优=每 adjustable 只留最大折扣一条（Adjuster） |
| `pallastrade-customization`（必读） | ✅ 已读 | 决策树：核心模型行为/校验属 "Direct Gem Modification / 框架源修改"（本项目 git 跟踪、升级=merge）；行为副作用用事件、校验/关联用模型内直接修改（core gem 属团队产品，直接改源） |
| `harness-prd` / `pallastrade-prd`（流程） | ✅ 已读 | PRD 驱动闭环；查重>0.3 回写；approved 后 gate+REQ；AC↔测试映射 `prd verify`；知识同步门 |
| `pallastrade-testing` | ✅ 已读 | RSpec+FactoryBot；`pallastrade_dev_tools` 自动加载 core testing_support factories（promotion/order_with_line_items 等）；测试放 backend/spec/{models,services}；避免 Model.create；build 优先 |
| `pallastrade-admin` / `catalog`（模板必读） | ⬜ 不涉及 | 本批次不改 Admin 页面/控制器、不改商品目录；跨层搜索证实无 admin/catalog 面 → 判定不适用（结论性跳过，非漏读） |

## 需求描述

见 PRD（三组）：
1. **A0** 口径与决策：附录 A（discount_total 三档聚合+eligible+tie-break）与附录 B（函数唯一索引、store 级唯一、多码全局唯一、撞码防新增、偏差记录）——规范性固化（已写入 PRD，本批次以测试锁定）。
2. **P0** 契约测试：I1 金额恒等 / I2 重算确定性 / I3 移除幂等 / I4 best-per-adjustable / I5 不打负 / I6 暴露型（OrderPromotion#amount 未过滤 eligible）。
3. **P3** 优惠码唯一：Promotion store 级单码唯一（模型校验+i18n+DB 函数唯一索引）、存量重复处置迁移、`with_coupon_code` 确定性（去 `.last`，单码优先）、单码↔多码撞码新增侧防。

## 技术方案

- core `Promotion`：`before_validation :downcase_code`（已有）后新增 `validate :code_unique_in_store`（SQL `lower(btrim(code))` 命中同 store 其它单码促销）；`with_coupon_code` 去 `.last`：单码精确匹配 + CouponCode 匹配合并为确定性（单码优先），同源多条按最新取。
- core `CouponCode`：新增撞码校验（code 与同 store 单码促销冲突即拒）——生成侧。
- migration：函数唯一索引 `(store_id, lower(btrim(code))) WHERE code IS NOT NULL`；前置数据检查+处置 rake/迁移（用过保留→最新保留→未用改名 `-dup-<id>`；绝不删使用记录）。
- locale：core en.yml 新增错误 key。
- spec：contracts + model specs（见 PRD §8）。

## 风险点

- 迁移对存量重复数据的处置策略（已与用户确认）；测试库/开发库均需迁移通过。
- `with_coupon_code` 行为变化（确定性优先）对现有调用方的兼容——保持合法数据返回不变，仅消除歧义。
- OrderPromotion#amount 偏差不修（记录并暴露），避免本批扩大资金语义变更。

## 验证方案（AC↔命令）

| AC 组 | 验证 | 命令 |
|---|---|---|
| P0 全部 | contract+model specs | backend 容器 `bundle exec rspec spec/services/pallastrade/promotions spec/models/pallastrade/promotion_spec.rb ...` |
| P3 | 模型 spec + 迁移 | 同上 + migration 运行 + `harness check --profile quick` |
| 回归 | Ruby 最小验证 | `npx harness check --profile quick`；相关既有 spec 全绿 |

## 决策节点

- 用户已于 2026-09-10 "认可" PRD（含两个决策点）。✅
