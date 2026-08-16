# PallasTrade 管理后台导航架构统一重构 —— 方案文档

> 状态：approved（用户已确认 3 项设计决策）
> 创建：2026-08-16 | 分支：dev | 基线：aedd302
> 性质：架构级重构方案（实施备忘录，防遗忘）

---

## 0. 核心设计原则

1. **稳定导航（常显）**：菜单项只允许被**权限**（`can?`）过滤；**业务状态禁止隐藏菜单**——状态一律用 **badge 角标 / 空态引导 / 禁用态** 表达。
2. **单一事实源（SCOT）**：菜单结构、点击目标、显示、面包屑、页面头全部由**导航配置**声明并自动推导；控制器/视图零导航代码。
3. **一套渲染管线**：主区与设置区共用同一布局/渲染逻辑，不因区域产生第二套行为。
4. **声明即得**：新增一级+二级菜单 = 只写导航配置 + 建控制器 + 建视图，其余自动。

## 1. 已确认的设计决策（用户拍板）

| # | 决策 | 结论 |
|---|---|---|
| 1 | **顶级落地语义** | 统一为「**顶级 = 模块主页面**」（Email 模式）。每个模块顶级点击 → 自己的主页面（Email=设置页、Orders=列表页均可，取决于模块）；次级菜单恒显并高亮当前项 |
| 2 | **getting_started** | **保留 wizard 完成后隐藏**（`!setup_completed?` 例外豁免） |
| 3 | **单语言店铺 translations** | **常显 + 空态引导**（删 `locales>1` 的 `if:`；单语言店铺进入页面显示引导文案） |

## 2. 问题清单（现状 vs 目标）

| # | 现状问题 | 目标 |
|---|---|---|
| B1 | 设置区 `#settings-header` 固定高度(58px)+flex 居中 → 有页面头的设置页**面包屑溢出到浏览器顶部上方**（top:-16 实测） | 面包屑恒在 header 内正常显示（高度自适应） |
| B2 | `orders_to_fulfill` 被 `if: count>0` 业务条件隐藏 → 次级菜单不完整/为空 | **常显 + badge(数量)** |
| B3 | `translations` 被 `if: locales>1` 隐藏 | **常显 + 空态引导** |
| B4 | 面包屑需每模块手写 concern + 每控制器 `add_breadcrumb` + 每视图 `page_title` | **导航配置自动推导**，零导航代码 |
| B5 | 主区/设置区两套布局，设置区 section banner 用 4 个手写 partial（_developers_nav/_team_nav/_audit_nav/_returns_and_refunds_nav） | **单一布局 + section/tabs 统一机制** |
| B6 | 子项 `if:` 可写任意业务条件（无约束） | **schema 校验器强制 permission-only** |

## 3. 目标架构

```
┌─────────────────────────────────────────────────────────┐
│ ① 导航配置 Schema（唯一事实源）                          │
│    sidebar_nav / settings_nav / sections / tabs          │
│    + 配置校验器（harness nav:validate）                   │
├─────────────────────────────────────────────────────────┤
│ ② 导航渲染层（navigation_helper 重构）                    │
│    统一：渲染、点击目标、active 高亮、次级菜单恒显、      │
│          badge、折叠态 dropdown、mobile                   │
├─────────────────────────────────────────────────────────┤
│ ③ 面包屑自动推导层（BreadcrumbConcern 重构）              │
│    请求路径 → 命中导航项 → 自动 图标+父+子 面包屑         │
│    对象页 hook：breadcrumb_object（可覆盖）               │
├─────────────────────────────────────────────────────────┤
│ ④ 页面头/主内容渲染层（单一布局）                         │
│    header(面包屑) + 主内容区(页面头/tabs/内容) 统一        │
│    page_title 自动 fallback → 导航项 label                │
├─────────────────────────────────────────────────────────┤
│ ⑤ 设置区 section/tabs 统一（替换 4 个手写 partial）       │
└─────────────────────────────────────────────────────────┘
```

## 4. 导航 Schema 规范（声明即得）

