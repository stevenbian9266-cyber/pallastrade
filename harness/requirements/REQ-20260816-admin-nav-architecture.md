# REQ-20260816-admin-nav-architecture — 管理后台导航架构统一重构

> 任务类型：feature | 任务：`TASK-20260816091432-b943ec84` | Gate：`GATE-2026-08-16T09-14-53`
> 分支：dev | 方案文档：`docs/research/admin-navigation-refactor-plan.md`
> 关联 PRD：`docs/prd/admin/PRD-20260816-admin-管理后台导航架构统一重构-常显原则-面包屑自动推导-单一布局.md`

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

- **P1**：`_layout.css` 的 `#settings-header` 高度自适应（`height:auto`+`min-height`+`flex-col`），修复面包屑溢出。
- **P2**：导航配置 `orders_to_fulfill` 删 `if: count>0`（保留 badge）；`translations` 删 `if: locales>1`；`navigation_helper` 渲染层"子项恒显"规则（子项仅权限过滤）。
- **P3**：`Navigation::Item` 加 path→item 索引；`BreadcrumbConcern` 自动推导面包屑；删手写 concern/crumb（渐进）。
- **P4**：单一布局收敛 + page_title fallback + 设置区 section/tabs 统一（删 4 个 banner partial）。
- **P5**：`harness nav:validate` + 全量迁移 + SKILL/GS 沉淀。

### 验收标准

- AC-001：设置页面包屑 top>=0（不溢出）。
- AC-002：orders_to_fulfill/translations 常显（count=0/单语言仍显示）。
- AC-003：面包屑自动推导（抽查 5 页无手写 crumb 正确）。
- AC-004：主区/设置区页面头一致；section/tabs 统一。
- AC-005：nav:validate 通过 + SKILL/GS 沉淀。

### 测试计划

- `navigation_consistency_spec` 扩展（AC-001~004，标注 `# PRD-xxx AC-x`）
- 浏览器 e2e：面包屑 top>=0、子项恒显、顶级点击
- 每阶段：容器 rspec + quick check + 部署 dev + 浏览器抽查
