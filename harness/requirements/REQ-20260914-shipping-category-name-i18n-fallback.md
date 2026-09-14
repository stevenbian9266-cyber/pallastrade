# REQ-20260914-shipping-category-name-i18n-fallback — ShippingCategory 名称落库为 translation-missing

> 关联 PRD：`docs/prd/shipping/PRD-20260914-shipping-category-name-i18n-fallback.md`（done）
> 来源：用户 bug 报告「shipping categories 翻译异常：Translation missing: en.PallasTrade.seed.shipping.categories.default / …digital」（2026-09-14）
> Task：`TASK-20260914005817-a02278a8`；Gate：`GATE-2026-09-14T00-58-27`（bugfix，critical 风险）
> 产出：Core 命名去 i18n 依赖 + 幂等数据修复入口 + dev 遗留数据修复

## Step 0：跨层搜索（已执行）

| 层 | 路径 | 结果 |
|---|---|---|
| App | `backend/app/` | 无宿主层实现 |
| Core | `pallastrade_core/app/` | `models/pallastrade/shipping_category.rb`（仅 `DIGITAL_NAME`/`self.digital`，无 Default 常量与修复入口）；`services/pallastrade/seeds/shipping_categories.rb` L7-8（**`I18n.t` 驱动名称** → 缺词条时把 missing 文案写进 `name`）；`models/pallastrade/product.rb` L959（同 pattern）；`config/locales/en.yml` L1433-1435（词条实际存在） |
| API | `pallastrade_api/app/` | 无分类写入端点（仅序列化引用） |
| Admin | `pallastrade_admin/app/` | 控制器 + `_form.html.erb` 直接渲染 `name` 原值 → 数据脏则显示脏；**无需改代码** |
| Storefront | `storefront/src/` | 无消费点 |
| Platform | `platform/packages/` | 无 |

**结论**：缺陷单点 = Core 命名来源 + dev 历史数据；修复后后台显示即恢复正常（无需展示层改动）。

## Step 1：Skill 咨询

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-data-model` | ✅ 已读 | 分类名等「参与关联的数据字段」不应由 I18n 输出驱动；数据修复须保持引用完整性（先迁移引用再删行） |
| `pallastrade-deployment` / `pallastrade-admin` | ✅ 已读 | 运维入口以 rake 任务形式提供；后台展示层不改，数据修复即可自愈 |

## 实施结果（2026-09-14）

| 项 | 结果 |
|---|---|
| 模型（FR-001） | ✅ `DEFAULT_NAME`、`default_category`、`legacy_translation_name?`、幂等 `repair_legacy_names!`（迁移商品 + 关联表后删遗留行） |
| seed（FR-002） | ✅ 常量命名 + 先 `repair_legacy_names!`（重跑 seed 自愈） |
| 商品钩子（FR-003） | ✅ `default_category \|\| create!(DEFAULT_NAME)`，去 `I18n.t` 依赖 |
| 运维入口（FR-004） | ✅ `pallastrade:shipping_categories:repair_legacy_names` |
| dev 数据修复（FR-005） | ✅ 已执行（备份 `/tmp/scat-backup-20260914.json`）：遗留 1→`Default`、2→`Digital`；`Free` 关联=[4]；商品 37/37→4 |
| 测试 | ✅ `spec/models/pallastrade/shipping_category_spec.rb` 4 例通过 |

## 验证与证据（2026-09-14）

| 证据 | 结果 |
|---|---|
| `shipping_category_spec.rb`（AC-001..004） | ✅ 4 examples, 0 failures |
| dev DB 修复前后对比（AC-005） | ✅ BEFORE 2 行 missing → AFTER `MISSING_ROWS=0`（仅 `Digital`/`Default`） |
| dev 重跑 seed（AC-006） | ⏳ 部署后执行 rake 任务复验（应空操作） |
| dev 下单回归（AC-007） | ✅ 订单 `or_86uR0I7fEb`：账单地址 = 配送地址（Austin）；`Free`→`Default` 关联生效 |

## 后续任务

| # | 内容 |
|---|---|
| 1 | 其他环境（如有历史数据）执行同一 rake 任务即可自愈 |
| 2 | 如需多语言分类名展示，应改走展示层映射（不在数据里存翻译键） |