```ruby
sidebar_nav.add :module_key,            # 顶级
  label: :module,
  url: :admin_module_path,              # 必须 symbol route（lambda 仅白名单）
  icon: 'tabler-icon',                  # 顶级必填
  position: 30,
  permission: :module,                  # can?(:manage, Model) 统一
  landing: :sub_primary,                # 顶级点击默认落地子项（缺省=模块 url）
  do |m|
    m.add :sub_primary,                 # 主子项：必存在、无条件可见
      label: :sub_primary,
      url: :admin_sub_primary_path,
      position: 10,
      permission: :sub_primary,         # 仅权限
      badge: -> { count }               # 业务状态 → badge，禁止用于 if
  end
end
```

**校验器强制约束**：
- [ ] 顶级 icon 必填；URL 必须可解析
- [ ] 有子项的顶级必须含 ≥1 个无条件可见主子项
- [ ] 子项 `if:` 只接受 permission；出现 count/size/state 业务条件 → 校验失败
- [ ] 业务计数走 badge；配置类差异（单语言）→ 常显+空态，不隐藏
- [ ] active 由 URL 推导（手写仅覆盖钩子）

## 5. 现有菜单改造清单

| 模块/项 | 改造 |
|---|---|
| Orders `orders_to_fulfill` | 删 `if: count>0` → 常显 + badge（B2） |
| Products `translations` | 删 `if: locales>1` → 常显 + 空态引导（B3） |
| Orders/Returns/Products/Customers/Promotions/Reports/Blog | 迁 schema 声明（permission/landing/active 推导） |
| Emails | **标准模板**（已是声明即得形态），迁移到新 schema |
| getting_started | 保留（决策 2） |
| 设置区全部 + Developers/Team/Audit/Returns section | 迁 schema + section/tabs 统一（B5） |
| 布局/CSS | 单一布局 + `#settings-header` 修复（B1） |

## 6. 分阶段实施路线图（每阶段独立 gate+测试+部署）

| 阶段 | 内容 | 涉及 | 风险 |
|---|---|---|---|
| **P1** | 设置区布局修复：`#settings-header` 高度自适应（B1） | `_layout.css` | 低 |
| **P2** | 常显原则落地：orders_to_fulfill/translations 常显+badge/空态；渲染层"子项恒显"（B2/B3） | 导航配置 + navigation_helper | 中 |
| **P3** | 面包屑自动推导：path 索引 + BreadcrumbConcern 重构；删手写 concern/crumb（B4） | Navigation::Item + BaseController + 各控制器 | 中（query/嵌套/对象页边界） |
| **P4** | page_title fallback + 单一布局 + section/tabs 统一（B5） | 布局 + _content_header + 设置区 partial | 中 |
| **P5** | schema 校验器 `nav:validate` + 全量迁移 + SKILL/GS 沉淀（B6） | harness + SKILL.md + scenarios.json | 中 |

## 7. 验证与自进化

- 每阶段：容器内 rspec（navigation_consistency 扩展）+ 浏览器逐页抽查（面包屑不溢出、子项恒显、顶级点击）
- P5：`harness nav:validate` 接入 check/pre-commit
- 规范沉淀：`pallastrade-admin/SKILL.md` 导航 Schema 权威章节 + scenarios.json 新增 GS
- 部署：每阶段 push dev + 服务器部署 + 浏览器验证

## 8. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-16 | v1.0 | 方案初版；用户确认决策 1/2/3 | AI |
| 2026-08-16 | v1.1 | **P1+P2 完成**（提交 24220a6）：设置区头部溢出修复 + 常显原则 | AI |
| 2026-08-16 | v1.2 | **P3 完成**（提交 5c09baf）：面包屑自动推导引擎（`Navigation#find_breadcrumb_chain` + `Item#match_path?`）+ `BreadcrumbConcern` 自动推导；删除 5 个手写 concern；清理 27 个主区控制器手写 crumb；对象页 crumb 保留；设置区保留（归 P4）；SKILL.md 章节重写 + GS-033 | AI |
