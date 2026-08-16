# REQ-20260816-admin-nav-architecture — 管理后台导航架构统一重构（P3 面包屑自动推导）

> 任务类型：feature | 任务：`TASK-20260816093819-84a08105` | Gate：`GATE-2026-08-16T09-38-33`
> 分支：dev | 基线：`24220a6` | 方案文档：`docs/research/admin-navigation-refactor-plan.md`
> 关联 PRD：`docs/prd/admin/PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局.md`（approved）

---

## Step 0：跨层搜索（已执行）

| 层 | 搜索路径 | 关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | breadcrumb/nav | `ai_controller.rb`（Pattern B） | 不涉及 |
| Core | `pallastrade_core/app/` | nav/breadcrumb | 无 | 不涉及 |
| API | `pallastrade_api/app/` | nav | 无 | 不涉及 |
| Admin | `pallastrade_admin/app/` | navigation/add_breadcrumb/settings-header/if: | 导航配置、helper、Item、布局、25+控制器 | **本次修改对象** |
| Storefront | `storefront/src/` | breadcrumb | 前台组件 | 不涉及 |
| Platform | `platform/packages/` | nav | 无 | 不涉及 |

## Step 1：Skill 文件咨询（已执行）

| Skill | 状态 | 关键结论 |
|---|---|---|
| `pallastrade-customization/SKILL.md` | ✅ | 导航自定义 → `pallastrade-admin` |
| `pallastrade-admin/SKILL.md` | ✅ | 已有「两套布局统一规范」章节（GS-031/032）；本重构将其升级为 Schema 权威章节 |
| `pallastrade-prd/SKILL.md` | ✅ | AC→测试注解 `# PRD-xxx AC-x` |

---

## 需求标题：管理后台导航架构统一重构（P1-P5）

### 背景 / 已确认决策

- 决策 1：顶级落地 = 模块主页面（Email 模式）
- 决策 2：getting_started 保留 wizard 完成后隐藏
- 决策 3：translations 常显 + 空态引导

### 改动清单（按阶段）

- **P1** ✅（已提交 24220a6）：`_layout.css` 的 `#settings-header` 高度自适应，修复面包屑溢出。
- **P2** ✅（已提交 24220a6）：`orders_to_fulfill`/`translations` 常显 + badge/空态。
- **P3**（本次）：面包屑自动推导 ——
  1. `Navigation::Item` 加 `match_path?`（URL 精确/前缀匹配）；`Navigation` 加 `find_breadcrumb_chain(path, context)`（最深匹配 + 祖先链）。
  2. `BreadcrumbConcern` 加 `before_action :derive_breadcrumbs_from_navigation`：**主区(sidebar)** 自动按 请求路径→导航项→ 图标 + 父+子面包屑；设置区保留现有机制（settings nav 为 section 级，crumb 移除归 P4）。
  3. 新增对象页 hook：`breadcrumb_object` / `breadcrumb_object_name` / `breadcrumb_object_url`（控制器可覆盖，products/promotions 迁移）。
  4. 删除 5 个手写 concern：`emails/posts/order/products/promotions_breadcrumb_concern`；清理主区控制器 `include` + `add_breadcrumb` + `add_breadcrumb_icon`（设置区控制器保留，归 P4）。
  5. 保留宿主应用 `ai_controller.rb` 手写面包屑（AI 模块不在导航配置，属宿主自定义）。
- **P4**：单一布局收敛 + page_title fallback + 设置区 section/tabs 统一（删 4 个 banner partial）。
- **P5**：`harness nav:validate` + 全量迁移 + SKILL/GS 沉淀。

### 验收标准（P3 部分）

- AC-003：面包屑自动推导 —— 主区抽查 /admin/posts、/admin/emails、/admin/orders、/admin/checkouts、/admin/product_translations、/admin/gift_cards 无手写 crumb 仍正确（模块→子页）。
- AC-003b：对象页 —— /admin/products/:id/edit 显示 Products > 产品名；/admin/promotions/:id 显示 Promotions > 促销名。
- AC-003c：设置区回归 —— /admin/channels、/admin/api_keys 等仍为 Settings > 页面（不回归）。
- AC-003d：`navigation_consistency_spec` + `emails_spec` 全绿。

### 测试计划

- `navigation_consistency_spec` 扩展（AC-001~004，标注 `# PRD-xxx AC-x`）
- 浏览器 e2e：面包屑 top>=0、子项恒显、顶级点击
- 每阶段：容器 rspec + quick check + 部署 dev + 浏览器抽查
