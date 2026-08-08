# PRD-20260808-admin-remove-enterprise-edition-notice

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-08 |
| 来源 | 需求：去掉管理后台左侧菜单的升级逻辑（Community Edition 升级提示） |
| 分类 | admin（自动判定） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **一句话需求**：去掉管理后台左侧菜单中的升级提示（Community Edition → Enterprise）
- **背景**：交付源码给客户，不应出现向客户推销 Enterprise 升级的提示
- **目标**：管理后台侧边栏不再显示升级提示；相关逻辑（视图/路由/控制器/文案/CSS/helper）彻底移除
- **成功指标**：侧边栏无升级提示；代码中无 enterprise_edition_notice 引用残留

## 2. 用户故事 / 场景

- 作为后台管理员，登录管理后台 → 左侧菜单**不再出现**升级提示块

## 3. 功能需求（FR）

- FR-001：管理后台侧边栏不渲染升级提示
- FR-002：移除升级提示相关全部代码（视图/路由/控制器/文案/CSS/helper）
- FR-003：不破坏侧边栏其他功能（导航、用户菜单、折叠等）

## 4. 非功能需求（NFR）

- 兼容性：后台其他页面正常渲染
- 可维护性：无死代码残留（无 enterprise_edition_notice 引用）

## 5. 验收标准（AC）

- AC-001：登录后台侧边栏无升级提示块（浏览器验证）
- AC-002：git grep enterprise_edition_notice 无命中
- AC-003：后台其他页面（如商品列表）正常 200

## 6. 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| App | backend/app/ | enterprise | 无 | — |
| Core | pallastrade_core/app/ | enterprise | 无 | — |
| API | pallastrade_api/app/ | enterprise | 无 | — |
| Admin | pallastrade_admin/app/ | enterprise_edition_notice | 视图/控制器/helper/路由/文案/CSS | ✅ 全部在此层 |
| Storefront | storefront/src/ | enterprise | 无 | — |
| Platform | platform/packages/ | enterprise | 无 | — |

**结论**：升级逻辑全部在 pallastrade_admin gem，7 处引用，无 spec 测试引用。

## 7. 技术影响

- 涉及：pallastrade_admin gem 的 sidebar 视图、dashboard 控制器、routes、base_helper、en.yml、_layout.css
- 影响面：仅管理后台侧边栏

## 8. 测试计划

- 新增：无（删除逻辑，现有后台功能不受影响）
- 更新：无 spec 引用
- 验证：浏览器侧边栏无提示 + git grep 无残留

## 9. 文档同步清单（知识同步门）

- [ ] Skill：pallastrade-admin（若涉及侧边栏定制约定变化）
- [x] API 文档：不涉及
- [x] README：不涉及

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-08 | 0.1 | 初稿 | AI |
